Pushing to Git
==============

Anonymous HEAD
--------------

Git does not allow anonymous heads, so what happens if you try to push
one? Well, you get nothing, since we only push bookmarks, but at we should inform the user of that.

Load commonly used test logic
  $ . "$TESTDIR/testutil"

Create a Git repository with a commit in it

  $ git init gitrepo
  Initialized empty Git repository in $TESTTMP/gitrepo/.git/
  $ cd gitrepo
  $ echo alpha > alpha
  $ git add alpha
  $ fn_git_commit -m "add alpha"
  $ git checkout -d master
  HEAD is now at 7eeab2e add alpha
  $ cd ..

Clone it, deactivate the bookmark, add a commit, and push!

  $ hg clone -U gitrepo hgrepo
  importing 1 git commits
  new changesets ff7a2f2d8d70 (1 drafts)
  $ cd hgrepo
  $ hg up tip
  1 files updated, 0 files merged, 0 files removed, 0 files unresolved
  $ echo beta > beta
  $ hg add beta
  $ fn_hg_commit -m "add beta"

Pushing that changeset should print a helpful message:

  $ hg push
  pushing to $TESTTMP/gitrepo
  searching for changes
  no changes found (ignoring 1 changesets without bookmarks or tags)
  [1]

But what about untagged, but secret changesets?

  $ hg phase -fs tip
  $ hg push
  pushing to $TESTTMP/gitrepo
  searching for changes
  no changes found
  [1]
