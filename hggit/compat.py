from __future__ import absolute_import, print_function

import sys

from mercurial.i18n import _
from mercurial import (
    context,
    error,
    hg,
    node,
    pycompat,
    templatekw,
    ui,
    util as hgutil,
)

try:
    from mercurial.utils import procutil, stringutil
    sshargs = procutil.sshargs
    shellquote = procutil.shellquote
    try:
        quotecommand = procutil.quotecommand
    except AttributeError:
        # procutil.quotecommand() returned the argument unchanged on Python
        # >= 2.7.1 and was removed after Mercurial raised the minimum
        # Python version to 2.7.4.
        assert sys.version_info[:3] >= (2, 7, 1)
        quotecommand = pycompat.identity
    binary = stringutil.binary
    try:
        # added in 4.8
        tonativestr = procutil.tonativestr
    except AttributeError:
        assert not pycompat.ispy3
        tonativestr = pycompat.identity
except ImportError:
    assert not pycompat.ispy3
    # these were moved in 4.6
    sshargs = hgutil.sshargs
    shellquote = hgutil.shellquote
    quotecommand = hgutil.quotecommand
    binary = hgutil.binary
    tonativestr = pycompat.identity

try:
    from mercurial.pycompat import iteritems, itervalues
except ImportError:
    assert not pycompat.ispy3
    iteritems = lambda x: x.iteritems()
    itervalues = lambda x: x.itervalues()

try:
    # added in 5.9
    from mercurial.node import sha1nodeconstants
except ImportError:
    class sha1nodeconstants(object):
        nodelen = len(node.nullid)

        nullid = node.nullid
        nullhex = node.nullhex
        newnodeid = node.newnodeid
        addednodeid = node.addednodeid
        modifiednodeid = node.modifiednodeid
        # added in 4.6
        if hasattr(node, 'wdirfilenodeids'):
            wdirfilenodeids = node.wdirfilenodeids
        wdirid = node.wdirid
        wdirhex = node.wdirhex

try:
    # added in 5.8
    from mercurial.utils import urlutil

    url = urlutil.url
    path = urlutil.path
except ImportError:
    urlutil = hgutil
    url = hgutil.url
    path = ui.path

try:
    from mercurial.cmdutil import check_at_most_one_arg
except (ImportError, AttributeError):
    # added in 5.3
    def check_at_most_one_arg(opts, *args):
        """abort if more than one of the arguments are in opts

        Returns the unique argument or None if none of them were specified.
        """

        def to_display(name):
            # 5.2 does not check this
            if isinstance(name, unicode):
                name = pycompat.sysbytes(name)
            return name.replace(b'_', b'-')

        previous = None
        for x in args:
            if opts.get(x):
                if previous:
                    raise error.Abort(
                        _(b'cannot specify both --%s and --%s')
                        % (to_display(previous), to_display(x))
                    )
                previous = x
        return previous

# added in 5.3 but changed in 5.4, so always use our implementation
def check_incompatible_arguments(opts, first, others):
    """abort if the first argument is given along with any of the others

    Unlike check_at_most_one_arg(), `others` are not mutually exclusive
    among themselves, and they're passed as a single collection.
    """
    for other in others:
        check_at_most_one_arg(opts, first, other)

try:
    from mercurial.scmutil import isrevsymbol
except (ImportError, AttributeError):
    # added in 4.6, although much more thorough; if you want better
    # error checking, use the latest hg!
    def isrevsymbol(repo, symbol):
        try:
            repo.lookup(symbol)
            return True
        except error.RepoLookupError:
            return False

try:
    unicode = unicode
    assert unicode  # silence pyflakes
except NameError:
    from mercurial.pycompat import unicode

quote = hgutil.urlreq.quote
unquote = hgutil.urlreq.unquote


try:
    from mercurial.hg import sharedreposource
except (ImportError, AttributeError):
    # added in 4.6
    def sharedreposource(repo):
        """Returns repository object for source repository of a shared repo.

        If repo is not a shared repository, returns None.
        """
        if repo.sharedpath == repo.path:
            return None

        if hgutil.safehasattr(repo, b'srcrepo') and repo.srcrepo:
            return repo.srcrepo

        # the sharedpath always ends in the .hg; we want the path to the repo
        source = repo.vfs.split(repo.sharedpath)[0]
        srcurl, branches = hg.parseurl(source)
        srcrepo = hg.repository(repo.ui, srcurl)
        repo.srcrepo = srcrepo
        return srcrepo


def memfilectx(repo, changectx, path, data, islink=False,
               isexec=False, copysource=None):
    # Different versions of mercurial have different parameters to
    # memfilectx.  Try them from newest to oldest.
    parameters_to_try = (
        ((repo, changectx, path, data), { 'copysource': copysource }), # hg >= 5.0
        ((repo, changectx, path, data), { 'copied': copysource }),     # hg 4.5 - 4.9.1
        ((repo, path, data),            { 'copied': copysource }),     # hg 3.1 - 4.4.2
    )
    for (args, kwargs) in parameters_to_try:
        try:
            return context.memfilectx(*args,
                                      islink=islink,
                                      isexec=isexec,
                                      **kwargs)
        except TypeError as ex:
            last_ex = ex
    raise last_ex


CONFIG_DEFAULTS = {
    b'git': {
        b'authors': None,
        b'blockdotgit': True,
        b'blockdothg': True,
        b'branch_bookmark_suffix': None,
        b'debugextrainmessage': False,   # test only -- do not document this!
        b'findcopiesharder': False,
        b'intree': None,
        b'mindate': None,
        b'public': list,
        b'renamelimit': 400,
        b'similarity': 0,
    },
    b'hggit': {
        b'mapsavefrequency': 0,
        b'usephases': False,
    }
}

hasconfigitems = False


def registerconfigs(configitem):
    global hasconfigitems
    hasconfigitems = True
    for section, items in iteritems(CONFIG_DEFAULTS):
        for item, default in iteritems(items):
            configitem(section, item, default=default)


def config(ui, subtype, section, item):
    if subtype == b'string':
        subtype = b''
    getconfig = getattr(ui, 'config' + pycompat.sysstr(subtype))
    if hasconfigitems:
        return getconfig(section, item)
    return getconfig(section, item, CONFIG_DEFAULTS[section][item])


class templatekeyword(object):
    def __init__(self):
        self._table = {}

    def __call__(self, name):
        def decorate(func):
            templatekw.keywords.update({name: func})
            return func
        return decorate


class progress(object):
    '''Simplified implementation of mercurial.scmutil.progress for
    compatibility with hg < 4.7'''
    def __init__(self, ui, _updatebar, topic, unit=b"", total=None):
        self.ui = ui
        self.pos = 0
        self.topic = topic
        self.unit = unit
        self.total = total

    def __enter__(self):
        return self

    def __exit__(self, exc_type, exc_value, exc_tb):
        self.complete()

    def _updatebar(self, item=b""):
        self.ui.progress(self.topic, self.pos, item, self.unit, self.total)

    def update(self, pos, item=b"", total=None):
        self.pos = pos
        if total is not None:
            self.total = total
        self._updatebar(item)

    def increment(self, step=1, item=b"", total=None):
        self.update(self.pos + step, item, total)

    def complete(self):
        self.unit = b""
        self.total = None
        self.update(None)


# no makeprogress in < 4.7
if hgutil.safehasattr(ui.ui, b'makeprogress'):
    def makeprogress(ui, topic, unit=b"", total=None):
        return ui.makeprogress(topic, unit, total)
else:
    def makeprogress(ui, topic, unit=b"", total=None):
        return progress(ui, None, topic, unit, total)
