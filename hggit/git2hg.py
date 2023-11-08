# git2hg.py - convert Git repositories and commits to Mercurial ones
import collections
import io
import itertools

from dulwich import config as dul_config
from dulwich.objects import Commit, Tag
from dulwich.refs import (
    ANNOTATED_TAG_SUFFIX,
    LOCAL_BRANCH_PREFIX,
    LOCAL_TAG_PREFIX,
)
from mercurial.i18n import _

from mercurial.node import bin, short
from mercurial import error, util as hgutil
from mercurial import phases

from . import config


def get_public(ui, refs, remote_names):
    cfg = config.get_publishing_option(ui)

    paths = list(
        itertools.chain.from_iterable(
            ui.paths.get(name) for name in remote_names
        )
    )

    # we may have multiple paths listed, so parse their configuration
    # and deduplicate it
    configs = {path.hggit_publish for path in paths}

    # and if we find more then one, we don't know which is correct
    # (but if we actually had the original path object somehow, we
    # wouldn't have to do this)
    if len(configs) > 1:
        raise error.Abort(
            b'different publishing configurations for the same remote '
            b'location',
            hint=(b'conflicting paths: ' + b", ".join(sorted(remote_names))),
        )

    if configs and configs != {None}:
        cfg = configs.pop()

    use_phases, publish_defaults, refs_to_publish = cfg

    if not use_phases:
        return {}

    to_publish = set()

    use_phases, publish_defaults, refs_to_publish = cfg

    if not use_phases:
        return {}

    for remote_name in remote_names:
        refs_to_publish |= {
            ref[len(remote_name) + 1 :]
            for ref in refs_to_publish
            if ref.startswith(remote_name + b'/')
        }

    for ref_name, sha in refs.items():
        if ref_name.startswith(LOCAL_BRANCH_PREFIX):
            branch = ref_name[len(LOCAL_BRANCH_PREFIX) :]
            if branch in refs_to_publish:
                ui.note(b"publishing branch %s\n" % branch)
                to_publish.add(sha)

        elif ref_name.startswith(LOCAL_TAG_PREFIX):
            tag = ref_name[len(LOCAL_TAG_PREFIX) :]
            if publish_defaults or tag in refs_to_publish:
                ui.note(
                    b"publishing tag %s\n" % ref_name[len(LOCAL_TAG_PREFIX) :]
                )
                to_publish.add(sha)

        elif publish_defaults and ref_name == b'HEAD':
            ui.note(b"publishing remote HEAD\n")
            to_publish.add(sha)

    return to_publish


def find_incoming(ui, git_object_store, git_map, refs, remote):
    '''find what commits need to be imported

    git_object_store: is a dulwich object store.
    git_map: is a map with keys being Git commits that have already been
             imported
    refs: is a map of refs to SHAs that we're interested in.

    '''

    public = get_public(ui, refs, remote)
    done = set()

    # sort by commit date
    def commitdate(sha):
        obj = git_object_store[sha]
        return obj.commit_time - obj.commit_timezone

    # get a list of all the head shas
    def get_heads(refs):
        todo = []
        seenheads = set()
        for ref, sha in refs.items():
            # refs could contain refs on the server that we haven't pulled down
            # the objects for; also make sure it's a sha and not a symref
            if ref != b'HEAD' and sha in git_object_store:
                obj = git_object_store[sha]
                while isinstance(obj, Tag):
                    obj_type, sha = obj.object
                    obj = git_object_store[sha]
                if isinstance(obj, Commit) and sha not in seenheads:
                    seenheads.add(sha)
                    todo.append(sha)

        todo.sort(key=commitdate, reverse=True)
        return todo

    def get_unseen_commits(todo):
        '''get all unseen commits reachable from todo in topological order

        'unseen' means not reachable from the done set and not in the git map.
        Mutates todo and the done set in the process.'''
        commits = []
        while todo:
            sha = todo[-1]
            if sha in done or sha in git_map:
                todo.pop()
                continue
            assert isinstance(sha, bytes)
            obj = git_object_store[sha]
            assert isinstance(obj, Commit)
            for p in obj.parents:
                if sha in public:
                    public.add(p)

                if p not in done and p not in git_map:
                    todo.append(p)
                    # process parents of a commit before processing the
                    # commit itself, and come back to this commit later
                    break
            else:
                commits.append(sha)
                done.add(sha)
                todo.pop()

        return commits

    todo = get_heads(refs)
    commits = get_unseen_commits(todo)

    for sha in reversed(commits):
        for p in git_object_store[sha].parents:
            if sha in public:
                public.add(p)

    return [
        GitIncomingCommit(
            sha,
            phases.public if sha in public else phases.draft,
        )
        for sha in commits
    ]


class GitIncomingCommit:
    '''struct to store result from find_incoming'''

    __slots__ = 'sha', 'phase'

    def __init__(self, sha, phase):
        self.sha = sha
        self.phase = phase

    @property
    def node(self):
        return bin(self.sha)

    @property
    def short(self):
        return short(self.node)

    def __bytes__(self):
        return self.sha


def extract_hg_metadata(message, git_extra):
    split = message.split(b"\n--HG--\n", 1)
    # Renames are explicitly stored in Mercurial but inferred in Git. For
    # commits that originated in Git we'd like to optionally infer rename
    # information to store in Mercurial, but for commits that originated in
    # Mercurial we'd like to disable this. How do we tell whether the commit
    # originated in Mercurial or in Git? We rely on the presence of extra
    # hg-git fields in the Git commit.
    #
    # - Commits exported by hg-git versions past 0.7.0 always store at least
    #   one hg-git field.
    #
    # - For commits exported by hg-git versions before 0.7.0, this becomes a
    #   heuristic: if the commit has any extra hg fields, it definitely
    #   originated in Mercurial. If the commit doesn't, we aren't really sure.
    #
    # If we think the commit originated in Mercurial, we set renames to a
    # dict. If we don't, we set renames to None. Callers can then determine
    # whether to infer rename information.
    renames = None
    extra = {}
    branch = None
    if len(split) == 2:
        renames = {}
        message, meta = split
        lines = meta.split(b"\n")
        for line in lines:
            if line == b'':
                continue

            if b' : ' not in line:
                break
            command, data = line.split(b" : ", 1)

            if command == b'rename':
                before, after = data.split(b" => ", 1)
                renames[after] = before
            if command == b'branch':
                branch = data
            if command == b'extra':
                k, v = data.split(b" : ", 1)
                extra[k] = hgutil.urlreq.unquote(v)

    git_fn = 0
    for field, data in git_extra:
        if field.startswith(b'HG:'):
            if renames is None:
                renames = {}
            command = field[3:]
            if command == b'rename':
                before, after = data.split(b':', 1)
                renames[hgutil.urlreq.unquote(after)] = hgutil.urlreq.unquote(
                    before
                )
            elif command == b'extra':
                k, v = data.split(b':', 1)
                extra[hgutil.urlreq.unquote(k)] = hgutil.urlreq.unquote(v)
        else:
            # preserve ordering in Git by using an incrementing integer for
            # each field. Note that extra metadata in Git is an ordered list
            # of pairs.
            hg_field = b'GIT%d-%s' % (git_fn, field)
            git_fn += 1
            extra[hgutil.urlreq.quote(hg_field)] = hgutil.urlreq.quote(data)

    return (message, renames, branch, extra)


def convert_git_int_mode(mode):
    # TODO: make these into constants
    convert = {0o100644: b'', 0o100755: b'x', 0o120000: b'l'}
    if mode in convert:
        return convert[mode]
    return b''


def set_committer_from_author(commit):
    commit.committer = commit.author
    commit.commit_time = commit.author_time
    commit.commit_timezone = commit.author_timezone


def filter_refs(refs, heads):
    '''For a dictionary of refs: shas, if heads is None then return refs
    that match the heads. Otherwise, return refs that are heads or tags.

    '''
    filteredrefs = []
    if heads is not None:
        # contains pairs of ('refs/(heads|tags|...)/foo', 'foo')
        # if ref is just '<foo>', then we get ('foo', 'foo')
        stripped_refs = [
            (r, r[r.find(b'/', r.find(b'/') + 1) + 1 :]) for r in refs
        ]
        for h in heads:
            if h.endswith(b'/*'):
                prefix = h[:-1]  # include the / but not the *
                r = [
                    pair[0]
                    for pair in stripped_refs
                    if pair[1].startswith(prefix)
                ]
                r.sort()
                filteredrefs.extend(r)
            else:
                r = [pair[0] for pair in stripped_refs if pair[1] == h]
                if not r:
                    msg = _(b"unknown revision '%s'") % h
                    raise error.RepoLookupError(msg)
                elif len(r) == 1:
                    filteredrefs.append(r[0])
                else:
                    msg = _(b"ambiguous reference %s: %s")
                    msg %= (
                        h,
                        b', '.join(sorted(r)),
                    )
                    raise error.RepoLookupError(msg)
    else:
        for ref, sha in refs.items():
            if not ref.endswith(ANNOTATED_TAG_SUFFIX) and (
                ref.startswith(LOCAL_BRANCH_PREFIX)
                or ref.startswith(LOCAL_TAG_PREFIX)
                or ref == b'HEAD'
            ):
                filteredrefs.append(ref)
        filteredrefs.sort()

    # the choice of OrderedDict vs plain dict has no impact on stock
    # hg-git, but allows extensions to customize the order in which refs
    # are returned
    return collections.OrderedDict((r, refs[r]) for r in filteredrefs)


def parse_gitmodules(git, tree_obj):
    """Parse .gitmodules from a git tree specified by tree_obj

    Returns a list of tuples (submodule path, url, name), where name
    is hgutil.urlreq.quoted part of the section's name

    Raises KeyError if no modules exist, or ValueError if they're invalid
    """
    unused_mode, gitmodules_sha = tree_obj[b'.gitmodules']
    gitmodules_content = git[gitmodules_sha].data
    with io.BytesIO(gitmodules_content) as fp:
        cfg = dul_config.ConfigFile.from_file(fp)
    return dul_config.parse_submodules(cfg)


def git_file_readlines(git, tree_obj, fname):
    """Read content of a named entry from the git commit tree

    :return: list of lines
    """
    if fname in tree_obj:
        unused_mode, sha = tree_obj[fname]
        content = git[sha].data
        return content.splitlines()
    return []
