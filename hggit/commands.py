# git.py - git server bridge
#
# Copyright 2008 Scott Chacon <schacon at gmail dot com>
#   also some code (and help) borrowed from durin42
#
# This software may be used and distributed according to the terms
# of the GNU General Public License, incorporated herein by reference.

from __future__ import generator_stop

# global modules
import os

# local modules
from . import compat
from . import verify

from mercurial.node import hex, nullhex
from mercurial.i18n import _
from mercurial import (
    commands,
    error,
    extensions,
    pycompat,
    registrar,
    scmutil,
)

cmdtable = {}
command = registrar.command(cmdtable)

@command(b'gimport')
def gimport(ui, repo, remote_name=None):
    '''import commits from Git to Mercurial (ADVANCED)

    This command is equivalent to pulling from a Git source, but
    without actually accessing the network. Internally, hg-git relies
    on a local, cached git repository containing changes equivalent to
    the Mercurial repository. If you modify that Git repository
    somehow, use this command to import those changes.

    '''
    repo.githandler.import_commits(remote_name)


@command(b'gexport')
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


@command(b'gclear')
def gclear(ui, repo):
    '''clear out the Git cached data (ADVANCED)

    Strips all Git-related metadata from the repo, including the mapping
    between Git and Mercurial changesets. This is an irreversible
    destructive operation that may prevent further interaction with
    other clones.
    '''
    repo.ui.status(_(b"clearing out the git cache data\n"))
    repo.githandler.clear()


@command(b'debuggitdir')
def gitdir(ui, repo):
    '''get the root of the git repository'''
    repo.ui.write(os.path.normpath(repo.githandler.gitdir), b'\n')


@command(b'gverify',
         [(b'r', b'rev', b'', _(b'revision to verify'), _(b'REV'))],
         _(b'[-r REV]'))
def gverify(ui, repo, **opts):
    '''verify that a Mercurial rev matches the corresponding Git rev

    Given a Mercurial revision that has a corresponding Git revision in the
    map, this attempts to answer whether that revision has the same contents as
    the corresponding Git revision.

    '''
    ctx = scmutil.revsingle(repo, opts.get('rev'), b'.')
    return verify.verify(ui, repo, ctx)


@command(b'git-cleanup')
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


def tag(orig, ui, repo, *names, **opts):
    '''You can also use --git to create a lightweight Git tag. Please note
    that this requires an explicit -r/--rev, and does not support any
    of the other flags.

    Support for Git tags is somewhat minimal. The Git documentation
    heavily discourages changing tags once pushed, and suggests that
    users always create a new one instead. (Unlike Mercurial, Git does
    not track and version its tags within the repository.) As result,
    there's no support for removing and changing preexisting tags.
    Similarly, there's no support for annotated tags, i.e. tags with
    messages, nor for signing tags. For those, either use Git directly
    or use the integrated web interface for tags and releases offered
    by most hosting solutions, including GitHub and GitLab.

    '''

    if not opts.get('git'):
        return orig(ui, repo, *names, **opts)

    opts = pycompat.byteskwargs(opts)

    # check for various unimplemented arguments
    compat.check_incompatible_arguments(opts, b'git', [
        # conflict
        b'local',
        # we currently don't convert or expose this metadata, so
        # disallow setting it on creation
        b'edit',
        b'message',
        b'date',
        b'user',
    ])
    compat.check_at_most_one_arg(opts, b'rev', b'remove')

    if opts[b'remove']:
        opts[b'rev'] = b'null'

    if not opts.get(b'rev'):
        raise error.Abort(_(b'git tags require an explicit revision'),
                          hint=b'please specify -r/--rev')

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


def extsetup(ui):
    commands.table[b'tag'][1].append((b'', b'git', False,
                                  b'make it a git tag'))
    extensions.wrapcommand(
        commands.table,
        b'tag',
        tag,
        docstring='\n\n    ' + tag.__doc__.strip(),
    )
