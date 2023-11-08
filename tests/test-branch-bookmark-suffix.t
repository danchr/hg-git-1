#testcases with-path without-path

Load commonly used test logic
  $ . "$TESTDIR/testutil"

  $ echo "[git]" >> $HGRCPATH
  $ echo "branch_bookmark_suffix=_bookmark" >> $HGRCPATH

  $ git init -q --bare repo.git

  $ hg clone repo.git hgrepo
  updating to branch default
  0 files updated, 0 files merged, 0 files removed, 0 files unresolved
  $ cd hgrepo
#if without-path
  $ rm .hg/hgrc
#endif
  $ hg branch -q branch1
  $ hg bookmark branch1_bookmark
  $ echo f1 > f1
  $ hg add f1
  $ fn_hg_commit -m "add f1"
  $ hg branch -q branch2
  $ hg bookmark branch2_bookmark
  $ echo f2 > f2
  $ hg add f2
  $ fn_hg_commit -m "add f2"
  $ hg log --graph
  @  changeset:   1:600de9b6d498
  |  branch:      branch2
  |  bookmark:    branch2_bookmark
  |  tag:         tip
  |  user:        test
  |  date:        Mon Jan 01 00:00:11 2007 +0000
  |  summary:     add f2
  |
  o  changeset:   0:40a840c1f8ae
     branch:      branch1
     bookmark:    branch1_bookmark
     user:        test
     date:        Mon Jan 01 00:00:10 2007 +0000
     summary:     add f1
  

  $ hg push -B asdasd ../repo.git
  pushing to ../repo.git
  abort: the -B/--bookmarks option is not supported when branch_bookmark_suffix is set
  [255]

  $ hg push ../repo.git
  pushing to ../repo.git
  searching for changes
  adding objects
  remote: found 0 deltas to reuse (dulwich0210 !)
  added 2 commits with 2 trees and 2 blobs
  adding reference refs/heads/branch1
  adding reference refs/heads/branch2

  $ cd ..

  $ cd repo.git
  $ git symbolic-ref HEAD refs/heads/branch1
  $ git branch
  * branch1
    branch2
  $ cd ..

  $ git clone repo.git gitrepo
  Cloning into 'gitrepo'...
  done.
  $ cd gitrepo
  $ git checkout -q branch1
  $ echo g1 >> f1
  $ git add f1
  $ fn_git_commit -m "append f1"
  $ git checkout -q branch2
  $ echo g2 >> f2
  $ git add f2
  $ fn_git_commit -m "append f2"
  $ git checkout -b branch3
  Switched to a new branch 'branch3'
  $ echo g3 >> f3
  $ git add f3
  $ fn_git_commit -m "append f3"
  $ git push origin branch1 branch2 branch3
  To $TESTTMP/repo.git
     bbfe79a..d8aef79  branch1 -> branch1
     288e92b..f8f8de5  branch2 -> branch2
   * [new branch]      branch3 -> branch3
make sure the commit doesn't have an HG:rename-source annotation
  $ git cat-file commit d8aef79
  tree b5644d8071b8a5963b8d1fd089fb3fdfb14b1203
  parent bbfe79acf62dcd6a97763e2a67424a6de8a96941
  author test <test@example.org> 1167609612 +0000
  committer test <test@example.org> 1167609612 +0000
  
  append f1
  $ cd ..

  $ cd hgrepo
  $ hg paths
  default = $TESTTMP/repo.git (with-path !)
  $ hg pull ../repo.git
  pulling from ../repo.git
  importing 3 git commits
  updating bookmark branch1_bookmark
  updating bookmark branch2_bookmark
  adding bookmark branch3_bookmark
  new changesets 8211cade99e4:faf44fc3a4e8 (3 drafts)
  (run 'hg heads' to see heads)
  $ hg log --graph
  o  changeset:   4:faf44fc3a4e8
  |  bookmark:    branch3_bookmark
  |  tag:         default/branch3 (with-path !)
  |  tag:         tip
  |  user:        test <test@example.org>
  |  date:        Mon Jan 01 00:00:14 2007 +0000
  |  summary:     append f3
  |
  o  changeset:   3:ae8eb55f7090
  |  bookmark:    branch2_bookmark
  |  tag:         default/branch2 (with-path !)
  |  parent:      1:600de9b6d498
  |  user:        test <test@example.org>
  |  date:        Mon Jan 01 00:00:13 2007 +0000
  |  summary:     append f2
  |
  | o  changeset:   2:8211cade99e4
  | |  bookmark:    branch1_bookmark
  | |  tag:         default/branch1 (with-path !)
  | |  parent:      0:40a840c1f8ae
  | |  user:        test <test@example.org>
  | |  date:        Mon Jan 01 00:00:12 2007 +0000
  | |  summary:     append f1
  | |
  @ |  changeset:   1:600de9b6d498
  |/   branch:      branch2
  |    user:        test
  |    date:        Mon Jan 01 00:00:11 2007 +0000
  |    summary:     add f2
  |
  o  changeset:   0:40a840c1f8ae
     branch:      branch1
     user:        test
     date:        Mon Jan 01 00:00:10 2007 +0000
     summary:     add f1
  
  $ cd ..

Try cloning a bookmark, and make sure it gets checked out:

  $ rm -r hgrepo
  $ hg clone -r branch3 repo.git hgrepo
  importing 4 git commits
  new changesets 40a840c1f8ae:faf44fc3a4e8 (4 drafts)
  updating to bookmark branch3_bookmark
  3 files updated, 0 files merged, 0 files removed, 0 files unresolved
  $ cd hgrepo
  $ hg bookmarks
     branch2_bookmark          2:ae8eb55f7090
   * branch3_bookmark          3:faf44fc3a4e8
  $ hg log --graph
  @  changeset:   3:faf44fc3a4e8
  |  bookmark:    branch3_bookmark
  |  tag:         default/branch3
  |  tag:         tip
  |  user:        test <test@example.org>
  |  date:        Mon Jan 01 00:00:14 2007 +0000
  |  summary:     append f3
  |
  o  changeset:   2:ae8eb55f7090
  |  bookmark:    branch2_bookmark
  |  tag:         default/branch2
  |  user:        test <test@example.org>
  |  date:        Mon Jan 01 00:00:13 2007 +0000
  |  summary:     append f2
  |
  o  changeset:   1:600de9b6d498
  |  branch:      branch2
  |  user:        test
  |  date:        Mon Jan 01 00:00:11 2007 +0000
  |  summary:     add f2
  |
  o  changeset:   0:40a840c1f8ae
     branch:      branch1
     user:        test
     date:        Mon Jan 01 00:00:10 2007 +0000
     summary:     add f1
  
  $ cd ..

Try cloning something that's both a bookmark and a branch, and see the
results. They're a bit suprising as the bookmark does get activated,
but the branch get checked out. Although this does seem a bit odd, so
does the scenario.

  $ rm -r hgrepo
  $ hg clone -r branch1 repo.git hgrepo
  importing 2 git commits
  new changesets 40a840c1f8ae:8211cade99e4 (2 drafts)
  updating to branch branch1
  1 files updated, 0 files merged, 0 files removed, 0 files unresolved
  $ cd hgrepo
  $ hg bookmarks
   * branch1_bookmark          1:8211cade99e4
  $ hg log --graph
  o  changeset:   1:8211cade99e4
  |  bookmark:    branch1_bookmark
  |  tag:         default/branch1
  |  tag:         tip
  |  user:        test <test@example.org>
  |  date:        Mon Jan 01 00:00:12 2007 +0000
  |  summary:     append f1
  |
  @  changeset:   0:40a840c1f8ae
     branch:      branch1
     user:        test
     date:        Mon Jan 01 00:00:10 2007 +0000
     summary:     add f1
  

  $ cd ..

Now try pulling a diverged bookmark:

  $ rm -r hgrepo
#if with-path
  $ hg clone -U repo.git hgrepo
  importing 5 git commits
  new changesets 40a840c1f8ae:faf44fc3a4e8 (5 drafts)
#else
  $ hg init hgrepo
  $ hg -R hgrepo pull repo.git
  pulling from repo.git
  importing 5 git commits
  adding bookmark branch1_bookmark
  adding bookmark branch2_bookmark
  adding bookmark branch3_bookmark
  new changesets 40a840c1f8ae:faf44fc3a4e8 (5 drafts)
  (run 'hg heads' to see heads, 'hg merge' to merge)
#endif
  $ cd gitrepo
  $ git checkout -q branch1
  $ fn_git_rebase branch3
  $ git push -f
  To $TESTTMP/repo.git
   + d8aef79...ce1d1c5 branch1 -> branch1 (forced update)
  $ cd ../hgrepo
  $ hg pull ../repo.git
  pulling from ../repo.git
  importing 1 git commits
  not updating diverged bookmark branch1_bookmark
  new changesets 895d0307f8b7 (1 drafts)
  (run 'hg update' to get a working copy)
  $ hg log --graph
  o  changeset:   5:895d0307f8b7
  |  tag:         default/branch1 (with-path !)
  |  tag:         tip
  |  user:        test <test@example.org>
  |  date:        Mon Jan 01 00:00:12 2007 +0000
  |  summary:     append f1
  |
  o  changeset:   4:faf44fc3a4e8
  |  bookmark:    branch3_bookmark
  |  tag:         default/branch3 (with-path !)
  |  user:        test <test@example.org>
  |  date:        Mon Jan 01 00:00:14 2007 +0000
  |  summary:     append f3
  |
  o  changeset:   3:ae8eb55f7090
  |  bookmark:    branch2_bookmark
  |  tag:         default/branch2 (with-path !)
  |  user:        test <test@example.org>
  |  date:        Mon Jan 01 00:00:13 2007 +0000
  |  summary:     append f2
  |
  o  changeset:   2:600de9b6d498
  |  branch:      branch2
  |  parent:      0:40a840c1f8ae
  |  user:        test
  |  date:        Mon Jan 01 00:00:11 2007 +0000
  |  summary:     add f2
  |
  | o  changeset:   1:8211cade99e4
  |/   bookmark:    branch1_bookmark
  |    user:        test <test@example.org>
  |    date:        Mon Jan 01 00:00:12 2007 +0000
  |    summary:     append f1
  |
  o  changeset:   0:40a840c1f8ae
     branch:      branch1
     user:        test
     date:        Mon Jan 01 00:00:10 2007 +0000
     summary:     add f1
  
