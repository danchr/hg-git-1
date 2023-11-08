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
        elif hasattr(self.__orig, 'instance'):
            fn = self.__orig.instance
        else:
            # prior to Mercurial 6.4
            fn = self.__orig

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
    # added in Mercurial 6.4
    if hasattr(hg, 'repo_schemes') and hasattr(hg, 'peer_schemes'):
        peer_schemes = hg.peer_schemes

        hg.peer_schemes[b'https'] = RepoFactory(hg.peer_schemes[b'https'])
        hg.peer_schemes[b'http'] = RepoFactory(hg.peer_schemes[b'http'])
        hg.repo_schemes[b'file'] = RepoFactory(hg.repo_schemes[b'file'])

    else:
        peer_schemes = hg.schemes

        _oldlocal = hg.schemes[b'file']

        def _local(path):
            p = urlutil.url(path).localpath()
            if isgitdir(p):
                return gitrepo
            # detect git ssh urls (which mercurial thinks is a file-like path)
            if util.isgitsshuri(p):
                return gitrepo
            return _oldlocal(path)

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
        hg.schemes[b'file'] = _local

    # support for `hg clone git://github.com/defunkt/facebox.git`
    # also hg clone git+ssh://git@github.com/schacon/simplegit.git
    for _scheme in util.gitschemes:
        peer_schemes[_scheme] = gitrepo
