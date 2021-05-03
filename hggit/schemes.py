# git.py - git server bridge
#
# Copyright 2008 Scott Chacon <schacon at gmail dot com>
#   also some code (and help) borrowed from durin42
#
# This software may be used and distributed according to the terms
# of the GNU General Public License, incorporated herein by reference.

from __future__ import generator_stop

# global modules
import os

# local modules
from . import compat
from . import gitrepo
from . import util

from mercurial import (
    extensions,
    hg,
    localrepo,
)

# support for `hg clone localgitrepo`
_oldlocal = hg.schemes[b'file']

hgdefaultdest = hg.defaultdest

def isgitdir(path):
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


def defaultdest(source):
    for scheme in util.gitschemes:
        if source.startswith(b'%s://' % scheme) and source.endswith(b'.git'):
            return hgdefaultdest(source[:-4])

    if source.endswith(b'.git'):
        return hgdefaultdest(source[:-4])

    return hgdefaultdest(source)


def peer(orig, uiorrepo, *args, **opts):
    newpeer = orig(uiorrepo, *args, **opts)
    if isinstance(newpeer, gitrepo.gitrepo):
        if isinstance(uiorrepo, localrepo.localrepository):
            newpeer.localrepo = uiorrepo
    return newpeer


def isvalidlocalpath(orig, self, path):
    return orig(self, path) or isgitdir(path)


def isurllocal(orig, path):
    # recognise git scp-style paths when cloning
    return orig(path) and not util.isgitsshuri(path._origpath)


def islocal(orig, path):
    # recognise git scp-style paths when cloning
    return orig(path) and not util.isgitsshuri(path)



def hasscheme(orig, path):
    # recognise git scp-style paths
    return orig(path) or util.isgitsshuri(path)


def extsetup(ui):
    extensions.wrapfunction(hg, b'peer', peer)
    extensions.wrapfunction(hg, b'islocal', islocal)
    extensions.wrapfunction(compat.url, b'islocal', isurllocal)
    extensions.wrapfunction(compat.urlutil, b'hasscheme', hasscheme)
    extensions.wrapfunction(compat.path, b'_isvalidlocalpath', isvalidlocalpath)

    hg.schemes[b'https'] = _httpgitwrapper(hg.schemes[b'https'])
    hg.schemes[b'http'] = _httpgitwrapper(hg.schemes[b'http'])
    hg.schemes[b'file'] = _local

    hg.defaultdest = defaultdest

    # support for `hg clone git://github.com/defunkt/facebox.git`
    # also hg clone git+ssh://git@github.com/schacon/simplegit.git
    for _scheme in util.gitschemes:
        hg.schemes[_scheme] = gitrepo
