Test that rename detection works
  $ . "$TESTDIR/testutil"

  $ cat >> $HGRCPATH <<EOF
  > [diff]
  > git = True
  > [git]
  > similarity = 50
  > EOF

  $ git init -q gitrepo
  $ cd gitrepo
  $ for i in 1 2 3 4 5 6 7 8 9 10; do echo $i >> alpha; done
  $ git add alpha
  $ fn_git_commit -malpha

Rename a file
  $ git mv alpha beta
  $ echo 11 >> beta
  $ git add beta
  $ fn_git_commit -mbeta

Copy a file
  $ cp beta gamma
  $ echo 12 >> beta
  $ echo 13 >> gamma
  $ git add beta gamma
  $ fn_git_commit -mgamma

Add a submodule (gitlink) and move it to a different spot:
  $ cd ..
  $ git init -q gitsubmodule
  $ cd gitsubmodule
  $ touch subalpha
  $ git add subalpha
  $ fn_git_commit -msubalpha
  $ cd ../gitrepo

  $ rmpwd="import sys; print(sys.stdin.read().replace('$(dirname $(pwd))/', ''))"
  $ clonefilt='s/Cloning into/Initialized empty Git repository in/;s/in .*/in .../'

  $ git submodule add ../gitsubmodule 2>&1 | python -c "$rmpwd" | sed "$clonefilt" | grep -E -v '^done\.$'
  Initialized empty Git repository in ...
  
  $ fn_git_commit -m 'add submodule'
  $ sed -e 's/path = gitsubmodule/path = gitsubmodule2/' .gitmodules > .gitmodules-new
  $ mv .gitmodules-new .gitmodules
  $ mv gitsubmodule gitsubmodule2

Previous versions of git did not produce any output but 2.14 changed the output
to warn the user about submodules

  $ git add .gitmodules gitsubmodule2 2>/dev/null
  $ git rm --cached gitsubmodule
  rm 'gitsubmodule'
  $ fn_git_commit -m 'move submodule'

Rename a file elsewhere and replace it with a symlink:

  $ git mv beta beta-new
  $ ln -s beta-new beta
  $ git add beta
  $ fn_git_commit -m 'beta renamed'

Rename the file back:

  $ git rm beta
  rm 'beta'
  $ git mv beta-new beta
  $ fn_git_commit -m 'beta renamed back'

Rename a file elsewhere and replace it with a submodule:

  $ git mv gamma gamma-new
  $ git submodule add ../gitsubmodule gamma 2>&1 | python -c "$rmpwd" | sed "$clonefilt" | grep -E -v '^done\.$'
  Initialized empty Git repository in ...
  
  $ fn_git_commit -m 'rename and add submodule'

Remove the submodule and rename the file back:

  $ grep 'submodule "gitsubmodule"' -A2 .gitmodules > .gitmodules-new
  $ mv .gitmodules-new .gitmodules
  $ git add .gitmodules
  $ git rm --cached gamma
  rm 'gamma'
  $ rm -rf gamma
  $ git mv gamma-new gamma
  $ fn_git_commit -m 'remove submodule and rename back'

  $ git init -q --bare ../repo.git
  $ git push ../repo.git master
  To ../repo.git
   * [new branch]      master -> master

  $ cd ..
  $ hg clone -q repo.git hgrepo
  $ cd hgrepo
  $ hg book master -q
  $ hg log -p --graph --template "{rev} {node} {desc|firstline}\n{join(extras, ' ')}\n\n"
  @  8 497105ddbe119aa40af691eb2b1a029c29bf5247 remove submodule and rename back
  |  branch=default hg-git-rename-source=git
  |
  |  diff --git a/.hgsub b/.hgsub
  |  --- a/.hgsub
  |  +++ b/.hgsub
  |  @@ -1,2 +1,1 @@
  |   gitsubmodule2 = [git]../gitsubmodule
  |  -gamma = [git]../gitsubmodule
  |  diff --git a/.hgsubstate b/.hgsubstate
  |  --- a/.hgsubstate
  |  +++ b/.hgsubstate
  |  @@ -1,2 +1,1 @@
  |  -5944b31ff85b415573d1a43eb942e2dea30ab8be gamma
  |   5944b31ff85b415573d1a43eb942e2dea30ab8be gitsubmodule2
  |  diff --git a/gamma-new b/gamma
  |  rename from gamma-new
  |  rename to gamma
  |
  o  7 adfc1ce8461d3174dcf8425e112e2fa848de3913 rename and add submodule
  |  branch=default hg-git-rename-source=git
  |
  |  diff --git a/.hgsub b/.hgsub
  |  --- a/.hgsub
  |  +++ b/.hgsub
  |  @@ -1,1 +1,2 @@
  |   gitsubmodule2 = [git]../gitsubmodule
  |  +gamma = [git]../gitsubmodule
  |  diff --git a/.hgsubstate b/.hgsubstate
  |  --- a/.hgsubstate
  |  +++ b/.hgsubstate
  |  @@ -1,1 +1,2 @@
  |  +5944b31ff85b415573d1a43eb942e2dea30ab8be gamma
  |   5944b31ff85b415573d1a43eb942e2dea30ab8be gitsubmodule2
  |  diff --git a/gamma b/gamma-new
  |  rename from gamma
  |  rename to gamma-new
  |
  o  6 62c1a4b07240b53a71be1b1a46e94e99132c5391 beta renamed back
  |  branch=default hg-git-rename-source=git
  |
  |  diff --git a/beta b/beta
  |  old mode 120000
  |  new mode 100644
  |  --- a/beta
  |  +++ b/beta
  |  @@ -1,1 +1,12 @@
  |  -beta-new
  |  \ No newline at end of file
  |  +1
  |  +2
  |  +3
  |  +4
  |  +5
  |  +6
  |  +7
  |  +8
  |  +9
  |  +10
  |  +11
  |  +12
  |  diff --git a/beta-new b/beta-new
  |  deleted file mode 100644
  |  --- a/beta-new
  |  +++ /dev/null
  |  @@ -1,12 +0,0 @@
  |  -1
  |  -2
  |  -3
  |  -4
  |  -5
  |  -6
  |  -7
  |  -8
  |  -9
  |  -10
  |  -11
  |  -12
  |
  o  5 f93fefed957cff2220d3f0d11182398350b5fa9a beta renamed
  |  branch=default hg-git-rename-source=git
  |
  |  diff --git a/beta b/beta
  |  old mode 100644
  |  new mode 120000
  |  --- a/beta
  |  +++ b/beta
  |  @@ -1,12 +1,1 @@
  |  -1
  |  -2
  |  -3
  |  -4
  |  -5
  |  -6
  |  -7
  |  -8
  |  -9
  |  -10
  |  -11
  |  -12
  |  +beta-new
  |  \ No newline at end of file
  |  diff --git a/beta b/beta-new
  |  copy from beta
  |  copy to beta-new
  |
  o  4 b9e63d96abc2783afc59246e798a6936cf05a35e move submodule
  |  branch=default hg-git-rename-source=git
  |
  |  diff --git a/.hgsub b/.hgsub
  |  --- a/.hgsub
  |  +++ b/.hgsub
  |  @@ -1,1 +1,1 @@
  |  -gitsubmodule = [git]../gitsubmodule
  |  +gitsubmodule2 = [git]../gitsubmodule
  |  diff --git a/.hgsubstate b/.hgsubstate
  |  --- a/.hgsubstate
  |  +++ b/.hgsubstate
  |  @@ -1,1 +1,1 @@
  |  -5944b31ff85b415573d1a43eb942e2dea30ab8be gitsubmodule
  |  +5944b31ff85b415573d1a43eb942e2dea30ab8be gitsubmodule2
  |
  o  3 55537ea256c28be1b5637f4f93a601fdde8a9a7f add submodule
  |  branch=default hg-git-rename-source=git
  |
  |  diff --git a/.hgsub b/.hgsub
  |  new file mode 100644
  |  --- /dev/null
  |  +++ b/.hgsub
  |  @@ -0,0 +1,1 @@
  |  +gitsubmodule = [git]../gitsubmodule
  |  diff --git a/.hgsubstate b/.hgsubstate
  |  new file mode 100644
  |  --- /dev/null
  |  +++ b/.hgsubstate
  |  @@ -0,0 +1,1 @@
  |  +5944b31ff85b415573d1a43eb942e2dea30ab8be gitsubmodule
  |
  o  2 20f9e56b6d006d0403f853245e483d0892b8ac48 gamma
  |  branch=default hg-git-rename-source=git
  |
  |  diff --git a/beta b/beta
  |  --- a/beta
  |  +++ b/beta
  |  @@ -9,3 +9,4 @@
  |   9
  |   10
  |   11
  |  +12
  |  diff --git a/beta b/gamma
  |  copy from beta
  |  copy to gamma
  |  --- a/beta
  |  +++ b/gamma
  |  @@ -9,3 +9,4 @@
  |   9
  |   10
  |   11
  |  +13
  |
  o  1 9f7744e68def81da3b394f11352f602ca9c8ab68 beta
  |  branch=default hg-git-rename-source=git
  |
  |  diff --git a/alpha b/beta
  |  rename from alpha
  |  rename to beta
  |  --- a/alpha
  |  +++ b/beta
  |  @@ -8,3 +8,4 @@
  |   8
  |   9
  |   10
  |  +11
  |
  o  0 7bc844166f76e49562f81eacd54ea954d01a9e42 alpha
     branch=default hg-git-rename-source=git
  
     diff --git a/alpha b/alpha
     new file mode 100644
     --- /dev/null
     +++ b/alpha
     @@ -0,0 +1,10 @@
     +1
     +2
     +3
     +4
     +5
     +6
     +7
     +8
     +9
     +10
  

Make a new ordinary commit in Mercurial (no extra metadata)
  $ echo 14 >> gamma
  $ hg ci -m "gamma2"

Make a new commit with a copy and a rename in Mercurial
  $ hg cp gamma delta
  $ echo 15 >> delta
  $ hg mv beta epsilon
  $ echo 16 >> epsilon
  $ hg ci -m "delta/epsilon"
  $ hg export .
  # HG changeset patch
  # User test
  # Date 0 0
  #      Thu Jan 01 00:00:00 1970 +0000
  # Node ID ea6414fab78622fd53679e0593eddad96ff4178d
  # Parent  ee9ec792d5866c313a4cb7a2f8772f2cffa90df4
  delta/epsilon
  
  diff --git a/gamma b/delta
  copy from gamma
  copy to delta
  --- a/gamma
  +++ b/delta
  @@ -11,3 +11,4 @@
   11
   13
   14
  +15
  diff --git a/beta b/epsilon
  rename from beta
  rename to epsilon
  --- a/beta
  +++ b/epsilon
  @@ -10,3 +10,4 @@
   10
   11
   12
  +16
  $ hg push
  pushing to $TESTTMP/repo.git
  searching for changes
  adding objects
  remote: found 0 deltas to reuse (dulwich0210 !)
  added 2 commits with 2 trees and 3 blobs
  updating reference refs/heads/master

  $ cd ../repo.git
  $ git log master --pretty=oneline
  5f2948d029693346043f320620af99a615930dc4 delta/epsilon
  bbd2ec050f7fbc64f772009844f7d58a556ec036 gamma2
  50d116676a308b7c22935137d944e725d2296f2a remove submodule and rename back
  59fb8e82ea18f79eab99196f588e8948089c134f rename and add submodule
  f95497455dfa891b4cd9b524007eb9514c3ab654 beta renamed back
  055f482277da6cd3dd37c7093d06983bad68f782 beta renamed
  d7f31298f27df8a9226eddb1e4feb96922c46fa5 move submodule
  c610256cb6959852d9e70d01902a06726317affc add submodule
  e1348449e0c3a417b086ed60fc13f068d4aa8b26 gamma
  cc83241f39927232f690d370894960b0d1943a0e beta
  938bb65bb322eb4a3558bec4cdc8a680c4d1794c alpha

Make sure the right metadata is stored
  $ git cat-file commit master^
  tree 0adbde18545845f3b42ad1a18939ed60a9dec7a8
  parent 50d116676a308b7c22935137d944e725d2296f2a
  author test <none@none> 0 +0000
  committer test <none@none> 0 +0000
  HG:rename-source hg
  
  gamma2
  $ git cat-file commit master
  tree f8f32f4e20b56a5a74582c6a5952c175bf9ec155
  parent bbd2ec050f7fbc64f772009844f7d58a556ec036
  author test <none@none> 0 +0000
  committer test <none@none> 0 +0000
  HG:rename gamma:delta
  HG:rename beta:epsilon
  
  delta/epsilon

Now make another clone and compare the hashes

  $ cd ..
  $ hg clone -q repo.git hgrepo2
  $ cd hgrepo2
  $ hg book master -qf
  $ hg export master
  # HG changeset patch
  # User test
  # Date 0 0
  #      Thu Jan 01 00:00:00 1970 +0000
  # Node ID ea6414fab78622fd53679e0593eddad96ff4178d
  # Parent  ee9ec792d5866c313a4cb7a2f8772f2cffa90df4
  delta/epsilon
  
  diff --git a/gamma b/delta
  copy from gamma
  copy to delta
  --- a/gamma
  +++ b/delta
  @@ -11,3 +11,4 @@
   11
   13
   14
  +15
  diff --git a/beta b/epsilon
  rename from beta
  rename to epsilon
  --- a/beta
  +++ b/epsilon
  @@ -10,3 +10,4 @@
   10
   11
   12
  +16

Regenerate the Git metadata and compare the hashes
  $ hg debug-remove-hggit-state
  clearing out the git cache data
  $ hg gexport
  $ cd .hg/git
  $ git log master --pretty=oneline
  8a00d0fb75377c51c9a46e92ff154c919007f0e2 delta/epsilon
  dd7d4f1adb942a8d349dce585019f6949184bc64 gamma2
  3f1cdaf8b603816fcda02bd29e75198ae4cb13db remove submodule and rename back
  2a4abf1178a999e2054158ceb0c7768079665d03 rename and add submodule
  88c416e8d5e0e9dd1187d45ebafaa46111764196 beta renamed back
  027d2a6e050705bf6f7e226e7e97f02ce5ae3200 beta renamed
  dc70e620634887e70ac5dd108bcc7ebd99c60ec3 move submodule
  c610256cb6959852d9e70d01902a06726317affc add submodule
  e1348449e0c3a417b086ed60fc13f068d4aa8b26 gamma
  cc83241f39927232f690d370894960b0d1943a0e beta
  938bb65bb322eb4a3558bec4cdc8a680c4d1794c alpha

Test findcopiesharder

  $ cd $TESTTMP
  $ git init -q gitcopyharder
  $ cd gitcopyharder
  $ cat >> file0 << EOF
  > 1
  > 2
  > 3
  > 4
  > 5
  > EOF
  $ git add file0
  $ fn_git_commit -m file0
  $ cp file0 file1
  $ git add file1
  $ fn_git_commit -m file1
  $ cp file0 file2
  $ echo 6 >> file2
  $ git add file2
  $ fn_git_commit -m file2

  $ cd ..

Clone without findcopiesharder does not find copies from unmodified files

  $ hg clone gitcopyharder hgnocopyharder
  importing 3 git commits
  new changesets b45d023c6842:ec77ccdbefe0 (3 drafts)
  updating to bookmark master
  3 files updated, 0 files merged, 0 files removed, 0 files unresolved
  $ hg -R hgnocopyharder export 1::2
  # HG changeset patch
  # User test <test@example.org>
  # Date 1167609621 0
  #      Mon Jan 01 00:00:21 2007 +0000
  # Node ID 555831c93e2a250e5ba42efad45bf7ba71da13e4
  # Parent  b45d023c6842337ffe694663a44aa672d311081c
  file1
  
  diff --git a/file1 b/file1
  new file mode 100644
  --- /dev/null
  +++ b/file1
  @@ -0,0 +1,5 @@
  +1
  +2
  +3
  +4
  +5
  # HG changeset patch
  # User test <test@example.org>
  # Date 1167609622 0
  #      Mon Jan 01 00:00:22 2007 +0000
  # Node ID ec77ccdbefe023eb9898b0399f84f670c8c0f5fc
  # Parent  555831c93e2a250e5ba42efad45bf7ba71da13e4
  file2
  
  diff --git a/file2 b/file2
  new file mode 100644
  --- /dev/null
  +++ b/file2
  @@ -0,0 +1,6 @@
  +1
  +2
  +3
  +4
  +5
  +6

findcopiesharder finds copies from unmodified files if similarity is met

  $ hg --config git.findcopiesharder=true clone gitcopyharder hgcopyharder0
  importing 3 git commits
  new changesets b45d023c6842:9b3099834272 (3 drafts)
  updating to bookmark master
  3 files updated, 0 files merged, 0 files removed, 0 files unresolved
  $ hg -R hgcopyharder0 export 1::2
  # HG changeset patch
  # User test <test@example.org>
  # Date 1167609621 0
  #      Mon Jan 01 00:00:21 2007 +0000
  # Node ID cd05a87103eed9d270fc05b62b00f48e174ab960
  # Parent  b45d023c6842337ffe694663a44aa672d311081c
  file1
  
  diff --git a/file0 b/file1
  copy from file0
  copy to file1
  # HG changeset patch
  # User test <test@example.org>
  # Date 1167609622 0
  #      Mon Jan 01 00:00:22 2007 +0000
  # Node ID 9b30998342729c7357d418bebed7399986cfe643
  # Parent  cd05a87103eed9d270fc05b62b00f48e174ab960
  file2
  
  diff --git a/file0 b/file2
  copy from file0
  copy to file2
  --- a/file0
  +++ b/file2
  @@ -3,3 +3,4 @@
   3
   4
   5
  +6

  $ hg --config git.findcopiesharder=true --config git.similarity=95 clone gitcopyharder hgcopyharder1
  importing 3 git commits
  new changesets b45d023c6842:d9d2e8cbf050 (3 drafts)
  updating to bookmark master
  3 files updated, 0 files merged, 0 files removed, 0 files unresolved
  $ hg -R hgcopyharder1 export 1::2
  # HG changeset patch
  # User test <test@example.org>
  # Date 1167609621 0
  #      Mon Jan 01 00:00:21 2007 +0000
  # Node ID cd05a87103eed9d270fc05b62b00f48e174ab960
  # Parent  b45d023c6842337ffe694663a44aa672d311081c
  file1
  
  diff --git a/file0 b/file1
  copy from file0
  copy to file1
  # HG changeset patch
  # User test <test@example.org>
  # Date 1167609622 0
  #      Mon Jan 01 00:00:22 2007 +0000
  # Node ID d9d2e8cbf050772be31dccf78851f71dc547d139
  # Parent  cd05a87103eed9d270fc05b62b00f48e174ab960
  file2
  
  diff --git a/file2 b/file2
  new file mode 100644
  --- /dev/null
  +++ b/file2
  @@ -0,0 +1,6 @@
  +1
  +2
  +3
  +4
  +5
  +6

Config values out of range
  $ hg --config git.similarity=999 clone gitcopyharder hgcopyharder2
  importing 3 git commits
  abort: git.similarity must be between 0 and 100
  [255]
Left-over on Windows with some pack files
  $ rm -rf hgcopyharder2
  $ hg --config git.renamelimit=-5 clone gitcopyharder hgcopyharder2
  importing 3 git commits
  abort: git.renamelimit must be non-negative
  [255]
