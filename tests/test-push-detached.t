Pushing to Git
==============

Detached HEAD
-------------

Most remote Git repositories reside on a hosting service, such as
Github or GitLab, and have HEAD pointing to the default branch,
usually `master` or `main`. Local repositories, can end up in a
detached state, where HEAD rather than being a symref pointing to
another ref, is a direct ref pointing to a commit.

This test excercises that specific edge case: Pushing to a repository
with a detached head. With publishing-on-push, there are two possible
failure modes we want to prevent.

1) Did we assume that HEAD is a symref?
2) What happens when you push to a descendent of HEAD, but HEAD is draft?


Load commonly used test logic
  $ . "$TESTDIR/testutil"

Create a Git repository with a detached head

  $ git init gitrepo
  Initialized empty Git repository in $TESTTMP/gitrepo/.git/
  $ cd gitrepo
  $ echo alpha > alpha
  $ git add alpha
  $ fn_git_commit -m "add alpha"
  $ git checkout -d master
  HEAD is now at 7eeab2e add alpha
  $ cd ..

Verify that we can push to a Git repository that has a detached HEAD

With detection of HEAD on push, it is easy to implicitly assume that
HEAD is a symref. To prevent this, we specifically verify that pushing
in this case continues to work.

  $ hg clone gitrepo hgrepo
  importing 1 git commits
  new changesets ff7a2f2d8d70 (1 drafts)
  updating to bookmark master
  1 files updated, 0 files merged, 0 files removed, 0 files unresolved
  $ cd hgrepo
  $ echo beta > beta
  $ hg add beta
  $ fn_hg_commit -m "add beta"

Pushing that changeset, with phases, publishes the detached HEAD.
Whether this should happen is debatable, but it's a side effect from
the fact that pushing to the remote HEAD, with HEAD being the usual
symref, should publish it.

  $ hg push -v --config hggit.usephases=yes
  pushing to $TESTTMP/gitrepo
  finding unexported changesets
  exporting 1 changesets
  converting revision 47580592d3d6492421a1e6cebc5c2d701a2e858b
  searching for changes
  remote: counting objects: 5, done. (dulwich0210 !)
  1 commits found
  adding objects
  remote: counting objects: 5, done. (dulwich0210 !)
  remote: found 0 deltas to reuse (dulwich0210 !)
  added 1 commits with 1 trees and 1 blobs
  updating reference default::refs/heads/master => GIT:0f378ab6
  publishing remote HEAD
  $ hg phase 'all()'
  0: public
  1: draft
  $ cd ..

