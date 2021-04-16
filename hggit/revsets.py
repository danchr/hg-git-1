from __future__ import generator_stop

from mercurial import error
from mercurial import revset
from mercurial.i18n import _
from mercurial.node import hex


def extsetup(ui):
    revset.symbols.update({
        b'fromgit': revset_fromgit, b'gitnode': revset_gitnode
    })


def revset_fromgit(repo, subset, x):
    '''``fromgit()``
    Select changesets that originate from Git.
    '''
    revset.getargs(x, 0, 0, b"fromgit takes no arguments")
    git = repo.githandler
    node = repo.changelog.node
    return revset.baseset(r for r in subset
                          if git.map_git_get(hex(node(r))) is not None)


def revset_gitnode(repo, subset, x):
    '''``gitnode(hash)``
    Select the changeset that originates in the given Git revision. The hash
    may be abbreviated: `gitnode(a5b)` selects the revision whose Git hash
    starts with `a5b`. Aborts if multiple changesets match the abbreviation.
    '''
    args = revset.getargs(x, 1, 1, b"gitnode takes one argument")
    rev = revset.getstring(args[0],
                           b"the argument to gitnode() must be a hash")
    git = repo.githandler
    node = repo.changelog.node

    def matches(r):
        gitnode = git.map_git_get(hex(node(r)))
        if gitnode is None:
            return False
        return gitnode.startswith(rev)
    result = revset.baseset(r for r in subset if matches(r))
    if 0 <= len(result) < 2:
        return result

    raise error.AmbiguousPrefixLookupError(
        rev, git.map_file, _(b'ambiguous identifier'),
    )
