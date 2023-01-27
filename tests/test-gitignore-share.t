Load commonly used test logic
  $ . "$TESTDIR/testutil"

  $ cat >> $HGRCPATH <<EOF
  > [extensions]
  > share =
  > EOF

  $ git init --quiet --bare repo.git

  $ hg init hgrepo
  $ cd hgrepo
  $ cat > .hg/hgrc <<EOF
  > [paths]
  > default = $TESTTMP/repo.git
  > EOF
  $ echo ignored > .gitignore
  $ hg add .gitignore
  $ hg ci -m ignore
  $ hg book master
  $ hg push
  pushing to $TESTTMP/repo.git
  searching for changes
  adding objects
  remote: found 0 deltas to reuse (dulwich0210 !)
  added 1 commits with 1 trees and 1 blobs
  adding reference refs/heads/master
  $ cd ..

We should also ignore the file in a shared repository:

  $ hg share hgrepo sharerepo
  updating working directory
  1 files updated, 0 files merged, 0 files removed, 0 files unresolved
  $ cd sharerepo
  $ hg paths
  default = $TESTTMP/repo.git
  $ cat .gitignore
  ignored
  $ touch ignored
  $ hg status
