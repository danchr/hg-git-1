Load commonly used test logic
  $ . "$TESTDIR/testutil"

  $ git init gitrepo
  Initialized empty Git repository in $TESTTMP/gitrepo/.git/
  $ cd gitrepo
  $ echo alpha > alpha
  $ git add alpha
  $ fn_git_commit -m 'add alpha'
  $ git checkout -q --detach
  $ echo omega > omega
  $ git add omega
  $ fn_git_commit -m 'add omega'
  $ git tag theothertag
  $ git checkout -q master
  $ echo beta > beta
  $ git add beta
  $ fn_git_commit -m 'add beta'
  $ git tag thetag


  $ cd ..
  $ hg clone -U gitrepo hgrepo
  importing 3 git commits
  new changesets ff7a2f2d8d70:5403d6137622 (3 drafts)
  $ cd hgrepo
  $ hg up master
  2 files updated, 0 files merged, 0 files removed, 0 files unresolved
  (activating bookmark master)
  $ hg log --graph
  @  changeset:   2:5403d6137622
  |  bookmark:    master
  |  tag:         default/master
  |  tag:         thetag
  |  tag:         tip
  |  parent:      0:ff7a2f2d8d70
  |  user:        test <test@example.org>
  |  date:        Mon Jan 01 00:00:12 2007 +0000
  |  summary:     add beta
  |
  | o  changeset:   1:6202c19d7dd9
  |/   tag:         theothertag
  |    user:        test <test@example.org>
  |    date:        Mon Jan 01 00:00:11 2007 +0000
  |    summary:     add omega
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
  $ hg debugstrip --no-backup master
  0 files updated, 0 files merged, 1 files removed, 0 files unresolved
  $ hg pull
  pulling from $TESTTMP/gitrepo
  importing 1 git commits
  abort: you appear to have run strip - please run hg git-cleanup
  [255]
  $ hg tags
  tip                                1:6202c19d7dd9
  theothertag                        1:6202c19d7dd9
  $ hg git-cleanup
  git commit map cleaned

pull works after 'hg git-cleanup'

  $ hg pull
  pulling from $TESTTMP/gitrepo
  importing 2 git commits
  updating bookmark master
  new changesets 5403d6137622:1745c5b062eb (2 drafts)
  (run 'hg heads' to see heads, 'hg merge' to merge)
  $ hg log --graph
  o  changeset:   3:1745c5b062eb
  |  bookmark:    master
  |  tag:         default/master
  |  tag:         tip
  |  user:        test <test@example.org>
  |  date:        Mon Jan 01 00:00:13 2007 +0000
  |  summary:     add to beta
  |
  o  changeset:   2:5403d6137622
  |  tag:         thetag
  |  parent:      0:ff7a2f2d8d70
  |  user:        test <test@example.org>
  |  date:        Mon Jan 01 00:00:12 2007 +0000
  |  summary:     add beta
  |
  | o  changeset:   1:6202c19d7dd9
  |/   tag:         theothertag
  |    user:        test <test@example.org>
  |    date:        Mon Jan 01 00:00:11 2007 +0000
  |    summary:     add omega
  |
  @  changeset:   0:ff7a2f2d8d70
     user:        test <test@example.org>
     date:        Mon Jan 01 00:00:10 2007 +0000
     summary:     add alpha
  

  $ cd ..

And does it affect no-op pulls of tags?

  $ hg init hgrepo2
  $ cd hgrepo2
  $ hg pull ../gitrepo
  pulling from ../gitrepo
  importing 4 git commits
  adding bookmark master
  new changesets ff7a2f2d8d70:1745c5b062eb (4 drafts)
  (run 'hg heads' to see heads, 'hg merge' to merge)
  $ hg debugstrip --no-backup theothertag
  $ hg pull ../gitrepo
  pulling from ../gitrepo
  no changes found
  $ hg git-cleanup
  git commit map cleaned

pull works after 'hg git-cleanup'

  $ hg pull ../gitrepo
  pulling from ../gitrepo
  importing 1 git commits
  new changesets 6202c19d7dd9 (1 drafts)
  (run 'hg heads' to see heads, 'hg merge' to merge)
  $ cd ..
