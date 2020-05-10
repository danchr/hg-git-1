Load commonly used test logic
  $ . "$TESTDIR/testutil"

This test doesn’t test any git-related functionality. It checks that a previous
bug is not present where mercurial.hg.addbranchrevs() was erroneously
monkey-patched such that the 'checkout' return value was always None. This
caused the pull to not update to the passed revision.

  $ hg init orig
  $ cd orig
  $ echo a > a; hg add a; hg ci -m a
  $ hg branch foo -q
  $ echo b > b; hg add b; hg ci -m b

  $ cd ..
  $ hg clone orig clone -r 0 -q
  $ cd clone
  $ hg pull -u -r 1 -q
  $ hg id -n
  1
