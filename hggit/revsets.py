from mercurial import error
from mercurial import exthelper
from mercurial import revset
from mercurial.i18n import _
from mercurial.node import bin, hex
from mercurial.utils import stringutil

eh = exthelper.exthelper()


@eh.revsetpredicate(b'fromgit')
def revset_fromgit(repo, subset, x):
    '''``fromgit()``
    Select changesets that originate from Git.
    '''
    revset.getargs(x, 0, 0, b"fromgit takes no arguments")
    git = repo.githandler
    node = repo.changelog.node
    return revset.baseset(
        r for r in subset if git.map_git_get(hex(node(r))) is not None
    )


@eh.revsetpredicate(b'gitnode')
def revset_gitnode(repo, subset, x):
    '''``gitnode(hash)``
    Select the changeset that originates in the given Git revision. The hash
    may be abbreviated: `gitnode(a5b)` selects the revision whose Git hash
    starts with `a5b`. Aborts if multiple changesets match the abbreviation.
    '''
    args = revset.getargs(x, 1, 1, b"gitnode takes one argument")
    rev = revset.getstring(args[0], b"the argument to gitnode() must be a hash")
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
        rev,
        git.map_file,
        _(b'ambiguous identifier'),
    )


@eh.revsetpredicate(b'gittag')
def revset_gittag(repo, subset, x):
    """``gittag([name])``

    The specified Git tag by name, or all revisions tagged with Git if
    no name is given.

    Pattern matching is supported for `name`. See
    :hg:`help revisions.patterns`.

    """
    # mostly copied from tag() mercurial/revset.py

    # i18n: "tag" is a keyword
    args = revset.getargs(x, 0, 1, _(b"tag takes one or no arguments"))
    cl = repo.changelog
    git = repo.githandler

    if args:
        pattern = revset.getstring(
            args[0],
            # i18n: "tag" is a keyword
            _(b'the argument to tag must be a string'),
        )
        kind, pattern, matcher = stringutil.stringmatcher(pattern)
        if kind == b'literal':
            # avoid resolving all tags
            tn = git.tags.get(pattern, None)
            if tn is None:
                raise error.RepoLookupError(
                    _(b"git tag '%s' does not exist") % pattern
                )
            s = {repo[bin(tn)].rev()}
        else:
            s = {cl.rev(bin(n)) for t, n in git.tags.items() if matcher(t)}
    else:
        s = {cl.rev(bin(n)) for t, n in git.tags.items()}
    return subset & s
