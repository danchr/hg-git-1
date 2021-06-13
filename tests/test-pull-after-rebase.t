Load commonly used test logic
  $ . "$TESTDIR/testutil"

  $ cat >> $HGRCPATH <<EOF
  > [extensions]
  > rebase =
  > [experimental]
  > evolution = createmarkers
  > evolution.createmarkers = yes
  > EOF

  $ git init --bare --quiet repo.git
  $ git clone repo.git gitrepo > /dev/null 2>&1
  $ cd gitrepo
  $ echo alpha > alpha
  $ git add alpha
  $ fn_git_commit -m 'add alpha'

  $ echo beta > beta
  $ git add beta
  $ fn_git_commit -m 'add beta'

  $ git checkout --quiet -b branch master~1
  $ echo gamma > gamma
  $ git add gamma
  $ fn_git_commit -m 'add gamma'

  $ git push --all
  To $TESTTMP/repo.git
   * [new branch]      branch -> branch
   * [new branch]      master -> master
  $ cd ..

Clone it and rebase the branch

  $ hg clone -U repo.git hgrepo
  importing git objects into hg
  $ cd hgrepo
  $ hg log --graph -T '{bookmarks} {rev}:{node}\n'
  o  branch 2:205a004356ef32b8da782afb89d9179d12ca31e9
  |
  | o  master 1:7fe02317c63d9ee324d4b5df7c9296085162da1b
  |/
  o   0:ff7a2f2d8d7099694ae1e8b03838d40575bebb63
  
  $ hg up branch
  2 files updated, 0 files merged, 0 files removed, 0 files unresolved
  (activating bookmark branch)
  $ hg rebase --quiet -d master
  $ hg log --graph -T '{bookmarks} {rev}:{node}\n'
  @  branch 3:52def9937d74e43b83dfded6ce0e5adf731b9d22
  |
  | x   2:205a004356ef32b8da782afb89d9179d12ca31e9
  | |
  o |  master 1:7fe02317c63d9ee324d4b5df7c9296085162da1b
  |/
  o   0:ff7a2f2d8d7099694ae1e8b03838d40575bebb63
  

  $ hg push -fr tip
  pushing to $TESTTMP/repo.git
  searching for changes
  adding objects
  added 1 commits with 1 trees and 1 blobs
  updating reference refs/heads/branch
  $ cd ..

Now switch back to git and create a new commit based on what we just rebased

  $ cd gitrepo
  $ git checkout --quiet -b otherbranch branch
  $ echo delta > delta
  $ git add delta
  $ fn_git_commit -m 'add gamma'
  $ git push --quiet --set-upstream origin otherbranch
  Branch 'otherbranch' set up to track remote branch 'otherbranch' from 'origin'. (?)
  $ cd ..

Pull that

  $ cd hgrepo
  $ hg pull
  pulling from $TESTTMP/repo.git
  importing git objects into hg
  1 new orphan changesets (?)
  (run 'hg heads' to see heads, 'hg merge' to merge)
hg 4.4 lacks reporting new orphans, and the `*` marking unstable
changesets below
  $ hg log --graph -T '{bookmarks} {rev}:{node}\n'
  [*o]  otherbranch 4:f4bd265a9d39e5c4da2c0a752de5ea70335199c5 (re)
  |
  | @  branch 3:52def9937d74e43b83dfded6ce0e5adf731b9d22
  | |
  x |   2:205a004356ef32b8da782afb89d9179d12ca31e9
  | |
  | o  master 1:7fe02317c63d9ee324d4b5df7c9296085162da1b
  |/
  o   0:ff7a2f2d8d7099694ae1e8b03838d40575bebb63
  
