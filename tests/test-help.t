Tests that the various help files are properly registered

Load commonly used test logic
  $ . "$TESTDIR/testutil"

  $ hg help | grep 'git' | sed 's/  */ /g'
   git-cleanup clean up Git commit map after history editing (?)
   git-verify verify that a Mercurial rev matches the corresponding Git rev
   hggit push and pull from a Git server
