Load commonly used test logic
  $ . "$TESTDIR/testutil"

  $ git init gitrepo
  Initialized empty Git repository in $TESTTMP/gitrepo/.git/
  $ cd gitrepo
  $ echo alpha > alpha
  $ git add alpha
  $ fn_git_commit -m "add alpha"
  $ git checkout -b not-master 2>&1 | sed s/\'/\"/g
  Switched to a new branch "not-master"

  $ cd ..
  $ hg clone -u tip gitrepo hgrepo
  importing 1 git commits
  new changesets ff7a2f2d8d70 (1 drafts)
  updating to branch default
  1 files updated, 0 files merged, 0 files removed, 0 files unresolved

  $ cd hgrepo
  $ hg bookmark -q master
  $ echo beta > beta
  $ hg add beta
  $ fn_hg_commit -m 'add beta'


  $ echo gamma > gamma
  $ hg add gamma
  $ fn_hg_commit -m 'add gamma'

  $ hg book -r 1 beta
  $ hg push -r beta
  pushing to $TESTTMP/gitrepo
  searching for changes
  adding objects
  remote: found 0 deltas to reuse (dulwich0210 !)
  added 1 commits with 1 trees and 1 blobs
  adding reference refs/heads/beta

  $ cd ..

should have two different branches
  $ cd gitrepo
  $ git branch -v
    beta       0f378ab add beta
    master     7eeab2e add alpha
  * not-master 7eeab2e add alpha

some more work on master from git
  $ git checkout master 2>&1 | sed s/\'/\"/g
  Switched to branch "master"
  $ echo delta > delta
  $ git add delta
  $ fn_git_commit -m "add delta"
  $ git checkout not-master 2>&1 | sed s/\'/\"/g
  Switched to branch "not-master"

  $ cd ..

  $ cd hgrepo
this should fail
  $ hg push -r master
  pushing to $TESTTMP/gitrepo
  searching for changes
  abort: branch 'refs/heads/master' changed on the server, please pull and merge before pushing
  [255]

... even with -f
  $ hg push -fr master
  pushing to $TESTTMP/gitrepo
  searching for changes
  abort: branch 'refs/heads/master' changed on the server, please pull and merge before pushing
  [255]

  $ hg pull 2>&1 | grep -v 'divergent bookmark'
  pulling from $TESTTMP/gitrepo
  importing 1 git commits
  not updating diverged bookmark master
  new changesets 25eed24f5e8f (1 drafts)
  (run 'hg heads' to see heads, 'hg merge' to merge)
TODO shouldn't need to do this since we're (in theory) pushing master explicitly,
which should not implicitly also push the not-master ref.
  $ hg book not-master -r default/not-master --force
master and default/master should be diferent
  $ hg log -r master
  changeset:   2:953796e1cfd8
  bookmark:    master
  user:        test
  date:        Mon Jan 01 00:00:12 2007 +0000
  summary:     add gamma
  
  $ hg log -r default/master
  changeset:   3:25eed24f5e8f
  tag:         default/master
  tag:         tip
  parent:      0:ff7a2f2d8d70
  user:        test <test@example.org>
  date:        Mon Jan 01 00:00:13 2007 +0000
  summary:     add delta
  

this should also fail
  $ hg push -r master
  pushing to $TESTTMP/gitrepo
  searching for changes
  abort: pushing refs/heads/master overwrites 953796e1cfd8
  [255]

... but succeed with -f
  $ hg push -fr master
  pushing to $TESTTMP/gitrepo
  searching for changes
  adding objects
  remote: found 0 deltas to reuse (dulwich0210 !)
  added 1 commits with 1 trees and 1 blobs
  updating reference refs/heads/master

this should fail, no changes to push
  $ hg push -r master
  pushing to $TESTTMP/gitrepo
  searching for changes
  no changes found
  [1]

hg-git issue103 -- directories can lose information at hg-git export time

  $ hg up master
  0 files updated, 0 files merged, 0 files removed, 0 files unresolved
  $ mkdir dir1
  $ echo alpha > dir1/alpha
  $ hg add dir1/alpha
  $ fn_hg_commit -m 'add dir1/alpha'
  $ hg push -r master
  pushing to $TESTTMP/gitrepo
  searching for changes
  adding objects
  remote: found 0 deltas to reuse (dulwich0210 !)
  added 1 commits with 2 trees and 0 blobs
  updating reference refs/heads/master

  $ echo beta > dir1/beta
  $ hg add dir1/beta
  $ fn_hg_commit -m 'add dir1/beta'
  $ hg push -r master
  pushing to $TESTTMP/gitrepo
  searching for changes
  adding objects
  remote: found 0 deltas to reuse (dulwich0210 !)
  added 1 commits with 2 trees and 0 blobs
  updating reference refs/heads/master
  $ hg log -r master
  changeset:   5:ba0476ff1899
  bookmark:    master
  tag:         default/master
  tag:         tip
  user:        test
  date:        Mon Jan 01 00:00:15 2007 +0000
  summary:     add dir1/beta
  

  $ cat >> .hg/hgrc << EOF
  > [paths]
  > default:pushurl = file:///$TESTTMP/gitrepo
  > EOF
NB: the triple slashes are intentional, due to windows
  $ hg push -r master
  pushing to file:///$TESTTMP/gitrepo
  searching for changes
  no changes found
  [1]

  $ cd ..

  $ hg clone -u tip gitrepo hgrepo-test
  importing 5 git commits
  new changesets ff7a2f2d8d70:ba0476ff1899 (5 drafts)
  updating to branch default
  5 files updated, 0 files merged, 0 files removed, 0 files unresolved
  $ hg -R hgrepo-test log -r master
  changeset:   4:ba0476ff1899
  bookmark:    master
  tag:         default/master
  tag:         tip
  user:        test
  date:        Mon Jan 01 00:00:15 2007 +0000
  summary:     add dir1/beta
  
  $ hg tags -R hgrepo-test | grep ^default/
  default/master                     4:ba0476ff1899
  default/beta                       1:47580592d3d6
  default/not-master                 0:ff7a2f2d8d70

Push a fast-forward to a currently checked out branch, which sometimes
fails:

  $ cd hgrepo
  $ hg book -r master not-master
  moving bookmark 'not-master' forward from ff7a2f2d8d70
  $ hg push
  pushing to file:///$TESTTMP/gitrepo
  searching for changes
  warning: failed to update HEAD; unable to set b'HEAD' to b'7eeab2ea75ec1ac0ff3d500b5b6f8a3447dd7c03' (?)
  updating reference refs/heads/not-master
That should have updated the tag:
  $ hg tags | grep ^default/
  default/not-master                 5:ba0476ff1899
  default/master                     5:ba0476ff1899
  default/beta                       1:47580592d3d6
  $ cd ..

We can push only one of two bookmarks on the same revision:

  $ cd hgrepo
  $ hg book -r 0 also-not-master really-not-master
  $ hg push -B also-not-master
  pushing to file:///$TESTTMP/gitrepo
  searching for changes
  adding reference refs/heads/also-not-master

We can also push another bookmark to a path with another revision
specified:

  $ hg book -r 3 also-not-master
  moving bookmark 'also-not-master' forward from ff7a2f2d8d70
  $ hg push -B also-not-master "file:///$TESTTMP/gitrepo#master"
  pushing to file:///$TESTTMP/gitrepo
  searching for changes
  adding objects
  remote: found 0 deltas to reuse (dulwich0210 !)
  added 1 commits with 1 trees and 1 blobs
  updating reference refs/heads/also-not-master

And we can delete them again afterwards:

  $ hg book -d also-not-master really-not-master
  $ hg push -B also-not-master -B really-not-master
  pushing to file:///$TESTTMP/gitrepo
  searching for changes
  warning: unable to delete 'refs/heads/really-not-master' as it does not exist on the remote repository
  deleting reference refs/heads/also-not-master

Push empty Hg repo to empty Git repo (issue #58)
  $ hg init hgrepo2
  $ git init -q --bare repo.git
  $ hg -R hgrepo2 push repo.git
  pushing to repo.git
  searching for changes
  abort: no bookmarks or tags to push to git
  (see "hg help bookmarks" for details on creating them)
  [255]

The remote repo is empty and the local one doesn't have any bookmarks/tags
  $ cd hgrepo2
  $ echo init >> test.txt
  $ hg addremove
  adding test.txt
  $ fn_hg_commit -m init
  $ hg update null
  0 files updated, 0 files merged, 1 files removed, 0 files unresolved
  $ hg push ../repo.git
  pushing to ../repo.git
  searching for changes
  abort: no bookmarks or tags to push to git
  (see "hg help bookmarks" for details on creating them)
  [255]
  $ hg summary
  parent: -1:000000000000  (no revision checked out)
  branch: default
  commit: (clean)
  update: 1 new changesets (update)
  phases: 1 draft
That should not create any bookmarks
  $ hg bookmarks
  no bookmarks set
And no tags for the remotes either:
  $ hg tags
  tip                                0:8aded40be5af

test for ssh vulnerability

  $ cat >> $HGRCPATH << EOF
  > [ui]
  > ssh = ssh -o ConnectTimeout=1
  > EOF
  $ hg push -q 'git+ssh://-oProxyCommand=rm${IFS}nonexistent/path'
  abort: potentially unsafe hostname: '-oProxyCommand=rm${IFS}nonexistent'
  [255]
  $ hg push -q 'git+ssh://-oProxyCommand=rm%20nonexistent/path'
  abort: potentially unsafe hostname: '-oProxyCommand=rm nonexistent'
  [255]
  $ hg push -q 'git+ssh://fakehost|rm%20nonexistent/path'
  ssh: * fakehost%7?rm%20nonexistent* (glob)
  abort: git remote error: The remote server unexpectedly closed the connection.
  [255]
  $ hg push -q 'git+ssh://fakehost%7Crm%20nonexistent/path'
  ssh: * fakehost%7?rm%20nonexistent* (glob)
  abort: git remote error: The remote server unexpectedly closed the connection.
  [255]
