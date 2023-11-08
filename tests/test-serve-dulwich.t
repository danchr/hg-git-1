#require serve

Check cloning a Git repository over anonymous HTTP, served up by
Dulwich.

Load commonly used test logic
  $ . "$TESTDIR/testutil"

Enable progress debugging:

  $ cat >> $HGRCPATH <<EOF
  > [progress]
  > delay = 0
  > refresh = 0
  > width = 60
  > format = topic unit total number item bar
  > assume-tty = yes
  > EOF

Create a dummy repository

  $ git init -q gitrepo
  $ cd gitrepo
  $ echo foo > foo
  $ git add foo
  $ fn_git_commit -m test
  $ echo bar > bar
  $ git add bar
  $ fn_git_commit -m test
  $ cd ..

And a bare one:

  $ git clone -q --bare gitrepo repo.git

Serve them:

  $ $PYTHON $TESTDIR/testlib/daemonize.py dulwich.log \
  > $TESTDIR/testlib/dulwich-serve.py $HGPORT

Make sure that clone over unauthenticated HTTP doesn't break

  $ hg clone -U git+http://localhost:$HGPORT/gitrepo hgrepo 2>&1 || cat $TESTTMP/dulwich.log
  \r (no-eol) (esc)
  counting objects 1 [ <=>                                  ]\r (no-eol) (esc) (no-dulwich0210 !)
  counting objects 2 [  <=>                                 ]\r (no-eol) (esc) (no-dulwich0210 !)
  counting objects 3 [   <=>                                ]\r (no-eol) (esc) (no-dulwich0210 !)
  counting objects 4 [    <=>                               ]\r (no-eol) (esc) (no-dulwich0210 !)
  counting objects 5 [     <=>                              ]\r (no-eol) (esc) (no-dulwich0210 !)
  counting objects 6 [      <=>                             ]\r (no-eol) (esc) (no-dulwich0210 !)
                                                              \r (no-eol) (esc) (no-dulwich0210 !)
  \r (no-eol) (esc) (no-dulwich0210 !)
  importing commits 1/2 b23744d34f97         [======>       ]\r (no-eol) (esc)
  importing commits 2/2 3af9773036a9         [=============>]\r (no-eol) (esc)
                                                              \r (no-eol) (esc)
  importing 2 git commits
  new changesets c4d188f6e13d:221dd250e933 (2 drafts)
  $ hg log -T 'HG:{node|short} GIT:{gitnode|short}\n' -R hgrepo
  HG:221dd250e933 GIT:3af9773036a9
  HG:c4d188f6e13d GIT:b23744d34f97

Similarly, make sure that we detect repositories ending with .git

  $ hg clone -U http://localhost:$HGPORT/repo.git hgrepo-copy 2>&1 || cat $TESTTMP/dulwich.log
  \r (no-eol) (esc) (no-dulwich0210 !)
  counting objects 1 [ <=>                                  ]\r (no-eol) (esc) (no-dulwich0210 !)
  counting objects 2 [  <=>                                 ]\r (no-eol) (esc) (no-dulwich0210 !)
  counting objects 3 [   <=>                                ]\r (no-eol) (esc) (no-dulwich0210 !)
  counting objects 4 [    <=>                               ]\r (no-eol) (esc) (no-dulwich0210 !)
  counting objects 5 [     <=>                              ]\r (no-eol) (esc) (no-dulwich0210 !)
  counting objects 6 [      <=>                             ]\r (no-eol) (esc) (no-dulwich0210 !)
                                                              \r (no-eol) (esc) (no-dulwich0210 !)
  \r (no-eol) (esc)
  importing commits 1/2 b23744d34f97         [======>       ]\r (no-eol) (esc)
  importing commits 2/2 3af9773036a9         [=============>]\r (no-eol) (esc)
                                                              \r (no-eol) (esc)
  importing 2 git commits
  new changesets c4d188f6e13d:221dd250e933 (2 drafts)


#if dulwich02037 no-dulwich02044
Broken due to bug #977 in Dulwich
#else

  $ cd hgrepo
  $ hg up master
  \r (no-eol) (esc)
  updating files 2/2 foo                  [================>]\r (no-eol) (esc)
                                                              \r (no-eol) (esc)
  2 files updated, 0 files merged, 0 files removed, 0 files unresolved
  (activating bookmark master)
  $ echo baz > baz
  $ fn_hg_commit -A -m baz
  $ hg push || cat $TESTTMP/dulwich.log
  \r (no-eol) (esc)
  searching commits 1/1 daf1ae153bf8         [=============>]\r (no-eol) (esc)
                                                              \r (no-eol) (esc)
  \r (no-eol) (esc)
  exporting 1/1 daf1ae153bf8         [=====================>]\r (no-eol) (esc)
                                                              \r (no-eol) (esc)
  \r (no-eol) (esc) (no-dulwich0210 !)
  counting objects 4 [ <=>                                  ]\r (no-eol) (esc) (no-dulwich0210 !)
  counting objects 5 [  <=>                                 ]\r (no-eol) (esc) (no-dulwich0210 !)
  counting objects 6 [   <=>                                ]\r (no-eol) (esc) (no-dulwich0210 !)
                                                              \r (no-eol) (esc) (no-dulwich0210 !)
  pushing to git+http://localhost:$HGPORT/gitrepo
  searching for changes
  adding objects
  remote: found 0 deltas to reuse (dulwich0210 !)
  added 1 commits with 1 trees and 1 blobs
  updating reference refs/heads/master
  $ hg log -T 'HG:{node|short} GIT:{gitnode|short}\n' -r .
  HG:daf1ae153bf8 GIT:ab88565d0614
  $ cd ..
#endif
