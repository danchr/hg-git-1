Load commonly used test logic
  $ . "$TESTDIR/testutil"

  $ cat >> $HGRCPATH <<EOF
  > [extensions]
  > rebase =
  > [experimental]
  > evolution = createmarkers
  > evolution.createmarkers = yes
  > [templates]
  > state = {bookmarks} {tags} {rev}:{node}\\n{desc}\\n
  > [alias]
  > state = log --graph --template state
  > EOF

  $ git init -q --bare repo.git
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
  importing 3 git commits
  new changesets ff7a2f2d8d70:205a004356ef (3 drafts)
  $ cd hgrepo
  $ hg state
  o  branch default/branch tip 2:205a004356ef32b8da782afb89d9179d12ca31e9
  |  add gamma
  | o  master default/master 1:7fe02317c63d9ee324d4b5df7c9296085162da1b
  |/   add beta
  o    0:ff7a2f2d8d7099694ae1e8b03838d40575bebb63
     add alpha
  $ hg up branch
  2 files updated, 0 files merged, 0 files removed, 0 files unresolved
  (activating bookmark branch)
  $ hg rebase --quiet -d master
  $ hg state
  @  branch tip 3:52def9937d74e43b83dfded6ce0e5adf731b9d22
  |  add gamma
  | x   default/branch 2:205a004356ef32b8da782afb89d9179d12ca31e9
  | |  add gamma
  o |  master default/master 1:7fe02317c63d9ee324d4b5df7c9296085162da1b
  |/   add beta
  o    0:ff7a2f2d8d7099694ae1e8b03838d40575bebb63
     add alpha

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
  $ git log --oneline --graph --all --decorate
  * e5023f9 (HEAD -> otherbranch, origin/branch, branch) add gamma
  | * 9497a4e (origin/master, master) add beta
  |/  
  * 7eeab2e add alpha
  $ echo delta > delta
  $ git add delta
  $ fn_git_commit -m 'add gamma'
  $ git push --quiet --set-upstream origin otherbranch
  Branch 'otherbranch' set up to track remote branch 'otherbranch' from 'origin'. (?)
  $ git log --oneline --graph --all --decorate
  * c4cfa5e (HEAD -> otherbranch, origin/otherbranch) add gamma
  * e5023f9 (origin/branch, branch) add gamma
  | * 9497a4e (origin/master, master) add beta
  |/  
  * 7eeab2e add alpha
  $ cd ..

Pull that

  $ cd hgrepo
  $ hg pull
  pulling from $TESTTMP/repo.git
  importing 1 git commits
  adding bookmark otherbranch
  1 new orphan changesets
  new changesets f4bd265a9d39 (1 drafts)
  (run 'hg heads' to see heads, 'hg merge' to merge)
  $ hg state
  *  otherbranch default/otherbranch tip 4:f4bd265a9d39e5c4da2c0a752de5ea70335199c5
  |  add gamma
  | @  branch default/branch 3:52def9937d74e43b83dfded6ce0e5adf731b9d22
  | |  add gamma
  x |    2:205a004356ef32b8da782afb89d9179d12ca31e9
  | |  add gamma
  | o  master default/master 1:7fe02317c63d9ee324d4b5df7c9296085162da1b
  |/   add beta
  o    0:ff7a2f2d8d7099694ae1e8b03838d40575bebb63
     add alpha

  $ cd ..

Now try rebasing that branch, from the Git side of things

  $ cd gitrepo
  $ git checkout -q otherbranch
  $ git log --oneline --graph --all --decorate
  * c4cfa5e (HEAD -> otherbranch, origin/otherbranch) add gamma
  * e5023f9 (origin/branch, branch) add gamma
  | * 9497a4e (origin/master, master) add beta
  |/  
  * 7eeab2e add alpha
  $ fn_git_rebase --onto master branch otherbranch
  $ git log --oneline --graph --all --decorate
  * 5c9b4bb (HEAD -> otherbranch) add gamma
  * 9497a4e (origin/master, master) add beta
  | * c4cfa5e (origin/otherbranch) add gamma
  | * e5023f9 (origin/branch, branch) add gamma
  |/  
  * 7eeab2e add alpha
  $ git push -f
  To $TESTTMP/repo.git
   + c4cfa5e...5c9b4bb otherbranch -> otherbranch (forced update)
  $ git log --oneline --graph --all --decorate
  * 5c9b4bb (HEAD -> otherbranch, origin/otherbranch) add gamma
  * 9497a4e (origin/master, master) add beta
  | * e5023f9 (origin/branch, branch) add gamma
  |/  
  * 7eeab2e add alpha
  $ cd ..

And check that pulling something else doesn't delete that branch.

  $ cd hgrepo
  $ hg pull -r master
  pulling from $TESTTMP/repo.git
  no changes found

Now just pull it:

  $ hg pull
  pulling from $TESTTMP/repo.git
  importing 1 git commits
  not updating diverged bookmark otherbranch
  new changesets 5a1e52bb860a (1 drafts)
  (run 'hg heads .' to see heads, 'hg merge' to merge)
  $ hg state
  o   default/otherbranch tip 5:5a1e52bb860a4369dc5fff2e63a56d8103404336
  |  add gamma
  | *  otherbranch  4:f4bd265a9d39e5c4da2c0a752de5ea70335199c5
  | |  add gamma
  +---@  branch default/branch 3:52def9937d74e43b83dfded6ce0e5adf731b9d22
  | |    add gamma
  | x    2:205a004356ef32b8da782afb89d9179d12ca31e9
  | |  add gamma
  o |  master default/master 1:7fe02317c63d9ee324d4b5df7c9296085162da1b
  |/   add beta
  o    0:ff7a2f2d8d7099694ae1e8b03838d40575bebb63
     add alpha
  $ cd ..

And finally, delete it:

  $ cd gitrepo
  $ git push origin :otherbranch
  To $TESTTMP/repo.git
   - [deleted]         otherbranch
  $ cd ..

And pull that:

  $ cd hgrepo
  $ hg pull
  pulling from $TESTTMP/repo.git
  no changes found
  $ hg state
  o   tip 5:5a1e52bb860a4369dc5fff2e63a56d8103404336
  |  add gamma
  | *  otherbranch  4:f4bd265a9d39e5c4da2c0a752de5ea70335199c5
  | |  add gamma
  +---@  branch default/branch 3:52def9937d74e43b83dfded6ce0e5adf731b9d22
  | |    add gamma
  | x    2:205a004356ef32b8da782afb89d9179d12ca31e9
  | |  add gamma
  o |  master default/master 1:7fe02317c63d9ee324d4b5df7c9296085162da1b
  |/   add beta
  o    0:ff7a2f2d8d7099694ae1e8b03838d40575bebb63
     add alpha
