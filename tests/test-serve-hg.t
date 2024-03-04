#require serve

Load commonly used test logic
  $ . "$TESTDIR/testutil"

#testcases with-hggit without-hggit

Load commonly used test logic
  $ . "$TESTDIR/testutil"

#if with-hggit
  $ cat >> $HGRCPATH <<EOF
  > [experimental]
  > hg-git-serve = yes
  > EOF
#endif

  $ git init gitrepo
  Initialized empty Git repository in $TESTTMP/gitrepo/.git/
  $ cd gitrepo
  $ echo foo>foo
  $ mkdir foo.d foo.d/bAr.hg.d foo.d/baR.d.hg
  $ git add .
  $ fn_git_commit -m 1
  $ git tag thetag
  $ echo foo>foo.d/foo
  $ echo bar>foo.d/bAr.hg.d/BaR
  $ echo bar>foo.d/baR.d.hg/bAR
  $ git add .
  $ fn_git_commit -m 2
  $ cd ..

  $ hg clone gitrepo hgrepo
  importing 2 git commits
  new changesets f488b65fa424:c61c38c3d614 (2 drafts)
  updating to branch default (no-hg57 !)
  updating to bookmark master (hg57 !)
  4 files updated, 0 files merged, 0 files removed, 0 files unresolved
  $ cd hgrepo
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

Make sure that clone regular mercurial repos over http doesn't break,
and that we can transfer the hg-git metadata

  $ hg clone http://localhost:$HGPORT/ copy 2>&1
  requesting all changes
  adding changesets
  adding manifests
  adding file changes
  added 2 changesets with 4 changes to 4 files
  new changesets f488b65fa424:c61c38c3d614 (?)
  updating to branch default
  4 files updated, 0 files merged, 0 files removed, 0 files unresolved

And it shouldn't create a Git repository needlessly:
  $ test -e copy/git
  [1]
  $ cd copy

#if without-hggit
  $ hg tags
  tip                                1:c61c38c3d614
  $ hg log -T '{rev}:{node|short} | {bookmarks} | {gitnode} |\n'
  1:c61c38c3d614 | master |  |
  0:f488b65fa424 |  |  |
  $ hg pull -u ../gitrepo
  pulling from ../gitrepo
  importing 2 git commits
  0 files updated, 0 files merged, 0 files removed, 0 files unresolved
#else
  $ hg tags
  tip                                1:c61c38c3d614
  thetag                             0:f488b65fa424
  $ hg log -T '{rev}:{node|short} | {bookmarks} | {gitnode} |\n'
  1:c61c38c3d614 | master | 95bcbb72932335c132c10950b5e5dc1066138ea1 |
  0:f488b65fa424 |  | a874aa4c9506ed30ef2c2c7313abd2c518e9e71e |
  $ hg pull -u ../gitrepo
  pulling from ../gitrepo
  warning: created new git repository at $TESTTMP/copy/.hg/git
  no changes found
#endif

  $ hg tags
  tip                                1:c61c38c3d614
  thetag                             0:f488b65fa424
  $ hg log -T '{rev}:{node|short} | {bookmarks} | {gitnode} |\n'
  1:c61c38c3d614 | master | 95bcbb72932335c132c10950b5e5dc1066138ea1 |
  0:f488b65fa424 |  | a874aa4c9506ed30ef2c2c7313abd2c518e9e71e |

Furthermore, make sure that we pass all arguments when pushing:

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
