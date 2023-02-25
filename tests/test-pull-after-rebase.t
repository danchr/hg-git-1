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
  remote: found 0 deltas to reuse (dulwich0210 !)
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
  $ fn_git_commit -m 'add delta'
  $ git push --quiet --set-upstream origin otherbranch
  Branch 'otherbranch' set up to track remote branch 'otherbranch' from 'origin'. (?)
  $ git log --oneline --graph --all --decorate
  * bba0011 (HEAD -> otherbranch, origin/otherbranch) add delta
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
  new changesets 075302705298 (1 drafts)
  (run 'hg heads' to see heads, 'hg merge' to merge)
  $ hg state
  *  otherbranch default/otherbranch tip 4:0753027052980aef9c9c37adb7d76d5719e8d818
  |  add delta
  | @  branch default/branch 3:52def9937d74e43b83dfded6ce0e5adf731b9d22
  | |  add gamma
  x |    2:205a004356ef32b8da782afb89d9179d12ca31e9
  | |  add gamma
  | o  master default/master 1:7fe02317c63d9ee324d4b5df7c9296085162da1b
  |/   add beta
  o    0:ff7a2f2d8d7099694ae1e8b03838d40575bebb63
     add alpha

  $ cd ..

To reproduce bug #386, do like github and save the old commit in a
ref, and create a clone containing just the converted git commits:

  $ cd repo.git
  $ git update-ref refs/pr/1 otherbranch
  $ cd ..
  $ hg clone -U repo.git hgrepo-issue386
  importing 5 git commits
  new changesets ff7a2f2d8d70:075302705298 (5 drafts)

Now try rebasing that branch, from the Git side of things

  $ cd gitrepo
  $ git checkout -q otherbranch
  $ git log --oneline --graph --all --decorate
  * bba0011 (HEAD -> otherbranch, origin/otherbranch) add delta
  * e5023f9 (origin/branch, branch) add gamma
  | * 9497a4e (origin/master, master) add beta
  |/  
  * 7eeab2e add alpha
  $ fn_git_rebase --onto master branch otherbranch
  $ git log --oneline --graph --all --decorate
  * 9c58139 (HEAD -> otherbranch) add delta
  * 9497a4e (origin/master, master) add beta
  | * bba0011 (origin/otherbranch) add delta
  | * e5023f9 (origin/branch, branch) add gamma
  |/  
  * 7eeab2e add alpha
  $ git push -f
  To $TESTTMP/repo.git
   + bba0011...9c58139 otherbranch -> otherbranch (forced update)
  $ git log --oneline --graph --all --decorate
  * 9c58139 (HEAD -> otherbranch, origin/otherbranch) add delta
  * 9497a4e (origin/master, master) add beta
  | * e5023f9 (origin/branch, branch) add gamma
  |/  
  * 7eeab2e add alpha
  $ cd ..

Now strip the old commit

  $ cd hgrepo-issue386
  $ hg up null
  0 files updated, 0 files merged, 0 files removed, 0 files unresolved
  $ hg id -qr otherbranch
  075302705298
  $ hg pull
  pulling from $TESTTMP/repo.git
  importing 1 git commits
  not updating diverged bookmark otherbranch
  new changesets d64bf0521af6 (1 drafts)
  (run 'hg heads .' to see heads, 'hg merge' to merge)
  $ hg debugstrip --hidden --no-backup otherbranch
  $ hg book -d otherbranch
  $ hg git-cleanup
  git commit map cleaned
  $ hg pull
  pulling from $TESTTMP/repo.git
  no changes found
  adding bookmark otherbranch
  $ cd ..

And check that pulling something else doesn't delete that branch.

  $ cd hgrepo
  $ hg pull -r master
  pulling from $TESTTMP/repo.git
  no changes found
  $ cd ..

A special case, is that we can pull into a repository, where a commit
corresponding to the new branch exists, but that commit is obsolete.
In order to avoid “pinning” the obsolete commit, and thereby making it
visible, we first pull from Git as an unnamed remote.

  $ hg clone --config phases.publish=no hgrepo hgrepo-clone
  updating to branch default
  3 files updated, 0 files merged, 0 files removed, 0 files unresolved
  $ cd hgrepo-clone
  $ hg pull ../repo.git
  pulling from ../repo.git
  importing 4 git commits
  not updating diverged bookmark otherbranch
  new changesets d64bf0521af6 (1 drafts)
  (run 'hg heads .' to see heads, 'hg merge' to merge)
  $ hg debugobsolete d64bf0521af68fe2160791a1b4ab9baf282a3879
  1 new obsolescence markers
  obsoleted 1 changesets
  $ cp ../hgrepo/.hg/hgrc .hg
  $ hg pull
  pulling from $TESTTMP/repo.git
  no changes found
  not updating diverged bookmark otherbranch
  $ cd ..
  $ rm -rf hgrepo-clone

Another special case, is that we should update commits over obsolete boundaries:

  $ hg clone --config phases.publish=no hgrepo hgrepo-clone
  updating to branch default
  3 files updated, 0 files merged, 0 files removed, 0 files unresolved
  $ cd hgrepo-clone
  $ hg pull ../repo.git
  pulling from ../repo.git
  importing 4 git commits
  not updating diverged bookmark otherbranch
  new changesets d64bf0521af6 (1 drafts)
  (run 'hg heads .' to see heads, 'hg merge' to merge)
  $ hg debugobsolete 0753027052980aef9c9c37adb7d76d5719e8d818 d64bf0521af68fe2160791a1b4ab9baf282a3879
  1 new obsolescence markers
  obsoleted 1 changesets
  $ hg book -r 075302705298 otherbranch
  $ cp ../hgrepo/.hg/hgrc .hg
  $ hg pull
  pulling from $TESTTMP/repo.git
  no changes found
  updating bookmark otherbranch
  $ cd ..
  $ rm -rf hgrepo-clone

Now just pull it:

  $ cd hgrepo
  $ hg pull
  pulling from $TESTTMP/repo.git
  importing 1 git commits
  not updating diverged bookmark otherbranch
  new changesets d64bf0521af6 (1 drafts)
  (run 'hg heads .' to see heads, 'hg merge' to merge)
  $ hg state
  o   default/otherbranch tip 5:d64bf0521af68fe2160791a1b4ab9baf282a3879
  |  add delta
  | *  otherbranch  4:0753027052980aef9c9c37adb7d76d5719e8d818
  | |  add delta
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
  not deleting diverged bookmark otherbranch
  $ hg state
  o   tip 5:d64bf0521af68fe2160791a1b4ab9baf282a3879
  |  add delta
  | *  otherbranch  4:0753027052980aef9c9c37adb7d76d5719e8d818
  | |  add delta
  +---@  branch default/branch 3:52def9937d74e43b83dfded6ce0e5adf731b9d22
  | |    add gamma
  | x    2:205a004356ef32b8da782afb89d9179d12ca31e9
  | |  add gamma
  o |  master default/master 1:7fe02317c63d9ee324d4b5df7c9296085162da1b
  |/   add beta
  o    0:ff7a2f2d8d7099694ae1e8b03838d40575bebb63
     add alpha
  $ cd ..

We only get that message once:

  $ hg -R hgrepo pull
  pulling from $TESTTMP/repo.git
  no changes found

Now try deleting one already gone locally, which shouldn't output
anything:

  $ cd gitrepo
  $ git push origin :branch
  To $TESTTMP/repo.git
   - [deleted]         branch
  $ cd ../hgrepo
  $ hg book -d branch
  $ hg pull
  pulling from $TESTTMP/repo.git
  no changes found
  $ cd ..
