Load commonly used test logic
  $ . "$TESTDIR/testutil"

  $ git init gitrepo
  Initialized empty Git repository in $TESTTMP/gitrepo/.git/
  $ cd gitrepo
  $ git config receive.denyCurrentBranch ignore
  $ echo alpha > alpha
  $ git add alpha
  $ fn_git_commit -m "add alpha"

cloning with hggit.usephases publishes cloned changesets
  $ cd ..
  $ hg --config hggit.usephases=True clone gitrepo hgrepo
  importing git objects into hg
  updating to branch default
  1 files updated, 0 files merged, 0 files removed, 0 files unresolved

  $ cd hgrepo
  $ hg phase -r master
  0: public
  $ cd ..

pulled changesets are public
  $ cd gitrepo
  $ git checkout -q master
  $ echo beta > beta
  $ git add beta
  $ fn_git_commit -m 'add beta'
  $ git checkout -b not-master
  Switched to a new branch 'not-master'
  $ echo gamma > gamma
  $ git add gamma
  $ fn_git_commit -m 'add gamma'
  $ cd ..

  $ cd hgrepo
  $ cat >>$HGRCPATH <<EOF
  > [hggit]
  > usephases = True
  > EOF
  $ hg pull
  pulling from $TESTTMP/gitrepo
  importing git objects into hg
  (run 'hg update' to get a working copy)
  $ hg phase -r master
  1: public
  $ hg phase -r not-master
  2: public

public bookmark not pushed is published after pull
  $ hg update 0
  0 files updated, 0 files merged, 0 files removed, 0 files unresolved
  (leaving bookmark master)
  $ echo delta > delta
  $ hg bookmark not-pushed
  $ hg add delta
  $ hg commit -m 'add delta'
  created new head
  $ cat >>$HGRCPATH <<EOF
  > [git]
  > public = master,not-pushed
  > EOF
  $ hg pull
  pulling from $TESTTMP/gitrepo
  no changes found
  $ hg phase -r not-pushed
  3: public

pushing public bookmark does not publish local changesets
  $ hg update master
  1 files updated, 0 files merged, 1 files removed, 0 files unresolved
  (activating bookmark master)
  $ echo epsilon > epsilon
  $ hg add epsilon
  $ hg commit -m 'add epsilon'
  created new head
  $ hg push -B master
  pushing to $TESTTMP/gitrepo
  searching for changes
  adding objects
  added 1 commits with 1 trees and 1 blobs
  updating reference refs/heads/master
  $ hg phase -r master
  4: draft
