from __future__ import generator_stop

from mercurial.i18n import _
from mercurial import (
    error,
    node,
    pycompat,
    ui,
    util as hgutil,
)

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
            if isinstance(name, str):
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


CONFIG_DEFAULTS = {
    b'git': {
        b'authors': None,
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
        b'invalidpaths': b'skip',
    }
}

def registerconfigs(configitem):
    for section, items in CONFIG_DEFAULTS.items():
        for item, default in items.items():
            configitem(section, item, default=default)
