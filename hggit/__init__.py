# git.py - git server bridge
#
# Copyright 2008 Scott Chacon <schacon at gmail dot com>
#   also some code (and help) borrowed from durin42
#
# This software may be used and distributed according to the terms
# of the GNU General Public License, incorporated herein by reference.

r'''push and pull from a Git server

This extension lets you communicate (push and pull) with a Git server.
This way you can use Git hosting for your project or collaborate with a
project that is in Git. A bridger of worlds, this plugin be.

Try :hg:`clone git+https://github.com/dulwich/dulwich` or :hg:`clone
git+ssh://example.com/repo.git`.

Basic Use
---------

You can clone a Git repository from Mercurial by running :hg:`clone
<url> [dest]`. For example, if you were to run::

 $ hg clone git://github.com/schacon/hg-git.git

Hg-Git would clone the repository and convert it to a Mercurial repository for
you. There are a number of different protocols that can be used for Git
repositories. Examples of Git repository URLs include::

  git+https://github.com/hg-git/hg-git.git
  git+http://github.com/hg-git/hg-git.git
  git+ssh://git@github.com/hg-git/hg-git.git
  git://github.com/hg-git/hg-git.git
  file:///path/to/hg-git
  ../hg-git (local file path)

These also work::

  git+ssh://git@github.com:hg-git/hg-git.git
  git@github.com:hg-git/hg-git.git

Please note that you need to prepend HTTP, HTTPS, and SSH URLs with
``git+`` in order differentiate them from Mercurial URLs. For example,
an HTTPS URL would start with ``git+https://``. Also, note that Git
doesn't require the specification of the protocol for SSH, but
Mercurial does. Hg-Git automatically detects whether file paths should
be treated as Git repositories by their contents.

If you are starting from an existing Mercurial repository, you have to
set up a Git repository somewhere that you have push access to, add a
path entry for it in your .hg/hgrc file, and then run :hg:`push
[name]` from within your repository. For example::

 $ cd hg-git # (a Mercurial repository)
 $ # edit .hg/hgrc and add the target Git URL in the paths section
 $ hg push

This will convert all your Mercurial changesets into Git objects and push
them to the Git server.

Pulling new revisions into a repository is the same as from any other
Mercurial source. Within the earlier examples, the following commands are
all equivalent::

 $ hg pull
 $ hg pull default
 $ hg pull git://github.com/hg-git/hg-git.git

Git branches are exposed in Mercurial as bookmarks, while Git remote
branches are exposed as unchangable Mercurial local tags. See
:hg:`help bookmarks` and :hg:`help tags` for further information.

Finding and displaying Git revisions
------------------------------------

For displaying the Git revision ID, Hg-Git provides a template keyword:

  :gitnode: String.  The Git changeset identification hash, as a 40 hexadecimal
    digit string.

For example::

  $ hg log --template='{rev}:{node|short}:{gitnode|short} {desc}\n'
  $ hg log --template='hg: {node}\ngit: {gitnode}\n{date|isodate} {author}\n{desc}\n\n'

For finding changesets from Git, Hg-Git extends revsets to provide two new
selectors:

  :fromgit: Select changesets that originate from Git. Takes no arguments.
  :gitnode: Select changesets that originate in a specific Git revision. Takes
    a revision argument.

For example::

  $ hg log -r 'fromgit()'
  $ hg log -r 'gitnode(84f75b909fc3)'

Revsets are accepted by several Mercurial commands for specifying
revisions. See :hg:`help revsets` for details.

'''

from __future__ import absolute_import, print_function

# global modules
import os

# local modules
from . import compat
from . import gitrepo
from . import git_handler
from . import hgrepo
from . import overlay
from . import verify
from . import util

from mercurial.node import bin, hex, nullhex
from mercurial.i18n import _
from mercurial import (
    bundlerepo,
    cmdutil,
    commands,
    demandimport,
    dirstate,
    discovery,
    error,
    exchange,
    extensions,
    hg,
    util as hgutil,
    localrepo,
    manifest,
    pycompat,
    repoview,
    revset,
    scmutil,
    templatekw,
)

# COMPAT: hg 4.7 - demandimport.ignore was renamed to demandimport.IGNORES and
# became a set
try:
    demandimport.IGNORES |= {
        b'collections',
        b'brotli',  # only needed in Python 2.7
        b'ipaddress',  # only needed in Python 2.7
    }
except AttributeError:  # pre 4.7 API
    demandimport.ignore.extend([
        b'collections',
        b'brotli',
        b'ipaddress',
    ])

__version__ = b'0.10.1'

testedwith = (b'4.4.2 4.5.3 4.6.2 4.7.2 4.8.2 4.9.1 5.0.2 5.1.2 5.2 5.3 5.4 '
              b'5.5 5.6 5.7 5.8')
minimumhgversion = b'4.4'
buglink = b'https://foss.heptapod.net/mercurial/hg-git/issues'

cmdtable = {}
configtable = {}
try:
    from mercurial import registrar
    command = registrar.command(cmdtable)
    configitem = registrar.configitem(configtable)
    templatekeyword = registrar.templatekeyword()

except (ImportError, AttributeError):
    command = cmdutil.command(cmdtable)
    templatekeyword = compat.templatekeyword()

else:
    compat.registerconfigs(configitem)

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
    p = compat.url(path).localpath()
    if _isgitdir(p):
        return gitrepo
    # detect git ssh urls (which mercurial thinks is a file-like path)
    if util.isgitsshuri(p):
        return gitrepo
    return _oldlocal(path)


hg.schemes[b'file'] = _local


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


def reposetup(ui, repo):
    if not isinstance(repo, gitrepo.gitrepo):
        if (getattr(dirstate, 'rootcache', False) and
            git_handler.has_gitrepo(repo)):
            # only install our dirstate wrapper if it has a hope of working
            from . import gitdirstate
            dirstate.dirstate = gitdirstate.gitdirstate

        klass = hgrepo.generate_repo_subclass(repo.__class__)
        repo.__class__ = klass


extensions.wrapfunction(manifest.manifestdict, b'diff',
                        overlay.wrapmanifestdictdiff)


@command(b'gimport')
def gimport(ui, repo, remote_name=None):
    '''import commits from Git to Mercurial (ADVANCED)

    This command is equivalent to pulling from a Git source, but
    without actually accessing the network. Internally, hg-git relies
    on a local, cached git repository containing changes equivalent to
    the Mercurial repository. If you modify that Git repository
    somehow, use this command to import those changes.

    '''
    repo.githandler.import_commits(remote_name)


@command(b'gexport')
def gexport(ui, repo):
    '''export commits from Mercurial to Git (ADVANCED)

    This command is equivalent to pushing to a Git source, but without
    actually access the network. Internally, hg-git relies on a local,
    cached git repository containing changes equivalent to the
    Mercurial repository. If you wish to see what the Git commits
    would be, use this command to export those changes. As an example,
    it ensures that all changesets have a corresponding Git node.

    '''
    repo.githandler.export_commits()


@command(b'gclear')
def gclear(ui, repo):
    '''clear out the Git cached data (ADVANCED)

    Strips all Git-related metadata from the repo, including the mapping
    between Git and Mercurial changesets. This is an irreversible
    destructive operation that may prevent further interaction with
    other clones.
    '''
    repo.ui.status(_(b"clearing out the git cache data\n"))
    repo.githandler.clear()


@command(b'debuggitdir')
def gitdir(ui, repo):
    '''get the root of the git repository'''
    repo.ui.write(os.path.normpath(repo.githandler.gitdir), b'\n')


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
    gh = repo.githandler
    for line in gh.vfs(gh.map_file):
        gitsha, hgsha = line.strip().split(b' ', 1)
        if hgsha in repo:
            new_map.append(b'%s %s\n' % (gitsha, hgsha))
    with repo.githandler.store_repo.wlock():
        f = gh.vfs(gh.map_file, b'wb')
        f.writelines(new_map)
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


def tag(orig, ui, repo, *names, **opts):
    '''You can also use --git to create a lightweight Git tag. Please note
    that this requires an explicit -r/--rev, and does not support any
    of the other flags.

    Support for Git tags is somewhat minimal. The Git documentation
    heavily discourages changing tags once pushed, and suggests that
    users always create a new one instead. (Unlike Mercurial, Git does
    not track and version its tags within the repository.) As result,
    there's no support for removing and changing preexisting tags.
    Similarly, there's no support for annotated tags, i.e. tags with
    messages, nor for signing tags. For those, either use Git directly
    or use the integrated web interface for tags and releases offered
    by most hosting solutions, including GitHub and GitLab.

    '''

    if not opts.get('git'):
        return orig(ui, repo, *names, **opts)

    opts = pycompat.byteskwargs(opts)

    # check for various unimplemented arguments
    compat.check_incompatible_arguments(opts, b'git', [
        # conflict
        b'local',
        # we currently don't convert or expose this metadata, so
        # disallow setting it on creation
        b'edit',
        b'message',
        b'date',
        b'user',
    ])
    compat.check_at_most_one_arg(opts, b'rev', b'remove')

    if opts[b'remove']:
        opts[b'rev'] = b'null'

    if not opts.get(b'rev'):
        raise error.Abort(_(b'git tags require an explicit revision'),
                          hint=b'please specify -r/--rev')

    # the semantics of git tag editing are quite confusing, so we
    # don't bother; if you _really_ want to, use another tool to do
    # this, and ensure all contributors prune their tags -- otherwise,
    # it'll reappear next time someone pushes tags (ah, the wonders of
    # nonversioned markers!)
    #
    # see also https://git-scm.com/docs/git-tag#_discussion
    if opts[b'force']:
        raise error.Abort(
            b'cannot move git tags',
            hint=b'the git documentation heavily discourages editing tags',
        )

    names = [t.strip() for t in names]

    if len(names) != len(set(names)):
        raise error.Abort(_('tag names must be unique'))

    with repo.wlock(), repo.lock():
        target = hex(repo.lookup(opts[b'rev']))

        # see above
        if target == nullhex:
            raise error.Abort(
                b'cannot remove git tags',
                hint=b'the git documentation heavily discourages editing tags',
            )

        repo.githandler.add_tag(target, *names)


commands.table[b'tag'][1].append((b'', b'git', False,
                                  b'make it a git tag'))
extensions.wrapcommand(
    commands.table,
    b'tag',
    tag,
    docstring='\n\n    ' + tag.__doc__.strip(),
)


def pinnedrevs(orig, repo):
    pinned = orig(repo)

    # Mercurial pins bookmarks, even if obsoleted, so that they always
    # appear in e.g. log; do the same with git tags and remotes.
    if repo.local() and hasattr(repo, 'githandler'):
        rev = repo.changelog.rev

        pinned.update(rev(bin(r)) for r in repo.githandler.tags.values())
        pinned.update(rev(r) for r in repo.githandler.remote_refs.values())

    return pinned

extensions.wrapfunction(repoview, b'pinnedrevs', pinnedrevs)


def peer(orig, uiorrepo, *args, **opts):
    newpeer = orig(uiorrepo, *args, **opts)
    if isinstance(newpeer, gitrepo.gitrepo):
        if isinstance(uiorrepo, localrepo.localrepository):
            newpeer.localrepo = uiorrepo
    return newpeer


extensions.wrapfunction(hg, b'peer', peer)


def isvalidlocalpath(orig, self, path):
    return orig(self, path) or _isgitdir(path)


extensions.wrapfunction(compat.path, b'_isvalidlocalpath', isvalidlocalpath)


def isurllocal(orig, path):
    # recognise git scp-style paths when cloning
    return orig(path) and not util.isgitsshuri(path._origpath)


extensions.wrapfunction(compat.url, b'islocal', isurllocal)


def islocal(orig, path):
    # recognise git scp-style paths when cloning
    return orig(path) and not util.isgitsshuri(path)


extensions.wrapfunction(hg, b'islocal', islocal)


def hasscheme(orig, path):
    # recognise git scp-style paths
    return orig(path) or util.isgitsshuri(path)


extensions.wrapfunction(compat.urlutil, b'hasscheme', hasscheme)


@util.transform_notgit
def exchangepull(orig, repo, remote, heads=None, force=False, bookmarks=(),
                 **kwargs):
    if isinstance(remote, gitrepo.gitrepo):
        pullop = exchange.pulloperation(repo, remote, heads, force,
                                        bookmarks=bookmarks)
        pullop.trmanager = exchange.transactionmanager(repo, b'pull',
                                                       remote.url())

        wlock = repo.wlock()
        lock = repo.lock()
        try:
            pullop.cgresult = repo.githandler.fetch(remote.path, heads)
            pullop.trmanager.close()
            return pullop
        finally:
            pullop.trmanager.release()
            lock.release()
            wlock.release()
    else:
        return orig(repo, remote, heads, force, bookmarks=bookmarks, **kwargs)


extensions.wrapfunction(exchange, b'pull', exchangepull)


# TODO figure out something useful to do with the newbranch param
@util.transform_notgit
def exchangepush(orig, repo, remote, force=False, revs=None, newbranch=False,
                 bookmarks=(), opargs=None, **kwargs):
    if isinstance(remote, gitrepo.gitrepo):
        pushop = exchange.pushoperation(repo, remote, force, revs, newbranch,
                                        bookmarks,
                                        **pycompat.strkwargs(opargs or {}))
        pushop.cgresult = repo.githandler.push(remote.path, revs, force)
        return pushop
    else:
        return orig(repo, remote, force, revs, newbranch, bookmarks=bookmarks,
                    opargs=None, **kwargs)


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

    # added in 4.8
    exctype = getattr(error, 'AmbiguousPrefixLookupError', error.LookupError)

    raise exctype(rev, git.map_file, _(b'ambiguous identifier'))


def _gitnodekw(node, repo):
    if not hasattr(repo, 'githandler'):
        return None
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
