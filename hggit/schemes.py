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
    bookmarks,
    exthelper,
    hg,
    localrepo,
)

eh = exthelper.exthelper()

# support for `hg clone localgitrepo`
_oldlocal = hg.schemes[b'file']


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


@eh.wrapfunction(hg, b'defaultdest')
def defaultdest(orig, source):
    if source.endswith(b'.git'):
        return orig(source[:-4])

    return orig(source)


@eh.wrapfunction(hg, b'peer')
def peer(orig, uiorrepo, *args, **opts):
    newpeer = orig(uiorrepo, *args, **opts)
    if isinstance(newpeer, gitrepo.gitrepo):
        if isinstance(uiorrepo, localrepo.localrepository):
            newpeer.localrepo = uiorrepo
    return newpeer


@eh.wrapfunction(hg, b'clone')
def clone(orig, *args, **opts):
    srcpeer, destpeer = orig(*args, **opts)

    # HACK: suppress bookmark activation with `--noupdate`
    if isinstance(srcpeer, gitrepo.gitrepo) and not opts.get('update'):
        bookmarks.deactivate(destpeer._repo)

    return srcpeer, destpeer


@eh.wrapfunction(compat.path, b'_isvalidlocalpath')
def isvalidlocalpath(orig, self, path):
    return orig(self, path) or isgitdir(path)


@eh.wrapfunction(compat.url, b'islocal')
def isurllocal(orig, path):
    # recognise git scp-style paths when cloning
    return orig(path) and not util.isgitsshuri(path._origpath)


@eh.wrapfunction(hg, b'islocal')
def islocal(orig, path):
    # recognise git scp-style paths when cloning
    return orig(path) and not util.isgitsshuri(path)


@eh.wrapfunction(compat.urlutil, b'hasscheme')
def hasscheme(orig, path):
    # recognise git scp-style paths
    return orig(path) or util.isgitsshuri(path)


@eh.extsetup
def extsetup(ui):
    hg.schemes[b'https'] = _httpgitwrapper(hg.schemes[b'https'])
    hg.schemes[b'http'] = _httpgitwrapper(hg.schemes[b'http'])
    hg.schemes[b'file'] = _local

    # support for `hg clone git://github.com/defunkt/facebox.git`
    # also hg clone git+ssh://git@github.com/schacon/simplegit.git
    for _scheme in util.gitschemes:
        hg.schemes[_scheme] = gitrepo
