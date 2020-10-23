Load commonly used test logic
  $ . "$TESTDIR/testutil"

  $ git init gitrepo
  Initialized empty Git repository in $TESTTMP/gitrepo/.git/
  $ cd gitrepo
  $ git config receive.denyCurrentBranch ignore
  $ echo alpha > alpha
  $ git add alpha
  $ fn_git_commit -m 'add alpha'
  $ fn_git_tag alpha

  $ echo beta > beta
  $ git add beta
  $ fn_git_commit -m 'add beta'
  $ fn_git_tag -a -m 'added tag beta' beta

  $ cd ..
  $ hg clone gitrepo hgrepo | grep -v '^updating'
  importing git objects into hg
  2 files updated, 0 files merged, 0 files removed, 0 files unresolved

  $ cd hgrepo
  $ hg log --graph
  @  changeset:   1:5403d6137622
  |  bookmark:    master
  |  tag:         beta
  |  tag:         default/master
  |  tag:         tip
  |  user:        test <test@example.org>
  |  date:        Mon Jan 01 00:00:12 2007 +0000
  |  summary:     add beta
  |
  o  changeset:   0:ff7a2f2d8d70
     tag:         alpha
     user:        test <test@example.org>
     date:        Mon Jan 01 00:00:10 2007 +0000
     summary:     add alpha
  
  $ echo beta-fix >> beta
  $ hg commit -m 'fix for beta'
  $ hg push
  pushing to $TESTTMP/gitrepo
  searching for changes
  adding objects
  added 1 commits with 1 trees and 1 blobs
  updating reference refs/heads/master

Verify that amending commits known to remotes doesn't break anything

  $ cat >> .hg/hgrc << EOF
  > [experimental]
  > evolution = createmarkers
  > evolution.createmarkers = yes
  > EOF
  $ hg tags
  tip                                2:cb3879a0347e
  default/master                     2:cb3879a0347e
  beta                               1:5403d6137622
  alpha                              0:ff7a2f2d8d70
  $ echo beta-fix-again >> beta
  $ hg commit --amend
NB: rev is inconsistent, as older hg uses an intermetadiate commit
  $ hg log -T '{rev}:{node|short} {tags}{if(obsolete, " X")}\n'
  [34]:d4e231d3f8e3 tip (re)
  2:cb3879a0347e default/master X
  1:5403d6137622 beta
  0:ff7a2f2d8d70 alpha
  $ hg tags
  tip                                [34]:d4e231d3f8e3 (re)
  default/master                     2:cb3879a0347e
  beta                               1:5403d6137622
  alpha                              0:ff7a2f2d8d70
  $ hg push
  pushing to $TESTTMP/gitrepo
  searching for changes
  abort: pushing refs/heads/master overwrites d4e231d3f8e3
  [255]
  $ hg push -f
  pushing to $TESTTMP/gitrepo
  searching for changes
  adding objects
  added 1 commits with 1 trees and 1 blobs
  updating reference refs/heads/master

Now create a tag for the old, obsolete master

  $ cd ../gitrepo
  $ git tag detached $(hg log -R ../hgrepo --hidden -r 2 -T '{gitnode}\n')
  $ cd ../hgrepo
  $ hg pull
  pulling from $TESTTMP/gitrepo
  no changes found
  $ hg log -T '{rev}:{node|short} {tags}{if(obsolete, " X")}\n'
  [34]:d4e231d3f8e3 default/master tip (re)
  2:cb3879a0347e detached X
  1:5403d6137622 beta
  0:ff7a2f2d8d70 alpha
  $ hg tags
  tip                                [34]:d4e231d3f8e3 (re)
  default/master                     [34]:d4e231d3f8e3 (re)
  detached                           2:cb3879a0347e
  beta                               1:5403d6137622
  alpha                              0:ff7a2f2d8d70
  $ hg push
  pushing to $TESTTMP/gitrepo
  searching for changes
  no changes found
  [1]

  $ cd ..
