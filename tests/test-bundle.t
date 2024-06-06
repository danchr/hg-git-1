 Load commonly used test logic
  $ . "$TESTDIR/testutil"

Enable bundling, and add a nice template for inspecting Git state.

  $ cat >> $HGRCPATH <<EOF
  > [experimental]
  > hg-git-bundle = yes
  > [templates]
  > git = {rev}:{node|short} | {gitnode|short} | {tags} |\n
  > EOF

Create a Git repository containing a couple of commits and two non-tip
tags:

  $ git init gitrepo
  Initialized empty Git repository in $TESTTMP/gitrepo/.git/
  $ cd gitrepo
  $ echo alpha > alpha
  $ git add alpha
  $ fn_git_commit -m 'add alpha'
  $ git tag thetag
  $ echo beta > beta
  $ git add beta
  $ fn_git_commit -m 'add beta'
  $ git tag -m 'an annotated tag' theothertag
  $ echo gamma > gamma
  $ git add gamma
  $ git add .
  $ fn_git_commit -m 'add gamma'
  $ git tag -ln
  theothertag     an annotated tag
  thetag          add alpha
  $ cd ..

Clone it!

  $ hg clone gitrepo hgrepo
  importing 3 git commits
  new changesets ff7a2f2d8d70:ca33a262eb46 (3 drafts)
  updating to bookmark master
  3 files updated, 0 files merged, 0 files removed, 0 files unresolved
  $ cd hgrepo

Create a bundle with our metadata, and inspect it:

  $ hg bundle --all ../bundle-w-git.hg
  3 changesets found
  $ hg debugbundle --all ../bundle-w-git.hg | grep hg-git
  exp-hg-git-map -- {} (mandatory: False)
  exp-hg-git-tags -- {} (mandatory: False)
  $ hg debugbundle --all ../bundle-w-git.hg > bundle-w-git.out

Create a bundle without our metadata, and inspect it:

  $ hg bundle --all ../bundle-wo-git.hg --config experimental.hg-git-bundle=no
  3 changesets found
  $ hg debugbundle --all ../bundle-wo-git.hg | grep hg-git
  [1]

Verify that those are different:

  $ hg debugbundle --all ../bundle-wo-git.hg > bundle-wo-git.out
  $ cmp -s bundle-w-git.out bundle-wo-git.out
  [1]

Now create a bundle without hg-git enabled at all, which should be
exactly similar to what you get when you disable metadata embedding;
this verifies we don't accidentally pollute bundles.

  $ hg bundle --all  --config extensions.hggit=! ../bundle-wo-hggit.hg
  3 changesets found
  $ hg debugbundle --all ../bundle-wo-hggit.hg > bundle-wo-hggit.out
  $ cmp -s bundle-wo-git.hg bundle-wo-hggit.hg
  [2]
  $ cmp -s bundle-wo-git.out bundle-wo-hggit.out
  $ cd ..
  $ rm -r hgrepo

Does unbundling transfer state?

  $ hg init hgrepo
  $ hg -R hgrepo unbundle bundle-w-git.hg
  adding changesets
  adding manifests
  adding file changes
  added 3 changesets with 3 changes to 3 files
  new changesets * (glob)
  (run 'hg update' to get a working copy)
  $ hg -R hgrepo log -T git
  2:ca33a262eb46 | d338971a96e2 | tip |
  1:7fe02317c63d | 9497a4ee62e1 | theothertag |
  0:ff7a2f2d8d70 | 7eeab2ea75ec | thetag |
  $ hg -R hgrepo pull gitrepo
  pulling from gitrepo
  warning: created new git repository at $TESTTMP/hgrepo/.hg/git
  no changes found
  adding bookmark master
  $ rm -r hgrepo

Can we unbundle something without git state?

  $ hg init hgrepo
  $ hg -R hgrepo unbundle bundle-wo-git.hg
  adding changesets
  adding manifests
  adding file changes
  added 3 changesets with 3 changes to 3 files
  new changesets * (glob)
  (run 'hg update' to get a working copy)
  $ hg -R hgrepo log -T git
  2:ca33a262eb46 |  | tip |
  1:7fe02317c63d |  |  |
  0:ff7a2f2d8d70 |  |  |
  $ hg -R hgrepo pull gitrepo
  pulling from gitrepo
  importing 3 git commits
  adding bookmark master
  (run 'hg update' to get a working copy)
  $ rm -r hgrepo

Regular mercurial shouldn't choke on our bundle

  $ hg init hgrepo
  $ cat >> hgrepo/.hg/hgrc <<EOF
  > [extensions]
  > hggit = !
  > EOF
  $ hg -R hgrepo unbundle bundle-wo-git.hg
  adding changesets
  adding manifests
  adding file changes
  added 3 changesets with 3 changes to 3 files
  new changesets * (glob)
  (run 'hg update' to get a working copy)
  $ hg -R hgrepo log -T git
  2:ca33a262eb46 |  | tip |
  1:7fe02317c63d |  |  |
  0:ff7a2f2d8d70 |  |  |
  $ hg -R hgrepo pull gitrepo
  pulling from gitrepo
  abort: repository gitrepo not found!? (re)
  [255]
  $ rm -r hgrepo


What happens if we unbundle twice?

  $ hg init hgrepo
  $ hg -R hgrepo unbundle bundle-w-git.hg
  adding changesets
  adding manifests
  adding file changes
  added 3 changesets with 3 changes to 3 files
  new changesets * (glob)
  (run 'hg update' to get a working copy)
  $ hg -R hgrepo unbundle bundle-w-git.hg
  adding changesets
  adding manifests
  adding file changes
  added 0 changesets with 0 changes to 3 files
  (run 'hg update' to get a working copy)
  $ hg -R hgrepo log -T git
  2:ca33a262eb46 | d338971a96e2 | tip |
  1:7fe02317c63d | 9497a4ee62e1 | theothertag |
  0:ff7a2f2d8d70 | 7eeab2ea75ec | thetag |
  $ hg -R hgrepo pull gitrepo
  pulling from gitrepo
  warning: created new git repository at $TESTTMP/hgrepo/.hg/git
  no changes found
  adding bookmark master
  $ rm -r hgrepo

Alas, cloning a bundle doesn't work yet:

(Mercurial is apparently quite dumb here, so we won't try to fix this
for now, but this test mostly exists so that we notice if ever starts
working, or breaks entirely.)

  $ hg clone bundle-w-git.hg hgrepo
  requesting all changes
  adding changesets
  adding manifests
  adding file changes
  added 3 changesets with 3 changes to 3 files
  new changesets * (glob)
  updating to branch default
  3 files updated, 0 files merged, 0 files removed, 0 files unresolved
  $ hg -R hgrepo log -T git
  2:ca33a262eb46 |  | tip |
  1:7fe02317c63d |  |  |
  0:ff7a2f2d8d70 |  |  |
  $ rm -r hgrepo

Now, lets try to be a bit evil. How does pulling partial state work?

First, more git happenings:

  $ cd gitrepo
  $ git checkout -b otherbranch thetag
  Switched to a new branch 'otherbranch'
  $ echo 42 > baz
  $ git add baz
  $ fn_git_commit -m 3
  $ cd ..

Pull, 'em, and create a partial bundle:

  $ hg clone gitrepo hgrepo
  importing 4 git commits
  new changesets ff7a2f2d8d70:d87bf3ef6a53 (4 drafts)
  updating to bookmark otherbranch
  2 files updated, 0 files merged, 0 files removed, 0 files unresolved
  $ hg -R hgrepo bundle --base 'p1(tip)' -r tip bundle-w-git-2.hg
  1 changesets found
  $ rm -r hgrepo

Now, load only that bundle into a repository without any git state

  $ hg clone -r 1 bundle-w-git.hg hgrepo --config extensions.hggit=!
  adding changesets
  adding manifests
  adding file changes
  added 2 changesets with 2 changes to 2 files
  new changesets * (glob)
  updating to branch default
  2 files updated, 0 files merged, 0 files removed, 0 files unresolved
  $ cd hgrepo
  $ hg unbundle ../bundle-w-git-2.hg
  adding changesets
  adding manifests
  adding file changes
  added 1 changesets with 1 changes to 1 files (+1 heads)
  new changesets * (glob)
  (run 'hg heads' to see heads, 'hg merge' to merge)
  $ hg pull ../gitrepo
  pulling from ../gitrepo
  warning: created new git repository at $TESTTMP/hgrepo/.hg/git
  importing 3 git commits
  adding bookmark master
  adding bookmark otherbranch
  new changesets ca33a262eb46 (1 drafts)
  (run 'hg update' to get a working copy)
  $ cd ..
  $ rm -r hgrepo

Now, try pushing with only the metadata:

  $ hg init hgrepo
  $ cd hgrepo
  $ hg unbundle -u ../bundle-w-git.hg
  adding changesets
  adding manifests
  adding file changes
  added 3 changesets with 3 changes to 3 files
  new changesets * (glob)
  3 files updated, 0 files merged, 0 files removed, 0 files unresolved
  $ echo kaflaflibob > bajizmo
  $ fn_hg_commit -A -m 4
  $ hg book -r tip master
  $ hg push ../gitrepo
  pushing to ../gitrepo
  warning: created new git repository at $TESTTMP/hgrepo/.hg/git
  abort: cannot push git commit d338971a96e2 as it is not present locally
  (please try pulling first, or as a fallback run git-cleanup to re-export the missing commits)
  [255]

Try to repopulate the git state from a bundle

  $ hg debug-remove-hggit-state
  clearing out the git cache data
  $ hg log -qr 'fromgit()'
  $ hg unbundle -u ../bundle-w-git.hg
  adding changesets
  adding manifests
  adding file changes
  added 0 changesets with 0 changes to 3 files
  0 files updated, 0 files merged, 0 files removed, 0 files unresolved
  $ hg log -qr 'fromgit()'
  0:ff7a2f2d8d70
  1:7fe02317c63d
  2:ca33a262eb46
