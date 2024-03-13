# git.py - git server bridge
#
# Copyright 2008 Scott Chacon <schacon at gmail dot com>
#   also some code (and help) borrowed from durin42
#
# This software may be used and distributed according to the terms
# of the GNU General Public License, incorporated herein by reference.

# global modules
import os

from mercurial import (
    bookmarks,
    exthelper,
    hg,
    localrepo,
)
from mercurial.utils import urlutil

# local modules
from . import gitrepo
from . import util

eh = exthelper.exthelper()


def isgitdir(path):
    """True if the given file path is a git repo."""
    if os.path.exists(os.path.join(path, b'.hg')):
        return False

    if os.path.exists(os.path.join(path, b'.git')):
        # is full git repo
        return True

    if (
        os.path.exists(os.path.join(path, b'HEAD'))
        and os.path.exists(os.path.join(path, b'objects'))
        and os.path.exists(os.path.join(path, b'refs'))
    ):
        # is bare git repo
        return True

    return False


class RepoFactory:
    """thin wrapper to dispatch between git repos and mercurial ones"""

    __slots__ = ('__orig',)

    def __init__(self, orig):
        self.__orig = orig

    @property
    def islocal(self):
        '''indirection that allows us to only claim we're local if the wrappee is'''
        if hasattr(self.__orig, 'islocal'):
            return self.__islocal
        else:
            raise AttributeError('islocal')

    def __islocal(self, path: bytes) -> bool:
        if isgitdir(path):
            return True
        # detect git ssh urls (which mercurial thinks is a file-like path)
        if util.isgitsshuri(path):
            return False
        return self.__orig.islocal(path)

    def instance(self, ui, path, *args, **kwargs):
        if isinstance(path, bytes):
            url = urlutil.url(path)
        else:
            url = path.url

        p = url.localpath()
        # detect git ssh urls (which mercurial thinks is a file-like path)
        if isgitdir(p) or util.isgitsshuri(p) or p.endswith(b'.git'):
            fn = gitrepo.instance
        else:
            fn = self.__orig.instance

        return fn(ui, path, *args, **kwargs)

    def make_peer(self, ui, path, *args, **kwargs):
        p = path.url.localpath()
        # detect git ssh urls (which mercurial thinks is a file-like path)
        if isgitdir(p) or util.isgitsshuri(p) or p.endswith(b'.git'):
            fn = gitrepo.instance
        elif hasattr(self.__orig, 'make_peer'):
            fn = self.__orig.make_peer

        return fn(ui, path, *args, **kwargs)


@eh.wrapfunction(hg, 'defaultdest')
def defaultdest(orig, source):
    if source.endswith(b'.git'):
        return orig(source[:-4])

    return orig(source)


@eh.wrapfunction(hg, 'peer')
def peer(orig, uiorrepo, *args, **opts):
    newpeer = orig(uiorrepo, *args, **opts)
    if isinstance(newpeer, gitrepo.gitrepo):
        if isinstance(uiorrepo, localrepo.localrepository):
            newpeer.localrepo = uiorrepo
    return newpeer


@eh.wrapfunction(hg, 'clone')
def clone(orig, *args, **opts):
    srcpeer, destpeer = orig(*args, **opts)

    # HACK: suppress bookmark activation with `--noupdate`
    if isinstance(srcpeer, gitrepo.gitrepo) and not opts.get('update'):
        bookmarks.deactivate(destpeer._repo)

    return srcpeer, destpeer


@eh.wrapfunction(urlutil.path, '_isvalidlocalpath')
def isvalidlocalpath(orig, self, path):
    return orig(self, path) or isgitdir(path)


@eh.wrapfunction(urlutil.url, 'islocal')
def isurllocal(orig, path):
    # recognise git scp-style paths when cloning
    return orig(path) and not util.isgitsshuri(path._origpath)


@eh.wrapfunction(hg, 'islocal')
def islocal(orig, path):
    # recognise git scp-style paths when cloning
    return orig(path) and not util.isgitsshuri(path)


@eh.wrapfunction(urlutil, 'hasscheme')
def hasscheme(orig, path):
    # recognise git scp-style paths
    return orig(path) or util.isgitsshuri(path)


@eh.extsetup
def extsetup(ui):
    hg.peer_schemes[b'https'] = RepoFactory(hg.peer_schemes[b'https'])
    hg.peer_schemes[b'http'] = RepoFactory(hg.peer_schemes[b'http'])
    hg.repo_schemes[b'file'] = RepoFactory(hg.repo_schemes[b'file'])

    # support for `hg clone git://github.com/defunkt/facebox.git`
    # also hg clone git+ssh://git@github.com/schacon/simplegit.git
    for _scheme in util.gitschemes:
        hg.peer_schemes[_scheme] = gitrepo
