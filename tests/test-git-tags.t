#testcases secret draft

Load commonly used test logic
  $ . "$TESTDIR/testutil"

  $ cat >> $HGRCPATH <<EOF
  > [templates]
  > shorttags = '{rev}:{node|short} {phase} {tags}{if(obsolete, " X")}\n'
  > EOF

#if secret
The phases setting should not affect hg-git
  $ cat >> $HGRCPATH <<EOF
  > [phases]
  > new-commit = secret
  > EOF
#endif

Create a bare upstream repository

  $ git init --bare repo.git
  Initialized empty Git repository in $TESTTMP/repo.git/

Create a couple of commits from Git

  $ git init gitrepo
  Initialized empty Git repository in $TESTTMP/gitrepo/.git/
  $ cd gitrepo
  $ echo alpha > alpha
  $ git add alpha
  $ fn_git_commit -m 'add alpha'
  $ echo beta > beta
  $ git add beta
  $ fn_git_commit -m 'add beta'
  $ fn_git_tag -a -m 'added tag beta' beta
  $ git remote add origin $TESTTMP/repo.git
  $ git push --quiet --tags --set-upstream origin master
  Branch 'master' set up to track remote branch 'master' from 'origin'. (?)
  $ cd ..

Clone it:

  $ hg clone repo.git hgrepo
  importing 2 git commits
  new changesets ff7a2f2d8d70:7fe02317c63d (2 drafts)
  updating to bookmark master
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
  [10]
  $ hg tag --git alpha
  abort: git tags require an explicit revision
  (please specify -r/--rev)
  [255]
  $ hg tag --git alpha alpha -r 0
  abort: tag names must be unique
  [255]
  $ hg tag --git alpha -r 0 -e
  abort: cannot specify both --git and --edit
  [10]
  $ hg tag --git alpha -r 0 -m 42
  abort: cannot specify both --git and --message
  [10]
  $ hg tag --git alpha -r 0 -d 42
  abort: cannot specify both --git and --date
  [10]
  $ hg tag --git alpha -r 0 -u user@example.com
  abort: cannot specify both --git and --user
  [10]
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
  [10]

Create a git tag from hg

  $ hg tag --git alpha --debug -r 0
  adding git tag alpha
  finding unexported changesets
  saving git map to $TESTTMP/hgrepo/.hg/git-mapfile
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
  $ fn_hg_commit -m 'fix for beta'
#if secret
  $ hg phase -d
#endif
  $ hg push
  pushing to $TESTTMP/repo.git
  searching for changes
  adding objects
  remote: found 0 deltas to reuse (dulwich0210 !)
  added 1 commits with 1 trees and 1 blobs
  updating reference refs/heads/master
  adding reference refs/tags/alpha

Verify that amending commits known to remotes doesn't break anything

  $ cat >> $HGRCPATH << EOF
  > [experimental]
  > evolution = createmarkers
  > evolution.createmarkers = yes
  > EOF
  $ hg tags
  tip                                2:61175962e488
  default/master                     2:61175962e488
  beta                               1:7fe02317c63d
  alpha                              0:ff7a2f2d8d70
  $ echo beta-fix-again >> beta
  $ fn_hg_commit --amend
  $ hg log -T shorttags
  3:3094b9e8da41 draft tip
  2:61175962e488 draft default/master X
  1:7fe02317c63d draft beta
  0:ff7a2f2d8d70 draft alpha
  $ hg tags
  tip                                3:3094b9e8da41
  default/master                     2:61175962e488
  beta                               1:7fe02317c63d
  alpha                              0:ff7a2f2d8d70
  $ hg push
  pushing to $TESTTMP/repo.git
  searching for changes
  abort: pushing refs/heads/master overwrites 3094b9e8da41
  [255]
  $ hg push -f
  pushing to $TESTTMP/repo.git
  searching for changes
  adding objects
  remote: found 0 deltas to reuse (dulwich0210 !)
  added 1 commits with 1 trees and 1 blobs
  updating reference refs/heads/master

Now create a tag for the old, obsolete master

  $ cd ../repo.git
  $ git tag detached $(hg log -R ../hgrepo --hidden -r 2 -T '{gitnode}\n')
  $ git tag
  alpha
  beta
  detached
  $ cd ../hgrepo
  $ hg pull
  pulling from $TESTTMP/repo.git
  no changes found
  $ hg log -T shorttags
  3:3094b9e8da41 draft default/master tip
  2:61175962e488 draft detached X
  1:7fe02317c63d draft beta
  0:ff7a2f2d8d70 draft alpha
  $ hg tags
  tip                                3:3094b9e8da41
  default/master                     3:3094b9e8da41
  detached                           2:61175962e488
  beta                               1:7fe02317c63d
  alpha                              0:ff7a2f2d8d70
  $ hg push
  pushing to $TESTTMP/repo.git
  searching for changes
  no changes found
  [1]

  $ cd ..

Verify that revsets can point out git tags; for that we need an
untagged commit.

  $ cd hgrepo
  $ touch gamma
  $ fn_hg_commit -A -m 'add gamma'
#if secret
  $ hg phase -d
#endif
  $ hg log -T shorttags -r 'gittag()'
  0:ff7a2f2d8d70 draft alpha
  1:7fe02317c63d draft beta
  2:61175962e488 draft detached X
  $ hg log -T shorttags -r 'gittag(detached)'
  2:61175962e488 draft detached X
  $ hg log -T shorttags -r 'gittag("re:a$")'
  0:ff7a2f2d8d70 draft alpha
  1:7fe02317c63d draft beta

Create a git tag from hg, but pointing to a new commit:

  $ hg tag --git gamma --debug -r tip
  invalid branch cache (visible): tip differs (?)
  adding git tag gamma
  finding unexported changesets
  exporting 1 changesets
  converting revision 0eb1ab0073a885a498d4ae3dc5cf0c26e750fa3d
  saving git map to $TESTTMP/hgrepo/.hg/git-mapfile
  $ hg push
  pushing to $TESTTMP/repo.git
  searching for changes
  adding objects
  remote: found 0 deltas to reuse (dulwich0210 !)
  added 1 commits with 1 trees and 1 blobs
  updating reference refs/heads/master
  adding reference refs/tags/gamma
  $ cd ../gitrepo
  $ git fetch --quiet --tags
  $ git tag
  alpha
  beta
  detached
  gamma
  $ cd ..

Try to overwrite an annotated tag:

  $ cd hgrepo
  $ hg tags -v
  tip                                4:0eb1ab0073a8
  gamma                              4:0eb1ab0073a8 git
  default/master                     4:0eb1ab0073a8 git-remote
  detached                           2:61175962e488 git
  beta                               1:7fe02317c63d git
  alpha                              0:ff7a2f2d8d70 git
  $ hg book not-master
  $ hg tag beta
  abort: tag 'beta' already exists (use -f to force)
  [10]
  $ hg tag -f beta
#if secret
  $ hg phase -d
#endif
  $ hg push
  pushing to $TESTTMP/repo.git
  warning: not overwriting annotated tag 'beta'
  searching for changes
  adding objects
  remote: found 0 deltas to reuse (dulwich0210 !)
  added 1 commits with 1 trees and 1 blobs
  adding reference refs/heads/not-master
  $ hg tags
  tip                                5:c49682c7cba4
  default/not-master                 5:c49682c7cba4
  gamma                              4:0eb1ab0073a8
  default/master                     4:0eb1ab0073a8
  beta                               4:0eb1ab0073a8
  detached                           2:61175962e488
  alpha                              0:ff7a2f2d8d70
  $ cd ..

Check whether `gimport` handles tags

  $ cd hgrepo
  $ rm .hg/git-tags .hg/git-mapfile
  $ hg gimport
  importing 6 git commits
  $ hg tags -q
  tip
  default/not-master
  gamma
  default/master
  beta
  detached
  alpha
  $ cd ..

Test how pulling an explicit branch with an annotated tag:

  $ hg clone -r master repo.git hgrepo-2
  importing 4 git commits
  new changesets ff7a2f2d8d70:0eb1ab0073a8 (4 drafts)
  updating to branch default
  3 files updated, 0 files merged, 0 files removed, 0 files unresolved
  $ hg log -r 'ancestors(master) and tagged()' -T shorttags -R hgrepo-2
  0:ff7a2f2d8d70 draft alpha
  3:0eb1ab0073a8 draft default/master gamma tip
  $ rm -rf hgrepo-2

  $ hg clone -r master repo.git hgrepo-2
  importing 4 git commits
  new changesets ff7a2f2d8d70:0eb1ab0073a8 (4 drafts)
  updating to branch default
  3 files updated, 0 files merged, 0 files removed, 0 files unresolved
  $ hg log -r 'tagged()' -T shorttags -R hgrepo-2
  0:ff7a2f2d8d70 draft alpha
  3:0eb1ab0073a8 draft default/master gamma tip
This used to die:
  $ hg -R hgrepo-2 gexport
This used to fail, since we didn't actually pull the annotated tag:
  $ hg -R hgrepo-2 push
  pushing to $TESTTMP/repo.git
  searching for changes
  no changes found
  [1]
  $ rm -rf hgrepo-2

Check that pulling will update phases only:

  $ cd hgrepo
  $ hg phase -fs gamma detached
  $ hg pull
  pulling from $TESTTMP/repo.git
  no changes found
  $ hg log -T shorttags -r gamma -r detached
  4:0eb1ab0073a8 draft beta default/master gamma
  2:61175962e488 draft detached X
  $ cd ..
