# git.py - git server bridge
#
# Copyright 2008 Scott Chacon <schacon at gmail dot com>
#   also some code (and help) borrowed from durin42
#
# This software may be used and distributed according to the terms
# of the GNU General Public License, incorporated herein by reference.

from mercurial import exthelper

eh = exthelper.exthelper()


def _gitnodekw(node, repo):
    if not hasattr(repo, 'githandler'):
        return None
    gitnode = repo.githandler.map_git_get(node.hex())
    if gitnode is None:
        gitnode = b''
    return gitnode


@eh.templatekeyword(b'gitnode', requires={b'ctx', b'repo'})
def gitnodekw(context, mapping):
    """:gitnode: String. The Git changeset identification hash, as a
    40 hexadecimal digit string."""
    node = context.resource(mapping, b'ctx')
    repo = context.resource(mapping, b'repo')
    return _gitnodekw(node, repo)
