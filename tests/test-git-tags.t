Load commonly used test logic
  $ . "$TESTDIR/testutil"

  $ git init gitrepo
  Initialized empty Git repository in $TESTTMP/gitrepo/.git/
  $ cd gitrepo
  $ git config receive.denyCurrentBranch ignore
  $ echo alpha > alpha
  $ git add alpha
  $ fn_git_commit -m 'add alpha'

  $ echo beta > beta
  $ git add beta
  $ fn_git_commit -m 'add beta'
  $ fn_git_tag -a -m 'added tag beta' beta

  $ cd ..
  $ hg clone gitrepo hgrepo
  importing git objects into hg
  updating to bookmark master (hg57 !)
  updating to branch default (no-hg57 !)
  2 files updated, 0 files merged, 0 files removed, 0 files unresolved

  $ cd hgrepo

Verify that annotated tags are unaffected by reexports:

  $ GIT_DIR=.hg/git git tag -ln
  beta            added tag beta
  $ hg gexport
  $ GIT_DIR=.hg/git git tag -ln
  beta            added tag beta

Error checking on tag creation

  $ hg tag --git beta --remove
  abort: cannot remove git tags
  (the git documentation heavily discourages editing tags)
  [255]
  $ hg tag --git beta -r null
  abort: cannot remove git tags
  (the git documentation heavily discourages editing tags)
  [255]
  $ hg tag --git beta --remove -r 0
  abort: cannot specify both --rev and --remove
  [255]
  $ hg tag --git alpha
  abort: git tags require an explicit revision
  (please specify -r/--rev)
  [255]
  $ hg tag --git alpha alpha -r 0
  abort: tag names must be unique
  [255]
  $ hg tag --git alpha -r 0 -e
  abort: cannot specify both --git and --edit
  [255]
  $ hg tag --git alpha -r 0 -m 42
  abort: cannot specify both --git and --message
  [255]
  $ hg tag --git alpha -r 0 -d 42
  abort: cannot specify both --git and --date
  [255]
  $ hg tag --git alpha -r 0 -u user@example.com
  abort: cannot specify both --git and --user
  [255]
  $ hg tag --git 'with space' -r 0
  abort: the name 'with space' is not a valid git tag
  [255]
  $ hg tag --git ' beta' -r 0
  abort: the name 'beta' already exists
  [255]
  $ hg tag --git master -r 0
  abort: the name 'master' already exists
  [255]
  $ hg tag --git tip -r 0
  abort: the name 'tip' is reserved
  [255]

Create a git tag from hg

  $ hg tag --git alpha --debug -r 0
  adding git tag alpha
  finding hg commits to export
  $ hg log --graph
  @  changeset:   1:7fe02317c63d
  |  bookmark:    master
  |  tag:         beta
  |  tag:         default/master
  |  tag:         tip
  |  user:        test <test@example.org>
  |  date:        Mon Jan 01 00:00:11 2007 +0000
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
  adding reference refs/tags/alpha

Verify that amending commits known to remotes doesn't break anything

  $ cat >> .hg/hgrc << EOF
  > [experimental]
  > evolution = createmarkers
  > evolution.createmarkers = yes
  > EOF
  $ hg tags
  tip                                2:7aa44ff368c7
  default/master                     2:7aa44ff368c7
  beta                               1:7fe02317c63d
  alpha                              0:ff7a2f2d8d70
  $ echo beta-fix-again >> beta
  $ hg commit --amend
  $ hg log -T '{rev}:{node|short} {tags}{if(obsolete, " X")}\n'
  3:132f4c8814d2 tip
  2:7aa44ff368c7 default/master X
  1:7fe02317c63d beta
  0:ff7a2f2d8d70 alpha
  $ hg tags
  tip                                3:132f4c8814d2
  default/master                     2:7aa44ff368c7
  beta                               1:7fe02317c63d
  alpha                              0:ff7a2f2d8d70
  $ hg push
  pushing to $TESTTMP/gitrepo
  searching for changes
  abort: pushing refs/heads/master overwrites 132f4c8814d2
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
  $ git tag
  alpha
  beta
  detached
  $ cd ../hgrepo
  $ hg pull
  pulling from $TESTTMP/gitrepo
  no changes found
  $ hg log -T '{rev}:{node|short} {tags}{if(obsolete, " X")}\n'
  3:132f4c8814d2 default/master tip
  2:7aa44ff368c7 detached X
  1:7fe02317c63d beta
  0:ff7a2f2d8d70 alpha
  $ hg tags
  tip                                3:132f4c8814d2
  default/master                     3:132f4c8814d2
  detached                           2:7aa44ff368c7
  beta                               1:7fe02317c63d
  alpha                              0:ff7a2f2d8d70
  $ hg push
  pushing to $TESTTMP/gitrepo
  searching for changes
  no changes found
  [1]

  $ cd ..

Create a git tag from hg, but pointing to a new commit:

  $ cd hgrepo
  $ touch gamma
  $ fn_hg_commit -A -m 'add gamma'
  $ hg tag --git gamma --debug -r tip
  adding git tag gamma
  finding hg commits to export
  exporting hg objects to git
  converting revision dfeaa5393d25ea2c143fff73f448bfeab0b90ed6
  $ hg push
  pushing to $TESTTMP/gitrepo
  searching for changes
  adding objects
  added 1 commits with 1 trees and 1 blobs
  updating reference refs/heads/master
  adding reference refs/tags/gamma
  $ cd ../gitrepo
  $ git tag
  alpha
  beta
  detached
  gamma
  $ cd ..

Try to overwrite an annotated tag:

  $ cd hgrepo
#if hg57
  $ hg tags -v
  tip                                4:dfeaa5393d25
  gamma                              4:dfeaa5393d25 git
  default/master                     4:dfeaa5393d25 git-remote
  detached                           2:7aa44ff368c7 git
  beta                               1:7fe02317c63d git
  alpha                              0:ff7a2f2d8d70 git
#endif
  $ hg tag beta
  abort: tag 'beta' already exists (use -f to force)
  [255]
  $ hg tag -f beta
  $ hg push
  pushing to $TESTTMP/gitrepo
  warning: not overwriting annotated tag 'beta'
  searching for changes
  adding objects
  added 1 commits with 1 trees and 1 blobs
  updating reference refs/heads/master
#if hg57
  $ hg tags -v
  tip                                5:97a843c5e338
  default/master                     5:97a843c5e338 git-remote
  gamma                              4:dfeaa5393d25 git
  beta                               4:dfeaa5393d25
  detached                           2:7aa44ff368c7 git
  alpha                              0:ff7a2f2d8d70 git
#endif
