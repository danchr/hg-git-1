Load commonly used test logic
  $ . "$TESTDIR/testutil"

  $ git init gitrepo
  Initialized empty Git repository in $TESTTMP/gitrepo/.git/
  $ cd gitrepo
  $ echo alpha > alpha
  $ git add alpha
  $ fn_git_commit -m 'add alpha'
  $ echo beta > beta
  $ git add beta
  $ fn_git_commit -m 'add beta'

This commit is called gamma10 so that its hash will have the same initial digit
as commit alpha. This lets us test ambiguous abbreviated identifiers.

  $ echo gamma10 > gamma10
  $ git add gamma10
  $ fn_git_commit -m 'add gamma10'

  $ cd ..

  $ hg clone gitrepo hgrepo
  importing 3 git commits
  new changesets ff7a2f2d8d70:8e3f0ecc9aef (3 drafts)
  updating to bookmark master
  3 files updated, 0 files merged, 0 files removed, 0 files unresolved

  $ cd hgrepo

  $ hg log -r 'gitnode(7e)'
  abort: git-mapfile@7e: ambiguous identifier!? (re)
  [50]
