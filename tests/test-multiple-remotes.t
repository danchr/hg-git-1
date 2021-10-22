#require hg59

Load commonly used test logic
  $ . "$TESTDIR/testutil"

  $ git init gitrepo
  Initialized empty Git repository in $TESTTMP/gitrepo/.git/
  $ cd gitrepo
  $ echo alpha > alpha
  $ git add alpha
  $ fn_git_commit -m "add alpha"
  $ git checkout -b not-master
  Switched to a new branch 'not-master'
  $ cd ..

  $ git clone --bare --quiet gitrepo repo.git

  $ hg init hgrepo
  $ cd hgrepo
  $ cat > .hg/hgrc <<EOF
  > [paths]
  > default:multi-urls = yes
  > default = path://git, path://bare
  > git = $TESTTMP/gitrepo
  > also-git = $TESTTMP/gitrepo
  > bare = $TESTTMP/repo.git
  > also-bare = $TESTTMP/repo.git
  > EOF

  $ hg pull
  pulling from $TESTTMP/gitrepo
  importing git objects into hg
  new changesets ff7a2f2d8d70 (1 drafts)
  (run 'hg update' to get a working copy)
  pulling from $TESTTMP/repo.git
  no changes found
  $ hg tags
  tip                                0:ff7a2f2d8d70
  default/not-master                 0:ff7a2f2d8d70
  default/master                     0:ff7a2f2d8d70

  $ hg up master
  1 files updated, 0 files merged, 0 files removed, 0 files unresolved
  (activating bookmark master)
  $ echo beta > beta
  $ fn_hg_commit -A -m "add beta"
  $ hg push
  pushing to $TESTTMP/gitrepo
  searching for changes
  adding objects
  added 1 commits with 1 trees and 1 blobs
  updating reference refs/heads/master
  pushing to $TESTTMP/repo.git
  searching for changes
  adding objects
  added 1 commits with 1 trees and 1 blobs
  updating reference refs/heads/master

  $ hg tags
  tip                                1:47580592d3d6
  default/master                     1:47580592d3d6
  default/not-master                 0:ff7a2f2d8d70

