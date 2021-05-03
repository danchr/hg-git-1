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

Invalid and dangerous paths
---------------------------

Both Mercurial and Git consider paths as just bytestrings internally,
and allow almost anything. The difference, however, is in the _almost_
part. For example, many Git servers will reject a push for security
reasons if it contains a nested Git repository. Similarly, Mercurial
cannot checkout commits with a nested repository, and it cannot even
store paths containing an embedded newline or carrage return
character.

The default is to issue a warning and skip these paths. You can
change this by setting ``hggit.invalidpaths`` in :hg:`config`::

  [hggit]
  invalidpaths = keep

Possible values are ``keep``, ``skip`` or ``abort``.

'''

from __future__ import generator_stop

# local modules
from . import commands
from . import compat
from . import gitrepo
from . import git_handler
from . import hgrepo
from . import overlay
from . import revsets
from . import schemes
from . import templates
from . import util

from mercurial.node import bin
from mercurial import (
    bundlerepo,
    demandimport,
    dirstate,
    discovery,
    exchange,
    extensions,
    hg,
    manifest,
    pycompat,
    registrar,
    repoview,
)

demandimport.IGNORES |= {
    b'collections',
}

__version__ = b'0.11.0dev'

testedwith = (b'5.2 5.3 5.4 5.5 5.6 5.7 5.8')
minimumhgversion = b'5.2'
buglink = b'https://foss.heptapod.net/mercurial/hg-git/issues'

cmdtable = commands.cmdtable
configtable = {}
configitem = registrar.configitem(configtable)
templatekeyword = templates.templatekeyword

compat.registerconfigs(configitem)


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
    commands.extsetup(ui)
    revsets.extsetup(ui)
    schemes.extsetup(ui)


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

