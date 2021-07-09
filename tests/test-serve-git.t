#require serve

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
  $ git daemon --listen=localhost --port=$HGPORT \
  > --pid-file=$DAEMON_PIDS --detach --export-all --verbose \
  > --base-path=$TESTTMP \
  > || exit 80
  $ cd ..

Make sure that clone over the old git protocol doesn't break

  $ hg clone -U git://localhost:$HGPORT/test copy 2>&1
  importing git objects into hg
  $ hg log -T 'HG:{node|short} GIT:{gitnode|short}\n' -R copy
  HG:221dd250e933 GIT:3af9773036a9
  HG:c4d188f6e13d GIT:b23744d34f97
