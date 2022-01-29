Load commonly used test logic
  $ . "$TESTDIR/testutil"

  $ cat >> $HGRCPATH <<EOF
  > [templates]
  > info =
  >   commit:  {rev}:{node|short}  {desc|fill68}
  >   added:   {file_adds}
  >   removed: {file_dels}\n
  > EOF

This test ensures that we clean up properly when deleting Git
submodules.

  $ git init --bare repo.git
  Initialized empty Git repository in $TESTTMP/repo.git/

Create a repository with a submodule:

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
  $ git submodule add ../gitsubrepo subrepo
  Cloning into '$TESTTMP/gitrepo/subrepo'...
  done.
  $ fn_git_commit -m 'add subrepo'

Now delete all submodules:

  $ git rm .gitmodules subrepo
  rm '.gitmodules'
  rm 'subrepo'
  $ fn_git_commit -m 'delete subrepo'
  $ git push
  To $TESTTMP/repo.git
   * [new branch]      master -> master
  $ cd ..

And there should be nothing in Mercurial either:

  $ hg clone -U repo.git hgrepo
  importing 3 git commits
  new changesets e532b2bfda10:cc611d35fb62 (3 drafts)
  $ cd hgrepo
  $ hg log --graph --template info
  o
  |  commit:  2:cc611d35fb62  delete subrepo
  |  added:
  |  removed: .hgsub .hgsubstate
  o
  |  commit:  1:8d549bcc5179  add subrepo
  |  added:   .hgsub .hgsubstate
  |  removed:
  o
     commit:  0:e532b2bfda10  add alpha
     added:   alpha
     removed:
  $ hg manifest -r tip
  alpha
  $ cd ..
