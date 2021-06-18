#testcases publish-defaults publish-specific

Phases
======

This test verifies our behaviour with the ``hggit.usephases`` option.
We run it in two modes:

1) The defaults, i.e. the remote HEAD.
2) Specificly set what should be published to correspond to the defaults.


Load commonly used test logic
  $ . "$TESTDIR/testutil"

  $ git init gitrepo
  Initialized empty Git repository in $TESTTMP/gitrepo/.git/
  $ cd gitrepo
  $ git config receive.denyCurrentBranch ignore
  $ echo alpha > alpha
  $ git add alpha
  $ fn_git_commit -m "add alpha"
  $ cd ..

cloning with hggit.usephases publishes cloned HEAD
  $ hg --config hggit.usephases=True clone -U gitrepo hgrepo
  importing git objects into hg

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
  $ git tag thetag
  $ echo delta > delta
  $ git add delta
  $ fn_git_commit -m 'add delta'
  $ git checkout master
  Switched to branch 'master'
  $ cd ..

  $ cd hgrepo
  $ cat >>$HGRCPATH <<EOF
  > [paths]
  > other = $TESTTMP/gitrepo/.git
  > [hggit]
  > usephases = True
  > EOF

  $ hg phase -fd 'all()'

we can restrict publishing to the remote HEAD, which happens to be the
same thing here

#if publish-specific
  $ cat >>$HGRCPATH <<EOF
  > [git]
  > public = master
  > EOF
#endif

pulling publishes the branch

  $ hg phase -r master
  0: draft
  $ hg pull -r master other
  pulling from $TESTTMP/gitrepo/.git
  importing git objects into hg
  (run 'hg update' to get a working copy)
  $ hg phase -r master
  1: public
  $ hg phase -fd master
  $ hg pull
  pulling from $TESTTMP/gitrepo
  importing git objects into hg
  (run 'hg update' to get a working copy)
  $ hg phase -r master -r not-master -r thetag
  1: public
  3: draft
  2: draft

public bookmark not pushed is incorrectly published after pull

  $ hg update 0
  1 files updated, 0 files merged, 0 files removed, 0 files unresolved
  (leaving bookmark master)
  $ echo delta > delta
  $ hg bookmark not-pushed
  $ hg add delta
  $ hg commit -m 'add delta'
  created new head
  $ hg phase -r 'all()' > $TESTTMP/before
  $ hg pull --config git.public=master,not-pushed
  pulling from $TESTTMP/gitrepo
  no changes found
  $ hg phase -r 'all()' > $TESTTMP/after
  $ cmp -s $TESTTMP/before $TESTTMP/after
  [1]
NB: this is wrong
  $ hg phase -r not-pushed
  4: public
  $ hg phase -fd not-pushed
  $ rm $TESTTMP/before $TESTTMP/after

pushing public bookmark does not publish local changesets, yet

  $ hg update master
  1 files updated, 0 files merged, 1 files removed, 0 files unresolved
  (activating bookmark master)
  $ echo epsilon > epsilon
  $ hg add epsilon
  $ hg commit -m 'add epsilon'
  created new head
  $ hg phase -r 'all() - master' > $TESTTMP/before
  $ hg push -B not-pushed
  pushing to $TESTTMP/gitrepo
  searching for changes
  adding objects
  added 1 commits with 1 trees and 1 blobs
  adding reference refs/heads/not-pushed
  $ hg phase -r 'all() - master' > $TESTTMP/after
  $ diff $TESTTMP/before $TESTTMP/after | tr '<>' '-+'
  $ hg phase -r not-pushed -r master
  4: draft
  5: draft
  $ hg push -B master
  pushing to $TESTTMP/gitrepo
  searching for changes
  adding objects
  added 1 commits with 1 trees and 1 blobs
  updating reference refs/heads/master
  $ hg phase -r 'all() - master' > $TESTTMP/after
  $ diff $TESTTMP/before $TESTTMP/after | tr '<>' '-+'
NB: we'd expect this to be published
  $ hg phase -r master
  5: draft
