#require serve

Load commonly used test logic
  $ . "$TESTDIR/testutil"

  $ git init test
  Initialized empty Git repository in $TESTTMP/test/.git/
  $ cd test
  $ echo foo > foo
  $ git add foo
  $ fn_git_commit -m test
  $ cd $TESTTMP
  $ git daemon --listen=localhost --port=$HGPORT \
  > --pid-file=$DAEMON_PIDS --detach --export-all --verbose \
  > --base-path=$TESTTMP \
  > || exit 80

Show that clone over the old git protocol breaks

  $ hg clone git://localhost:$HGPORT/test copy 2>&1 | tail -n 1
  AttributeError: 'bytes' object has no attribute 'encode'
