Load commonly used test logic
  $ . "$TESTDIR/testutil"

  $ git init --bare repo.git
  Initialized empty Git repository in $TESTTMP/repo.git/

  $ hg init hgsubrepo
  $ cd hgsubrepo
  $ echo thefile > thefile
  $ hg add thefile
  $ fn_hg_commit -m 'add thefile'
  $ cd ..

  $ git init gitsubrepo
  Initialized empty Git repository in $TESTTMP/gitsubrepo/.git/
  $ cd gitsubrepo
  $ echo thefile > thefile
  $ git add thefile
  $ fn_git_commit -m 'add thefile'
  $ cd ..

  $ hg clone repo.git hgrepo
  updating to branch default
  0 files updated, 0 files merged, 0 files removed, 0 files unresolved
  $ cd hgrepo
  $ hg book master
  $ echo alpha > alpha
  $ hg add alpha
  $ fn_hg_commit -m 'add alpha'
  $ touch .hgsub
  $ hg add .hgsub
  $ fn_hg_commit -m "add .hgsub"
  $ hg clone -q ../hgsubrepo hg
  $ echo "hg = ../hgsubrepo" >> .hgsub
  $ fn_hg_commit -m 'add hg subrepo'
  $ git clone --quiet ../gitsubrepo git
  $ echo "git = [git]../gitsubrepo" >> .hgsub
  $ fn_hg_commit -m 'add git subrepo'
  $ hg push
  pushing to $TESTTMP/repo.git
  pushing subrepo hg to $TESTTMP/hgsubrepo
  searching for changes
  no changes found
  searching for changes
  adding objects
  remote: found 0 deltas to reuse (dulwich0210 !)
  added 4 commits with 2 trees and 2 blobs
  adding reference refs/heads/master
  $ cat .hgsub
  hg = ../hgsubrepo
  git = [git]../gitsubrepo
  $ cat .hgsubstate
  aaae5224095dca7403147c0e20cbac1f450b0e95 git
  df643c539c7541d48eacc76745581e00cbaf3d45 hg
  $ cd ..

Now clone it. Note that no Mercurial state persists:

  $ git clone --recurse-submodules repo.git gitrepo
  Cloning into 'gitrepo'...
  done.
  Submodule 'git' ($TESTTMP/gitsubrepo) registered for path 'git'
  Cloning into '$TESTTMP/gitrepo/git'...
  done.
  Submodule path 'git': checked out 'aaae5224095dca7403147c0e20cbac1f450b0e95'
  $ cd gitrepo
  $ ls -A
  .git
  .gitmodules
  alpha
  git
  $ cat .gitmodules
  [submodule "git"]
  	path = git
  	url = ../gitsubrepo
  $ ls -A git
  .git
  thefile
