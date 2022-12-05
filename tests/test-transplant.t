Load commonly used test logic
  $ . "$TESTDIR/testutil"

Check that hg-git doesn't break the -s/--source option for transplant
https://foss.heptapod.net/mercurial/hg-git/-/issues/392

  $ cat <<EOF >> $HGRCPATH
  > [extensions]
  > transplant=
  > graphlog=
  > EOF

  $ hg init baserepo
  $ cd baserepo
  $ for c in A B C
  > do
  >   echo $c > $c && hg add $c && fn_hg_commit -m $c
  > done
  $ hg clone -r 2 . ../otherrepo
  adding changesets
  adding manifests
  adding file changes
  added 3 changesets with 3 changes to 3 files
  new changesets d2296e4d4e8a:f21e074b4681
  updating to branch default
  3 files updated, 0 files merged, 0 files removed, 0 files unresolved
  $ cd ../otherrepo
  $ hg up 1
  0 files updated, 0 files merged, 1 files removed, 0 files unresolved
  $ hg transplant -s ../baserepo tip
  no changes found
