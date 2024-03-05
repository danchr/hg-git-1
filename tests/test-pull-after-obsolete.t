Load commonly used test logic
  $ . "$TESTDIR/testutil"

  $ cat >> $HGRCPATH <<EOF
  > [experimental]
  > evolution = all
  > EOF

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

Create a commit, obsolete it, and pull, to ensure that we can pull if
the tipmost commit is hidden.

  $ cd ../hgrepo
  $ hg bookmark --inactive
  $ echo gamma > gamma
  $ hg add gamma
  $ fn_hg_commit -m 'add gamma'
  $ hg up master
  0 files updated, 0 files merged, 1 files removed, 0 files unresolved
  (activating bookmark master)
  $ hg log -T '{rev}:{node} {desc}\n' -r tip
  2:4090a1266584bc1a47ce562e9349b1e0f1b44611 add gamma
  $ hg debugobsolete 4090a1266584bc1a47ce562e9349b1e0f1b44611
  1 new obsolescence markers
  obsoleted 1 changesets

  $ hg pull
  pulling from $TESTTMP/gitrepo
  importing 1 git commits
  updating bookmark master
  new changesets cc1e605d90db (1 drafts)
  (run 'hg update' to get a working copy)
