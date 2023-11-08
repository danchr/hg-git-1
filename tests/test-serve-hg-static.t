#require no-reposimplestore

Copied from Mercurial's `tests/test-static-http.t`, with the following
line added to load commonly used test logic:

  $ . "$TESTDIR/testutil"

  $ hg clone http://localhost:$HGPORT/ copy
  abort: * (glob)
  [100]
  $ test -d copy
  [1]

This server doesn't do range requests so it's basically only good for
one pull

  $ "$PYTHON" "$TESTDIR/testlib/dumbhttp.py" -p $HGPORT --pid dumb.pid \
  > --logfile server.log
  $ cat dumb.pid >> $DAEMON_PIDS
  $ hg init remote
  $ cd remote
  $ echo foo > bar
  $ echo c2 > '.dotfile with spaces'
  $ hg add
  adding .dotfile with spaces
  adding bar
  $ hg commit -m"test"
  $ hg tip
  changeset:   0:02770d679fb8
  tag:         tip
  user:        test
  date:        Thu Jan 01 00:00:00 1970 +0000
  summary:     test
  
  $ cd ..
  $ hg clone static-http://localhost:$HGPORT/remote local
  requesting all changes
  adding changesets
  adding manifests
  adding file changes
  added 1 changesets with 2 changes to 2 files
  new changesets 02770d679fb8
  updating to branch default
  2 files updated, 0 files merged, 0 files removed, 0 files unresolved
  $ cd local
  $ hg verify
  checking changesets
  checking manifests
  crosschecking files in changesets and manifests
  checking files
  checking dirstate (?)
  checked 1 changesets with 2 changes to 2 files
  $ cat bar
  foo
  $ cd ../remote
  $ echo baz > quux
  $ hg commit -A -mtest2
  adding quux

check for HTTP opener failures when cachefile does not exist

  $ rm .hg/cache/*
  $ cd ../local
  $ hg pull
  pulling from static-http://localhost:$HGPORT/remote
  searching for changes
  adding changesets
  adding manifests
  adding file changes
  added 1 changesets with 1 changes to 1 files
  new changesets 4ac2e3648604
  (run 'hg update' to get a working copy)

trying to push

  $ hg update
  1 files updated, 0 files merged, 0 files removed, 0 files unresolved
  $ echo more foo >> bar
  $ hg commit -m"test"
  $ hg push
  pushing to static-http://localhost:$HGPORT/remote
  abort: destination does not support push
  [255]

trying clone -r

  $ cd ..
  $ hg clone -r doesnotexist static-http://localhost:$HGPORT/remote local0
  abort: unknown revision 'doesnotexist'!? (re)
  [10]
  $ hg clone -r 0 static-http://localhost:$HGPORT/remote local0
  adding changesets
  adding manifests
  adding file changes
  added 1 changesets with 2 changes to 2 files
  new changesets 02770d679fb8
  updating to branch default
  2 files updated, 0 files merged, 0 files removed, 0 files unresolved

test with "/" URI (issue747) and subrepo

  $ hg init
  $ hg init sub
  $ touch sub/test
  $ hg -R sub commit -A -m "test"
  adding test
  $ hg -R sub tag not-empty
  $ echo sub=sub > .hgsub
  $ echo a > a
  $ hg add a .hgsub
  $ hg -q ci -ma
  $ hg clone static-http://localhost:$HGPORT/ local2
  requesting all changes
  adding changesets
  adding manifests
  adding file changes
  added 1 changesets with 3 changes to 3 files
  new changesets a9ebfbe8e587
  updating to branch default
  cloning subrepo sub from static-http://localhost:$HGPORT/sub
  requesting all changes
  adding changesets
  adding manifests
  adding file changes
  added 2 changesets with 2 changes to 2 files
  new changesets be090ea66256:322ea90975df
  3 files updated, 0 files merged, 0 files removed, 0 files unresolved
  $ cd local2
  $ hg verify
  checking changesets
  checking manifests
  crosschecking files in changesets and manifests
  checking files
  checking dirstate (?)
  checked 1 changesets with 3 changes to 3 files
  checking subrepo links
  $ cat a
  a
  $ hg paths
  default = static-http://localhost:$HGPORT/

test with empty repo (issue965)

  $ cd ..
  $ hg init remotempty
  $ hg clone static-http://localhost:$HGPORT/remotempty local3
  no changes found
  updating to branch default
  0 files updated, 0 files merged, 0 files removed, 0 files unresolved
  $ cd local3
  $ hg verify
  checking changesets
  checking manifests
  crosschecking files in changesets and manifests
  checking files
  checking dirstate (?)
  checked 0 changesets with 0 changes to 0 files
  $ hg paths
  default = static-http://localhost:$HGPORT/remotempty
  $ cd ..

Clone with tags and branches works

  $ hg init remote-with-names
  $ cd remote-with-names
  $ echo 0 > foo
  $ hg -q commit -A -m initial
  $ echo 1 > foo
  $ hg commit -m 'commit 1'
  $ hg -q up 0
  $ hg branch mybranch
  marked working directory as branch mybranch
  (branches are permanent and global, did you want a bookmark?)
  $ echo 2 > foo
  $ hg commit -m 'commit 2 (mybranch)'
  $ hg tag -r 1 'default-tag'
  $ hg tag -r 2 'branch-tag'

  $ cd ..

  $ hg clone static-http://localhost:$HGPORT/remote-with-names local-with-names
  requesting all changes
  adding changesets
  adding manifests
  adding file changes
  added 5 changesets with 5 changes to 2 files (+1 heads)
  new changesets 68986213bd44:0c325bd2b5a7
  updating to branch default
  1 files updated, 0 files merged, 0 files removed, 0 files unresolved

Clone a specific branch works

  $ hg clone -r mybranch static-http://localhost:$HGPORT/remote-with-names local-with-names-branch
  adding changesets
  adding manifests
  adding file changes
  added 4 changesets with 4 changes to 2 files
  new changesets 68986213bd44:0c325bd2b5a7
  updating to branch mybranch
  2 files updated, 0 files merged, 0 files removed, 0 files unresolved

Clone a specific tag works

  $ hg clone -r default-tag static-http://localhost:$HGPORT/remote-with-names local-with-names-tag
  adding changesets
  adding manifests
  adding file changes
  added 2 changesets with 2 changes to 1 files
  new changesets 68986213bd44:4ee3fcef1c80
  updating to branch default
  1 files updated, 0 files merged, 0 files removed, 0 files unresolved

  $ killdaemons.py
