from __future__ import generator_stop

from mercurial import registrar

configtable = {}
configitem = registrar.configitem(configtable)

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

for section, items in CONFIG_DEFAULTS.items():
    for item, default in items.items():
        configitem(section, item, default=default)
