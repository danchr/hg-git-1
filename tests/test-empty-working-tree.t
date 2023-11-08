Load commonly used test logic
  $ . "$TESTDIR/testutil"

  $ git init gitrepo
  Initialized empty Git repository in $TESTTMP/gitrepo/.git/
  $ cd gitrepo
  $ git commit --allow-empty -m empty >/dev/null 2>/dev/null || echo "git commit error"

  $ cd ..
  $ git init -q --bare repo.git

  $ hg clone gitrepo hgrepo
  importing 1 git commits
  new changesets 01708ca54a8f (1 drafts)
  updating to bookmark master
  0 files updated, 0 files merged, 0 files removed, 0 files unresolved
  $ cd hgrepo
  $ hg log -r tip --template 'files: {files}\n'
  files: 
  $ hg gverify
  verifying rev 01708ca54a8f against git commit 678256865a8c85ae925bf834369264193c88f8de

  $ hg debug-remove-hggit-state
  clearing out the git cache data
  $ hg push ../repo.git
  pushing to ../repo.git
  searching for changes
  adding objects
  remote: found 0 deltas to reuse (dulwich0210 !)
  added 1 commits with 1 trees and 0 blobs
  adding reference refs/heads/master
  $ cd ..
  $ git --git-dir=repo.git log --pretty=medium
  commit 678256865a8c85ae925bf834369264193c88f8de
  Author: test <test@example.org>
  Date:   Mon Jan 1 00:00:00 2007 +0000
  
      empty
