Load commonly used test logic
  $ . "$TESTDIR/testutil"

  $ git init gitrepo
  Initialized empty Git repository in $TESTTMP/gitrepo/.git/
  $ cd gitrepo
  $ mkdir d1
  $ echo a > d1/f1
  $ echo b > d1/f2
  $ git add d1/f1 d1/f2
  $ fn_git_commit -m initial

  $ mkdir d2
  $ git mv d1/f2 d2/f2
  $ fn_git_commit -m 'rename'

  $ rm -r d1
  $ echo c > d1
  $ git add --all d1
  $ fn_git_commit -m 'replace a dir with a file'


  $ cd ..
  $ git init -q --bare repo.git

  $ hg clone gitrepo hgrepo
  importing 3 git commits
  new changesets d4d3d2417141:541f27994b81 (3 drafts)
  updating to bookmark master
  2 files updated, 0 files merged, 0 files removed, 0 files unresolved
  $ cd hgrepo
  $ hg log --template 'adds: {file_adds}\ndels: {file_dels}\n'
  adds: d1
  dels: d1/f1
  adds: d2/f2
  dels: d1/f2
  adds: d1/f1 d1/f2
  dels: 

  $ hg debug-remove-hggit-state
  clearing out the git cache data
  $ hg push ../repo.git
  pushing to ../repo.git
  searching for changes
  adding objects
  remote: found 0 deltas to reuse
  added 3 commits with 6 trees and 3 blobs
  adding reference refs/heads/master
  $ cd ..

  $ git --git-dir=repo.git log --pretty=medium
  commit 6e0dbd8cd92ed4823c69cb48d8a2b81f904e6e69
  Author: test <test@example.org>
  Date:   Mon Jan 1 00:00:12 2007 +0000
  
      replace a dir with a file
  
  commit a1874d5cd0b1549ed729e36f0da4a93ed36259ee
  Author: test <test@example.org>
  Date:   Mon Jan 1 00:00:11 2007 +0000
  
      rename
  
  commit 102c17a5deda49db3f10ec5573f9378867098b7c
  Author: test <test@example.org>
  Date:   Mon Jan 1 00:00:10 2007 +0000
  
      initial
