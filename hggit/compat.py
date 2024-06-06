from dulwich import objects
from dulwich import __version__ as dulvers

from mercurial import exthelper


eh = exthelper.exthelper()


@eh.extsetup
def extsetup(ui):
    # disable optimized implementation that is likely buggy and breaks
    # our tests -- see https://github.com/jelmer/dulwich/issues/1325
    if (0, 22, 0) <= dulvers < (0, 22, 2):
        objects.sorted_tree_items = objects._sorted_tree_items_py
