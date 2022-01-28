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
  new changesets e532b2bfda10:824fb8f70a77 (3 drafts)
  $ cd hgrepo
  $ hg log --graph --template info
  o
  |  commit:  2:824fb8f70a77  delete subrepo
  |  added:
  |  removed: .gitmodules .hgsub .hgsubstate
  o
  |  commit:  1:32c6bd4f29bd  add subrepo
  |  added:   .gitmodules .hgsub .hgsubstate
  |  removed:
  o
     commit:  0:e532b2bfda10  add alpha
     added:   alpha
     removed:
  $ hg manifest -r tip
  alpha
  $ cd ..
