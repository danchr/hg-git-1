Load commonly used test logic
  $ . "$TESTDIR/testutil"

  $ cat >> $HGRCPATH <<EOF
  > [hggit]
  > usephases = yes
  > EOF

  $ git init --bare repo.git
  Initialized empty Git repository in $TESTTMP/repo.git/

  $ hg clone repo.git hgrepo
  updating to branch default
  0 files updated, 0 files merged, 0 files removed, 0 files unresolved

  $ cd hgrepo

Create two commits, one secret:

  $ touch alpha
  $ hg add alpha
  $ fn_hg_commit -m alpha
  $ touch beta
  $ hg add beta
  $ fn_hg_commit --secret -m beta
  $ hg push
  pushing to $TESTTMP/repo.git
  searching for changes
  adding objects
  added 1 commits with 1 trees and 1 blobs
  adding reference refs/heads/master
  $ cd ..
  $ hg -R hgrepo log --graph --template phases
  @  changeset:   1:62966756ea96
  |  tag:         tip
  |  phase:       secret
  |  user:        test
  |  date:        Mon Jan 01 00:00:11 2007 +0000
  |  summary:     beta
  |
  o  changeset:   0:d4b83afc35d1
     bookmark:    master
     tag:         default/master
     phase:       draft
     user:        test
     date:        Mon Jan 01 00:00:10 2007 +0000
     summary:     alpha
  

Only one changeset was pushed:

  $ GIT_DIR=repo.git git log --graph --all --decorate=short
  * commit 2cc4e3d19551e459a0dd606f4cf890de571c7d33 (HEAD -> master)
    Author: test <none@none>
    Date:   Mon Jan 1 00:00:10 2007 +0000
    
        alpha

  $ cd hgrepo
  $ hg phase 'all()'
  0: draft
  1: secret
  $ hg pull
  pulling from $TESTTMP/repo.git
  no changes found
  $ hg phase 'all()'
  0: public
  1: secret
  $ cd ..
