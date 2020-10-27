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

Make sure that clone over the old git protocol doesn't break

  $ hg clone git://localhost:$HGPORT/test copy 2>&1
  importing git objects into hg
  updating to branch default
  1 files updated, 0 files merged, 0 files removed, 0 files unresolved
  $ ls copy
  foo
