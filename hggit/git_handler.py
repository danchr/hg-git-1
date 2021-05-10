from __future__ import absolute_import, print_function

import collections
import itertools
import io
import os
import re
import shutil

from dulwich.errors import HangupException, GitProtocolError
from dulwich.objects import Blob, Commit, Tag, Tree, parse_timezone
from dulwich.pack import create_delta, apply_delta
from dulwich.repo import Repo, check_ref_format
from dulwich import client
from dulwich import config as dul_config
from dulwich import diff_tree

from mercurial.i18n import _
from mercurial.node import hex, bin, nullid
from mercurial import (
    bookmarks,
    commands,
    context,
    encoding,
    error,
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


RE_GIT_AUTHOR = re.compile(br'^(.*?) ?\<(.*?)(?:\>(.*))?$')

RE_GIT_SANITIZE_AUTHOR = re.compile(br'[<>\n]')

RE_GIT_AUTHOR_EXTRA = re.compile(br'^(.*?)\ ext:\((.*)\) <(.*)\>$')

RE_GIT_EXTRA_KEY = re.compile(br'GIT([0-9]*)-(.*)')

# Test for git:// and git+ssh:// URI.
# Support several URL forms, including separating the
# host and path with either a / or : (sepr)
RE_GIT_URI = re.compile(
    br'^(?P<scheme>git([+]ssh)?://)(?P<host>.*?)(:(?P<port>\d+))?'
    br'(?P<sepr>[:/])(?P<path>.*)$')

RE_NEWLINES = re.compile(br'[\r\n]')
RE_GIT_PROGRESS = re.compile(br'\((\d+)/(\d+)\)')

RE_AUTHOR_FILE = re.compile(br'\s*=\s*')

# mercurial.utils.dateutil functions were in mercurial.util in Mercurial < 4.6
try:
    from mercurial.utils import dateutil
    dateutil.parsedate
except ImportError:
    dateutil = hgutil

CALLBACK_BUFFER = b''


class GitProgress(object):
    """convert git server progress strings into mercurial progress"""
    def __init__(self, ui):
        self.ui = ui

        self._progress = None
        self.msgbuf = b''

    def progress(self, msg):
        # 'Counting objects: 33640, done.\n'
        # 'Compressing objects:   0% (1/9955)   \r
        msgs = RE_NEWLINES.split(self.msgbuf + msg)
        self.msgbuf = msgs.pop()

        for msg in msgs:
            td = msg.split(b':', 1)
            data = td.pop()
            if not td:
                self.flush(data)
                continue
            topic = td[0]

            m = RE_GIT_PROGRESS.search(data)
            if m:
                if self._progress and self._progress.topic != topic:
                    self.flush()
                if not self._progress:
                    self._progress = compat.makeprogress(self.ui, topic)

                pos, total = map(int, m.group(1, 2))
                self._progress.update(pos, total=total)
            else:
                self.flush(msg)

    def flush(self, msg=None):
        if self._progress is None:
            return
        self._progress.complete()
        self._progress = None
        if msg:
            self.ui.note(msg + b'\n')


def get_repo_and_gitdir(repo):
    if repo.shared():
        repo = compat.sharedreposource(repo)

    if compat.config(repo.ui, b'bool', b'git', b'intree'):
        gitdir = repo.wvfs.join(b'.git')
    else:
        gitdir = repo.vfs.join(b'git')

    return repo, gitdir


def has_gitrepo(repo):
    if not hgutil.safehasattr(repo, b'vfs'):
        return False

    repo, gitdir = get_repo_and_gitdir(repo)

    return os.path.isdir(gitdir)


class GitHandler(object):
    map_file = b'git-mapfile'
    remote_refs_file = b'git-remote-refs'
    tags_file = b'git-tags'

    def __init__(self, dest_repo, ui):
        self.repo = dest_repo
        self.store_repo, self.gitdir = get_repo_and_gitdir(self.repo)
        self.ui = ui

        self.init_author_file()

        self.branch_bookmark_suffix = compat.config(
            ui, b'string', b'git', b'branch_bookmark_suffix')

        self._map_git_real = None
        self._map_hg_real = None
        self.load_tags()
        self._remote_refs = None

        # the HTTP authentication realm -- this specifies that we've
        # tried an unauthenticated request, gotten a realm, and are now
        # ready to prompt the user, if necessary
        self._http_auth_realm = None

    @property
    def vfs(self):
        return self.store_repo.vfs

    @property
    def _map_git(self):
        if self._map_git_real is None:
            self.load_map()
        return self._map_git_real

    @property
    def _map_hg(self):
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
        gitpath = self.gitdir.decode(pycompat.sysstr(encoding.encoding),
                                     pycompat.sysstr(encoding.encodingmode))
        # make the git data directory
        if os.path.exists(self.gitdir):
            return Repo(gitpath)
        else:
            os.mkdir(self.gitdir)
            return Repo.init_bare(gitpath)

    def init_author_file(self):
        self.author_map = {}
        authors_path = compat.config(self.ui, b'string', b'git', b'authors')
        if authors_path:
            with open(self.repo.wvfs.join(authors_path)) as f:
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

    def map_hg_get(self, gitsha):
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
                        _(b'corrupt mapfile: incorrect line length %d') %
                        len(line))
                gitsha = line[:40]
                hgsha = line[41:81]
                map_git_real[gitsha] = hgsha
                map_hg_real[hgsha] = gitsha
        self._map_git_real = map_git_real
        self._map_hg_real = map_hg_real

    def save_map(self, map_file):
        with self.store_repo.wlock():
            map_hg = self._map_hg
            with self.vfs(map_file, b'wb+', atomictemp=True) as buf:
                bwrite = buf.write
                for hgsha, gitsha in compat.iteritems(map_hg):
                    bwrite(b"%s %s\n" % (gitsha, hgsha))

    def load_tags(self):
        self.tags = {}
        if os.path.exists(self.vfs.join(self.tags_file)):
            for line in self.vfs(self.tags_file):
                sha, name = line.strip().split(b' ', 1)
                self.tags[name] = sha

    def save_tags(self):
        with self.repo.wlock(), self.store_repo.wlock():
            with self.vfs(self.tags_file, b'w+', atomictemp=True) as fp:
                for name, sha in sorted(compat.iteritems(self.tags)):
                    if not self.repo.tagtype(name) == b'global':
                        fp.write(b"%s %s\n" % (sha, name))

    def load_remote_refs(self):
        self._remote_refs = {}
        refdir = os.path.join(self.gitdir, b'refs', b'remotes')

        # if no paths are set, we should still check 'default'
        pathnames = list(self.ui.paths) or [b'default']

        # we avoid using dulwich's refs method because it is incredibly slow;
        # on a repo with a few hundred branches and a few thousand tags,
        # dulwich took about 200ms
        for pathname in pathnames:
            remotedir = os.path.join(refdir, pathname)
            for root, dirs, files in os.walk(remotedir):
                for f in files:
                    try:
                        ref = root.replace(refdir + pycompat.ossep, b'') + b'/'
                        node = open(os.path.join(root, f), 'rb').read().strip()
                        self._remote_refs[ref + f] = bin(self._map_git[node])
                    except (KeyError, IOError):
                        pass

    # END FILE LOAD AND SAVE METHODS

    # COMMANDS METHODS

    def import_commits(self, remote_name):
        refs = self.git.refs.as_dict()
        filteredrefs = self.filter_min_date(refs)
        try:
            self.import_git_objects(remote_name, filteredrefs)
            self.update_hg_bookmarks(refs)
        finally:
            self.save_map(self.map_file)

    def fetch(self, remote, heads):
        result = self.fetch_pack(remote, heads)
        remote_name = self.remote_name(remote, False)

        # if remote returns a symref for HEAD, then let's store that
        rhead = None
        rnode = None
        oldheads = self.repo.changelog.heads()
        imported = 0
        if result.refs:
            filteredrefs = self.filter_min_date(self.filter_refs(result.refs,
                                                                 heads))
            imported = self.import_git_objects(remote_name, filteredrefs)
            self.import_tags(result.refs)
            self.update_hg_bookmarks(result.refs)

            try:
                symref = result.symrefs[b'HEAD']
                if symref.startswith(b'refs/heads'):
                    rhead = symref.replace(b'refs/heads/', b'')

                rnode = result.refs[b'refs/heads/%s' % rhead]
                rnode = self._map_git[rnode]
                rnode = self.repo[rnode].node()
            except KeyError:
                # if there is any error make sure to clear the variables
                rhead = None
                rnode = None

            if remote_name:
                self.update_remote_branches(remote_name, result.refs)
            elif not self.git.refs.as_dict(b'refs/remotes/'):
                # intial cloning
                self.update_remote_branches(b'default', result.refs)

                # "Activate" a tipmost bookmark.
                bms = self.repo[b'tip'].bookmarks()

                # override the 'tipmost' behavior if we know the remote HEAD
                if rnode:
                    # make sure the bookmark exists; at the point the remote
                    # branches has already been set up
                    suffix = self.branch_bookmark_suffix or b''
                    changes = [(rhead + suffix, rnode)]
                    util.updatebookmarks(self.repo, changes)
                    bms = [rhead + suffix]

                if bms:
                    bookmarks.activate(self.repo, bms[0])

        self.save_map(self.map_file)

        # also mark public any branches the user specified
        blist = [self.repo._bookmarks[branch] for branch in
                 self.ui.configlist(b'git', b'public')]
        if rnode and self.ui.configbool(b'hggit', b'usephases'):
            blist.append(rnode)

        if blist:
            lock = self.repo.lock()
            try:
                tr = self.repo.transaction(b"phase")
                phases.advanceboundary(self.repo, tr, phases.public,
                                       blist)
                tr.close()
            finally:
                if tr is not None:
                    tr.release()
                lock.release()

        if imported == 0:
            return 0

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
            self.update_references()
        finally:
            self.save_map(self.map_file)

    def get_refs(self, remote):
        self.export_commits()
        old_refs = {}
        new_refs = {}

        def changed(refs):
            old_refs.update(refs)
            exportable = self.get_exportable()
            new_refs.update(self.get_changed_refs(refs, exportable, True))
            return refs  # always return the same refs to make the send a no-op

        try:
            self._call_client(remote, 'send_pack', changed, lambda have, want: [])

            changed_refs = [ref for ref, sha in compat.iteritems(new_refs)
                            if sha != old_refs.get(ref)]

            new = [
                bin(sha) for sha in map(self.map_hg_get, changed_refs) if sha
            ]
            old = {}

            for ref, sha in compat.iteritems(old_refs):
                try:
                    gittag = self.git.get_object(sha)
                except KeyError:
                    gittag = None

                # make sure we don't accidentally dereference and lose
                # annotated tags
                if isinstance(gittag, Tag):
                    sha = gittag.object[1]

                old_target = self.map_hg_get(sha)

                if old_target:
                    self.ui.debug(b'unchanged ref %s: %s\n' % (ref, old_target))
                    old[bin(old_target)] = 1
                else:
                    self.ui.debug(b'changed ref %s\n' % (ref))

            return old, new
        except (HangupException, GitProtocolError) as e:
            raise error.Abort(_(b"git remote error: ")
                              + pycompat.sysbytes(str(e)))

    def push(self, remote, revs, force):
        self.export_commits()
        old_refs, new_refs = self.upload_pack(remote, revs, force)
        remote_name = self.remote_name(remote, True)

        if not isinstance(new_refs, dict):
            # dulwich 0.20.6 changed the API and deprectated treating
            # the result as a dictionary
            new_refs = new_refs.refs

        if remote_name and new_refs:
            for ref, new_sha in sorted(compat.iteritems(new_refs)):
                old_sha = old_refs.get(ref)
                if old_sha is None:
                    if self.ui.verbose:
                        self.ui.note(b"adding reference %s::%s => GIT:%s\n" %
                                     (remote_name, ref, new_sha[0:8]))
                    else:
                        self.ui.status(b"adding reference %s\n" % ref)
                elif new_sha != old_sha:
                    if self.ui.verbose:
                        self.ui.note(b"updating reference %s::%s => GIT:%s\n" %
                                     (remote_name, ref, new_sha[0:8]))
                    else:
                        self.ui.status(b"updating reference %s\n" % ref)
                else:
                    self.ui.debug(b"unchanged reference %s::%s => GIT:%s\n" %
                                  (remote_name, ref, new_sha[0:8]))

            self.update_remote_branches(remote_name, new_refs)
        if old_refs == new_refs:
            self.ui.status(_(b"no changes found\n"))
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
                for n in (b'refs/heads/' + rev, b'refs/tags/' + rev):
                    if n in result.refs:
                        reqrefs[n] = result.refs[n]
        else:
            reqrefs = result.refs

        commits = [bin(c) for c in self.get_git_incoming(reqrefs).commits]

        b = overlayrepo(self, commits, result.refs)

        return (b, commits, lambda: None)

    # CHANGESET CONVERSION METHODS

    def export_git_objects(self):
        self.ui.note(_(b"finding hg commits to export\n"))
        repo = self.repo
        clnode = repo.changelog.node

        nodes = (clnode(n) for n in repo)
        to_export = (repo[node] for node in nodes if not hex(node) in
                     self._map_hg)

        todo_total = len(repo) - len(self._map_hg)
        topic = b'find commits to export'
        unit = b'commits'

        with compat.makeprogress(repo.ui, topic, unit, todo_total) as progress:
            export = []
            for ctx in to_export:
                item = hex(ctx.node())
                progress.increment(item=item, total=todo_total)
                if ctx.extra().get(b'hg-git', None) != b'octopus':
                    export.append(ctx)

            total = len(export)
            if not total:
                return

        self.ui.note(_(b"exporting hg objects to git\n"))

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
            try:
                gitcommit = self.git[gitsha]
            except KeyError:
                raise error.Abort(_(b'Parent SHA-1 not present in Git'
                                    b'repo: %s' % gitsha))

        exporter = hg2git.IncrementalChangesetExporter(
            self.repo, pctx, self.git.object_store, gitcommit)

        mapsavefreq = compat.config(self.ui, b'int', b'hggit',
                                    b'mapsavefrequency')
        with compat.makeprogress(self.ui, b'exporting', total=total) as progress:
            for i, ctx in enumerate(export):
                progress.update(i, total=total)
                self.export_hg_commit(ctx.node(), exporter)
                if mapsavefreq and i % mapsavefreq == 0:
                    self.ui.debug(_(b"saving mapfile\n"))
                    self.save_map(self.map_file)

    def set_commiter_from_author(self, commit):
        commit.committer = commit.author
        commit.commit_time = commit.author_time
        commit.commit_timezone = commit.author_timezone

    # convert this commit into git objects
    # go through the manifest, convert all blobs/trees we don't have
    # write the commit object (with metadata info)
    def export_hg_commit(self, rev, exporter):
        self.ui.note(_(b"converting revision %s\n") % hex(rev))

        oldenc = self.swap_out_encoding()

        ctx = self.repo[rev]
        extra = ctx.extra()

        commit = Commit()

        (time, timezone) = ctx.date()
        # work around to bad timezone offets - dulwich does not handle
        # sub minute based timezones. In the one known case, it was a
        # manual edit that led to the unusual value. Based on that,
        # there is no reason to round one way or the other, so do the
        # simplest and round down.
        timezone -= (timezone % 60)
        commit.author = self.get_git_author(ctx)
        commit.author_time = int(time)
        commit.author_timezone = -timezone

        if b'committer' in extra:
            try:
                # fixup timezone
                (name, timestamp, timezone) = extra[b'committer'].rsplit(b' ', 2)
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
            except:    # extra is essentially user-supplied, we must be careful
                self.set_commiter_from_author(commit)
        else:
            self.set_commiter_from_author(commit)

        commit.parents = []
        for parent in self.get_git_parents(ctx):
            hgsha = hex(parent.node())
            git_sha = self.map_git_get(hgsha)
            if git_sha:
                if git_sha not in self.git.object_store:
                    raise error.Abort(_(b'Parent SHA-1 not present in Git'
                                        b'repo: %s' % git_sha))

                commit.parents.append(git_sha)

        commit.message, extra = self.get_git_message_and_extra(ctx)
        commit.extra.extend(extra)

        if b'encoding' in extra:
            commit.encoding = extra[b'encoding']
        if b'gpgsig' in extra:
            commit.gpgsig = extra[b'gpgsig']

        for obj, nodeid in exporter.update_changeset(ctx):
            if obj.id not in self.git.object_store:
                self.git.object_store.add_object(obj)

        tree_sha = exporter.root_tree_sha

        if tree_sha not in self.git.object_store:
            raise error.Abort(_(b'Tree SHA-1 not present in Git repo: %s' %
                                tree_sha))

        commit.tree = tree_sha

        if commit.id not in self.git.object_store:
            self.git.object_store.add_object(commit)
        self.map_set(commit.id, ctx.hex())

        self.swap_out_encoding(oldenc)
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
        return RE_GIT_SANITIZE_AUTHOR.sub(b'?', name.lstrip(b'< ').rstrip(b'> '))

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
                name += b' ext:(' + compat.quote(a.group(3)) + b')'
            author = b'%s <%s>'\
                     % (self.get_valid_git_username_email(name),
                         self.get_valid_git_username_email(email))
        elif b'@' in author:
            author = b'%s <%s>'\
                     % (self.get_valid_git_username_email(author),
                         self.get_valid_git_username_email(author))
        else:
            author = self.get_valid_git_username_email(author) + b' <none@none>'

        if b'author' in ctx.extra():
            author = b"".join(apply_delta(author, ctx.extra()[b'author']))

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
            message = b"".join(apply_delta(message, extra[b'message']))

        # HG EXTRA INFORMATION

        # test only -- do not document this!
        extra_in_message = compat.config(self.ui, b'bool', b'git',
                                         b'debugextrainmessage')
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
            git_extra.append((compat.unquote(field), compat.unquote(value)))

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
                        extra_message += (b"rename : " + oldfile + b" => " +
                                          newfile + b"\n")
                    else:
                        spec = b'%s:%s' % (compat.quote(oldfile),
                                           compat.quote(newfile))
                        git_extra.append((b'HG:rename', spec))

        # hg extra items always go at the end
        for key, value in sorted(extra.items()):
            if key in (b'author', b'committer', b'encoding', b'message', b'branch',
                       b'hg-git', b'hg-git-rename-source'):
                continue
            else:
                if extra_in_message:
                    extra_message += (b"extra : " + key + b" : " +
                                      compat.quote(value) + b"\n")
                else:
                    spec = b'%s:%s' % (compat.quote(key),
                                       compat.quote(value))
                    git_extra.append((b'HG:extra', spec))

        if extra_message:
            message += b"\n--HG--\n" + extra_message

        if (extra.get(b'hg-git-rename-source', None) != b'git' and not
            extra_in_message and not git_extra and extra_message == b''):
            # We need to store this if no other metadata is stored. This
            # indicates that when reimporting the commit into Mercurial we'll
            # know not to detect renames.
            git_extra.append((b'HG:rename-source', b'hg'))

        return message, git_extra

    def get_git_incoming(self, refs):
        return git2hg.find_incoming(self.git.object_store, self._map_git, refs)

    def import_git_objects(self, remote_name, refs):
        result = self.get_git_incoming(refs)
        commits = result.commits
        commit_cache = result.commit_cache
        # import each of the commits, oldest first
        total = len(commits)
        if total:
            self.ui.status(_(b"importing git objects into hg\n"))
        else:
            self.ui.status(_(b"no changes found\n"))

        mapsavefreq = compat.config(self.ui, b'int', b'hggit',
                                    b'mapsavefrequency')
        with compat.makeprogress(self.ui, b'importing', unit=b'commits', total=total) as progress:
            for i, csha in enumerate(commits):
                progress.update(i)
                commit = commit_cache[csha]
                self.import_git_commit(commit)
                if mapsavefreq and i % mapsavefreq == 0:
                    self.ui.debug(_(b"saving mapfile\n"))
                    self.save_map(self.map_file)

        # TODO if the tags cache is used, remove any dangling tag references
        return total

    def import_git_commit(self, commit):
        self.ui.debug(_(b"importing: %s\n") % commit.id)
        unfiltered = self.repo.unfiltered()

        detect_renames = False
        (strip_message, hg_renames,
         hg_branch, extra) = git2hg.extract_hg_metadata(
             commit.message, commit.extra)
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
                raise error.Abort(_(b'you appear to have run strip - '
                                    b'please run hg git-cleanup'))

        # get a list of the changed, added, removed files and gitlinks
        files, gitlinks, git_renames = self.get_files_changed(commit,
                                                              detect_renames)
        if detect_renames:
            renames = git_renames

        git_commit_tree = self.git[commit.tree]

        # Analyze hgsubstate and build an updated version using SHAs from
        # gitlinks. Order of application:
        # - preexisting .hgsubstate in git tree
        # - .hgsubstate from hg parent
        # - changes in gitlinks
        hgsubstate = util.parse_hgsubstate(
            self.git_file_readlines(git_commit_tree, b'.hgsubstate'))
        parentsubdata = b''
        if gparents:
            p1ctx = unfiltered[gparents[0]]
            if b'.hgsubstate' in p1ctx:
                parentsubdata = p1ctx.filectx(b'.hgsubstate').data()
                parentsubdata = parentsubdata.splitlines()
                parentsubstate = util.parse_hgsubstate(parentsubdata)
                for path, sha in compat.iteritems(parentsubstate):
                    hgsubstate[path] = sha
        for path, sha in compat.iteritems(gitlinks):
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
        gitmodules = self.parse_gitmodules(git_commit_tree)
        if gitmodules:
            hgsub = util.parse_hgsub(self.git_file_readlines(git_commit_tree,
                                                             b'.hgsub'))
            for (sm_path, sm_url, sm_name) in gitmodules:
                hgsub[sm_path] = b'[git]' + sm_url
            files[b'.hgsub'] = (False, 0o100644, None)
        elif (commit.parents and b'.gitmodules' in
              self.git[self.git[commit.parents[0]].tree]):
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
            text = self.decode_guess(text, commit.encoding)

        text = b'\n'.join(l.rstrip() for l in text.splitlines()).strip(b'\n')
        if text + b'\n' != origtext:
            extra[b'message'] = create_delta(text + b'\n', origtext)

        author = commit.author

        # convert extra data back to the end
        if b' ext:' in commit.author:
            m = RE_GIT_AUTHOR_EXTRA.match(commit.author)
            if m:
                name = m.group(1)
                ex = compat.unquote(m.group(2))
                email = m.group(3)
                author = name + b' <' + email + b'>' + ex

        if b' <none@none>' in commit.author:
            author = commit.author[:-12]

        try:
            author.decode('utf-8')
        except UnicodeDecodeError:
            origauthor = author
            author = self.decode_guess(author, commit.encoding)
            extra[b'author'] = create_delta(author, origauthor)

        oldenc = self.swap_out_encoding()

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
            return [path for path, node1 in compat.iteritems(manifest1) if path not
                    in files and manifest2.get(path, node1) != node1]

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
                    e = self.convert_git_int_mode(mode)
            else:
                # it's a converged file
                fc = context.filectx(unfiltered, f, changeid=memctx.p1().rev())
                data = fc.data()
                e = fc.flags()
                copied_path = None
                copied = fc.renamed()
                if copied:
                    copied_path = copied[0]

            return compat.memfilectx(unfiltered, memctx, f, data,
                                     islink=b'l' in e,
                                     isexec=b'x' in e,
                                     copysource=copied_path)

        p1, p2 = (nullid, nullid)
        octopus = False

        if len(gparents) > 1:
            # merge, possibly octopus
            def commit_octopus(p1, p2):
                ctx = context.memctx(unfiltered, (p1, p2), text, list(files) +
                                     findconvergedfiles(p1, p2), getfilectx,
                                     author, date, {b'hg-git': b'octopus'})
                # See comment below about setting substate to None.
                ctx.substate = None
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
        if commit.author != commit.committer\
           or commit.author_time != commit.commit_time\
           or commit.author_timezone != commit.commit_timezone:
            extra[b'committer'] = b"%s %d %d" % (
                commit.committer, commit.commit_time, -commit.commit_timezone)

        if commit.encoding:
            extra[b'encoding'] = commit.encoding
        if commit.gpgsig:
            extra[b'gpgsig'] = commit.gpgsig

        if octopus:
            extra[b'hg-git'] = b'octopus-done'

        ctx = context.memctx(unfiltered, (p1, p2), text,
                             list(files) + findconvergedfiles(p1, p2),
                             getfilectx, author, date, extra)
        # Starting Mercurial commit d2743be1bb06, memctx imports from
        # committablectx. This means that it has a 'substate' property that
        # contains the subrepo state. Ordinarily, Mercurial expects the subrepo
        # to be present while making a new commit -- since hg-git is importing
        # purely in-memory commits without backing stores for the subrepos,
        # that won't work. Forcibly set the substate to None so that there's no
        # attempt to read subrepos.
        ctx.substate = None
        node = unfiltered.commitctx(ctx)

        self.swap_out_encoding(oldenc)

        # save changeset to mapping file
        cs = hex(node)
        self.map_set(commit.id, cs)

    # PACK UPLOADING AND FETCHING

    def upload_pack(self, remote, revs, force):
        old_refs = {}
        change_totals = {}

        def changed(refs):
            self.ui.status(_(b"searching for changes\n"))
            old_refs.update(refs)
            all_exportable = self.get_exportable()
            if revs is None:
                exportable = all_exportable
            else:
                exportable = {}
                for rev in (hex(r) for r in revs):
                    if rev not in all_exportable:
                        raise error.Abort(b"revision %s cannot be pushed since"
                                          b" it doesn't have a bookmark" %
                                          self.repo[rev])
                    exportable[rev] = all_exportable[rev]
            return self.get_changed_refs(refs, exportable, force)

        def genpack(have, want, progress=None, ofs_delta=True):
            commits = []
            for mo in self.git.object_store.find_missing_objects(have, want):
                (sha, name) = mo
                o = self.git.object_store[sha]
                t = type(o)
                change_totals[t] = change_totals.get(t, 0) + 1
                if isinstance(o, Commit):
                    commits.append(sha)
            commit_count = len(commits)
            self.ui.note(_(b"%d commits found\n") % commit_count)
            if commit_count > 0:
                self.ui.debug(_(b"list of commits:\n"))
                for commit in commits:
                    self.ui.debug(b"%s\n" % commit)
                self.ui.status(_(b"adding objects\n"))
            return self.git.object_store.generate_pack_data(
                have, want, progress=progress, ofs_delta=ofs_delta)

        def callback(remote_info):
            # dulwich (perhaps git?) wraps remote output at a fixed width but
            # signifies the end of transmission with a double new line
            global CALLBACK_BUFFER
            if remote_info and not remote_info.endswith(b'\n\n'):
                CALLBACK_BUFFER += remote_info
                return

            remote_info = CALLBACK_BUFFER + remote_info
            CALLBACK_BUFFER = b''
            if not remote_info:
                remote_info = b'\n'

            for line in remote_info[:-1].split(b'\n'):
                self.ui.status(_(b"remote: %s\n") % line)

        try:
            new_refs = self._call_client(remote, 'send_pack', changed, genpack,
                                         progress=callback)

            if len(change_totals) > 0:
                self.ui.status(_(b"added %d commits with %d trees"
                                 b" and %d blobs\n") %
                               (change_totals.get(Commit, 0),
                                change_totals.get(Tree, 0),
                                change_totals.get(Blob, 0)))
            return old_refs, new_refs
        except (HangupException, GitProtocolError) as e:
            raise error.Abort(_(b"git remote error: ")
                              + pycompat.sysbytes(str(e)))

    def get_changed_refs(self, refs, exportable, force):
        new_refs = refs.copy()

        # The remote repo is empty and the local one doesn't have
        # bookmarks/tags
        #
        # (older dulwich versions return the proto-level
        # capabilities^{} key when the dict should have been
        # empty. That check can probably be removed at some point in
        # the future.)
        if not refs or next(iter(refs.keys())) == b'capabilities^{}':
            if not exportable:
                tip = self.repo.filtered(b'served').lookup(b'tip')
                if tip != nullid:
                    if b'capabilities^{}' in new_refs:
                        del new_refs[b'capabilities^{}']
                    tip = hex(tip)
                    commands.bookmark(self.ui, self.repo, b'master',
                                      rev=tip, force=True)
                    bookmarks.activate(self.repo, b'master')
                    new_refs[b'refs/heads/master'] = self.map_git_get(tip)

        # mapped nodes might be hidden
        unfiltered = self.repo.unfiltered()
        for rev, rev_refs in compat.iteritems(exportable):
            ctx = self.repo[rev]
            if not rev_refs:
                raise error.Abort(b"revision %s cannot be pushed since"
                                  b" it doesn't have a bookmark" % ctx)

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
                if ref not in refs:
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
                        raise error.Abort(b"pushing %s overwrites %s"
                                          % (ref, ctx))
                elif ref in uptodate_annotated_tags:
                    # we already have the annotated tag.
                    pass
                else:
                    raise error.Abort(
                        b"branch '%s' changed on the server, "
                        b"please pull and merge before pushing" % ref)

        return new_refs

    def fetch_pack(self, remote_name, heads=None):
        # The dulwich default walk only checks refs/heads/. We also want to
        # consider remotes when doing discovery, so we build our own list. We
        # can't just do 'refs/' here because the tag class doesn't have a
        # parents function for walking, and older versions of dulwich don't
        # like that.
        haveheads = list(self.git.refs.as_dict(b'refs/remotes/').values())
        haveheads.extend(self.git.refs.as_dict(b'refs/heads/').values())
        graphwalker = self.git.get_graph_walker(heads=haveheads)

        def determine_wants(refs):
            if refs is None:
                return None
            filteredrefs = self.filter_refs(refs, heads)
            return [x for x in compat.itervalues(filteredrefs) if x not in self.git]

        try:
            progress = GitProgress(self.ui)
            f = io.BytesIO()

            ret = self._call_client(remote_name, 'fetch_pack', determine_wants,
                                    graphwalker, f.write, progress.progress)

            if(f.tell() != 0):
                f.seek(0)
                self.git.object_store.add_thin_pack(f.read, None)
            progress.flush()

            # For empty repos dulwich gives us None, but since later
            # we want to iterate over this, we really want an empty
            # iterable
            if ret is None:
                ret = {}

            return ret
        except (HangupException, GitProtocolError) as e:
            raise error.Abort(_(b"git remote error: ")
                              + pycompat.sysbytes(str(e)))

    def _call_client(self, remote_name, method, *args, **kwargs):
        clientobj, path = self._get_transport_and_path(remote_name)

        func = getattr(clientobj, method)

        # dulwich 0.19, used in python 2.7, does not offer a specific
        # exception class
        HTTPUnauthorized = getattr(
            client, 'HTTPUnauthorized', type('<dummy>', (Exception,), {}),
        )

        try:
            return func(path, *args, **kwargs)
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
            # dulwich 0.19
            elif 'unexpected http resp 401' in e.args[0]:
                self._http_auth_realm = 'Git'
            else:
                raise

            clientobj, path = self._get_transport_and_path(remote_name)
            func = getattr(clientobj, method)

            try:
                return func(path, *args, **kwargs)
            except HTTPUnauthorized:
                raise error.Abort(_(b'authorization failed'))
            except GitProtocolError as e:
                # python 2.7
                if 'unexpected http resp 401' in e.args[0]:
                    raise error.Abort(_(b'authorization failed'))
                else:
                    raise



    # REFERENCES HANDLING

    def filter_refs(self, refs, heads):
        '''For a dictionary of refs: shas, if heads is None then return refs
        that match the heads. Otherwise, return refs that are heads or tags.

        '''
        filteredrefs = []
        if heads is not None:
            # contains pairs of ('refs/(heads|tags|...)/foo', 'foo')
            # if ref is just '<foo>', then we get ('foo', 'foo')
            stripped_refs = [(r, r[r.find(b'/', r.find(b'/') + 1) + 1:]) for r in
                             refs]
            for h in heads:
                if h.endswith(b'/*'):
                    prefix = h[:-1]  # include the / but not the *
                    r = [pair[0] for pair in stripped_refs
                         if pair[1].startswith(prefix)]
                    r.sort()
                    filteredrefs.extend(r)
                else:
                    r = [pair[0] for pair in stripped_refs if pair[1] == h]
                    if not r:
                        raise error.Abort(b"ref %s not found on remote server"
                                          % h)
                    elif len(r) == 1:
                        filteredrefs.append(r[0])
                    else:
                        raise error.Abort(b"ambiguous reference %s: %r"
                                          % (h, r))
        else:
            for ref, sha in compat.iteritems(refs):
                if (not ref.endswith(b'^{}') and
                    (ref.startswith(b'refs/heads/') or
                     ref.startswith(b'refs/tags/'))):
                    filteredrefs.append(ref)
            filteredrefs.sort()

        # the choice of OrderedDict vs plain dict has no impact on stock
        # hg-git, but allows extensions to customize the order in which refs
        # are returned
        return util.OrderedDict((r, refs[r]) for r in filteredrefs)

    def filter_min_date(self, refs):
        '''filter refs by minimum date

        This only works for refs that are available locally.'''
        min_date = compat.config(self.ui, b'string', b'git', b'mindate')
        if min_date is None:
            return refs

        # filter refs older than min_timestamp
        min_timestamp, min_offset = dateutil.parsedate(min_date)

        def check_min_time(obj):
            if isinstance(obj, Tag):
                return obj.tag_time >= min_timestamp
            else:
                return obj.commit_time >= min_timestamp
        return util.OrderedDict((ref, sha) for ref, sha in compat.iteritems(refs)
                                if check_min_time(self.git[sha]))

    def update_references(self):
        exportable = self.get_exportable()

        # Create a local Git branch name for each
        # Mercurial bookmark.
        for hg_sha, refs in compat.iteritems(exportable):
            for git_ref in refs.heads:
                git_sha = self.map_git_get(hg_sha)
                if git_sha:
                    self.git.refs[git_ref] = git_sha

    def export_hg_tags(self):
        for tag, sha in compat.iteritems(self.repo.tags()):
            if self.repo.tagtype(tag) in (b'global', b'git'):
                tag = tag.replace(b' ', b'_')
                target = self.map_git_get(hex(sha))

                if target is None:
                    self.repo.ui.warn(b"warning: not exporting tag '%s' "
                                      b"due to missing git "
                                      b"revision\n" % tag)
                    continue

                tag_refname = b'refs/tags/' + tag

                if not check_ref_format(tag_refname):
                    self.repo.ui.warn(b"warning: not exporting tag '%s' "
                                      b"due to invalid name\n" % tag)
                    continue

                # check whether the tag already exists and is
                # annotated
                if tag_refname in self.git.refs:
                    gittarget = self.git.refs[tag_refname]
                    gittag = self.git.get_object(gittarget)
                    if isinstance(gittag, Tag):
                        if gittag.object[1] != target:
                            self.repo.ui.warn(
                                b"warning: not overwriting annotated "
                                b"tag '%s'\n" % tag
                            )

                        # never overwrite annotated tags, otherwise
                        # it'd happen on every pull
                        target = gittarget

                self.git.refs[tag_refname] = target
                self.tags[tag] = hex(sha)

    def _filter_for_bookmarks(self, bms):
        if not self.branch_bookmark_suffix:
            return [(bm, bm) for bm in bms]
        else:
            def _filter_bm(bm):
                if bm.endswith(self.branch_bookmark_suffix):
                    return bm[0:-(len(self.branch_bookmark_suffix))]
                else:
                    return bm
            return [(_filter_bm(bm), bm) for bm in bms]

    def get_exportable(self):
        class heads_tags(object):
            def __init__(self):
                self.heads = set()
                self.tags = set()

            def __iter__(self):
                return itertools.chain(self.heads, self.tags)

            def __nonzero__(self):
                return bool(self.heads) or bool(self.tags)
            __bool__ = __nonzero__

        res = collections.defaultdict(heads_tags)

        bms = self.repo._bookmarks
        for filtered_bm, bm in self._filter_for_bookmarks(bms):
            ref_name = b'refs/heads/' + filtered_bm
            if check_ref_format(ref_name):
                res[hex(bms[bm])].heads.add(ref_name)
            else:
                self.repo.ui.warn(b"warning: not exporting bookmark '%s' "
                                  b"due to invalid name\n" % bm)

        for tag, sha in compat.iteritems(self.tags):
            res[sha].tags.add(b'refs/tags/' + tag)
        return res

    def import_tags(self, refs):
        if not refs:
            return
        repotags = self.repo.tags()
        for k in refs:
            ref_name = k
            parts = k.split(b'/')
            if parts[0] == b'refs' and parts[1] == b'tags':
                ref_name = b"/".join(v for v in parts[2:])
                # refs contains all the refs in the server, not just
                # the ones we are pulling
                if refs[k] not in self.git.object_store:
                    continue
                if ref_name[-3:] == b'^{}':
                    ref_name = ref_name[:-3]
                if ref_name not in repotags:
                    obj = self.git.get_object(refs[k])
                    sha = None
                    if isinstance(obj, Commit):  # lightweight
                        sha = self.map_hg_get(refs[k])
                        if sha is not None:
                            self.tags[ref_name] = sha
                    elif isinstance(obj, Tag):  # annotated
                        (obj_type, obj_sha) = obj.object
                        obj = self.git.get_object(obj_sha)
                        if isinstance(obj, Commit):
                            sha = self.map_hg_get(obj_sha)
                            # TODO: better handling for annotated tags
                            if sha is not None:
                                self.tags[ref_name] = sha
        self.save_tags()

    def add_tag(self, target, *tags):
        for tag in tags:
            scmutil.checknewlabel(self.repo, tag, b'tag')

            # -f/--force is deliberately unimplemented and unmentioned
            # as its git semantics are quite confusing
            if compat.isrevsymbol(self.repo, tag):
                raise error.Abort(b"the name '%s' already exists" % tag)

            if check_ref_format(b'refs/tags/' + tag):
                self.ui.debug(b'adding git tag %s\n' % tag)
                self.tags[tag] = target
            else:
                raise error.Abort(b"the name '%s' is not a valid git "
                                  b"tag" % tag)

        self.export_commits()
        self.save_tags()

    def update_hg_bookmarks(self, refs):
        try:
            bms = self.repo._bookmarks

            heads = {
                ref[11:]: refs[ref]
                for ref in refs
                if ref.startswith(b'refs/heads/')
            }

            suffix = self.branch_bookmark_suffix or b''
            changes = []
            for head, sha in compat.iteritems(heads):
                # refs contains all the refs in the server, not just
                # the ones we are pulling
                hgsha = self.map_hg_get(sha)
                if hgsha is None:
                    continue
                hgsha = bin(hgsha)
                if head not in bms:
                    # new branch
                    changes.append((head + suffix, hgsha))
                else:
                    bm = self.repo[bms[head]]
                    if bm.ancestor(self.repo[hgsha]) == bm:
                        # fast forward
                        changes.append((head + suffix, hgsha))

            if heads:
                util.updatebookmarks(self.repo, changes)

        except AttributeError:
            self.ui.warn(_(b'creating bookmarks failed, do you have'
                         b' bookmarks enabled?\n'))

    def update_remote_branches(self, remote_name, refs):
        remote_refs = self.remote_refs
        # since we re-write all refs for this remote each time, prune
        # all entries matching this remote from our refs list now so
        # that we avoid any stale refs hanging around forever
        for t in list(remote_refs):
            if t.startswith(remote_name + b'/'):
                del remote_refs[t]
        for ref_name, sha in compat.iteritems(refs):
            if ref_name.startswith(b'refs/heads'):
                hgsha = self.map_hg_get(sha)
                if hgsha is None or hgsha not in self.repo:
                    continue
                head = ref_name[11:]
                remote_refs[b'/'.join((remote_name, head))] = bin(hgsha)
                # TODO(durin42): what is this doing?
                new_ref = b'refs/remotes/%s/%s' % (remote_name, head)
                self.git.refs[new_ref] = sha
            elif (ref_name.startswith(b'refs/tags') and not
                  ref_name.endswith(b'^{}')):
                self.git.refs[ref_name] = sha

    # UTILITY FUNCTIONS

    def convert_git_int_mode(self, mode):
        # TODO: make these into constants
        convert = {
            0o100644: b'',
            0o100755: b'x',
            0o120000: b'l'
        }
        if mode in convert:
            return convert[mode]
        return b''

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

        changes = diff_tree.tree_changes(self.git.object_store, btree, tree,
                                         rename_detector=rename_detector)

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
                self.audit_hg_path(newfile)
                # new = file
                files[newfile] = False, newmode, newsha
                if renames is not None and newfile != oldfile:
                    renames[newfile] = oldfile
                    renamed_out.add(oldfile)
                    # the membership check is explained in a comment above
                    if (change.type == diff_tree.CHANGE_RENAME and
                        oldfile not in files):
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
        similarity = compat.config(self.ui, b'int', b'git', b'similarity')
        if similarity < 0 or similarity > 100:
            raise error.Abort(_(b'git.similarity must be between 0 and 100'))
        if similarity == 0:
            return None

        # default is borrowed from Git
        max_files = compat.config(self.ui, b'int', b'git', b'renamelimit')
        if max_files < 0:
            raise error.Abort(_(b'git.renamelimit must be non-negative'))
        if max_files == 0:
            max_files = None

        find_copies_harder = compat.config(self.ui, b'bool', b'git',
                                           b'findcopiesharder')
        return diff_tree.RenameDetector(self.git.object_store,
                                        rename_threshold=similarity,
                                        max_files=max_files,
                                        find_copies_harder=find_copies_harder)

    def parse_gitmodules(self, tree_obj):
        """Parse .gitmodules from a git tree specified by tree_obj

           :return: list of tuples (submodule path, url, name),
           where name is quoted part of the section's name, or
           empty list if nothing found
        """
        rv = []
        try:
            unused_mode, gitmodules_sha = tree_obj[b'.gitmodules']
        except KeyError:
            return rv
        gitmodules_content = self.git[gitmodules_sha].data
        fo = io.BytesIO(gitmodules_content)
        tt = dul_config.ConfigFile.from_file(fo)
        for section in tt.keys():
            section_kind, section_name = section
            if section_kind == b'submodule':
                sm_path = tt.get(section, b'path')
                sm_url = tt.get(section, b'url')
                rv.append((sm_path, sm_url, section_name))
        return rv

    def git_file_readlines(self, tree_obj, fname):
        """Read content of a named entry from the git commit tree

           :return: list of lines
        """
        if fname in tree_obj:
            unused_mode, sha = tree_obj[fname]
            content = self.git[sha].data
            return content.splitlines()
        return []

    def remote_name(self, remote, push):
        for path in compat.itervalues(self.ui.paths):
            if push and path.pushloc == remote:
                return path.name
            if path.loc == remote:
                return path.name

    def audit_hg_path(self, path):
        if b'.hg' in path.split(b'/'):
            if compat.config(self.ui, b'bool', b'git', b'blockdothg'):
                raise error.Abort(
                    (b"Refusing to import problematic path '%s'" % path),
                    hint=(b"Mercurial cannot check out paths inside nested " +
                          b"repositories; if you need to continue, then set " +
                          b"'[git] blockdothg = false' in your hgrc."))
            self.ui.warn((b"warning: path '%s' is within a nested " +
                          b'repository, which Mercurial cannot check out.\n')
                         % path)

    # Stolen from hgsubversion
    def swap_out_encoding(self, new_encoding=b'UTF-8'):
        try:
            from mercurial import encoding
            old = encoding.encoding
            encoding.encoding = new_encoding
        except (AttributeError, ImportError):
            old = hgutil._encoding
            hgutil._encoding = new_encoding
        return old

    def decode_guess(self, string, encoding):
        # text is not valid utf-8, try to make sense of it
        if encoding:
            try:
                return string.decode(pycompat.sysstr(encoding)).encode('utf-8')
            except UnicodeDecodeError:
                pass

        try:
            return string.decode('latin-1').encode('utf-8')
        except UnicodeDecodeError:
            return string.decode('ascii', 'replace').encode('utf-8')

    def _get_transport_and_path(self, uri):
        """Method that sets up the transport (either ssh or http(s))

        Tests:

        >>> from dulwich.client import HttpGitClient, SSHGitClient
        >>> from mercurial import ui
        >>> class SubHandler(GitHandler):
        ...    def __init__(self):
        ...         self.ui = ui.ui()
        ...         self._http_auth_realm = None
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

            proxy = compat.config(self.ui, b'string', b'http_proxy', b'host')
            if proxy:
                config.set(b'http', b'proxy', b'http://' + proxy)

                if compat.config(self.ui, b'string', b'http_proxy', b'passwd'):
                    self.ui.warn(
                        b"warning: proxy authentication is unsupported\n",
                    )

            if pycompat.ispy3:
                # urllib3.util.url._encode_invalid_chars() converts the path
                # back to bytes using the utf-8 codec
                str_uri = uri.decode('utf-8')
            else:
                str_uri = uri

            pwmgr = url.passwordmgr(self.ui, self.ui.httppasswordmgrdb)

            # not available in dulwich 0.19, used on Python 2.7
            if hasattr(client, 'get_credentials_from_store'):
                urlobj = compat.url(uri)
                auth = client.get_credentials_from_store(
                    urlobj.scheme,
                    urlobj.host,
                    urlobj.user,
                )
            else:
                auth = None

            if self._http_auth_realm:
                # since we've tried an unauthenticated request, and
                # obtain a realm, we can do a "full" search, including
                # a prompt
                username, password = pwmgr.find_user_password(
                    self._http_auth_realm, str_uri,
                )
            elif auth is not None:
                username, password = auth
                username = username.decode('utf-8')
                password = password.decode('utf-8')
            else:
                username, password = pwmgr.find_stored_password(str_uri)

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
            return client.LocalGitClient(), compat.url(uri).path

        # if its not git or git+ssh, try a local url..
        return client.SubprocessGitClient(), uri
