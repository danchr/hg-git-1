# git.py - git server bridge
#
# Copyright 2008 Scott Chacon <schacon at gmail dot com>
#   also some code (and help) borrowed from durin42
#
# This software may be used and distributed according to the terms
# of the GNU General Public License, incorporated herein by reference.

'''push and pull from a Git server

This extension lets you communicate (push and pull) with a Git server.
This way you can use Git hosting for your project or collaborate with a
project that is in Git.  A bridger of worlds, this plugin be.

Try hg clone git:// or hg clone git+ssh://

For more information and instructions, see :hg:`help git`
'''

from __future__ import absolute_import, print_function

# global modules
import os

# local modules
from . import compat
from . import gitrepo
from . import hgrepo
from . import overlay
from . import verify
from . import util

from bisect import insort
from .git_handler import GitHandler
from mercurial.node import hex
from mercurial.error import LookupError
from mercurial.i18n import _
from mercurial import (
    bundlerepo,
    cmdutil,
    demandimport,
    dirstate,
    discovery,
    exchange,
    extensions,
    help,
    hg,
    ui as hgui,
    util as hgutil,
    localrepo,
    manifest,
    pycompat,
    revset,
    scmutil,
    templatekw,
)

# COMPAT: hg 4.7 - demandimport.ignore was renamed to demandimport.IGNORES and
# became a set
try:
    demandimport.IGNORES.add(b'collections')
except AttributeError:  # pre 4.7 API
    demandimport.ignore.extend([
        b'collections',
    ])

__version__ = b'0.9.0a1'

testedwith = (b'4.3.3 4.4.2 4.5.3 4.6.2 '
              b'4.7.2 4.8.2 4.9.1 5.0.2 5.1.2 5.2 5.3 5.4')
minimumhgversion = b'4.3'
buglink = b'https://foss.heptapod.net/mercurial/hg-git/issues'

cmdtable = {}
configtable = {}
try:
    from mercurial import registrar
    command = registrar.command(cmdtable)
    configitem = registrar.configitem(configtable)
    compat.registerconfigs(configitem)
    templatekeyword = registrar.templatekeyword()

except (ImportError, AttributeError):
    command = cmdutil.command(cmdtable)
    templatekeyword = compat.templatekeyword()

# support for `hg clone git://github.com/defunkt/facebox.git`
# also hg clone git+ssh://git@github.com/schacon/simplegit.git
for _scheme in util.gitschemes:
    hg.schemes[_scheme] = gitrepo

# support for `hg clone localgitrepo`
_oldlocal = hg.schemes[b'file']

def _isgitdir(path):
    """True if the given file path is a git repo."""
    if os.path.exists(os.path.join(path, b'.hg')):
        return False

    if os.path.exists(os.path.join(path, b'.git')):
        # is full git repo
        return True

    if (os.path.exists(os.path.join(path, b'HEAD')) and
        os.path.exists(os.path.join(path, b'objects')) and
        os.path.exists(os.path.join(path, b'refs'))):
        # is bare git repo
        return True

    return False


def _local(path):
    p = hgutil.url(path).localpath()
    if _isgitdir(p):
        return gitrepo
    # detect git ssh urls (which mercurial thinks is a file-like path)
    if util.isgitsshuri(p):
        return gitrepo
    return _oldlocal(path)


hg.schemes[b'file'] = _local


# we need to wrap this so that git-like ssh paths are not prepended with a
# local filesystem path. ugh.
def _url(orig, path, **kwargs):
    # we'll test for 'git@' then use our heuristic method to determine if it's
    # a git uri
    if not (path.startswith(pycompat.ossep) and b':' in path):
        return orig(path, **kwargs)

    # the file path will be everything up until the last slash right before the
    # ':'
    lastsep = path.rindex(pycompat.ossep, None, path.index(b':')) + 1
    gituri = path[lastsep:]

    if util.isgitsshuri(gituri):
        return orig(gituri, **kwargs)
    return orig(path, **kwargs)


extensions.wrapfunction(hgutil, b'url', _url)


def _httpgitwrapper(orig):
    # we should probably test the connection but for now, we just keep it
    # simple and check for a url ending in '.git'
    def httpgitscheme(uri):
        if uri.endswith(b'.git'):
            return gitrepo

        # the http(s) scheme just returns the _peerlookup
        return orig

    return httpgitscheme


hg.schemes[b'https'] = _httpgitwrapper(hg.schemes[b'https'])
hg.schemes[b'http'] = _httpgitwrapper(hg.schemes[b'http'])
hgdefaultdest = hg.defaultdest


def defaultdest(source):
    for scheme in util.gitschemes:
        if source.startswith(b'%s://' % scheme) and source.endswith(b'.git'):
            return hgdefaultdest(source[:-4])

    if source.endswith(b'.git'):
        return hgdefaultdest(source[:-4])

    return hgdefaultdest(source)


hg.defaultdest = defaultdest


def getversion():
    """return version with dependencies for hg --version -v"""
    import dulwich
    dulver = b'.'.join(pycompat.sysbytes(str(i)) for i in dulwich.__version__)
    return __version__ + (b" (dulwich %s)" % dulver)


# defend against tracebacks if we specify -r in 'hg pull'
def safebranchrevs(orig, lrepo, otherrepo, branches, revs):
    revs, co = orig(lrepo, otherrepo, branches, revs)
    if isinstance(otherrepo, gitrepo.gitrepo):
        # FIXME: Unless it's None, the 'co' result is passed to the lookup()
        # remote command. Since our implementation of the lookup() remote
        # command is incorrect, we set it to None to avoid a crash later when
        # the incorect result of the lookup() remote command would otherwise be
        # used. This can, in undocumented corner-cases, result in that a
        # different revision is updated to when passing both -u and -r to
        # 'hg pull'. An example of such case is in tests/test-addbranchrevs.t
        # (for the non-hg-git case).
        co = None
    return revs, co
extensions.wrapfunction(hg, b'addbranchrevs', safebranchrevs)


def extsetup(ui):
    revset.symbols.update({
        b'fromgit': revset_fromgit, b'gitnode': revset_gitnode
    })
    helpdir = os.path.join(os.path.dirname(pycompat.fsencode(__file__)),
                           b'help')
    entry = ([b'git'], _(b"Working with Git Repositories"),
             lambda ui: open(os.path.join(helpdir, b'git.rst'), 'rb').read())
    insort(help.helptable, entry)


def reposetup(ui, repo):
    if not isinstance(repo, gitrepo.gitrepo):

        if (getattr(dirstate, 'rootcache', False) and
            hgutil.safehasattr(repo, b'vfs') and
            os.path.exists(compat.gitvfs(repo).join(b'git'))):
            # only install our dirstate wrapper if it has a hope of working
            from . import gitdirstate
            dirstate.dirstate = gitdirstate.gitdirstate

        klass = hgrepo.generate_repo_subclass(repo.__class__)
        repo.__class__ = klass


if hgutil.safehasattr(manifest, b'_lazymanifest'):
    # Mercurial >= 3.4
    extensions.wrapfunction(manifest.manifestdict, b'diff',
                            overlay.wrapmanifestdictdiff)


@command(b'gimport')
def gimport(ui, repo, remote_name=None):
    '''import commits from Git to Mercurial'''
    repo.githandler.import_commits(remote_name)


@command(b'gexport')
def gexport(ui, repo):
    '''export commits from Mercurial to Git'''
    repo.githandler.export_commits()


@command(b'gclear')
def gclear(ui, repo):
    '''clear out the Git cached data

    Strips all Git-related metadata from the repo, including the mapping
    between Git and Mercurial changesets. This is an irreversible
    destructive operation that may prevent further interaction with
    other clones.
    '''
    repo.ui.status(_(b"clearing out the git cache data\n"))
    repo.githandler.clear()


@command(b'gverify',
         [(b'r', b'rev', b'', _(b'revision to verify'), _(b'REV'))],
         _(b'[-r REV]'))
def gverify(ui, repo, **opts):
    '''verify that a Mercurial rev matches the corresponding Git rev

    Given a Mercurial revision that has a corresponding Git revision in the
    map, this attempts to answer whether that revision has the same contents as
    the corresponding Git revision.

    '''
    ctx = scmutil.revsingle(repo, opts.get('rev'), b'.')
    return verify.verify(ui, repo, ctx)


@command(b'git-cleanup')
def git_cleanup(ui, repo):
    '''clean up Git commit map after history editing'''
    new_map = []
    vfs = compat.gitvfs(repo)
    for line in vfs(GitHandler.map_file):
        gitsha, hgsha = line.strip().split(b' ', 1)
        if hgsha in repo:
            new_map.append(b'%s %s\n' % (gitsha, hgsha))
    wlock = repo.wlock()
    try:
        f = vfs(GitHandler.map_file, b'wb')
        f.writelines(new_map)
    finally:
        wlock.release()
    ui.status(_(b'git commit map cleaned\n'))


def findcommonoutgoing(orig, repo, other, *args, **kwargs):
    if isinstance(other, gitrepo.gitrepo):
        heads = repo.githandler.get_refs(other.path)[0]
        kw = {}
        kw.update(kwargs)
        for val, k in zip(args,
                          ('onlyheads', 'force', 'commoninc', 'portable')):
            kw[k] = val
        force = kw.get('force', False)
        commoninc = kw.get('commoninc', None)
        if commoninc is None:
            commoninc = discovery.findcommonincoming(repo, other, heads=heads,
                                                     force=force)
            kw['commoninc'] = commoninc
        return orig(repo, other, **kw)
    return orig(repo, other, *args, **kwargs)


extensions.wrapfunction(discovery, b'findcommonoutgoing', findcommonoutgoing)


def getremotechanges(orig, ui, repo, other, *args, **opts):
    if isinstance(other, gitrepo.gitrepo):
        if args:
            revs = args[0]
        else:
            revs = opts.get('onlyheads', opts.get('revs'))
        r, c, cleanup = repo.githandler.getremotechanges(other, revs)
        # ugh. This is ugly even by mercurial API compatibility standards
        if 'onlyheads' not in orig.__code__.co_varnames:
            cleanup = None
        return r, c, cleanup
    return orig(ui, repo, other, *args, **opts)


extensions.wrapfunction(bundlerepo, b'getremotechanges', getremotechanges)


def peer(orig, uiorrepo, *args, **opts):
    newpeer = orig(uiorrepo, *args, **opts)
    if isinstance(newpeer, gitrepo.gitrepo):
        if isinstance(uiorrepo, localrepo.localrepository):
            newpeer.localrepo = uiorrepo
    return newpeer


extensions.wrapfunction(hg, b'peer', peer)


def isvalidlocalpath(orig, self, path):
    return orig(self, path) or _isgitdir(path)


if (hgutil.safehasattr(hgui, b'path') and
    hgutil.safehasattr(hgui.path, b'_isvalidlocalpath')):
    extensions.wrapfunction(hgui.path, b'_isvalidlocalpath', isvalidlocalpath)


@util.transform_notgit
def exchangepull(orig, repo, remote, heads=None, force=False, bookmarks=(),
                 **kwargs):
    if isinstance(remote, gitrepo.gitrepo):
        # transaction manager is present in Mercurial >= 3.3
        try:
            trmanager = getattr(exchange, 'transactionmanager')
        except AttributeError:
            trmanager = None
        pullop = exchange.pulloperation(repo, remote, heads, force,
                                        bookmarks=bookmarks)
        if trmanager:
            pullop.trmanager = trmanager(repo, b'pull', remote.url())
        wlock = repo.wlock()
        lock = repo.lock()
        try:
            pullop.cgresult = repo.githandler.fetch(remote.path, heads)
            if trmanager:
                pullop.trmanager.close()
            else:
                pullop.closetransaction()
            return pullop
        finally:
            if trmanager:
                pullop.trmanager.release()
            else:
                pullop.releasetransaction()
            lock.release()
            wlock.release()
    else:
        return orig(repo, remote, heads, force, bookmarks=bookmarks, **kwargs)


extensions.wrapfunction(exchange, b'pull', exchangepull)


# TODO figure out something useful to do with the newbranch param
@util.transform_notgit
def exchangepush(orig, repo, remote, force=False, revs=None, newbranch=False,
                 bookmarks=(), **kwargs):
    if isinstance(remote, gitrepo.gitrepo):
        # opargs is in Mercurial >= 3.6
        opargs = kwargs.get('opargs')
        if opargs is None:
            opargs = {}
        pushop = exchange.pushoperation(repo, remote, force, revs, newbranch,
                                        bookmarks,
                                        **pycompat.strkwargs(opargs))
        pushop.cgresult = repo.githandler.push(remote.path, revs, force)
        return pushop
    else:
        return orig(repo, remote, force, revs, newbranch, bookmarks=bookmarks,
                    **kwargs)


extensions.wrapfunction(exchange, b'push', exchangepush)


def revset_fromgit(repo, subset, x):
    '''``fromgit()``
    Select changesets that originate from Git.
    '''
    revset.getargs(x, 0, 0, b"fromgit takes no arguments")
    git = repo.githandler
    node = repo.changelog.node
    return revset.baseset(r for r in subset
                          if git.map_git_get(hex(node(r))) is not None)


def revset_gitnode(repo, subset, x):
    '''``gitnode(hash)``
    Select the changeset that originates in the given Git revision. The hash
    may be abbreviated: `gitnode(a5b)` selects the revision whose Git hash
    starts with `a5b`. Aborts if multiple changesets match the abbreviation.
    '''
    args = revset.getargs(x, 1, 1, b"gitnode takes one argument")
    rev = revset.getstring(args[0],
                           b"the argument to gitnode() must be a hash")
    git = repo.githandler
    node = repo.changelog.node

    def matches(r):
        gitnode = git.map_git_get(hex(node(r)))
        if gitnode is None:
            return False
        return gitnode.startswith(rev)
    result = revset.baseset(r for r in subset if matches(r))
    if 0 <= len(result) < 2:
        return result
    raise LookupError(rev, git.map_file, _(b'ambiguous identifier'))


def _gitnodekw(node, repo):
    gitnode = repo.githandler.map_git_get(node.hex())
    if gitnode is None:
        gitnode = b''
    return gitnode


if (hgutil.safehasattr(templatekw, b'templatekeyword') and
        hgutil.safehasattr(templatekw.templatekeyword._table[b'node'],
                           b'_requires')):
    @templatekeyword(b'gitnode', requires={b'ctx', b'repo'})
    def gitnodekw(context, mapping):
        """:gitnode: String. The Git changeset identification hash, as a
        40 hexadecimal digit string."""
        node = context.resource(mapping, b'ctx')
        repo = context.resource(mapping, b'repo')
        return _gitnodekw(node, repo)

else:
    # COMPAT: hg < 4.6 - templatekeyword API changed
    @templatekeyword(b'gitnode')
    def gitnodekw(**args):
        """:gitnode: String. The Git changeset identification hash, as a
        40 hexadecimal digit string."""
        node = args[b'ctx']
        repo = args[b'repo']
        return _gitnodekw(node, repo)
