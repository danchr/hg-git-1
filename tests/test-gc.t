Garbage collection
==================

This test excercises our internal transparent packing of loose objects.

Load commonly used test logic
  $ . "$TESTDIR/testutil"

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
  $ hg clone -U gitrepo hgrepo
  importing 100 git commits
  new changesets 1c8407413fa3:eda59117ba04 (100 drafts)
  $ cd hgrepo
  $ hg debug-remove-hggit-state
  clearing out the git cache data

-----------

Test garbage collection of loose objects into packs. We first test
this with two threads, which is closest to the expected usage
scenario, as almost all computers have at least two cores these days.
The main downside is that this makes the output order unreliable, so
we just sort it.

  $ hg gexport --config hggit.mapsavefrequency=33 --config hggit.threads=2 --debug | grep pack | sort
  packed 3 loose objects!
  packed 75 loose objects!
  packed 78 loose objects!
  packed 86 loose objects!
  packing 3 loose objects...
  packing 75 loose objects...
  packing 78 loose objects...
  packing 86 loose objects...
  $ hg debug-remove-hggit-state
  clearing out the git cache data

Test the actual order of operations -- this uses a single thread,
which means that the packing happens synchronously in the main thread,
giving us a reliable output order.

In addition, the transaction size is set up such that we happen to do
nothing in the final, synchronous packing that happens on every pull.
Lots of other tests have a map save frequency higher than the total
amount of commits pulled, but let's just trigger that other odd
occurence here.

  $ hg gexport --debug \
  > --config hggit.mapsavefrequency=10 --config hggit.threads=1 | \
  > sed 's/^converting revision.*/./'
  finding unexported changesets
  exporting 100 changesets
  .
  .
  .
  .
  .
  .
  .
  .
  .
  .
  saving git map to $TESTTMP/hgrepo/.hg/git-mapfile
  packing 30 loose objects...
  packed 30 loose objects!
  .
  .
  .
  .
  .
  .
  .
  .
  .
  .
  saving git map to $TESTTMP/hgrepo/.hg/git-mapfile
  packing 25 loose objects...
  packed 25 loose objects!
  .
  .
  .
  .
  .
  .
  .
  .
  .
  .
  saving git map to $TESTTMP/hgrepo/.hg/git-mapfile
  packing 25 loose objects...
  packed 25 loose objects!
  .
  .
  .
  .
  .
  .
  .
  .
  .
  .
  saving git map to $TESTTMP/hgrepo/.hg/git-mapfile
  packing 24 loose objects...
  packed 24 loose objects!
  .
  .
  .
  .
  .
  .
  .
  .
  .
  .
  saving git map to $TESTTMP/hgrepo/.hg/git-mapfile
  packing 24 loose objects...
  packed 24 loose objects!
  .
  .
  .
  .
  .
  .
  .
  .
  .
  .
  saving git map to $TESTTMP/hgrepo/.hg/git-mapfile
  packing 24 loose objects...
  packed 24 loose objects!
  .
  .
  .
  .
  .
  .
  .
  .
  .
  .
  saving git map to $TESTTMP/hgrepo/.hg/git-mapfile
  packing 24 loose objects...
  packed 24 loose objects!
  .
  .
  .
  .
  .
  .
  .
  .
  .
  .
  saving git map to $TESTTMP/hgrepo/.hg/git-mapfile
  packing 23 loose objects...
  packed 23 loose objects!
  .
  .
  .
  .
  .
  .
  .
  .
  .
  .
  saving git map to $TESTTMP/hgrepo/.hg/git-mapfile
  packing 22 loose objects...
  packed 22 loose objects!
  .
  .
  .
  .
  .
  .
  .
  .
  .
  .
  saving git map to $TESTTMP/hgrepo/.hg/git-mapfile
  packing 21 loose objects...
  packed 21 loose objects!
  packing 0 loose objects...
  packed 0 loose objects!
  saving git map to $TESTTMP/hgrepo/.hg/git-mapfile
  $ find .hg/git/objects -type f | grep -Fv .idx | sort
  .hg/git/objects/pack/pack-33903607b479000b976a29a349fe0f4dffb0aaac.pack
  .hg/git/objects/pack/pack-40d9440e392d9eab62fa38a2ed66cc763d77aca3.pack
  .hg/git/objects/pack/pack-4ab2dac268f94e407788d52d6ba087b626c41651.pack
  .hg/git/objects/pack/pack-543e3b37bd36218a4dc6611a96d7c218afb78429.pack
  .hg/git/objects/pack/pack-5fc80292253ee10d1b86b5c4d9c51b29d2b4ba47.pack
  .hg/git/objects/pack/pack-9c636f5f16302fc5fadf0cc4ed42aeb67fc51f6a.pack
  .hg/git/objects/pack/pack-ae74b1f0197dfb45cfb13889453860a40103969a.pack
  .hg/git/objects/pack/pack-b432e2f477cb765fc0aeaa850d56e04b10392e6c.pack
  .hg/git/objects/pack/pack-cf7023660ce10ede2896d1be117f6ba93a261ff9.pack
  .hg/git/objects/pack/pack-e601b2af6a91a9cf6817d71f4eb660d2218d4094.pack
