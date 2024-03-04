#require serve

Load commonly used test logic
  $ . "$TESTDIR/testutil"

  $ hg init test
  $ cd test
  $ echo foo>foo
  $ mkdir foo.d foo.d/bAr.hg.d foo.d/baR.d.hg
  $ echo foo>foo.d/foo
  $ echo bar>foo.d/bAr.hg.d/BaR
  $ echo bar>foo.d/baR.d.hg/bAR
  $ hg commit -A -m 1
  adding foo
  adding foo.d/bAr.hg.d/BaR
  adding foo.d/baR.d.hg/bAR
  adding foo.d/foo
  $ cat >> .hg/hgrc <<EOF
  > [push]
  > pushvars.server = true
  > [web]
  > allow-push = *
  > push_ssl = no
  > [hooks]
  > pretxnchangegroup = env | grep HG_USERVAR_ || true
  > EOF
  $ hg serve -p $HGPORT -d --pid-file=../hg1.pid -E ../error.log
  $ hg --config server.uncompressed=False serve -p $HGPORT1 -d --pid-file=../hg2.pid

Test server address cannot be reused

#if windows
  $ hg serve -p $HGPORT1 2>&1
  abort: cannot start server at '*:$HGPORT1': * (glob)
  [255]
#else
  $ hg serve -p $HGPORT1 2>&1
  abort: cannot start server at '*:$HGPORT1': Address* in use (glob)
  [255]
#endif
  $ cd ..
  $ cat hg1.pid hg2.pid >> $DAEMON_PIDS

Load commonly used test logic
  $ . "$TESTDIR/testutil"

Make sure that clone regular mercurial repos over http doesn't break

  $ hg clone http://localhost:$HGPORT/ copy 2>&1
  requesting all changes
  adding changesets
  adding manifests
  adding file changes
  added 1 changesets with 4 changes to 4 files
  new changesets 8b6053c928fe (?)
  updating to branch default
  4 files updated, 0 files merged, 0 files removed, 0 files unresolved

And it shouldn't create a Git repository needlessly:

  $ ls copy/.hg | grep git
  [1]

Furthermore, make sure that we pass all arguments when pushing:

  $ cd copy
  $ echo baz > baz
  $ fn_hg_commit -A -m baz
  $ hg push --pushvars FOO=BAR
  pushing to http://localhost:$HGPORT/
  searching for changes
  remote: adding changesets
  remote: adding manifests
  remote: adding file changes
  remote: HG_USERVAR_FOO=BAR
  remote: added 1 changesets with 1 changes to 1 files
  $ cd ..
