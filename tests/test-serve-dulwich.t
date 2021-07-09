#require serve

Check cloning a Git repository over anonymous HTTP, served up by
Dulwich. The script uses `os.fork()`, so this doesn't work on Windows.

Load commonly used test logic
  $ . "$TESTDIR/testutil"

Create a dummy repository and serve it

  $ git init -q test
  $ cd test
  $ echo foo > foo
  $ git add foo
  $ fn_git_commit -m test
  $ echo bar > bar
  $ git add bar
  $ fn_git_commit -m test
  $ $PYTHON $TESTDIR/testlib/dulwich-serve.py --port=$HGPORT
  $ cd ..

Make sure that clone over unauthenticated HTTP doesn't break

  $ hg clone -U git+http://localhost:$HGPORT copy 2>&1
  importing git objects into hg
  $ hg log -T 'HG:{node|short} GIT:{gitnode|short}\n' -R copy
  HG:221dd250e933 GIT:3af9773036a9
  HG:c4d188f6e13d GIT:b23744d34f97

  $ cd copy
  $ hg up master
  2 files updated, 0 files merged, 0 files removed, 0 files unresolved
  (activating bookmark master)
  $ echo baz > baz
  $ fn_hg_commit -A -m baz
  $ hg push
  pushing to git+http://localhost:$HGPORT/
  searching for changes
  adding objects
  added 1 commits with 1 trees and 1 blobs
  updating reference refs/heads/master
  $ hg log -T 'HG:{node|short} GIT:{gitnode|short}\n' -r .
  HG:daf1ae153bf8 GIT:ab88565d0614

Prevent the test from hanging:

  $ cat $DAEMON_PIDS | xargs kill

(As an aside, don't use `pkill -F` -- that doesn't work and causes a
hang on Alpine.)
