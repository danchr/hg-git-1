Load commonly used test logic
  $ . "$TESTDIR/testutil"

  $ cat >> $HGRCPATH <<EOF
  > [hggit]
  > usephases = yes
  > EOF

  $ git init -q --bare repo.git

  $ hg clone repo.git hgrepo
  updating to branch default
  0 files updated, 0 files merged, 0 files removed, 0 files unresolved

  $ cd hgrepo

Create two commits, one secret:

  $ touch alpha
  $ hg add alpha
  $ fn_hg_commit -m alpha
  $ hg book -r . master
  $ touch beta
  $ hg add beta
  $ fn_hg_commit --secret -m beta
  $ hg book -r . secret
  $ hg push
  pushing to $TESTTMP/repo.git
  warning: not exporting secret bookmark 'secret'
  searching for changes
  adding objects
  remote: found 0 deltas to reuse (dulwich0210 !)
  added 1 commits with 1 trees and 1 blobs
  adding reference refs/heads/master
  $ cd ..
  $ hg -R hgrepo log --graph --template phases
  @  changeset:   1:62966756ea96
  |  bookmark:    secret
  |  tag:         tip
  |  phase:       secret
  |  user:        test
  |  date:        Mon Jan 01 00:00:11 2007 +0000
  |  summary:     beta
  |
  o  changeset:   0:d4b83afc35d1
     bookmark:    master
     tag:         default/master
     phase:       public
     user:        test
     date:        Mon Jan 01 00:00:10 2007 +0000
     summary:     alpha
  

What happens when we push the secret?

  $ hg -R hgrepo push -B secret
  pushing to $TESTTMP/repo.git
  warning: not exporting secret bookmark 'secret'
  searching for changes
  abort: revision 62966756ea96 cannot be pushed since it doesn't have a bookmark
  [255]

Only one changeset was pushed:

  $ GIT_DIR=repo.git git log --graph --all --decorate=short
  * commit 2cc4e3d19551e459a0dd606f4cf890de571c7d33 (HEAD -> master)
    Author: test <none@none>
    Date:   Mon Jan 1 00:00:10 2007 +0000
    
        alpha

And this published the remote head:

  $ hg -R hgrepo phase 'all()'
  0: public
  1: secret
