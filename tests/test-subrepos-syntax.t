Load commonly used test logic
  $ . "$TESTDIR/testutil"

This is mostly equivalent to test-subrepos.t, but exercises a
particular case where we cannot possibly retain bidirectionality:
comments and [subpaths] in .hgsub

  $ git init --bare repo.git
  Initialized empty Git repository in $TESTTMP/repo.git/

  $ git init gitsubrepo
  Initialized empty Git repository in $TESTTMP/gitsubrepo/.git/
  $ cd gitsubrepo
  $ echo beta > beta
  $ git add beta
  $ fn_git_commit -m 'add beta'
  $ cd ..

  $ git clone repo.git gitrepo
  Cloning into 'gitrepo'...
  warning: You appear to have cloned an empty repository.
  done.
  $ cd gitrepo
  $ echo alpha > alpha
  $ git add alpha
  $ fn_git_commit -m 'add alpha'
  $ git submodule add ../gitsubrepo subrepo1
  Cloning into '*subrepo1'... (glob)
  done.
  $ fn_git_commit -m 'add subrepo1'
  $ git submodule add ../gitsubrepo xyz/subrepo2
  Cloning into '*xyz/subrepo2'... (glob)
  done.
  $ fn_git_commit -m 'add subrepo2'
  $ git push
  To $TESTTMP/repo.git
   * [new branch]      master -> master
  $ cd ..

  $ hg clone -U repo.git hgrepo
  importing 3 git commits
  new changesets e532b2bfda10:3c4fd561cbeb (3 drafts)
  $ cd hgrepo
  $ hg up master
  Cloning into '$TESTTMP/hgrepo/subrepo1'...
  done.
  Cloning into '$TESTTMP/hgrepo/xyz/subrepo2'...
  done.
  cloning subrepo subrepo1 from $TESTTMP/gitsubrepo
  cloning subrepo xyz/subrepo2 from $TESTTMP/gitsubrepo
  3 files updated, 0 files merged, 0 files removed, 0 files unresolved
  (activating bookmark master)
  $ cat >> .hgsub <<EOF
  > # this is a comment
  > [subpaths]
  > flaf = blyf
  > EOF
  $ fn_hg_commit -m 'add comment & subsection'
  $ hg push
  pushing to $TESTTMP/repo.git
  searching for changes
  adding objects
  remote: found 0 deltas to reuse (dulwich0210 !)
  added 1 commits with 1 trees and 0 blobs
  updating reference refs/heads/master
  $ cd ..

  $ cd gitrepo
  $ git pull --ff-only
  From $TESTTMP/repo
     89c22d7..106b34e  master     -> origin/master
  Updating 89c22d7..106b34e
  Fast-forward
  $ cat .gitmodules
  [submodule "subrepo1"]
  	path = subrepo1
  	url = ../gitsubrepo
  [submodule "xyz/subrepo2"]
  	path = xyz/subrepo2
  	url = ../gitsubrepo
  $ cd ..

We broke bidirectionality:

  $ hg clone -U repo.git hgrepo2
  importing 4 git commits
  new changesets e532b2bfda10:cbf584fe001b (4 drafts)
  $ hg id -r tip hgrepo
  c58a542b18bc default/master/tip master
  $ hg id -r tip hgrepo2
  cbf584fe001b default/master/tip master
