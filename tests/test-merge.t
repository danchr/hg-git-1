Load commonly used test logic
  $ . "$TESTDIR/testutil"

  $ git init gitrepo
  Initialized empty Git repository in $TESTTMP/gitrepo/.git/
  $ cd gitrepo
  $ echo alpha > alpha
  $ git add alpha
  $ fn_git_commit -m 'add alpha'

  $ git checkout -b beta 2>&1 | sed s/\'/\"/g
  Switched to a new branch "beta"
  $ echo beta > beta
  $ git add beta
  $ fn_git_commit -m 'add beta'

  $ git checkout master 2>&1 | sed s/\'/\"/g
  Switched to branch "master"
  $ echo gamma > gamma
  $ git add gamma
  $ fn_git_commit -m 'add gamma'

clean merge
  $ git merge -q -m "Merge branch 'beta'" beta
  $ git show --oneline
  5806851 Merge branch 'beta'
  

  $ cd ..
  $ git init -q --bare repo.git

  $ hg clone gitrepo hgrepo
  importing 4 git commits
  new changesets ff7a2f2d8d70:89ca4a68d6b9 (4 drafts)
  updating to bookmark master
  3 files updated, 0 files merged, 0 files removed, 0 files unresolved
  $ cd hgrepo

clear the cache to be sure it is regenerated correctly
  $ hg debug-remove-hggit-state
  clearing out the git cache data
  $ hg push ../repo.git
  pushing to ../repo.git
  searching for changes
  adding objects
  remote: found 0 deltas to reuse (dulwich0210 !)
  added 4 commits with 4 trees and 3 blobs
  adding reference refs/heads/beta
  adding reference refs/heads/master

  $ cd ..
git log in repo pushed from hg
  $ git --git-dir=repo.git log --pretty=medium master | sed 's/\.\.\.//g'
  commit 5806851511aaf3bfe813ae3a86c5027165fa9b96
  Merge: e5023f9 9497a4e
  Author: test <test@example.org>
  Date:   Mon Jan 1 00:00:12 2007 +0000
  
      Merge branch 'beta'
  
  commit e5023f9e5cb24fdcec7b6c127cec45d8888e35a9
  Author: test <test@example.org>
  Date:   Mon Jan 1 00:00:12 2007 +0000
  
      add gamma
  
  commit 9497a4ee62e16ee641860d7677cdb2589ea15554
  Author: test <test@example.org>
  Date:   Mon Jan 1 00:00:11 2007 +0000
  
      add beta
  
  commit 7eeab2ea75ec1ac0ff3d500b5b6f8a3447dd7c03
  Author: test <test@example.org>
  Date:   Mon Jan 1 00:00:10 2007 +0000
  
      add alpha
  $ git --git-dir=repo.git log --pretty=medium beta | sed 's/\.\.\.//g'
  commit 9497a4ee62e16ee641860d7677cdb2589ea15554
  Author: test <test@example.org>
  Date:   Mon Jan 1 00:00:11 2007 +0000
  
      add beta
  
  commit 7eeab2ea75ec1ac0ff3d500b5b6f8a3447dd7c03
  Author: test <test@example.org>
  Date:   Mon Jan 1 00:00:10 2007 +0000
  
      add alpha
