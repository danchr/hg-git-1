# git.py - git server bridge
#
# Copyright 2008 Scott Chacon <schacon at gmail dot com>
#   also some code (and help) borrowed from durin42
#
# This software may be used and distributed according to the terms
# of the GNU General Public License, incorporated herein by reference.

# global modules
from dulwich import porcelain

from mercurial.node import hex, nullhex
from mercurial.i18n import _
from mercurial import (
    cmdutil,
    error,
    exthelper,
    pycompat,
    registrar,
    scmutil,
)

# local modules
from . import verify

eh = exthelper.exthelper()


@eh.command(
    b'git-import|gimport',
    helpcategory=registrar.command.CATEGORY_IMPORT_EXPORT,
)
def gimport(ui, repo, remote_name=None):
    '''import commits from Git to Mercurial (ADVANCED)

    This command is equivalent to pulling from a Git source, but
    without actually accessing the network. Internally, hg-git relies
    on a local, cached git repository containing changes equivalent to
    the Mercurial repository. If you modify that Git repository
    somehow, use this command to import those changes.

    '''
    with repo.wlock():
        repo.githandler.import_commits(remote_name)


@eh.command(
    b'git-export|gexport',
    helpcategory=registrar.command.CATEGORY_IMPORT_EXPORT,
)
def gexport(ui, repo):
    '''export commits from Mercurial to Git (ADVANCED)

    This command is equivalent to pushing to a Git source, but without
    actually access the network. Internally, hg-git relies on a local,
    cached git repository containing changes equivalent to the
    Mercurial repository. If you wish to see what the Git commits
    would be, use this command to export those changes. As an example,
    it ensures that all changesets have a corresponding Git node.

    '''
    repo.githandler.export_commits()


@eh.command(
    b'git-verify|gverify',
    [
        (b'r', b'rev', b'', _(b'revision to verify'), _(b'REV')),
        (b'c', b'fsck', False, _(b'verify repository integrity as well')),
    ],
    _(b'[-r REV]'),
    helpcategory=registrar.command.CATEGORY_MAINTENANCE,
)
def gverify(ui, repo, **opts):
    '''verify that a Mercurial rev matches the corresponding Git rev

    Given a Mercurial revision that has a corresponding Git revision in the
    map, this attempts to answer whether that revision has the same contents as
    the corresponding Git revision.

    '''

    if opts.get('fsck'):
        for badsha, e in porcelain.fsck(repo.githandler.git):
            raise error.Abort(b'git repository is corrupt!')

    ctx = scmutil.revsingle(repo, opts.get('rev'), b'.')
    return verify.verify(ui, repo, ctx)


@eh.command(b'git-cleanup', helpcategory=registrar.command.CATEGORY_MAINTENANCE)
def git_cleanup(ui, repo):
    '''clean up Git commit map after history editing'''
    new_map = []
    gh = repo.githandler
    for line in gh.vfs(gh.map_file):
        gitsha, hgsha = line.strip().split(b' ', 1)
        if hgsha in repo:
            new_map.append(b'%s %s\n' % (gitsha, hgsha))
    with repo.githandler.store_repo.wlock():
        f = gh.vfs(gh.map_file, b'wb')
        f.writelines(new_map)
    ui.status(_(b'git commit map cleaned\n'))


@eh.wrapcommand(
    b'tag',
    opts=[
        (
            b'',
            b'git',
            False,
            b'''create a lightweight Git tag; this requires an explicit -r/--rev,
        and does not support any of the other flags''',
        )
    ],
)
def tag(orig, ui, repo, *names, **opts):
    if not opts.get('git'):
        return orig(ui, repo, *names, **opts)

    opts = pycompat.byteskwargs(opts)

    # check for various unimplemented arguments
    cmdutil.check_incompatible_arguments(
        opts,
        b'git',
        [
            # conflict
            b'local',
            # we currently don't convert or expose this metadata, so
            # disallow setting it on creation
            b'edit',
            b'message',
            b'date',
            b'user',
        ],
    )
    cmdutil.check_at_most_one_arg(opts, b'rev', b'remove')

    if opts[b'remove']:
        opts[b'rev'] = b'null'

    if not opts.get(b'rev'):
        raise error.Abort(
            _(b'git tags require an explicit revision'),
            hint=b'please specify -r/--rev',
        )

    # the semantics of git tag editing are quite confusing, so we
    # don't bother; if you _really_ want to, use another tool to do
    # this, and ensure all contributors prune their tags -- otherwise,
    # it'll reappear next time someone pushes tags (ah, the wonders of
    # nonversioned markers!)
    #
    # see also https://git-scm.com/docs/git-tag#_discussion
    if opts[b'force']:
        raise error.Abort(
            b'cannot move git tags',
            hint=b'the git documentation heavily discourages editing tags',
        )

    names = [t.strip() for t in names]

    if len(names) != len(set(names)):
        raise error.Abort(_('tag names must be unique'))

    with repo.wlock(), repo.lock():
        target = hex(repo.lookup(opts[b'rev']))

        # see above
        if target == nullhex:
            raise error.Abort(
                b'cannot remove git tags',
                hint=b'the git documentation heavily discourages editing tags',
            )

        repo.githandler.add_tag(target, *names)
