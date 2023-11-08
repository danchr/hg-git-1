import bisect
import collections

from mercurial import exthelper
from mercurial import help
from mercurial.i18n import _
from mercurial.utils import stringutil, urlutil

from . import util

eh = exthelper.exthelper()

CONFIG_DEFAULTS = {
    b'git': {
        b'authors': None,
        b'branch_bookmark_suffix': None,
        b'debugextrainmessage': False,  # test only -- do not document this!
        b'findcopiesharder': False,
        b'intree': None,
        b'mindate': None,
        b'public': list,
        b'renamelimit': 400,
        b'similarity': 0,
        b'pull-prune-remote-branches': True,
        b'pull-prune-bookmarks': True,
    },
    b'hggit': {
        b'fetchbuffer': 100,
        b'mapsavefrequency': 1000,
        b'usephases': False,
        b'retries': 3,
        b'invalidpaths': b'skip',
    },
}

for section, items in CONFIG_DEFAULTS.items():
    for item, default in items.items():
        eh.configitem(section, item, default=default)


publishoption = collections.namedtuple(
    'publishoption', ['use_phases', 'publish_defaults', 'refs_to_publish']
)


def get_publishing_option(ui):
    refs = set(ui.configlist(b'git', b'public'))

    return publishoption(ui.configbool(b'hggit', b'usephases'), not refs, refs)


@eh.extsetup
def extsetup(ui):
    @urlutil.pathsuboption(b'hg-git.publish', 'hggit_publish')
    def pathsuboption(ui, path, value):
        b = stringutil.parsebool(value)
        if b is True:
            return publishoption(True, True, frozenset())
        elif b is False:
            return publishoption(False, False, frozenset())
        else:
            return publishoption(
                True, False, frozenset(stringutil.parselist(value))
            )

    def insertconfigurationhelp(ui, topic, doc):
        doc += (
            b'\n\n' + util.get_package_resource("helptext/config.rst").strip()
        )

        return doc

    help.addtopichook(b'config', insertconfigurationhelp)

    entry = (
        [b'hggit-config'],
        _(b"Configuring hg-git"),
        lambda ui: util.get_package_resource("helptext/config.rst"),
        help.TOPIC_CATEGORY_CONFIG,
    )
    bisect.insort(help.helptable, entry)
