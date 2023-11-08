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
  updating to bookmark master
  1 files updated, 0 files merged, 0 files removed, 0 files unresolved
  $ cd hgrepo
  $ echo beta > beta
  $ fn_hg_commit -A -m "add beta"

The output is confusing, and this even more-so:

  $ hg push
  pushing to $TESTTMP/gitrepo
  searching for changes
  adding objects
  remote: found 0 deltas to reuse (dulwich0210 !)
  remote: error: refusing to update checked out branch: refs/heads/master
  remote: error: By default, updating the current branch in a non-bare repository
  remote: is denied, because it will make the index and work tree inconsistent
  remote: with what you pushed, and will require 'git reset --hard' to match
  remote: the work tree to HEAD.
  remote: 
  remote: You can set the 'receive.denyCurrentBranch' configuration variable
  remote: to 'ignore' or 'warn' in the remote repository to allow pushing into
  remote: its current branch; however, this is not recommended unless you
  remote: arranged to update its work tree to match what you pushed in some
  remote: other way.
  remote: 
  remote: To squelch this message and still keep the default behaviour, set
  remote: 'receive.denyCurrentBranch' configuration variable to 'refuse'.
  added 1 commits with 1 trees and 1 blobs
  warning: failed to update refs/heads/master; branch is currently checked out

  $ hg push
  pushing to $TESTTMP/gitrepo
  searching for changes
  adding objects
  remote: found 0 deltas to reuse (dulwich0210 !)
  remote: error: refusing to update checked out branch: refs/heads/master
  remote: error: By default, updating the current branch in a non-bare repository
  remote: is denied, because it will make the index and work tree inconsistent
  remote: with what you pushed, and will require 'git reset --hard' to match
  remote: the work tree to HEAD.
  remote: 
  remote: You can set the 'receive.denyCurrentBranch' configuration variable
  remote: to 'ignore' or 'warn' in the remote repository to allow pushing into
  remote: its current branch; however, this is not recommended unless you
  remote: arranged to update its work tree to match what you pushed in some
  remote: other way.
  remote: 
  remote: To squelch this message and still keep the default behaviour, set
  remote: 'receive.denyCurrentBranch' configuration variable to 'refuse'.
  added 1 commits with 1 trees and 1 blobs
  warning: failed to update refs/heads/master; branch is currently checked out

Show that it really didn't get pushed:

  $ hg tags
  tip                                1:47580592d3d6
  default/master                     0:ff7a2f2d8d70
  $ cd ../gitrepo
  $ git log --all --oneline --decorate
  7eeab2e (HEAD -> master) add alpha
