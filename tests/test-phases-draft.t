Load commonly used test logic
  $ . "$TESTDIR/testutil"

  $ git init gitrepo
  Initialized empty Git repository in $TESTTMP/gitrepo/.git/
  $ cd gitrepo
  $ git config receive.denyCurrentBranch ignore
  $ echo alpha > alpha
  $ git add alpha
  $ fn_git_commit -m "add alpha"

cloning without hggit.usephases does not publish local changesets
  $ cd ..
  $ hg clone gitrepo hgrepo | grep -v '^updating'
  importing 1 git commits
  new changesets ff7a2f2d8d70 (1 drafts)
  1 files updated, 0 files merged, 0 files removed, 0 files unresolved

  $ cd hgrepo
  $ hg phase -r master
  0: draft

pulling advances the draft phase, though

  $ hg phase -fs 0
  $ hg pull
  pulling from $TESTTMP/gitrepo
  no changes found
  $ hg phase tip
  0: draft

even if we don't have a name?

  $ hg phase -fs 0
  $ mv .hg/hgrc .hg/hgrc.bak
  $ hg pull ../gitrepo
  pulling from ../gitrepo
  no changes found
  $ hg phase tip
  0: draft
  $ mv .hg/hgrc.bak .hg/hgrc
  $ cd ..


pulling without hggit.usephases does not publish local changesets
  $ cd gitrepo
  $ git checkout -q master
  $ echo beta > beta
  $ git add beta
  $ fn_git_commit -m 'add beta'
  $ cd ..

  $ cd hgrepo
  $ hg pull
  pulling from $TESTTMP/gitrepo
  importing 1 git commits
  updating bookmark master
  new changesets 7fe02317c63d (1 drafts)
  (run 'hg update' to get a working copy)
  $ hg phase -r master
  1: draft

pulling with git.public does not publish local changesets
  $ hg --config git.public=master pull
  pulling from $TESTTMP/gitrepo
  no changes found
  $ hg phase -r master
  1: draft

pushing without hggit.usephases does not publish local changesets
  $ hg update master
  1 files updated, 0 files merged, 0 files removed, 0 files unresolved
  $ echo gamma > gamma
  $ hg add gamma
  $ hg commit -m 'gamma'
  $ hg push
  pushing to $TESTTMP/gitrepo
  searching for changes
  adding objects
  remote: found 0 deltas to reuse (dulwich0210 !)
  added 1 commits with 1 trees and 1 blobs
  updating reference refs/heads/master
  $ hg phase -r master
  2: draft
