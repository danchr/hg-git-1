Transactions
============

This test excercises our transaction logic, and the behaviour when a
conversion fails or is interrupted.

Load commonly used test logic
  $ . "$TESTDIR/testutil"

Enable a few other extensions:

  $ cat >> $HGRCPATH <<EOF
  > [extensions]
  > breakage = $TESTDIR/testlib/ext-break-git-import.py
  > EOF

Create a git repository with 100 commits, that touches 10 different
files. We also have 10 tags.

  $ git init gitrepo
  Initialized empty Git repository in $TESTTMP/gitrepo/.git/
  $ cd gitrepo
  $ for i in $(seq 10)
  > do
  >   for f in $(seq 10)
  >   do
  >     n=$(expr $i \* $f)
  >     echo $n > $f
  >     git add $f
  >     fn_git_commit -m $n
  >   done
  >   fn_git_tag -m $i v$i
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

The user experience
-------------------

The map save interval affects how and when changes are reported to the
user.

First, create a repository, set up to pull from git, and where we can interrupt the conversion.

  $ hg init hgrepo
  $ cat >> hgrepo/.hg/hgrc <<EOF
  > [paths]
  > default = $TESTTMP/gitrepo
  > EOF
  $ cd hgrepo

A low save interval causes a lot of reports:

  $ hg --config hggit.mapsavefrequency=25 pull
  pulling from $TESTTMP/gitrepo
  importing 100 git commits
  new changesets 1c8407413fa3:abc468b9e51b (25 drafts)
  new changesets 217c308baf47:d5d14eeedd08 (25 drafts)
  new changesets d9807ef6abcb:4678067bd500 (25 drafts)
  adding bookmark master
  new changesets c31a154888bb:eda59117ba04 (25 drafts)
  (run 'hg update' to get a working copy)

Reset the repository

  $ hg debugstrip --no-backup 'all()'
  $ hg debug-remove-hggit-state
  clearing out the git cache data

And with phases? No mention of draft changesets, as we publish changes
during the conversion:

  $ hg --config hggit.mapsavefrequency=25 --config hggit.usephases=yes pull
  pulling from $TESTTMP/gitrepo
  importing 100 git commits
  new changesets 1c8407413fa3:abc468b9e51b
  new changesets 217c308baf47:d5d14eeedd08
  new changesets d9807ef6abcb:4678067bd500
  updating bookmark master
  new changesets c31a154888bb:eda59117ba04
  (run 'hg update' to get a working copy)

Reset the repository

  $ hg debugstrip --no-backup 'all()'
  $ hg debug-remove-hggit-state
  clearing out the git cache data

Interruptions
-------------

How does hg-git behave if a conversion fails or is interrupted?

Ideally, we would always save the results of whatever happened, but
that causes a significant slowdown. Transactions are an important
optimisation within Mercurial.

Test an error in a pull:

  $ ABORT_AFTER=99 hg pull
  pulling from $TESTTMP/gitrepo
  importing 100 git commits
  transaction abort!
  rollback completed
  abort: aborted after 99 commits!
  [255]
  $ hg log -l 10 -T '{rev} {gitnode}\n'

Test the user exiting in the first transaction:

  $ EXIT_AFTER=5 hg --config hggit.mapsavefrequency=10 pull
  pulling from $TESTTMP/gitrepo
  importing 100 git commits
  transaction abort!
  rollback completed
  interrupted!
  [255]
  $ hg log -l 10 -T '{rev} {gitnode}\n'

Check that we have no state, but clear it just in case

  $ ls -d .hg/git*
  .hg/git
  $ hg debug-remove-hggit-state
  clearing out the git cache data

Test the user exiting in the middle of a conversion, after the first
transaction:

  $ EXIT_AFTER=15 hg --config hggit.mapsavefrequency=10 pull
  pulling from $TESTTMP/gitrepo
  importing 100 git commits
  new changesets 1c8407413fa3:7c8c534a5fbe (10 drafts)
  transaction abort!
  rollback completed
  interrupted!
  [255]
  $ hg log -l 10 -T '{rev} {gitnode}\n'
  9 7cbb16ec981b308e1e2b181f8e1f22c8f409f44e
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
  > --cwd hgrepo \
  > clone -U $TESTTMP/gitrepo .
  importing 100 git commits
  transaction abort!
  rollback completed
  interrupted!
  [255]
the leftover below appeared in Mercurial 5.9+; it is unintentional
  $ ls -A hgrepo
  .git
  $ rm -rf hgrepo
