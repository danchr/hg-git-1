import collections
import itertools
import os
import re
import shutil

from dulwich.client import HTTPUnauthorized
from dulwich.errors import HangupException, GitProtocolError, ApplyDeltaError
from dulwich.objects import Blob, Commit, Tag, Tree, parse_timezone
from dulwich.pack import apply_delta
from dulwich.refs import (
    ANNOTATED_TAG_SUFFIX,
    LOCAL_BRANCH_PREFIX,
    LOCAL_TAG_PREFIX,
)
from dulwich.repo import Repo, check_ref_format
from dulwich import client
from dulwich import config as dul_config
from dulwich import diff_tree

from mercurial.i18n import _
from mercurial.node import hex, bin, nullid, nullhex, short
from mercurial.utils import dateutil, urlutil
from mercurial import (
    bookmarks,
    context,
    encoding,
    error,
    hg,
    obsutil,
    phases,
    pycompat,
    url,
    util as hgutil,
    scmutil,
)

from . import _ssh
from . import compat
from . import git2hg
from . import hg2git
from . import util
from .overlay import overlayrepo

REMOTE_BRANCH_PREFIX = b'refs/remotes/'

RE_GIT_AUTHOR = re.compile(br'^(.*?) ?\<(.*?)(?:\>(.*))?$')

RE_GIT_SANITIZE_AUTHOR = re.compile(br'[<>\n]')

RE_GIT_AUTHOR_EXTRA = re.compile(br'^(.*?)\ ext:\((.*)\) <(.*)\>$')

RE_GIT_EXTRA_KEY = re.compile(br'GIT([0-9]*)-(.*)')

# Test for git:// and git+ssh:// URI.
# Support several URL forms, including separating the
# host and path with either a / or : (sepr)
RE_GIT_URI = re.compile(
    br'^(?P<scheme>git([+]ssh)?://)(?P<host>.*?)(:(?P<port>\d+))?'
    br'(?P<sepr>[:/])(?P<path>.*)$'
)

RE_NEWLINES = re.compile(br'[\r\n]$')
RE_GIT_DETERMINATE_PROGRESS = re.compile(br'\((\d+)/(\d+)\)')
RE_GIT_INDETERMINATE_PROGRESS = re.compile(br'(\d+)')
RE_GIT_TOTALS_LINE = re.compile(
    br'Total \d+ \(delta \d+\), reused \d+ \(delta \d+\)',
)

RE_AUTHOR_FILE = re.compile(br'\s*=\s*')


class GitProgress(object):
    """convert git server progress strings into mercurial progress

    but also detect the intertwined "remote" messages
    """

    def __init__(self, ui):
        self.ui = ui

        self._progress = None
        self.msgbuf = b''

    def progress(self, message):
        # 'Counting objects: 33640, done.\n'
        # 'Compressing objects:   0% (1/9955)   \r

        lines = (self.msgbuf + pycompat.sysbytes(message)).splitlines(
            keepends=True
        )
        self.msgbuf = b''

        for msg in lines:
            # if it's still a partial line, postpone processing
            if not RE_NEWLINES.search(msg):
                self.msgbuf = msg
                return

            # anything that endswith a newline, we should probably print out
            if msg.endswith(b'\n'):
                # except some final statistics
                if RE_GIT_TOTALS_LINE.search(msg) or msg.endswith(b', done.\n'):
                    self.ui.note(_(b'remote: %s\n') % msg[:-1])
                else:
                    self.ui.status(_(b'remote: %s\n') % msg[:-1])
                self.flush()
                continue

            # this is a progress message
            assert msg.endswith(b'\r'), f"{msg} is not a progress message"

            td = msg.split(b':', 1)
            data = td.pop()

            try:
                topic = td[0]
            except IndexError:
                topic = b''

            determinate = RE_GIT_DETERMINATE_PROGRESS.search(data)
            indeterminate = RE_GIT_INDETERMINATE_PROGRESS.search(data)

            if self._progress and self._progress.topic != topic:
                return False
            if not self._progress:
                self._progress = self.ui.makeprogress(topic)

            if determinate:
                pos, total = map(int, determinate.group(1, 2))
            elif indeterminate:
                pos = int(indeterminate.group(1))
                total = None
            else:
                continue

            self._progress.update(pos, total=total)

    def flush(self, msg=b''):
        if self._progress is not None:
            self._progress.complete()
            self._progress = None
        self.progress(b'')


class heads_tags(object):
    __slots__ = "heads", "tags"

    def __init__(self, heads=(), tags=()):
        self.heads = set(heads)
        self.tags = set(tags)

    def __iter__(self):
        return itertools.chain(self.heads, self.tags)

    def __bool__(self):
        return bool(self.heads) or bool(self.tags)

    def __repr__(self):
        return f"heads_tags(heads={self.heads}, tags={self.tags})"


def get_repo_and_gitdir(repo):
    if repo.local() and repo.shared():
        repo = hg.sharedreposource(repo)

    if repo.ui.configbool(b'git', b'intree'):
        gitdir = repo.wvfs.join(b'.git')
    else:
        gitdir = repo.vfs.join(b'git')

    return repo, gitdir


def has_gitrepo(repo):
    if not hasattr(repo, 'vfs'):
        return False

    repo, gitdir = get_repo_and_gitdir(repo)

    return os.path.isdir(gitdir)


class GitHandler(object):
    map_file = b'git-mapfile'
    tags_file = b'git-tags'

    def __init__(self, dest_repo, ui):
        self.repo = dest_repo
        self.store_repo, self.gitdir = get_repo_and_gitdir(self.repo)
        self.ui = ui

        self.init_author_file()

        self.branch_bookmark_suffix = ui.config(
            b'git', b'branch_bookmark_suffix'
        )

        self._map_git_real = None
        self._map_hg_real = None
        self.load_tags()
        self._remote_refs = None

        self._pwmgr = url.passwordmgr(self.ui, self.ui.httppasswordmgrdb)

        self._clients = {}

        # the HTTP authentication realm -- this specifies that we've
        # tried an unauthenticated request, gotten a realm, and are now
        # ready to prompt the user, if necessary
        self._http_auth_realm = None

    @property
    def vfs(self):
        return self.store_repo.vfs

    @property
    def is_clone(self):
        """detect whether the current operation is an 'hg clone'"""
        # a bit of a hack, but it has held true for quite some time
        return self.ui.configsource(b'paths', b'default') == b'clone'

    @property
    def _map_git(self):
        """mapping of `git-sha` to `hg-sha`"""
        if self._map_git_real is None:
            self.load_map()
        return self._map_git_real

    @property
    def _map_hg(self):
        """mapping of `hg-sha` to `git-sha`"""
        if self._map_hg_real is None:
            self.load_map()
        return self._map_hg_real

    @property
    def remote_refs(self):
        if self._remote_refs is None:
            self.load_remote_refs()
        return self._remote_refs

    @hgutil.propertycache
    def git(self):
        # Dulwich is going to try and join unicode ref names against
        # the repository path to try and read unpacked refs. This
        # doesn't match hg's bytes-only view of filesystems, we just
        # have to cope with that. As a workaround, try decoding our
        # (bytes) path to the repo in hg's active encoding and hope
        # for the best.
        gitpath = self.gitdir.decode(
            pycompat.sysstr(encoding.encoding),
            pycompat.sysstr(encoding.encodingmode),
        )
        # make the git data directory
        if os.path.exists(self.gitdir):
            return Repo(gitpath)
        else:
            if self._map_git:
                self.ui.warn(
                    b'warning: created new git repository at %s\n'
                    % self.gitdir,
                )
            os.mkdir(self.gitdir)
            return Repo.init_bare(gitpath)

    def init_author_file(self):
        self.author_map = {}
        authors_path = self.ui.config(b'git', b'authors')
        if authors_path:
            with open(self.repo.wvfs.join(authors_path), 'rb') as f:
                for line in f:
                    line = line.strip()
                    if not line or line.startswith(b'#'):
                        continue
                    from_, to = RE_AUTHOR_FILE.split(line, 2)
                    self.author_map[from_] = to

    # FILE LOAD AND SAVE METHODS

    def map_set(self, gitsha, hgsha):
        self._map_git[gitsha] = hgsha
        self._map_hg[hgsha] = gitsha

    def map_hg_get(self, gitsha, deref=False):
        if deref:
            try:
                unpeeled, peeled = compat.peel_sha(
                    self.git.object_store, gitsha
                )
                gitsha = peeled.id
            except KeyError:
                self.ui.note(b'note: failed to dereference %s\n' % gitsha)
                return None

        return self._map_git.get(gitsha)

    def map_git_get(self, hgsha):
        return self._map_hg.get(hgsha)

    def load_map(self):
        map_git_real = {}
        map_hg_real = {}
        if os.path.exists(self.vfs.join(self.map_file)):
            for line in self.vfs(self.map_file):
                # format is <40 hex digits> <40 hex digits>\n
                if len(line) != 82:
                    raise ValueError(
                        _(b'corrupt mapfile: incorrect line length %d')
                        % len(line)
                    )
                gitsha = line[:40]
                hgsha = line[41:81]
                map_git_real[gitsha] = hgsha
                map_hg_real[hgsha] = gitsha
        self._map_git_real = map_git_real
        self._map_hg_real = map_hg_real

    def save_map(self, map_file):
        self.ui.debug(_(b"saving git map to %s\n") % self.vfs.join(map_file))

        with self.repo.lock():
            map_hg = self._map_hg
            with self.vfs(map_file, b'wb+', atomictemp=True) as buf:
                bwrite = buf.write
                for hgsha, gitsha in map_hg.items():
                    bwrite(b"%s %s\n" % (gitsha, hgsha))

    def load_tags(self):
        self.tags = {}
        if os.path.exists(self.vfs.join(self.tags_file)):
            for line in self.vfs(self.tags_file):
                sha, name = line.strip().split(b' ', 1)
                if sha in self.repo.unfiltered():
                    self.tags[name] = sha

    def save_tags(self):
        with self.repo.lock():
            with self.vfs(self.tags_file, b'w+', atomictemp=True) as fp:
                for name, sha in sorted(self.tags.items()):
                    if not self.repo.tagtype(name) == b'global':
                        fp.write(b"%s %s\n" % (sha, name))

    def load_remote_refs(self):
        self._remote_refs = {}

        # don't do anything if there's no git repository, as accessing
        # `self.git` will create it
        if not os.path.isdir(self.gitdir):
            return

        # if no paths are set, we should still check 'default'
        pathnames = list(self.ui.paths) or [b'default']

        for pathname in pathnames:
            base = b'refs/remotes/%s/' % pathname
            for ref in self.git.refs.subkeys(base):
                ref = base + ref
                sha = self.git.refs[ref]
                if sha in self._map_git:
                    node = bin(self._map_git[sha])
                    if node in self.repo.unfiltered():
                        self._remote_refs[ref[13:]] = node

    # END FILE LOAD AND SAVE METHODS

    # COMMANDS METHODS

    def import_commits(self, remote_name):
        remote_names = [remote_name] if remote_name is not None else []
        refs = self.git.refs.as_dict()
        self.import_git_objects(b'gimport', remote_names, refs)

    def fetch(self, remote, heads):
        result = self.fetch_pack(remote.path, heads)
        remote_names = self.remote_names(remote.path, False)

        oldheads = self.repo.changelog.heads()

        if result.refs:
            imported = self.import_git_objects(
                b'pull',
                remote_names,
                result.refs,
                heads=heads,
            )
        else:
            imported = 0

        if imported == 0:
            return 0

        # determine whether to activate a bookmark on clone
        if self.is_clone:
            if heads:
                # -r/--rev was specified, so try to activate any first
                # bookmark specified, which is what mercurial would
                # update to -- _except_ if that also happens to
                # resolve to a branch or tag. that seems fairly
                # esoteric, though, so we can live with that
                activate = heads[0]
            else:
                # no heads means no -r/--rev and that everything was
                # pulled, so activate the remote HEAD
                headname, headnode = self.get_result_head(result)

                if headname is not None:
                    # head is a symref, pick the corresponding
                    # bookmark
                    activate = headname
                elif headnode is not None and self.repo[headnode].bookmarks():
                    # head is detached, but there's a bookmark
                    # pointing to it
                    activate = self.repo[headnode].bookmarks()[0]
                else:
                    # head is fully detached, so don't do anything
                    # special other than issue a warning (at some
                    # point in the furture, we could convert HEAD into
                    # @)
                    self.ui.warn(
                        b"warning: the git source repository has a "
                        b"detached head\n"
                        b"(you may want to update to a bookmark)\n"
                    )
                    activate = None

            if activate is not None:
                activate += self.branch_bookmark_suffix or b''

                if activate in self.repo._bookmarks:
                    bookmarks.activate(self.repo, activate)

        # code taken from localrepo.py:addchangegroup
        dh = 0
        if oldheads:
            heads = self.repo.changelog.heads()
            dh = len(heads) - len(oldheads)
            for h in heads:
                if h not in oldheads and self.repo[h].closesbranch():
                    dh -= 1

        if dh < 0:
            return dh - 1
        else:
            return dh + 1

    def export_commits(self):
        try:
            self.export_git_objects()
            self.export_hg_tags()
            return self.update_references()
        finally:
            self.save_map(self.map_file)

    def get_refs(self, remote):
        exportable = self.export_commits()
        old_refs = {}
        new_refs = {}

        def changed(refs):
            old_refs.update(refs)
            new_refs.update(self.get_changed_refs(refs, exportable, True))
            return refs  # always return the same refs to make the send a no-op

        try:
            self._call_client(
                remote, 'send_pack', changed, lambda have, want: []
            )

            changed_refs = [
                ref for ref, sha in new_refs.items() if sha != old_refs.get(ref)
            ]

            new = [
                bin(sha) for sha in map(self.map_hg_get, changed_refs) if sha
            ]
            old = {}

            for ref, sha in old_refs.items():
                # make sure we don't accidentally dereference and lose
                # annotated tags
                old_target = self.map_hg_get(sha, deref=True)

                if old_target:
                    self.ui.debug(b'unchanged ref %s: %s\n' % (ref, old_target))
                    old[bin(old_target)] = 1
                else:
                    self.ui.debug(b'changed ref %s\n' % (ref))

            return old, new
        except (HangupException, GitProtocolError) as e:
            raise error.Abort(
                _(b"git remote error: ") + pycompat.sysbytes(str(e))
            )

    def push(self, remote, revs, bookmarks, force):
        self.repo.hook(
            b"preoutgoing",
            git=True,
            source=b'push',
            url=remote,
        )

        old_refs, new_refs = self.upload_pack(remote, revs, bookmarks, force)
        remote_names = self.remote_names(remote, True)
        remote_desc = remote_names[0] if remote_names else b''

        ref_status = new_refs.ref_status
        new_refs = new_refs.refs

        for ref, new_sha in sorted(new_refs.items()):
            old_sha = old_refs.get(ref)
            if ref_status.get(ref) is not None:
                self.ui.warn(
                    b'warning: failed to update %s; %s\n'
                    % (ref, pycompat.sysbytes(ref_status[ref])),
                )
            elif new_sha == nullhex:
                self.ui.status(b"deleting reference %s\n" % ref)
            elif old_sha is None:
                if self.ui.verbose:
                    self.ui.note(
                        b"adding reference %s::%s => GIT:%s\n"
                        % (remote_desc, ref, new_sha[0:8])
                    )
                else:
                    self.ui.status(b"adding reference %s\n" % ref)
            elif new_sha != old_sha:
                if self.ui.verbose:
                    self.ui.note(
                        b"updating reference %s::%s => GIT:%s\n"
                        % (remote_desc, ref, new_sha[0:8])
                    )
                else:
                    self.ui.status(b"updating reference %s\n" % ref)
            else:
                self.ui.debug(
                    b"unchanged reference %s::%s => GIT:%s\n"
                    % (remote_desc, ref, new_sha[0:8])
                )

        if new_refs and remote_names:
            # make sure that we know the remote head, for possible
            # publishing
            new_refs_with_head = new_refs.copy()

            try:
                new_refs_with_head.update(
                    self.fetch_pack(remote, [b'HEAD']).refs,
                )
            except error.RepoLookupError:
                self.ui.debug(b'remote repository has no HEAD\n')

            self.update_remote_branches(remote_names, new_refs_with_head)

        if old_refs == new_refs:
            if revs or not old_refs:
                # fast path to skip the check below
                self.ui.status(_(b"no changes found\n"))
            else:
                # check whether any commits were skipped due to
                # missing names; this is equivalent to the stock
                # (ignoring %d secret commits) message, but specific
                # to pushing to Git, which doesn't have anonymous
                # heads
                served = self.repo.filtered(b'served')
                exported = set(
                    filter(
                        None,
                        (
                            self.map_hg_get(sha, deref=True)
                            for sha in old_refs.values()
                        ),
                    )
                )
                unexported = served.revs(
                    b"not ancestors(%s)" % b" or ".join(exported),
                )

                if not unexported:
                    self.ui.status(_(b"no changes found\n"))
                else:
                    self.ui.status(
                        b"no changes found "
                        b"(ignoring %d changesets without bookmarks or tags)\n"
                        % len(unexported),
                    )

            ret = None
        elif len(new_refs) > len(old_refs):
            ret = 1 + (len(new_refs) - len(old_refs))
        elif len(old_refs) > len(new_refs):
            ret = -1 - (len(new_refs) - len(old_refs))
        else:
            ret = 1
        return ret

    def clear(self):
        mapfile = self.vfs.join(self.map_file)
        tagsfile = self.vfs.join(self.tags_file)
        if os.path.exists(self.gitdir):
            shutil.rmtree(self.gitdir)
        if os.path.exists(mapfile):
            os.remove(mapfile)
        if os.path.exists(tagsfile):
            os.remove(tagsfile)

    # incoming support
    def getremotechanges(self, remote, revs):
        self.export_commits()
        result = self.fetch_pack(remote.path, revs)

        # refs contains all remote refs. Prune to only those requested.
        if revs:
            reqrefs = {}
            for rev in revs:
                for n in (LOCAL_BRANCH_PREFIX + rev, LOCAL_TAG_PREFIX + rev):
                    if n in result.refs:
                        reqrefs[n] = result.refs[n]
        else:
            reqrefs = result.refs

        commits = [
            c.node
            for c in self.get_git_incoming(
                reqrefs, self.remote_names(remote.path, push=False)
            )
        ]

        b = overlayrepo(self, commits, result.refs)

        return (b, commits, lambda: None)

    # CHANGESET CONVERSION METHODS

    def export_git_objects(self):
        self.ui.note(_(b"finding unexported changesets\n"))
        repo = self.repo
        clnode = repo.changelog.node

        nodes = (clnode(n) for n in repo)
        to_export = (
            repo[node] for node in nodes if not hex(node) in self._map_hg
        )

        todo_total = len(repo) - len(self._map_hg)
        topic = b'searching'
        unit = b'commits'

        with repo.ui.makeprogress(topic, unit, todo_total) as progress:
            export = []
            for ctx in to_export:
                progress.increment(item=short(ctx.node()))
                if ctx.extra().get(b'hg-git', None) != b'octopus':
                    export.append(ctx)

            total = len(export)
            if not total:
                return

        self.ui.note(_(b"exporting %d changesets\n") % total)

        self.repo.hook(b'gitexport', nodes=[c.hex() for c in export], git=True)

        # By only exporting deltas, the assertion is that all previous objects
        # for all other changesets are already present in the Git repository.
        # This assertion is necessary to prevent redundant work. Here, nodes,
        # and therefore export, is in topological order. By definition,
        # export[0]'s parents must be present in Git, so we start the
        # incremental exporter from there.
        pctx = export[0].p1()
        pnode = pctx.node()
        if pnode == nullid:
            gitcommit = None
        else:
            gitsha = self._map_hg[hex(pnode)]
            with util.abort_push_on_keyerror():
                gitcommit = self.git[gitsha]

        exporter = hg2git.IncrementalChangesetExporter(
            self.repo, pctx, self.git.object_store, gitcommit
        )

        mapsavefreq = self.ui.configint(b'hggit', b'mapsavefrequency')
        with self.repo.ui.makeprogress(b'exporting', total=total) as progress:
            for i, ctx in enumerate(export, 1):
                progress.increment(item=short(ctx.node()))
                self.export_hg_commit(ctx.node(), exporter)
                if mapsavefreq and i % mapsavefreq == 0:
                    self.save_map(self.map_file)

    # convert this commit into git objects
    # go through the manifest, convert all blobs/trees we don't have
    # write the commit object (with metadata info)
    def export_hg_commit(self, rev, exporter):
        self.ui.note(_(b"converting revision %s\n") % hex(rev))

        oldenc = util.swap_out_encoding()

        ctx = self.repo[rev]
        extra = ctx.extra()

        commit = Commit()

        (time, timezone) = ctx.date()
        # work around to bad timezone offets - dulwich does not handle
        # sub minute based timezones. In the one known case, it was a
        # manual edit that led to the unusual value. Based on that,
        # there is no reason to round one way or the other, so do the
        # simplest and round down.
        timezone -= timezone % 60
        commit.author = self.get_git_author(ctx)
        commit.author_time = int(time)
        commit.author_timezone = -timezone

        if b'committer' in extra:
            try:
                # fixup timezone
                (name, timestamp, timezone) = extra[b'committer'].rsplit(
                    b' ', 2
                )
                commit.committer = name
                commit.commit_time = int(timestamp)

                # work around a timezone format change
                if int(timezone) % 60 != 0:  # pragma: no cover
                    timezone = parse_timezone(timezone)
                    # Newer versions of Dulwich return a tuple here
                    if isinstance(timezone, tuple):
                        timezone, neg_utc = timezone
                        commit._commit_timezone_neg_utc = neg_utc
                else:
                    timezone = -int(timezone)
                commit.commit_timezone = timezone
            except ValueError:
                self.ui.traceback()
                git2hg.set_committer_from_author(commit)
        else:
            git2hg.set_committer_from_author(commit)

        commit.parents = []
        for parent in self.get_git_parents(ctx):
            hgsha = hex(parent.node())
            git_sha = self.map_git_get(hgsha)
            if git_sha:
                if git_sha not in self.git.object_store:
                    raise error.Abort(
                        _(
                            b'Parent SHA-1 not present in Git'
                            b'repo: %s' % git_sha
                        )
                    )

                commit.parents.append(git_sha)

        commit.message, extra = self.get_git_message_and_extra(ctx)
        commit._extra.extend(extra)

        if b'encoding' in extra:
            commit.encoding = extra[b'encoding']
        if b'gpgsig' in extra:
            commit.gpgsig = extra[b'gpgsig']

        for obj in exporter.update_changeset(ctx):
            if obj.id not in self.git.object_store:
                self.git.object_store.add_object(obj)

        tree_sha = exporter.root_tree_sha

        if tree_sha not in self.git.object_store:
            raise error.Abort(
                _(b'Tree SHA-1 not present in Git repo: %s' % tree_sha)
            )

        commit.tree = tree_sha

        if commit.id not in self.git.object_store:
            self.git.object_store.add_object(commit)
        self.map_set(commit.id, ctx.hex())

        util.swap_out_encoding(oldenc)
        return commit.id

    @staticmethod
    def get_valid_git_username_email(name):
        r"""Sanitize usernames and emails to fit git's restrictions.

        The following is taken from the man page of git's fast-import
        command:

            [...] Likewise LF means one (and only one) linefeed [...]

            committer
                The committer command indicates who made this commit,
                and when they made it.

                Here <name> is the person's display name (for example
                "Com M Itter") and <email> is the person's email address
                ("cm@example.com[1]"). LT and GT are the literal
                less-than (\x3c) and greater-than (\x3e) symbols. These
                are required to delimit the email address from the other
                fields in the line. Note that <name> and <email> are
                free-form and may contain any sequence of bytes, except
                LT, GT and LF. <name> is typically UTF-8 encoded.

        Accordingly, this function makes sure that there are none of the
        characters <, >, or \n in any string which will be used for
        a git username or email. Before this, it first removes left
        angle brackets and spaces from the beginning, and right angle
        brackets and spaces from the end, of this string, to convert
        such things as " <john@doe.com> " to "john@doe.com" for
        convenience.

        TESTS:

        >>> g = GitHandler.get_valid_git_username_email
        >>> g(b'John Doe')
        'John Doe'
        >>> g(b'john@doe.com')
        'john@doe.com'
        >>> g(b' <john@doe.com> ')
        'john@doe.com'
        >>> g(b'    <random<\n<garbage\n>  > > ')
        'random???garbage?'
        >>> g(b'Typo in hgrc >but.hg-git@handles.it.gracefully>')
        'Typo in hgrc ?but.hg-git@handles.it.gracefully'
        """
        return RE_GIT_SANITIZE_AUTHOR.sub(
            b'?', name.lstrip(b'< ').rstrip(b'> ')
        )

    def get_git_author(self, ctx):
        # hg authors might not have emails
        author = ctx.user()

        # see if a translation exists
        author = self.author_map.get(author, author)

        # check for git author pattern compliance
        a = RE_GIT_AUTHOR.match(author)

        if a:
            name = self.get_valid_git_username_email(a.group(1))
            email = self.get_valid_git_username_email(a.group(2))
            if a.group(3) is not None and len(a.group(3)) != 0:
                name += b' ext:(' + hgutil.urlreq.quote(a.group(3)) + b')'
            author = b'%s <%s>' % (
                self.get_valid_git_username_email(name),
                self.get_valid_git_username_email(email),
            )
        elif b'@' in author:
            author = b'%s <%s>' % (
                self.get_valid_git_username_email(author),
                self.get_valid_git_username_email(author),
            )
        else:
            author = self.get_valid_git_username_email(author) + b' <none@none>'

        if b'author' in ctx.extra():
            try:
                author = b"".join(apply_delta(author, ctx.extra()[b'author']))
            except (ApplyDeltaError, AssertionError):
                self.ui.traceback()
                self.ui.warn(
                    b"warning: disregarding possibly invalid metadata in %s\n"
                    % ctx
                )

        return author

    def get_git_parents(self, ctx):
        def is_octopus_part(ctx):
            olist = (b'octopus', b'octopus-done')
            return ctx.extra().get(b'hg-git', None) in olist

        parents = []
        if ctx.extra().get(b'hg-git', None) == b'octopus-done':
            # implode octopus parents
            part = ctx
            while is_octopus_part(part):
                (p1, p2) = part.parents()
                assert ctx.extra().get(b'hg-git', None) != b'octopus'
                parents.append(p1)
                part = p2
            parents.append(p2)
        else:
            parents = ctx.parents()

        return parents

    def get_git_message_and_extra(self, ctx):
        extra = ctx.extra()

        message = ctx.description() + b"\n"
        if b'message' in extra:
            try:
                message = b"".join(apply_delta(message, extra[b'message']))
            except (ApplyDeltaError, AssertionError):
                self.ui.traceback()
                self.ui.warn(
                    b"warning: disregarding possibly invalid metadata in %s\n"
                    % ctx
                )

        # HG EXTRA INFORMATION

        # test only -- do not document this!
        extra_in_message = self.ui.configbool(b'git', b'debugextrainmessage')
        extra_message = b''
        git_extra = []
        if ctx.branch() != b'default':
            # we always store the branch in the extra message
            extra_message += b"branch : " + ctx.branch() + b"\n"

        # Git native extra items always come first, followed by hg renames,
        # followed by hg extra keys
        git_extraitems = []
        for key, value in extra.items():
            m = RE_GIT_EXTRA_KEY.match(key)
            if m is not None:
                git_extraitems.append((int(m.group(1)), m.group(2), value))
                del extra[key]

        git_extraitems.sort()
        for i, field, value in git_extraitems:
            git_extra.append(
                (hgutil.urlreq.unquote(field), hgutil.urlreq.unquote(value))
            )

        if extra.get(b'hg-git-rename-source', None) != b'git':
            renames = []
            for f in ctx.files():
                if f not in ctx.manifest():
                    continue
                rename = ctx.filectx(f).renamed()
                if rename:
                    renames.append((rename[0], f))

            if renames:
                for oldfile, newfile in renames:
                    if extra_in_message:
                        extra_message += (
                            b"rename : " + oldfile + b" => " + newfile + b"\n"
                        )
                    else:
                        spec = b'%s:%s' % (
                            hgutil.urlreq.quote(oldfile),
                            hgutil.urlreq.quote(newfile),
                        )
                        git_extra.append((b'HG:rename', spec))

        # hg extra items always go at the end
        for key, value in sorted(extra.items()):
            if key in (
                b'author',
                b'committer',
                b'encoding',
                b'message',
                b'branch',
                b'hg-git',
                b'hg-git-rename-source',
            ):
                continue
            else:
                if extra_in_message:
                    extra_message += (
                        b"extra : "
                        + key
                        + b" : "
                        + hgutil.urlreq.quote(value)
                        + b"\n"
                    )
                else:
                    spec = b'%s:%s' % (
                        hgutil.urlreq.quote(key),
                        hgutil.urlreq.quote(value),
                    )
                    git_extra.append((b'HG:extra', spec))

        if extra_message:
            message += b"\n--HG--\n" + extra_message

        if (
            extra.get(b'hg-git-rename-source', None) != b'git'
            and not extra_in_message
            and not git_extra
            and extra_message == b''
        ):
            # We need to store this if no other metadata is stored. This
            # indicates that when reimporting the commit into Mercurial we'll
            # know not to detect renames.
            git_extra.append((b'HG:rename-source', b'hg'))

        return message, git_extra

    def get_git_incoming(self, refs, remote_names):
        return git2hg.find_incoming(
            self.ui,
            self.git.object_store,
            self._map_git,
            refs,
            remote_names,
        )

    def get_transaction(self, desc=b"hg-git"):
        """obtain a transaction specific for the repository

        this ensures that we only save the map on close

        """
        tr = self.repo.transaction(desc)

        tr.addfinalize(b'hg-git-save', lambda tr: self.save_map(self.map_file))
        scmutil.registersummarycallback(self.repo, tr, b'pull')

        return tr

    def get_result_head(self, result):
        symref = result.symrefs.get(b'HEAD')

        if symref and symref.startswith(LOCAL_BRANCH_PREFIX):
            rhead = symref[len(LOCAL_BRANCH_PREFIX) :]

            if symref in result.refs:
                rsha = result.refs.get(symref)
            else:
                rsha = None
        else:
            rhead = None
            rsha = result.refs.get(b'HEAD')

        if rsha is not None and rsha in self._map_git:
            return rhead, bin(self._map_git[rsha])
        else:
            return None, None

    def import_git_objects(self, command, remote_names, refs, heads=None):
        self.repo.hook(
            b'gitimport',
            source=command,
            git=True,
            names=remote_names,
            refs=refs,
            heads=heads,
        )

        filteredrefs = git2hg.filter_refs(self.filter_min_date(refs), heads)
        commits = self.get_git_incoming(filteredrefs, remote_names)
        # import each of the commits, oldest first
        total = len(commits)
        if total:
            self.ui.status(_(b"importing %d git commits\n") % total)
        else:
            self.ui.status(_(b"no changes found\n"))

        # don't bother saving the map if we're in a clone, as Mercurial
        # deletes the repository on errors
        if self.is_clone:
            mapsavefreq = 0
        else:
            mapsavefreq = self.ui.configint(b'hggit', b'mapsavefrequency')

        chunksize = max(mapsavefreq or total, 1)
        progress = self.ui.makeprogress(
            b'importing', unit=b'commits', total=total
        )

        self.ui.note(b"processing commits in batches of %d\n" % chunksize)

        with progress, self.repo.lock():
            # the weird range below speeds up conversion by batching
            # commits in a transaction, while ensuring that we always
            # get at least one chunk
            for offset in range(0, max(total, 1), chunksize):
                with self.get_transaction(b"gimport"):
                    cl = self.repo.unfiltered().changelog
                    oldtiprev = cl.tiprev()

                    for commit in commits[offset : offset + chunksize]:
                        progress.increment(item=commit.short)
                        self.import_git_commit(
                            command,
                            self.git[commit.sha],
                            commit.phase,
                        )

                    lastrev = cl.tiprev()

                    self.import_tags(refs)
                    self.update_hg_bookmarks(remote_names, refs)
                    self.update_remote_branches(remote_names, refs)

                    if oldtiprev != lastrev:
                        first = cl.node(oldtiprev + 1)
                        last = cl.node(lastrev)

                        self.repo.hook(
                            b"changegroup",
                            source=b'push',
                            git=True,
                            node=hex(first),
                            node_last=hex(last),
                        )

        # TODO if the tags cache is used, remove any dangling tag references
        return total

    def import_git_commit(self, command, commit, phase):
        self.ui.debug(_(b"importing: %s\n") % commit.id)
        unfiltered = self.repo.unfiltered()

        detect_renames = False
        (
            strip_message,
            hg_renames,
            hg_branch,
            extra,
        ) = git2hg.extract_hg_metadata(commit.message, commit._extra)
        if hg_renames is None:
            detect_renames = True
            # We have to store this unconditionally, even if there are no
            # renames detected from Git. This is because we export an extra
            # 'HG:rename-source' Git parameter when this isn't set, which will
            # break bidirectionality.
            extra[b'hg-git-rename-source'] = b'git'
        else:
            renames = hg_renames

        gparents = pycompat.maplist(self.map_hg_get, commit.parents)

        for parent in gparents:
            if parent not in unfiltered:
                raise error.Abort(
                    _(
                        b'you appear to have run strip - '
                        b'please run hg git-cleanup'
                    )
                )

        # get a list of the changed, added, removed files and gitlinks
        files, gitlinks, git_renames = self.get_files_changed(
            commit, detect_renames
        )
        if detect_renames:
            renames = git_renames

        git_commit_tree = self.git[commit.tree]

        # Analyze hgsubstate and build an updated version using SHAs from
        # gitlinks. Order of application:
        # - preexisting .hgsubstate in git tree
        # - .hgsubstate from hg parent
        # - changes in gitlinks
        hgsubstate = util.parse_hgsubstate(
            git2hg.git_file_readlines(self.git, git_commit_tree, b'.hgsubstate')
        )
        parentsubdata = b''
        if gparents:
            p1ctx = unfiltered[gparents[0]]
            if b'.hgsubstate' in p1ctx:
                parentsubdata = p1ctx.filectx(b'.hgsubstate').data()
                parentsubdata = parentsubdata.splitlines()
                parentsubstate = util.parse_hgsubstate(parentsubdata)
                for path, sha in parentsubstate.items():
                    hgsubstate[path] = sha
        for path, sha in gitlinks.items():
            if sha is None:
                hgsubstate.pop(path, None)
            else:
                hgsubstate[path] = sha
        # in case .hgsubstate wasn't among changed files
        # force its inclusion if it wasn't already deleted
        hgsubdeleted = files.get(b'.hgsubstate')
        if hgsubdeleted:
            hgsubdeleted = hgsubdeleted[0]
        if hgsubdeleted or (not hgsubstate and parentsubdata):
            files[b'.hgsubstate'] = True, None, None
        elif util.serialize_hgsubstate(hgsubstate) != parentsubdata:
            files[b'.hgsubstate'] = False, 0o100644, None

        # Analyze .hgsub and merge with .gitmodules
        hgsub = None
        try:
            gitmodules = git2hg.parse_gitmodules(self.git, git_commit_tree)
        except KeyError:
            gitmodules = None
        except ValueError:
            self.ui.traceback()
            self.ui.warn(
                b'warning: failed to parse .gitmodules in %s\n'
                % commit.id[:12],
            )
            gitmodules = None

        if gitmodules is not None:
            hgsub = util.parse_hgsub(
                git2hg.git_file_readlines(self.git, git_commit_tree, b'.hgsub')
            )
            for sm_path, sm_url, sm_name in gitmodules:
                hgsub[sm_path] = b'[git]' + sm_url
            for path in hgsubstate.keys() - hgsub.keys():
                del hgsubstate[path]
            files[b'.hgsub'] = (False, 0o100644, None)
            files.pop(b'.gitmodules', None)
        elif (
            commit.parents
            and b'.gitmodules' in self.git[self.git[commit.parents[0]].tree]
        ):
            # no .gitmodules in this commit, however present in the parent
            # mark its hg counterpart as deleted (assuming .hgsub is there
            # due to the same import_git_commit process
            files[b'.hgsub'] = (True, 0o100644, None)

        date = (commit.author_time, -commit.author_timezone)
        text = strip_message

        origtext = text
        try:
            text.decode('utf-8')
        except UnicodeDecodeError:
            text = util.decode_guess(text, commit.encoding)

        text = b'\n'.join(l.rstrip() for l in text.splitlines()).strip(b'\n')
        if text + b'\n' != origtext:
            extra[b'message'] = util.create_delta(text + b'\n', origtext)

        author = commit.author

        # convert extra data back to the end
        if b' ext:' in commit.author:
            m = RE_GIT_AUTHOR_EXTRA.match(commit.author)
            if m:
                name = m.group(1)
                ex = hgutil.urlreq.unquote(m.group(2))
                email = m.group(3)
                author = name + b' <' + email + b'>' + ex

        if b' <none@none>' in commit.author:
            author = commit.author[:-12]

        try:
            author.decode('utf-8')
        except UnicodeDecodeError:
            origauthor = author
            author = util.decode_guess(author, commit.encoding)
            extra[b'author'] = util.create_delta(author, origauthor)

        oldenc = util.swap_out_encoding()

        def findconvergedfiles(p1, p2):
            # If any files have the same contents in both parents of a merge
            # (and are therefore not reported as changed by Git) but are at
            # different file revisions in Mercurial (because they arrived at
            # those contents in different ways), we need to include them in
            # the list of changed files so that Mercurial can join up their
            # filelog histories (same as if the merge was done in Mercurial to
            # begin with).
            if p2 == nullid:
                return []
            manifest1 = unfiltered[p1].manifest()
            manifest2 = unfiltered[p2].manifest()
            return [
                path
                for path, node1 in manifest1.items()
                if path not in files and manifest2.get(path, node1) != node1
            ]

        def getfilectx(repo, memctx, f):
            info = files.get(f)
            if info is not None:
                # it's a file reported as modified from Git
                delete, mode, sha = info
                if delete:
                    return None

                if not sha:  # indicates there's no git counterpart
                    e = b''
                    copied_path = None
                    if b'.hgsubstate' == f:
                        data = util.serialize_hgsubstate(hgsubstate)
                    elif b'.hgsub' == f:
                        data = util.serialize_hgsub(hgsub)
                else:
                    data = self.git[sha].data
                    copied_path = renames.get(f)
                    e = git2hg.convert_git_int_mode(mode)
            else:
                # it's a converged file
                fc = context.filectx(unfiltered, f, changeid=memctx.p1().rev())
                data = fc.data()
                e = fc.flags()
                copied_path = None
                copied = fc.renamed()
                if copied:
                    copied_path = copied[0]

            return context.memfilectx(
                unfiltered,
                memctx,
                f,
                data,
                islink=b'l' in e,
                isexec=b'x' in e,
                copysource=copied_path,
            )

        p1, p2 = (nullid, nullid)
        octopus = False

        if len(gparents) > 1:
            # merge, possibly octopus
            def commit_octopus(p1, p2):
                ctx = context.memctx(
                    unfiltered,
                    (p1, p2),
                    text,
                    list(files) + findconvergedfiles(p1, p2),
                    getfilectx,
                    author,
                    date,
                    {b'hg-git': b'octopus'},
                )
                # See comment below about setting substate to None.
                ctx.substate = None
                with util.forcedraftcommits():
                    return hex(unfiltered.commitctx(ctx))

            octopus = len(gparents) > 2
            p2 = gparents.pop()
            p1 = gparents.pop()
            while len(gparents) > 0:
                p2 = commit_octopus(p1, p2)
                p1 = gparents.pop()
        else:
            if gparents:
                p1 = gparents.pop()

        # if named branch, add to extra
        if hg_branch:
            extra[b'branch'] = hg_branch
        else:
            extra[b'branch'] = b'default'

        # if committer is different than author, add it to extra
        if (
            commit.author != commit.committer
            or commit.author_time != commit.commit_time
            or commit.author_timezone != commit.commit_timezone
        ):
            extra[b'committer'] = b"%s %d %d" % (
                commit.committer,
                commit.commit_time,
                -commit.commit_timezone,
            )

        if commit.encoding:
            extra[b'encoding'] = commit.encoding
        if commit.gpgsig:
            extra[b'gpgsig'] = commit.gpgsig

        if octopus:
            extra[b'hg-git'] = b'octopus-done'

        ctx = context.memctx(
            unfiltered,
            (p1, p2),
            text,
            list(files) + findconvergedfiles(p1, p2),
            getfilectx,
            author,
            date,
            extra,
        )

        # Starting Mercurial commit d2743be1bb06, memctx imports from
        # committablectx. This means that it has a 'substate' property that
        # contains the subrepo state. Ordinarily, Mercurial expects the subrepo
        # to be present while making a new commit -- since hg-git is importing
        # purely in-memory commits without backing stores for the subrepos,
        # that won't work. Forcibly set the substate to None so that there's no
        # attempt to read subrepos.
        ctx.substate = None
        with util.forcedraftcommits():
            node = unfiltered.commitctx(ctx)

        util.swap_out_encoding(oldenc)

        with self.repo.lock(), self.repo.transaction(b"phase") as tr:
            phases.advanceboundary(
                self.repo,
                tr,
                phase,
                [node],
            )

        # save changeset to mapping file
        cs = hex(node)
        self.map_set(commit.id, cs)

        self.repo.hook(
            b'incoming',
            git=True,
            source=command,
            node=cs,
            git_node=commit.id,
        )

    # PACK UPLOADING AND FETCHING

    def upload_pack(self, remote, revs, bookmarks, force):
        if bookmarks and self.branch_bookmark_suffix:
            raise error.Abort(
                b"the -B/--bookmarks option is not supported when "
                b"branch_bookmark_suffix is set",
            )

        all_exportable = self.export_commits()
        old_refs = {}
        change_totals = {}

        def changed(refs):
            self.ui.status(_(b"searching for changes\n"))
            old_refs.update(refs)
            if revs is None:
                exportable = all_exportable
            else:
                exportable = {}
                for rev in (hex(r) for r in revs):
                    if rev == nullhex:
                        # a deletion
                        exportable[rev] = heads_tags(
                            heads={
                                LOCAL_BRANCH_PREFIX + bm
                                for bm in bookmarks
                                if bm not in self.repo._bookmarks
                            }
                        )
                    elif rev not in all_exportable:
                        raise error.Abort(
                            b"revision %s cannot be pushed since"
                            b" it doesn't have a bookmark" % self.repo[rev]
                        )
                    elif bookmarks:
                        # we should only push the listed bookmarks,
                        # and not any other bookmarks that might point
                        # to the same changeset
                        exportable[rev] = heads_tags(
                            heads=all_exportable[rev].heads
                            & {LOCAL_BRANCH_PREFIX + bm for bm in bookmarks},
                        )
                    else:
                        exportable[rev] = all_exportable[rev]

            changes = self.get_changed_refs(refs, exportable, force)

            self.repo.hook(
                b"prechangegroup",
                source=b'push',
                git=True,
                url=remote,
                changes=changes,
            )

            return changes

        def genpack(have, want, progress=None, ofs_delta=True):
            commits = []

            with util.abort_push_on_keyerror():
                for sha, name in compat.MissingObjectFinder(
                    self.git.object_store,
                    have,
                    want,
                    progress=progress,
                ):
                    o = self.git.object_store[sha]
                    t = type(o)
                    change_totals[t] = change_totals.get(t, 0) + 1
                    if isinstance(o, Commit):
                        commits.append(sha)

                        self.repo.hook(
                            b"outgoing",
                            source=b'push',
                            git=True,
                            url=remote,
                            node=self.map_hg_get(sha),
                            git_node=sha,
                        )

            commit_count = len(commits)
            self.ui.note(_(b"%d commits found\n") % commit_count)
            if commit_count > 0:
                self.ui.debug(_(b"list of commits:\n"))
                for commit in commits:
                    self.ui.debug(b"%s\n" % commit)
                self.ui.status(_(b"adding objects\n"))
            return self.git.object_store.generate_pack_data(
                have,
                want,
                progress=progress or progressfunc,
                ofs_delta=ofs_delta,
            )

        progress = GitProgress(self.ui)
        progressfunc = progress.progress

        try:
            new_refs = self._call_client(
                remote, 'send_pack', changed, genpack, progress=progressfunc
            )

            if len(change_totals) > 0:
                self.ui.status(
                    _(b"added %d commits with %d trees" b" and %d blobs\n")
                    % (
                        change_totals.get(Commit, 0),
                        change_totals.get(Tree, 0),
                        change_totals.get(Blob, 0),
                    )
                )
            return old_refs, new_refs
        except (HangupException, GitProtocolError) as e:
            raise error.Abort(
                _(b"git remote error: ") + pycompat.sysbytes(str(e))
            )
        finally:
            progress.flush()

    def get_changed_refs(self, refs, exportable, force):
        new_refs = refs.copy()

        if not any(exportable.values()):
            raise error.Abort(
                b'no bookmarks or tags to push to git',
                hint=b'see "hg help bookmarks" for details on creating them',
            )

        # mapped nodes might be hidden
        unfiltered = self.repo.unfiltered()
        for rev, rev_refs in exportable.items():
            ctx = self.repo[rev]

            # Check if the tags the server is advertising are annotated tags,
            # by attempting to retrieve it from the our git repo, and building
            # a list of these tags.
            #
            # This is possible, even though (currently) annotated tags are
            # dereferenced and stored as lightweight ones, as the annotated tag
            # is still stored in the git repo.
            uptodate_annotated_tags = []
            for ref in rev_refs.tags:
                # Check tag.
                if ref not in refs:
                    continue
                try:
                    # We're not using Repo.tag(), as it's deprecated.
                    tag = self.git.get_object(refs[ref])
                    if not isinstance(tag, Tag):
                        continue
                except KeyError:
                    continue

                # If we've reached here, the tag's good.
                uptodate_annotated_tags.append(ref)

            for ref in rev_refs:
                if ctx.node() == nullid:
                    if ref not in new_refs:
                        # this is reasonably consistent with
                        # mercurial; git aborts with an error in this
                        # case
                        self.ui.warn(
                            b"warning: unable to delete '%s' as it does not "
                            b"exist on the remote repository\n" % ref,
                        )
                    else:
                        new_refs[ref] = nullhex
                elif (
                    not util.ref_exists(ref, self.git.refs)
                    and ref not in new_refs
                ):
                    self.ui.warn(b"warning: cannot update '%s'\n" % ref)
                elif ref not in refs:
                    if ref not in self.git.refs:
                        self.ui.note(
                            b'note: cannot update %s\n' % (ref),
                        )
                    else:
                        gitobj = self.git.get_object(self.git.refs[ref])
                        if isinstance(gitobj, Tag):
                            new_refs[ref] = gitobj.id
                        else:
                            new_refs[ref] = self.map_git_get(ctx.hex())
                elif new_refs[ref] in self._map_git:
                    rctx = unfiltered[self.map_hg_get(new_refs[ref])]
                    if rctx.ancestor(ctx) == rctx or force:
                        new_refs[ref] = self.map_git_get(ctx.hex())
                    else:
                        raise error.Abort(
                            b"pushing %s overwrites %s" % (ref, ctx)
                        )
                elif ref in uptodate_annotated_tags:
                    # we already have the annotated tag.
                    pass
                else:
                    raise error.Abort(
                        b"branch '%s' changed on the server, "
                        b"please pull and merge before pushing" % ref
                    )

        return new_refs

    def fetch_pack(self, remote, heads=None):
        # The dulwich default walk only checks refs/heads/. We also want to
        # consider remotes when doing discovery, so we build our own list. We
        # can't just do 'refs/' here because the tag class doesn't have a
        # parents function for walking, and older versions of dulwich don't
        # like that.
        haveheads = list(self.git.refs.as_dict(REMOTE_BRANCH_PREFIX).values())
        haveheads.extend(self.git.refs.as_dict(LOCAL_BRANCH_PREFIX).values())
        graphwalker = self.git.get_graph_walker(heads=haveheads)

        def determine_wants(refs):
            if refs is None:
                return None
            filteredrefs = git2hg.filter_refs(refs, heads)
            return [x for x in filteredrefs.values() if x not in self.git]

        progress = GitProgress(self.ui)

        try:
            with util.add_pack(self.git.object_store) as f:
                ret = self._call_client(
                    remote,
                    'fetch_pack',
                    determine_wants,
                    graphwalker,
                    f.write,
                    progress.progress,
                )

            # For empty repos dulwich gives us None, but since later
            # we want to iterate over this, we really want an empty
            # iterable
            if ret is None:
                ret = {}

            return ret
        except (HangupException, GitProtocolError) as e:
            raise error.Abort(
                _(b"git remote error: ") + pycompat.sysbytes(str(e))
            )
        finally:
            progress.flush()

    def _call_client(self, remote, method, *args, **kwargs):
        if not isinstance(remote, bytes):
            remote = remote.loc

        if remote in self._clients:
            clientobj, path = self._clients[remote]
            return getattr(clientobj, method)(path, *args, **kwargs)

        for ignored in range(self.ui.configint(b'hggit', b'retries')):
            clientobj, path = self._get_transport_and_path(remote)
            func = getattr(clientobj, method)

            try:
                ret = func(path, *args, **kwargs)

                # it worked, so save the client for later!
                self._clients[remote] = clientobj, path

                return ret

            except (HTTPUnauthorized, GitProtocolError) as e:
                self.ui.traceback()

                if isinstance(e, HTTPUnauthorized):
                    # this is a fallback just in case the header isn't
                    # specified
                    self._http_auth_realm = 'Git'
                    if e.www_authenticate:
                        m = re.search(r'realm="([^"]*)"', e.www_authenticate)
                        if m:
                            self._http_auth_realm = m.group(1)

                elif 'unexpected http resp 407' in e.args[0]:
                    raise error.Abort(
                        b'HTTP proxy requires authentication',
                    )
                else:
                    raise

        raise error.Abort(_(b'authorization failed'))

    # REFERENCES HANDLING

    def filter_min_date(self, refs):
        '''filter refs by minimum date

        This only works for refs that are available locally.'''
        min_date = self.ui.config(b'git', b'mindate')
        if min_date is None:
            return refs

        # filter refs older than min_timestamp
        min_timestamp, min_offset = dateutil.parsedate(min_date)

        def check_min_time(obj):
            if isinstance(obj, Tag):
                return obj.tag_time >= min_timestamp
            else:
                return obj.commit_time >= min_timestamp

        return collections.OrderedDict(
            (ref, sha)
            for ref, sha in refs.items()
            if check_min_time(self.git[sha])
        )

    def update_references(self):
        exportable = self.get_exportable()

        # Create a local Git branch name for each
        # Mercurial bookmark.
        for hg_sha, refs in exportable.items():
            for git_ref in refs.heads:
                git_sha = self.map_git_get(hg_sha)
                # prior to 0.20.22, dulwich couldn't handle refs
                # pointing to missing objects, so don't add them
                if git_sha and git_sha in self.git:
                    util.set_refs(self.ui, self.git, {git_ref: git_sha})

        return exportable

    def export_hg_tags(self):
        new_refs = {}

        for tag, sha in self.repo.tags().items():
            if self.repo.tagtype(tag) in (b'global', b'git'):
                tag = tag.replace(b' ', b'_')
                target = self.map_git_get(hex(sha))

                if target is None:
                    self.repo.ui.warn(
                        b"warning: not exporting tag '%s' "
                        b"due to missing git "
                        b"revision\n" % tag
                    )
                    continue

                tag_refname = LOCAL_TAG_PREFIX + tag

                if not check_ref_format(tag_refname):
                    self.repo.ui.warn(
                        b"warning: not exporting tag '%s' "
                        b"due to invalid name\n" % tag
                    )
                    continue

                # check whether the tag already exists and is
                # annotated
                if util.ref_exists(tag_refname, self.git.refs):
                    reftarget = self.git.refs[tag_refname]
                    try:
                        peeledtarget = self.git.get_peeled(tag_refname)
                    except KeyError:
                        self.ui.note(
                            b'note: failed to peel tag %s' % (tag_refname)
                        )
                        peeledtarget = None

                    if peeledtarget != reftarget:
                        # warn the user if they tried changing the tag
                        if target != peeledtarget:
                            self.repo.ui.warn(
                                b"warning: not overwriting annotated "
                                b"tag '%s'\n" % tag
                            )

                        # and never overwrite annotated tags,
                        # otherwise it'd happen on every pull
                        target = reftarget

                new_refs[tag_refname] = target
                self.tags[tag] = hex(sha)

        if new_refs:
            util.set_refs(self.ui, self.git, new_refs)

    def get_filtered_bookmarks(self):
        bms = self.repo._bookmarks

        if not self.branch_bookmark_suffix:
            return [(bm, bm, n) for bm, n in bms.items()]
        else:

            def _filter_bm(bm):
                if bm.endswith(self.branch_bookmark_suffix):
                    return bm[0 : -(len(self.branch_bookmark_suffix))]
                else:
                    return bm

            return [(_filter_bm(bm), bm, n) for bm, n in bms.items()]

    def get_exportable(self):
        res = collections.defaultdict(heads_tags)

        for filtered_bm, bm, node in self.get_filtered_bookmarks():
            ref_name = LOCAL_BRANCH_PREFIX + filtered_bm
            if node not in self.repo.filtered(b'served'):
                # technically, we don't _know_ that it's secret,
                # but it's a very good guess
                self.repo.ui.warn(
                    b"warning: not exporting secret bookmark '%s'\n" % bm
                )
            elif check_ref_format(ref_name):
                res[hex(node)].heads.add(ref_name)
            else:
                self.repo.ui.warn(
                    b"warning: not exporting bookmark '%s' "
                    b"due to invalid name\n" % bm
                )

        for tag, sha in self.tags.items():
            res[sha].tags.add(LOCAL_TAG_PREFIX + tag)
        return res

    def import_tags(self, refs):
        if not refs:
            return
        repotags = self.repo.tags()
        for k in refs:
            if k.startswith(LOCAL_TAG_PREFIX):
                ref_name = k[len(LOCAL_TAG_PREFIX) :]

                # refs contains all the refs in the server, not just
                # the ones we are pulling
                if refs[k] not in self.git.object_store:
                    continue
                if ref_name.endswith(ANNOTATED_TAG_SUFFIX):
                    continue

                util.set_refs(self.ui, self.git, {k: refs[k]})

                if ref_name not in repotags:
                    sha = self.map_hg_get(refs[k], deref=True)
                    if sha is not None and sha is not None:
                        self.tags[ref_name] = sha

        self.save_tags()

    def add_tag(self, target, *tags):
        for tag in tags:
            scmutil.checknewlabel(self.repo, tag, b'tag')

            # -f/--force is deliberately unimplemented and unmentioned
            # as its git semantics are quite confusing
            if scmutil.isrevsymbol(self.repo, tag):
                raise error.Abort(b"the name '%s' already exists" % tag)

            if check_ref_format(LOCAL_TAG_PREFIX + tag):
                self.ui.debug(b'adding git tag %s\n' % tag)
                self.tags[tag] = target
            else:
                raise error.Abort(
                    b"the name '%s' is not a valid git " b"tag" % tag
                )

        self.export_commits()
        self.save_tags()

    def _get_ref_nodes(self, remote_names, refs):
        """get a {ref_name → node} mapping

        We generally assume that `refs` contains all the refs in the
        server, not just the ones we are pulling.

        Please note that this function returns binary node ids. A node
        ID of `nullid` means that the commit isn't present locally;
        `None` means that the branch was deleted.

        """
        ref_nodes = {}

        for ref, git_sha in refs.items():
            if not ref.startswith(LOCAL_BRANCH_PREFIX):
                continue

            h = ref[len(LOCAL_BRANCH_PREFIX) :]
            hg_sha = self.map_hg_get(git_sha)

            # refs contains all the refs in the server,
            # not just the ones we are pulling
            ref_nodes[h] = bin(hg_sha) if hg_sha is not None else nullid

        # detect deletions; do this last to retain ordering
        if self.ui.configbool(b'git', b'pull-prune-bookmarks'):
            for remote_name in remote_names:
                prefix = remote_name + b'/'
                for remote_ref in self.remote_refs:
                    if remote_ref.startswith(prefix):
                        h = remote_ref[len(prefix) :]
                        ref_nodes.setdefault(h, None)

        return ref_nodes

    def update_hg_bookmarks(self, remote_names, refs):
        bms = self.repo._bookmarks
        unfiltered = self.repo.unfiltered()
        changes = []

        for ref_name, wanted_node in self._get_ref_nodes(
            remote_names, refs
        ).items():
            bm = ref_name + (self.branch_bookmark_suffix or b'')
            current_node = bms.get(bm)

            if current_node is not None and current_node == wanted_node:
                self.ui.note(_(b"bookmark %s is up-to-date\n") % bm)

            elif wanted_node == nullid:
                self.ui.note(_(b"bookmark %s is not known yet\n") % bm)

            elif wanted_node is None and current_node is None:
                self.ui.note(b"bookmark %s is deleted locally as well\n" % bm)

            elif wanted_node is None:
                # possibly deleted branch, check if we have a
                # matching remote ref
                unmoved = any(
                    self.remote_refs.get(b'%s/%s' % (remote_name, ref_name))
                    == current_node
                    for remote_name in remote_names
                )

                # only delete unmoved bookmarks
                if unmoved:
                    changes.append((bm, None))
                    self.ui.status(_(b"deleting bookmark %s\n") % bm)
                else:
                    self.ui.status(b"not deleting diverged bookmark %s\n" % bm)

            elif current_node is None:
                # new branch
                changes.append((bm, wanted_node))

                # only log additions on subsequent pulls
                if not self.is_clone:
                    self.ui.status(_(b"adding bookmark %s\n") % bm)

            elif unfiltered[current_node].isancestorof(unfiltered[wanted_node]):
                # fast forward
                changes.append((bm, wanted_node))
                self.ui.status(_(b"updating bookmark %s\n") % bm)

            elif unfiltered.obsstore and wanted_node in obsutil.foreground(
                unfiltered, [current_node]
            ):
                # this is fast-forward or a rebase, across
                # obsolescence markers too. (ideally we would have
                # a background thingy that is more efficient that
                # the foreground one.)
                changes.append((bm, wanted_node))
                self.ui.status(_(b"updating bookmark %s\n") % bm)

            else:
                self.ui.status(
                    _(b"not updating diverged bookmark %s\n") % bm,
                )

        if changes:
            with self.repo.wlock(), self.repo.lock():
                with self.repo.transaction(b"hg-git") as tr:
                    bms.applychanges(self.repo, tr, changes)

    def _update_remote_branches_for(self, remote_name, refs):
        remote_refs = self.remote_refs

        if self.ui.configbool(b'git', b'pull-prune-remote-branches'):
            # since we re-write all refs for this remote each time,
            # prune all entries matching this remote from our refs
            # list now so that we avoid any stale refs hanging around
            # forever
            for t in list(remote_refs):
                if t.startswith(remote_name + b'/'):
                    del remote_refs[t]
                    if (
                        LOCAL_BRANCH_PREFIX + t[len(remote_name) + 1 :]
                        not in refs
                    ):
                        del self.git.refs[REMOTE_BRANCH_PREFIX + t]

        for ref_name, sha in refs.items():
            if ref_name.endswith(ANNOTATED_TAG_SUFFIX):
                # the sha points to a peeled tag; we should either
                # pick it up through the tag itself, or ignore it
                continue

            hgsha = self.map_hg_get(sha, deref=True)

            if (
                ref_name.startswith(LOCAL_BRANCH_PREFIX)
                and hgsha is not None
                and hgsha in self.repo
            ):
                head = ref_name[len(LOCAL_BRANCH_PREFIX) :]
                remote_head = b'/'.join((remote_name, head))

                # actually update the remote ref
                remote_refs[remote_head] = bin(hgsha)
                new_ref = REMOTE_BRANCH_PREFIX + remote_head

                util.set_refs(self.ui, self.git, {new_ref: sha})

    def update_remote_branches(self, remote_names, refs):
        for remote_name in remote_names:
            self._update_remote_branches_for(remote_name, refs)

        with self.repo.lock(), self.repo.transaction(b"hg-git-phases") as tr:
            all_remote_nodeids = set()

            for ref_name, sha in refs.items():
                hgsha = self.map_hg_get(sha)

                if hgsha:
                    all_remote_nodeids.add(bin(hgsha))

            # sanity check: ensure that all corresponding commits
            # are at least draft; this can happen on no-op pulls
            # where the commit already exists, but is secret
            phases.advanceboundary(
                self.repo,
                tr,
                phases.draft,
                all_remote_nodeids,
            )

            # ensure that we update phases on push and no-op pulls
            nodeids_to_publish = set()

            for sha in git2hg.get_public(self.ui, refs, remote_names):
                hgsha = self.map_hg_get(sha, deref=True)
                if hgsha:
                    nodeids_to_publish.add(bin(hgsha))

            phases.advanceboundary(
                self.repo,
                tr,
                phases.public,
                nodeids_to_publish,
            )

    # UTILITY FUNCTIONS

    def get_file(self, commit, f):
        otree = self.git.tree(commit.tree)
        parts = f.split(b'/')
        for part in parts:
            (mode, sha) = otree[part]
            obj = self.git.get_object(sha)
            if isinstance(obj, Blob):
                return (mode, sha, obj._text)
            elif isinstance(obj, Tree):
                otree = obj

    def get_files_changed(self, commit, detect_renames):
        tree = commit.tree
        btree = None

        if commit.parents:
            btree = self.git[commit.parents[0]].tree

        files = {}
        gitlinks = {}
        renames = None
        rename_detector = None
        if detect_renames:
            renames = {}
            rename_detector = self._rename_detector

        # this set is unused if rename detection isn't enabled -- that makes
        # the code below simpler
        renamed_out = set()

        changes = diff_tree.tree_changes(
            self.git.object_store, btree, tree, rename_detector=rename_detector
        )

        for change in changes:
            oldfile, oldmode, oldsha = change.old
            newfile, newmode, newsha = change.new
            # actions are described by the following table ('no' means 'does
            # not exist'):
            #    old        new     |    action
            #     no        file    |  record file
            #     no      gitlink   |  record gitlink
            #    file        no     |  delete file
            #    file       file    |  record file
            #    file     gitlink   |  delete file and record gitlink
            #  gitlink       no     |  delete gitlink
            #  gitlink      file    |  delete gitlink and record file
            #  gitlink    gitlink   |  record gitlink
            #
            # There's an edge case here -- symlink <-> regular file transitions
            # are returned by dulwich as separate deletes and adds, not
            # modifications. The order of those results is unspecified and
            # could be either way round. Handle both cases: delete first, then
            # add -- delete stored in 'old = file' case, then overwritten by
            # 'new = file' case. add first, then delete -- record stored in
            # 'new = file' case, then membership check fails in 'old = file'
            # case so is not overwritten there. This is not an issue for
            # gitlink <-> {symlink, regular file} transitions because they
            # write to separate dictionaries.
            #
            # There's a similar edge case when rename detection is enabled: if
            # a file is renamed and then replaced by a symlink (typically to
            # the new location), it is returned by dulwich as an add and a
            # rename. The order of those results is unspecified. Handle both
            # cases: rename first, then add -- delete stored in 'new = file'
            # case with renamed_out, then renamed_out check passes in 'old =
            # file' case so is overwritten. add first, then rename -- add
            # stored in 'old = file' case, then membership check fails in 'new
            # = file' case so is overwritten.
            if newmode == 0o160000:
                if not self.audit_hg_path(newfile):
                    # disregard illegal or inconvenient paths
                    continue
                # new = gitlink
                gitlinks[newfile] = newsha
                if change.type == diff_tree.CHANGE_RENAME:
                    # don't record the rename because only file -> file renames
                    # make sense in Mercurial
                    gitlinks[oldfile] = None
                if oldmode is not None and oldmode != 0o160000:
                    # file -> gitlink
                    files[oldfile] = True, None, None
                continue
            if oldmode == 0o160000 and newmode != 0o160000:
                # gitlink -> no/file (gitlink -> gitlink is covered above)
                gitlinks[oldfile] = None
                continue
            if newfile is not None:
                if not self.audit_hg_path(newfile):
                    continue
                # new = file
                files[newfile] = False, newmode, newsha
                if renames is not None and newfile != oldfile:
                    renames[newfile] = oldfile
                    renamed_out.add(oldfile)
                    # the membership check is explained in a comment above
                    if (
                        change.type == diff_tree.CHANGE_RENAME
                        and oldfile not in files
                    ):
                        files[oldfile] = True, None, None
            else:
                # old = file
                #   files  renamed_out  |  action
                #     no       *        |   write
                #    yes       no       |  ignore
                #    yes      yes       |   write
                if oldfile not in files or oldfile in renamed_out:
                    files[oldfile] = True, None, None

        return files, gitlinks, renames

    @hgutil.propertycache
    def _rename_detector(self):
        # disabled by default to avoid surprises
        similarity = self.ui.configint(b'git', b'similarity')
        if similarity < 0 or similarity > 100:
            raise error.Abort(_(b'git.similarity must be between 0 and 100'))
        if similarity == 0:
            return None

        # default is borrowed from Git
        max_files = self.ui.configint(b'git', b'renamelimit')
        if max_files < 0:
            raise error.Abort(_(b'git.renamelimit must be non-negative'))
        if max_files == 0:
            max_files = None

        find_copies_harder = self.ui.configbool(b'git', b'findcopiesharder')
        return diff_tree.RenameDetector(
            self.git.object_store,
            rename_threshold=similarity,
            max_files=max_files,
            find_copies_harder=find_copies_harder,
        )

    def remote_names(self, remote, push):
        if not isinstance(remote, bytes):
            return [remote.name] if remote.name is not None else []

        names = set()
        url = urlutil.url(remote)

        if url.islocal() and not url.isabs():
            remote = os.path.abspath(url.localpath())

        for name, paths in self.ui.paths.items():
            for path in paths:
                # ignore aliases
                if hasattr(path, 'raw_url') and path.raw_url.scheme == b'path':
                    continue
                if push:
                    loc = compat.get_push_location(path)
                else:
                    loc = path.loc
                if loc == remote:
                    names.add(name)

        return list(names)

    def audit_hg_path(self, path):
        if b'.hg' in path.split(b'/') or b'\r' in path or b'\n' in path:
            ui = self.ui

            # escape the path when printing it out
            prettypath = path.decode('latin1').encode('unicode-escape')

            opt = ui.config(b'hggit', b'invalidpaths')
            if opt == b'abort':
                raise error.Abort(
                    b"invalid path '%s' rejected by configuration" % prettypath,
                    hint=b"see 'hg help config.hggit.invalidpaths for details",
                )
            elif opt == b'keep' and b'\r' not in path and b'\n' not in path:
                ui.warn(
                    b"warning: path '%s' contains an invalid path component\n"
                    % prettypath,
                )
                return True
            else:
                # undocumented: just let anything else mean "skip"
                ui.warn(b"warning: skipping invalid path '%s'\n" % prettypath)
                return False

        return True

    def _get_transport_and_path(self, uri):
        """Method that sets up the transport (either ssh or http(s))

        Tests:

        >>> from dulwich.client import HttpGitClient, SSHGitClient
        >>> from mercurial import ui
        >>> class SubHandler(GitHandler):
        ...    def __init__(self):
        ...         self.ui = ui.ui()
        ...         self._http_auth_realm = None
        ...         self._pwmgr = url.passwordmgr(
        ...             self.ui, self.ui.httppasswordmgrdb,
        ...         )
        >>> tp = SubHandler()._get_transport_and_path
        >>> client, url = tp(b'http://fqdn.com/test.git')
        >>> print(isinstance(client, HttpGitClient))
        True
        >>> print(url.decode())
        http://fqdn.com/test.git
        >>> client, url = tp(b'c:/path/to/repo.git')
        >>> print(isinstance(client, SSHGitClient))
        False
        >>> client, url = tp(b'git@fqdn.com:user/repo.git')
        >>> print(isinstance(client, SSHGitClient))
        True
        >>> print(url.decode())
        user/repo.git
        >>> print(client.host)
        git@fqdn.com
        """
        # pass hg's ui.ssh config to dulwich
        if not issubclass(client.get_ssh_vendor, _ssh.SSHVendor):
            client.get_ssh_vendor = _ssh.generate_ssh_vendor(self.ui)

        # test for raw git ssh uri here so that we can reuse the logic below
        if util.isgitsshuri(uri):
            uri = b"git+ssh://" + uri

        git_match = RE_GIT_URI.match(uri)
        if git_match:
            res = git_match.groupdict()
            host, port, sepr = res['host'], res['port'], res['sepr']
            transport = client.TCPGitClient
            if b'ssh' in res['scheme']:
                util.checksafessh(pycompat.bytesurl(host))
                transport = client.SSHGitClient
            path = res['path']
            if sepr == b'/' and not path.startswith(b'~'):
                path = b'/' + path
            # strip trailing slash for heroku-style URLs
            # ssh+git://git@heroku.com:project.git/
            if sepr == b':' and path.endswith(b'.git/'):
                path = path.rstrip(b'/')
            if port:
                client.port = port

            return transport(pycompat.strurl(host), port=port), path

        if uri.startswith(b'git+http://') or uri.startswith(b'git+https://'):
            uri = uri[4:]

        if uri.startswith(b'http://') or uri.startswith(b'https://'):
            ua = b'git/20x6 (hg-git ; uses dulwich and hg ; like git-core)'
            config = dul_config.ConfigDict()
            config.set(b'http', b'useragent', ua)

            proxy = self.ui.config(b'http_proxy', b'host')

            if proxy:
                config.set(b'http', b'proxy', b'http://' + proxy)

                if self.ui.config(b'http_proxy', b'passwd'):
                    self.ui.warn(
                        b"warning: proxy authentication is unsupported\n",
                    )

            str_uri = uri.decode('utf-8')
            urlobj = urlutil.url(uri)
            auth = client.get_credentials_from_store(
                urlobj.scheme,
                urlobj.host,
                urlobj.user,
            )

            if self._http_auth_realm:
                # since we've tried an unauthenticated request, and
                # obtain a realm, we can do a "full" search, including
                # a prompt
                username, password = self._pwmgr.find_user_password(
                    self._http_auth_realm,
                    str_uri,
                )
                # NB: probably bytes here
            elif auth is not None:
                username, password = auth
                # NB: probably string here
            else:
                username, password = self._pwmgr.find_stored_password(str_uri)
                # NB: probably string here

            if isinstance(username, bytes):
                username = username.decode('utf-8')

            if isinstance(password, bytes):
                password = password.decode('utf-8')

            return (
                client.HttpGitClient(
                    str_uri,
                    config=config,
                    username=username,
                    password=password,
                ),
                uri,
            )

        if uri.startswith(b'file://'):
            return client.LocalGitClient(), urlutil.url(uri).path

        # if its not git or git+ssh, try a local url..
        return client.SubprocessGitClient(), uri
