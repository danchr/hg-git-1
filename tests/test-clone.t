#testcases secret draft

Load commonly used test logic
  $ . "$TESTDIR/testutil"

#if secret
The phases setting should not affect hg-git
  $ cat >> $HGRCPATH <<EOF
  > [phases]
  > new-commit = secret
  > EOF
#endif

  $ git init gitrepo
  Initialized empty Git repository in $TESTTMP/gitrepo/.git/
  $ cd gitrepo
  $ echo alpha > alpha
  $ git add alpha
  $ fn_git_commit -m 'add alpha'

  $ git tag alpha

  $ git checkout -b beta 2>&1 | sed s/\'/\"/g
  Switched to a new branch "beta"
  $ echo beta > beta
  $ git add beta
  $ fn_git_commit -m 'add beta'
  $ git checkout -b gamma 2>&1 | sed s/\'/\"/g
  Switched to a new branch "gamma"
  $ echo gamma > gamma
  $ git add gamma
  $ fn_git_commit -m 'add gamma'
  $ git checkout -q beta


  $ cd ..

clone a tag

  $ hg clone -r alpha gitrepo hgrepo-a
  importing 1 git commits
  new changesets ff7a2f2d8d70 (1 drafts)
  updating to branch default
  1 files updated, 0 files merged, 0 files removed, 0 files unresolved
  $ hg -R hgrepo-a bookmarks
     master                    0:ff7a2f2d8d70
  $ hg -R hgrepo-a log --graph --template=phases
  @  changeset:   0:ff7a2f2d8d70
     bookmark:    master
     tag:         alpha
     tag:         default/master
     tag:         tip
     phase:       draft
     user:        test <test@example.org>
     date:        Mon Jan 01 00:00:10 2007 +0000
     summary:     add alpha
  
  $ git --git-dir hgrepo-a/.hg/git for-each-ref
  7eeab2ea75ec1ac0ff3d500b5b6f8a3447dd7c03 commit	refs/remotes/default/master
  7eeab2ea75ec1ac0ff3d500b5b6f8a3447dd7c03 commit	refs/tags/alpha
Make sure this is still draft since we didn't pull remote's HEAD
  $ hg -R hgrepo-a phase -r alpha
  0: draft

clone a branch
  $ hg clone -r beta gitrepo hgrepo-b
  importing 2 git commits
  new changesets ff7a2f2d8d70:7fe02317c63d (2 drafts)
  updating to branch default
  2 files updated, 0 files merged, 0 files removed, 0 files unresolved
  $ hg -R hgrepo-b bookmarks
   * beta                      1:7fe02317c63d
     master                    0:ff7a2f2d8d70
  $ hg -R hgrepo-b log --graph
  @  changeset:   1:7fe02317c63d
  |  bookmark:    beta
  |  tag:         default/beta
  |  tag:         tip
  |  user:        test <test@example.org>
  |  date:        Mon Jan 01 00:00:11 2007 +0000
  |  summary:     add beta
  |
  o  changeset:   0:ff7a2f2d8d70
     bookmark:    master
     tag:         alpha
     tag:         default/master
     user:        test <test@example.org>
     date:        Mon Jan 01 00:00:10 2007 +0000
     summary:     add alpha
  
  $ git --git-dir hgrepo-b/.hg/git for-each-ref
  9497a4ee62e16ee641860d7677cdb2589ea15554 commit	refs/remotes/default/beta
  7eeab2ea75ec1ac0ff3d500b5b6f8a3447dd7c03 commit	refs/remotes/default/master
  7eeab2ea75ec1ac0ff3d500b5b6f8a3447dd7c03 commit	refs/tags/alpha

Make sure that a deleted .hgsubstate does not confuse hg-git

  $ cd gitrepo
  $ echo 'HASH random' > .hgsubstate
  $ git add .hgsubstate
  $ fn_git_commit -m 'add bogus .hgsubstate'
  $ git rm -q .hgsubstate
  $ fn_git_commit -m 'remove bogus .hgsubstate'
  $ cd ..

  $ hg clone -r beta gitrepo hgrepo-c
  importing 4 git commits
  new changesets ff7a2f2d8d70:47d12948785d (4 drafts)
  updating to branch default
  2 files updated, 0 files merged, 0 files removed, 0 files unresolved
  $ hg -R hgrepo-c bookmarks
   * beta                      3:47d12948785d
     master                    0:ff7a2f2d8d70
  $ hg --cwd hgrepo-c status
  $ git --git-dir hgrepo-c/.hg/git for-each-ref
  b5329119ed77cb37a31fe523621d684eb55779a4 commit	refs/remotes/default/beta
  7eeab2ea75ec1ac0ff3d500b5b6f8a3447dd7c03 commit	refs/remotes/default/master
  7eeab2ea75ec1ac0ff3d500b5b6f8a3447dd7c03 commit	refs/tags/alpha

test shared repositories

  $ hg clone gitrepo hgrepo-base
  importing 5 git commits
  new changesets ff7a2f2d8d70:47d12948785d (5 drafts)
  updating to bookmark beta
  2 files updated, 0 files merged, 0 files removed, 0 files unresolved
  $ hg -R hgrepo-base bookmarks
   * beta                      4:47d12948785d
     gamma                     2:ca33a262eb46
     master                    0:ff7a2f2d8d70
  $ hg  --config extensions.share= share hgrepo-base hgrepo-shared
  updating working directory
  2 files updated, 0 files merged, 0 files removed, 0 files unresolved
  $ hg -R hgrepo-shared pull gitrepo
  pulling from gitrepo
  no changes found
  adding bookmark beta
  adding bookmark gamma
  adding bookmark master
  $ hg -R hgrepo-shared push gitrepo
  pushing to gitrepo
  searching for changes
  no changes found
  [1]
  $ ls hgrepo-shared/.hg | grep git
  [1]
  $ hg -R hgrepo-shared git-cleanup
  git commit map cleaned
  $ rm -rf hgrepo-base hgrepo-shared

test cloning HEAD

  $ cd gitrepo
  $ git checkout -q master
  $ cd ..
  $ hg clone gitrepo hgrepo-2
  importing 5 git commits
  new changesets ff7a2f2d8d70:47d12948785d (5 drafts)
  updating to bookmark master
  1 files updated, 0 files merged, 0 files removed, 0 files unresolved
  $ git --git-dir hgrepo-2/.hg/git for-each-ref
  b5329119ed77cb37a31fe523621d684eb55779a4 commit	refs/remotes/default/beta
  d338971a96e20113bb980a5dc4355ba77eed3714 commit	refs/remotes/default/gamma
  7eeab2ea75ec1ac0ff3d500b5b6f8a3447dd7c03 commit	refs/remotes/default/master
  7eeab2ea75ec1ac0ff3d500b5b6f8a3447dd7c03 commit	refs/tags/alpha
  $ rm -rf hgrepo-2

clone empty repo
  $ git init empty
  Initialized empty Git repository in $TESTTMP/empty/.git/
  $ hg clone empty emptyhg
  updating to branch default
  0 files updated, 0 files merged, 0 files removed, 0 files unresolved
  $ rm -rf empty emptyhg

test cloning detached HEAD, but pointing to a branch; we detect this
and activate the corresponding bookmark

  $ cd gitrepo
  $ git checkout -q -d master
  $ cd ..
  $ hg clone gitrepo hgrepo-2
  importing 5 git commits
  new changesets ff7a2f2d8d70:47d12948785d (5 drafts)
  updating to bookmark master
  1 files updated, 0 files merged, 0 files removed, 0 files unresolved
  $ hg -R hgrepo-2 book
     beta                      4:47d12948785d
     gamma                     2:ca33a262eb46
   * master                    0:ff7a2f2d8d70
  $ git --git-dir hgrepo-2/.hg/git for-each-ref
  b5329119ed77cb37a31fe523621d684eb55779a4 commit	refs/remotes/default/beta
  d338971a96e20113bb980a5dc4355ba77eed3714 commit	refs/remotes/default/gamma
  7eeab2ea75ec1ac0ff3d500b5b6f8a3447dd7c03 commit	refs/remotes/default/master
  7eeab2ea75ec1ac0ff3d500b5b6f8a3447dd7c03 commit	refs/tags/alpha
  $ rm -rf hgrepo-2

test cloning fully detached HEAD; we don't convert the
anonymous/detached head, so we just issue a warning and don't do
anything special

  $ cd gitrepo
  $ git checkout -q -d master
  $ echo delta > delta
  $ git add delta
  $ fn_git_commit -m 'add delta'
  $ cd ..
  $ hg clone gitrepo hgrepo-2
  importing 5 git commits
  new changesets ff7a2f2d8d70:47d12948785d (5 drafts)
  warning: the git source repository has a detached head
  (you may want to update to a bookmark)
  updating to branch default
  2 files updated, 0 files merged, 0 files removed, 0 files unresolved
  $ hg -R hgrepo-2 book
     beta                      4:47d12948785d
     gamma                     2:ca33a262eb46
     master                    0:ff7a2f2d8d70
  $ hg -R hgrepo-2 id --tags
  default/beta tip
  $ git --git-dir hgrepo-2/.hg/git for-each-ref
  b5329119ed77cb37a31fe523621d684eb55779a4 commit	refs/remotes/default/beta
  d338971a96e20113bb980a5dc4355ba77eed3714 commit	refs/remotes/default/gamma
  7eeab2ea75ec1ac0ff3d500b5b6f8a3447dd7c03 commit	refs/remotes/default/master
  7eeab2ea75ec1ac0ff3d500b5b6f8a3447dd7c03 commit	refs/tags/alpha
  $ rm -rf hgrepo-2
