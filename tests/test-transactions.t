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
  11
  $ rm -rf hgrepo

pull with mapsavefreq set

  $ hg init hgrepo
  $ cat >> hgrepo/.hg/hgrc <<EOF
  > [paths]
  > default = $TESTTMP/gitrepo
  > EOF
  $ hg -R hgrepo --config hggit.mapsavefrequency=10 pull --debug \
  > | grep -c saving
  11
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
  abort: aborted after 99 commits!
  [255]
  $ hg log -l 10 -T '{rev} {gitnode}\n'
  99 
  98 
  97 
  96 
  95 
  94 
  93 
  92 
  91 
  90 

Reset the repository

  $ hg strip --no-backup 'all()'
  $ hg gclear
  clearing out the git cache data

How does map save interval work?

  $ EXIT_AFTER=15 hg --config hggit.mapsavefrequency=10 pull
  pulling from $TESTTMP/gitrepo
  importing git objects into hg
  interrupted!
  [255]
  $ hg log -l 10 -T '{rev} {gitnode}\n'
  15 
  14 
  13 
  12 
  11 
  10 
  9 1d6b9d3de3098d28bb786d18849f5790a08a9a08
  8 42da70ed92bbecf9f348ba59c93646be723d0bf2
  7 17e841146e5744b81af9959634d82c20a5d7df52
  6 c31065bf97bf014815e37cdfbdef2c32c687f314

Reset the repository

  $ hg strip --no-backup 'all()'
  $ hg gclear
  clearing out the git cache data

Test the user exiting in the middle of a conversion:

  $ EXIT_AFTER=15 hg --config hggit.mapsavefrequency=10 pull
  pulling from $TESTTMP/gitrepo
  importing git objects into hg
  interrupted!
  [255]
  $ hg log -l 10 -T '{rev} {gitnode}\n'
  15 
  14 
  13 
  12 
  11 
  10 
  9 1d6b9d3de3098d28bb786d18849f5790a08a9a08
  8 42da70ed92bbecf9f348ba59c93646be723d0bf2
  7 17e841146e5744b81af9959634d82c20a5d7df52
  6 c31065bf97bf014815e37cdfbdef2c32c687f314
  $ cd ..
  $ rm -rf hgrepo

And with a clone into an in-tree repository

  $ mkdir hgrepo
  $ EXIT_AFTER=15 \
  > hg --config hggit.mapsavefrequency=10 --config git.intree=yes \
  > --config extensions.breakage=$TESTDIR/testlib/ext-break-git-import.py \
  > clone gitrepo hgrepo
  importing git objects into hg
  interrupted!
  [255]
  $ hg id hgrepo
  abort: repository hgrepo not found (hg57 !)
  abort: repository hgrepo not found! (no-hg57 !)
  [255]
  $ rm -rf hgrepo
