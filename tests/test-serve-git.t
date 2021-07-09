#require serve

Load commonly used test logic
  $ . "$TESTDIR/testutil"

Create a dummy repository and serve it

  $ git init -q test
  $ cd test
  $ echo foo > foo
  $ git add foo
  $ fn_git_commit -m test
  $ git daemon --listen=localhost --port=$HGPORT \
  > --pid-file=$DAEMON_PIDS --detach --export-all --verbose \
  > --base-path=$TESTTMP \
  > || exit 80
  $ cd ..

Make sure that clone over the old git protocol doesn't break

  $ hg clone -U git://localhost:$HGPORT/test copy 2>&1
  importing git objects into hg
  $ hg id -r tip copy
  c4d188f6e13d default/master/tip master
