Load commonly used test logic
  $ . "$TESTDIR/testutil"

Create a Git repository with a single, checked out commit in master:

  $ git init gitrepo
  Initialized empty Git repository in $TESTTMP/gitrepo/.git/
  $ cd gitrepo
  $ echo alpha > alpha
  $ git add alpha
  $ fn_git_commit -m "add alpha"
  $ cd ..

Clone it, and push back to master:

  $ hg clone gitrepo hgrepo
  importing 1 git commits
  new changesets ff7a2f2d8d70 (1 drafts)
  updating to branch default (no-hg57 !)
  updating to bookmark master (hg57 !)
  1 files updated, 0 files merged, 0 files removed, 0 files unresolved
  $ cd hgrepo
  $ echo beta > beta
  $ fn_hg_commit -A -m "add beta"

#if dulwich0204
The output is confusing, and this even more-so:

  $ hg push
  pushing to $TESTTMP/gitrepo
  searching for changes
  adding objects
  remote: error: refusing to update checked out branch: refs/heads/master
  added 1 commits with 1 trees and 1 blobs
  warning: failed to update refs/heads/master; branch is currently checked out

  $ hg push
  pushing to $TESTTMP/gitrepo
  searching for changes
  adding objects
  remote: error: refusing to update checked out branch: refs/heads/master
  added 1 commits with 1 trees and 1 blobs
  warning: failed to update refs/heads/master; branch is currently checked out

#else
This is a bit more sensible:

  $ hg push
  pushing to $TESTTMP/gitrepo
  searching for changes
  adding objects
  remote: error: refusing to update checked out branch: refs/heads/master
  abort: git remote error: refs/heads/master failed to update
  [255]
#endif

Show that it really didn't get pushed:

  $ hg tags
  tip                                1:47580592d3d6
  default/master                     0:ff7a2f2d8d70
  $ cd ../gitrepo
  $ git log --all --oneline --decorate
  7eeab2e (HEAD -> master) add alpha
