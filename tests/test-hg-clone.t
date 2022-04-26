Load commonly used test logic
  $ . "$TESTDIR/testutil"

  $ git init gitrepo
  Initialized empty Git repository in $TESTTMP/gitrepo/.git/
  $ cd gitrepo
  $ echo alpha > alpha
  $ git add alpha
  $ fn_git_commit -m 'add alpha'
  $ git tag alpha
  $ cd ..

  $ hg clone -U gitrepo hgrepo
  importing 1 git commits
  new changesets ff7a2f2d8d70 (1 drafts)

By default, the Git state isn't preserved across a copying/linking
clone

  $ hg clone -U hgrepo otherhgrepo
  $ cd otherhgrepo
  $ find .hg -name 'git*' | sort
  $ hg tags -v
  tip                                0:ff7a2f2d8d70
  $ hg log -r 'fromgit()' -T '{rev}:{node|short} {gitnode|short}\n'
  $ cd ..
  $ rm -r otherhgrepo

Nor using a pull clone

  $ hg clone -U --pull hgrepo otherhgrepo
  requesting all changes
  adding changesets
  adding manifests
  adding file changes
  added 1 changesets with 1 changes to 1 files
  new changesets ff7a2f2d8d70
  $ cd otherhgrepo
  $ find .hg -name 'git*' | sort
  $ hg tags -v
  tip                                0:ff7a2f2d8d70
  $ hg log -r 'fromgit()' -T '{rev}:{node|short} {gitnode|short}\n'
  $ cd ..
  $ rm -r otherhgrepo

But we can enable it!

  $ cat >> $HGRCPATH <<EOF
  > [experimental]
  > hg-git-serve = yes
  > EOF

Check transferring between Mercurial repositories using a
copying/linking clone

  $ hg clone -U hgrepo otherhgrepo
  $ cd otherhgrepo
  $ find .hg -name 'git*' | sort
  $ hg tags -q
  tip
  $ hg log -r 'fromgit()' -T '{rev}:{node|short} {gitnode|short}\n'
  $ cd ..

Checking using a pull clone

  $ rm -rf otherhgrepo
  $ hg clone -U --pull hgrepo otherhgrepo
  requesting all changes
  adding changesets
  adding manifests
  adding file changes
  added 1 changesets with 1 changes to 1 files
  new changesets ff7a2f2d8d70
  $ cd otherhgrepo
  $ hg tags -q
  tip
  alpha
  $ hg log -r 'fromgit()' -T '{rev}:{node|short} {gitnode|short}\n'
  0:ff7a2f2d8d70 7eeab2ea75ec
  $ cd ..

Can we repopulate the state from a Mercurial repository?

  $ cd otherhgrepo
  $ hg debug-remove-hggit-state
  clearing out the git cache data
  $ hg log -qr 'fromgit()'
  $ hg tags
  tip                                0:ff7a2f2d8d70
  $ hg pull
  pulling from $TESTTMP/hgrepo
  searching for changes
  no changes found
  $ hg log -qr 'fromgit()'
  $ hg tags
  tip                                0:ff7a2f2d8d70

Sadly, no.
