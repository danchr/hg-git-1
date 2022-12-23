Load commonly used test logic
  $ . "$TESTDIR/testutil"

  $ git init gitrepo
  Initialized empty Git repository in $TESTTMP/gitrepo/.git/
  $ cd gitrepo
  $ echo alpha > alpha
  $ git add alpha
  $ fn_git_commit -m 'add alpha'
  $ echo beta > beta
  $ git add beta
  $ fn_git_commit -m 'add beta'
  $ git tag thetag


  $ cd ..
  $ hg clone -U gitrepo hgrepo
  importing 2 git commits
  new changesets ff7a2f2d8d70:7fe02317c63d (2 drafts)
  $ cd hgrepo
  $ hg up master
  2 files updated, 0 files merged, 0 files removed, 0 files unresolved
  (activating bookmark master)
  $ hg log --graph
  @  changeset:   1:7fe02317c63d
  |  bookmark:    master
  |  tag:         default/master
  |  tag:         thetag
  |  tag:         tip
  |  user:        test <test@example.org>
  |  date:        Mon Jan 01 00:00:11 2007 +0000
  |  summary:     add beta
  |
  o  changeset:   0:ff7a2f2d8d70
     user:        test <test@example.org>
     date:        Mon Jan 01 00:00:10 2007 +0000
     summary:     add alpha
  
  $ cd ../gitrepo
  $ echo beta line 2 >> beta
  $ git add beta
  $ fn_git_commit -m 'add to beta'

  $ cd ..
  $ cd hgrepo
  $ hg debugstrip --no-backup tip
  0 files updated, 0 files merged, 1 files removed, 0 files unresolved
  $ hg pull
  pulling from $TESTTMP/gitrepo
  importing 1 git commits
  abort: you appear to have run strip - please run hg git-cleanup
  [255]
  $ hg tags
  tip                                0:ff7a2f2d8d70
  $ hg git-cleanup
  git commit map cleaned

pull works after 'hg git-cleanup'

  $ hg pull
  pulling from $TESTTMP/gitrepo
  importing 2 git commits
  updating bookmark master
  new changesets 7fe02317c63d:cc1e605d90db (2 drafts)
  (run 'hg update' to get a working copy)
  $ hg log --graph
  o  changeset:   2:cc1e605d90db
  |  bookmark:    master
  |  tag:         default/master
  |  tag:         tip
  |  user:        test <test@example.org>
  |  date:        Mon Jan 01 00:00:12 2007 +0000
  |  summary:     add to beta
  |
  o  changeset:   1:7fe02317c63d
  |  tag:         thetag
  |  user:        test <test@example.org>
  |  date:        Mon Jan 01 00:00:11 2007 +0000
  |  summary:     add beta
  |
  @  changeset:   0:ff7a2f2d8d70
     user:        test <test@example.org>
     date:        Mon Jan 01 00:00:10 2007 +0000
     summary:     add alpha
  

  $ cd ..
