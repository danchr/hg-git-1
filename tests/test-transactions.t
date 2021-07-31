Transactions
============

This test excercises our transaction logic, and the behaviour when a
conversion fails or is interrupted.

Load commonly used test logic
  $ . "$TESTDIR/testutil"

Create a git repository with lots of commits, that touches lots of
different files.

  $ git init gitrepo
  Initialized empty Git repository in $TESTTMP/gitrepo/.git/
  $ cd gitrepo
  $ for i in $(seq 100)
  > do
  >   f=$(expr $i % 10)
  >   echo $i > $f
  >   git add $f
  >   fn_git_commit -m $i
  > done
  $ cd ..

Map saving
----------

First, test that hggit.mapsavefrequency actually works

clone with mapsavefreq set

  $ hg clone gitrepo hgrepo --config hggit.mapsavefrequency=10 --debug \
  > | grep -c saving
  1
  $ rm -rf hgrepo

pull with mapsavefreq set

  $ hg init hgrepo
  $ cat >> hgrepo/.hg/hgrc <<EOF
  > [paths]
  > default = $TESTTMP/gitrepo
  > EOF
  $ hg -R hgrepo --config hggit.mapsavefrequency=10 pull --debug \
  > | grep -c saving
  10
  $ rm -rf hgrepo

Interruptions
-------------

How does hg-git behave if a conversion fails or is interrupted?

Ideally, we would always save the results of whatever happened

  $ hg init hgrepo
  $ cat >> hgrepo/.hg/hgrc <<EOF
  > [paths]
  > default = $TESTTMP/gitrepo
  > [extensions]
  > breakage = $TESTDIR/testlib/ext-break-git-import.py
  > strip =
  > EOF
  $ cd hgrepo

Test an error in a pull:

  $ ABORT_AFTER=99 hg pull
  pulling from $TESTTMP/gitrepo
  importing git objects into hg
  transaction abort!
  rollback completed
  abort: aborted after 99 commits!
  [255]
  $ hg log -l 10 -T '{rev} {gitnode}\n'

How does map save interval work?

  $ EXIT_AFTER=15 hg --config hggit.mapsavefrequency=10 pull
  pulling from $TESTTMP/gitrepo
  importing git objects into hg
  transaction abort!
  rollback completed
  interrupted!
  [255]
  $ hg log -l 10 -T '{rev} {gitnode}\n'
  9 1d6b9d3de3098d28bb786d18849f5790a08a9a08
  8 42da70ed92bbecf9f348ba59c93646be723d0bf2
  7 17e841146e5744b81af9959634d82c20a5d7df52
  6 c31065bf97bf014815e37cdfbdef2c32c687f314
  5 fcf21b8e0520ec1cced1d7593d13f9ee54721269
  4 46acd02d0352e4b92bd6a099bb0490305d847a18
  3 61eeda444b37b8aa3892d5f04c66c5441d21dd66
  2 e55db11bb0472791c7af3fc636772174cdea4a36
  1 17a2672b3c24c02d568f99d8d55ccae2bf362d5c
  0 4e195b4c6e77604b70a8ad3b01306adbb9b1c7e7

Reset the repository

  $ hg strip --no-backup 'all()'
  $ hg gclear
  clearing out the git cache data

Test the user exiting in the middle of a conversion:

  $ EXIT_AFTER=15 hg --config hggit.mapsavefrequency=10 pull
  pulling from $TESTTMP/gitrepo
  importing git objects into hg
  transaction abort!
  rollback completed
  interrupted!
  [255]
  $ hg log -l 10 -T '{rev} {gitnode}\n'
  9 1d6b9d3de3098d28bb786d18849f5790a08a9a08
  8 42da70ed92bbecf9f348ba59c93646be723d0bf2
  7 17e841146e5744b81af9959634d82c20a5d7df52
  6 c31065bf97bf014815e37cdfbdef2c32c687f314
  5 fcf21b8e0520ec1cced1d7593d13f9ee54721269
  4 46acd02d0352e4b92bd6a099bb0490305d847a18
  3 61eeda444b37b8aa3892d5f04c66c5441d21dd66
  2 e55db11bb0472791c7af3fc636772174cdea4a36
  1 17a2672b3c24c02d568f99d8d55ccae2bf362d5c
  0 4e195b4c6e77604b70a8ad3b01306adbb9b1c7e7
  $ cd ..
  $ rm -rf hgrepo

And with a clone into an existing directory using an in-tree
repository. Mercurial deletes the repository on errors, and so should
we do with the Git repository, ideally. The current design doesn't
make that easy to do, so this test mostly exists to document the
current behaviour.

  $ mkdir hgrepo
  $ EXIT_AFTER=15 \
  > hg --config hggit.mapsavefrequency=10 --config git.intree=yes \
  > --config extensions.breakage=$TESTDIR/testlib/ext-break-git-import.py \
  > --cwd hgrepo \
  > clone -U $TESTTMP/gitrepo .
  importing git objects into hg
  transaction abort!
  rollback completed
  interrupted!
  [255]
the leftover below only appears in Mercurial 5.9+; it is unintentional
TODO: once the first rc is released, change (?) to (hg59 !)
  $ ls -A hgrepo
  .git (?)
  $ rm -rf hgrepo
