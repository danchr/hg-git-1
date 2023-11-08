Load commonly used test logic
  $ . "$TESTDIR/testutil"

  $ git init gitrepo
  Initialized empty Git repository in $TESTTMP/gitrepo/.git/
  $ cd gitrepo
  $ git config receive.denyCurrentBranch ignore
  $ echo alpha > alpha
  $ git add alpha
  $ fn_git_commit -m "add alpha"
  $ git checkout -q master
  $ echo beta > beta
  $ git add beta
  $ fn_git_commit -m 'add beta'
  $ git checkout -b not-master master~1
  Switched to a new branch 'not-master'
  $ echo gamma > gamma
  $ git add gamma
  $ fn_git_commit -m 'add gamma'
  $ git checkout -qd master~1
  $ echo delta > delta
  $ git add delta
  $ fn_git_commit -m 'add delta'
  $ git tag thetag
  $ git checkout -q master
  $ cd ..

  $ hg clone --config hggit.usephases=True -U gitrepo hgrepo
  importing 4 git commits
  new changesets ff7a2f2d8d70:25eed24f5e8f (1 drafts)

  $ cd hgrepo
  $ hg log -G -T '{rev}|{phase}|{bookmarks}|{tags}\n'
  o  3|public||thetag tip
  |
  | o  2|draft|not-master|default/not-master
  |/
  | o  1|public|master|default/master
  |/
  o  0|public||
  
  $ hg phase -r 'all()' | tee $TESTTMP/after-clone
  0: public
  1: public
  2: draft
  3: public
  $ cat >> .hg/hgrc <<EOF
  > [paths]
  > other = $TESTTMP/gitrepo/.git
  > other:hg-git.publish = no
  > EOF
  $ cd ..

that disables publishing from that remote

  $ cd hgrepo
  $ hg phase -fd 'all()'
  $ hg pull other
  pulling from $TESTTMP/gitrepo/.git
  no changes found
  $ hg log -qr 'public()'
  $ hg pull -v --config hggit.usephases=True other
  pulling from $TESTTMP/gitrepo/.git
  no changes found
  processing commits in batches of 1000
  bookmark master is up-to-date
  bookmark not-master is up-to-date
  $ hg log -qr 'public()'
  $ cd ..

but not default when enable by the global setting

  $ cd hgrepo
  $ hg phase -fd 'all()'
  no phases changed
  $ hg pull -v --config hggit.usephases=True
  pulling from $TESTTMP/gitrepo
  publishing remote HEAD
  publishing tag thetag
  no changes found
  processing commits in batches of 1000
  bookmark master is up-to-date
  bookmark not-master is up-to-date
  publishing remote HEAD
  publishing tag thetag
  3 local changesets published
  $ hg phase -r 'all()' > $TESTTMP/after-pull
  $ cmp $TESTTMP/after-clone $TESTTMP/after-pull
  $ cd ..

or the path option

  $ cd hgrepo
  $ hg phase -fd 'all()'
  $ hg pull -v --config paths.default:hg-git.publish=yes
  pulling from $TESTTMP/gitrepo
  publishing remote HEAD
  publishing tag thetag
  no changes found
  processing commits in batches of 1000
  bookmark master is up-to-date
  bookmark not-master is up-to-date
  publishing remote HEAD
  publishing tag thetag
  3 local changesets published
  $ hg phase -r 'all()' > $TESTTMP/after-pull
  $ cmp $TESTTMP/after-clone $TESTTMP/after-pull
  $ cd ..

but we can specify individual branches

  $ cd hgrepo
  $ hg phase -fd 'all()'
  $ hg pull -v  --config paths.default:hg-git.publish=not-master
  pulling from $TESTTMP/gitrepo
  publishing branch not-master
  no changes found
  processing commits in batches of 1000
  bookmark master is up-to-date
  bookmark not-master is up-to-date
  publishing branch not-master
  2 local changesets published
  $ hg phase -r master -r not-master -r thetag
  1: draft
  2: public
  3: draft
  $ cd ..

and we can also specify the tag

  $ cd hgrepo
  $ hg phase -fd 'all()'
  $ hg pull -v --config paths.default:hg-git.publish=thetag
  pulling from $TESTTMP/gitrepo
  publishing tag thetag
  no changes found
  processing commits in batches of 1000
  bookmark master is up-to-date
  bookmark not-master is up-to-date
  publishing tag thetag
  2 local changesets published
  $ hg phase -r master -r not-master -r thetag
  1: draft
  2: draft
  3: public
  $ cd ..


Check multiple paths behavior
=============================


  $ cd hgrepo
  $ cat >> .hg/hgrc <<EOF
  > [paths]
  > multi:multi-urls = yes
  > multi = path://other, path://default
  > recursive:multi-urls = yes
  > recursive = path://multi, default
  > EOF

Using multiple path works fine:


  $ hg pull multi --config paths.default:hg-git.publish=yes
  abort: cannot use `path://multi`, "multi" is also defined as a `path://`
  [255]

Recursive multiple path are tricker, but Mercurial don't work with them either.
This test exist to make sure we bail out on our own.


`yes` should abort (until we implement it)

  $ hg pull multi --config paths.default:hg-git.publish=yes
  abort: cannot use `path://multi`, "multi" is also defined as a `path://`
  [255]

`some-value` should abort (until we implement it)

  $ hg pull multi --config paths.default:hg-git.publish=thetag
  abort: cannot use `path://multi`, "multi" is also defined as a `path://`
  [255]

`no` is fine

  $ hg pull multi --config paths.default:hg-git.publish=no
  abort: cannot use `path://multi`, "multi" is also defined as a `path://`
  [255]

  $ cd ..

Check conflicting paths behavior
================================

  $ cd hgrepo
  $ cat > .hg/hgrc <<EOF
  > [paths]
  > default = $TESTTMP/gitrepo
  > default:hg-git.publish = yes
  > also-default = $TESTTMP/gitrepo
  > EOF
  $ hg pull also-default
  pulling from $TESTTMP/gitrepo
  abort: different publishing configurations for the same remote location
  (conflicting paths: also-default, default)
  [255]
  $ hg pull --config paths.also-default:hg-git.publish=no
  pulling from $TESTTMP/gitrepo
  abort: different publishing configurations for the same remote location
  (conflicting paths: also-default, default)
  [255]
  $ hg pull --config paths.also-default:hg-git.publish=true
  pulling from $TESTTMP/gitrepo
  no changes found
  1 local changesets published
  $ cd ..

