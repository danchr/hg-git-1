Check for contents we should refuse to export to git repositories (or
at least warn).

Load commonly used test logic
  $ . "$TESTDIR/testutil"

  $ hg init hg
  $ cd hg
  $ mkdir -p .git/hooks
  $ cat > .git/hooks/post-update <<EOF
  > #!/bin/sh
  > echo pwned
  > EOF
  $ fn_touch_escaped foo/git~100/wat bar/.gi\\u200ct/wut this/is/safe
  $ hg addremove
  adding .git/hooks/post-update
  adding bar/.gi\xe2\x80\x8ct/wut (esc)
  adding foo/git~100/wat
  adding this/is/safe
  $ hg ci -m "we should refuse to export this"
  $ hg book master
  $ hg gexport
  warning: skipping invalid path '.git/hooks/post-update'
  warning: skipping invalid path 'bar/.gi\xe2\x80\x8ct/wut'
  warning: skipping invalid path 'foo/git~100/wat'
  $ GIT_DIR=.hg/git git ls-tree -r --name-only  master
  this/is/safe
  $ hg debug-remove-hggit-state
  clearing out the git cache data
  $ hg gexport --config hggit.invalidpaths=keep
  warning: path '.git/hooks/post-update' contains an invalid path component
  warning: path 'bar/.gi\xe2\x80\x8ct/wut' contains an invalid path component
  warning: path 'foo/git~100/wat' contains an invalid path component
  $ GIT_DIR=.hg/git git ls-tree -r --name-only  master
  .git/hooks/post-update
  "bar/.gi\342\200\214t/wut"
  foo/git~100/wat
  this/is/safe
  $ cd ..

  $ rm -rf hg
  $ hg init hg
  $ cd hg
  $ mkdir -p nested/.git/hooks/
  $ cat > nested/.git/hooks/post-update <<EOF
  > #!/bin/sh
  > echo pwnd
  > EOF
  $ chmod +x nested/.git/hooks/post-update
  $ hg addremove
  adding nested/.git/hooks/post-update
  $ hg ci -m "also refuse to export this"
  $ hg book master
  $ hg gexport
  warning: skipping invalid path 'nested/.git/hooks/post-update'
  $ git clone .hg/git git
  Cloning into 'git'...
  done.
  $ rm -rf git

We can trigger an error:

  $ hg -q debug-remove-hggit-state
  $ hg --config hggit.invalidpaths=abort gexport
  abort: invalid path 'nested/.git/hooks/post-update' rejected by configuration
  (see 'hg help config.hggit.invalidpaths for details)
  [255]

We can override if needed:

  $ hg --config hggit.invalidpaths=keep gexport
  warning: path 'nested/.git/hooks/post-update' contains an invalid path component
  $ cd ..
  $ # different git versions give different return codes
  $ git clone hg/.hg/git git || true
  Cloning into 'git'...
  done.
  error: [Ii]nvalid path 'nested/\.git/hooks/post-update' (re)
  fatal: unable to checkout working tree (?)
  warning: Clone succeeded, but checkout failed. (?)
  You can inspect what was checked out with 'git status' (?)
  and retry( the checkout)? with '.*' (re) (?)
   (?)

Now check something that case-folds to .git, which might let you own
Mac users:

  $ cd ..
  $ rm -rf hg
  $ hg init hg
  $ cd hg
  $ mkdir -p .GIT/hooks/
  $ cat > .GIT/hooks/post-checkout <<EOF
  > #!/bin/sh
  > echo pwnd
  > EOF
  $ chmod +x .GIT/hooks/post-checkout
  $ hg addremove
  adding .GIT/hooks/post-checkout
  $ hg ci -m "also refuse to export this"
  $ hg book master
  $ hg gexport
  $ cd ..

And the NTFS case:
  $ cd ..
  $ rm -rf hg
  $ hg init hg
  $ cd hg
  $ mkdir -p GIT~1/hooks/
  $ cat > GIT~1/hooks/post-checkout <<EOF
  > #!/bin/sh
  > echo pwnd
  > EOF
  $ chmod +x GIT~1/hooks/post-checkout
  $ hg addremove
  adding GIT~1/hooks/post-checkout
  $ hg ci -m "also refuse to export this"
  $ hg book master
  $ hg gexport
  warning: skipping invalid path 'GIT~1/hooks/post-checkout'
  $ cd ..

Now check a Git repository containing a Mercurial repository, which
you can't check out.

  $ rm -rf hg git nested
  $ git init -q git
  $ hg init nested
  $ mv nested git
  $ cd git
  $ git add nested
  $ fn_git_commit -m 'add a Mercurial repository'
  $ cd ..
  $ hg clone --config hggit.invalidpaths=abort git hg
  importing 1 git commits
  abort: invalid path 'nested/.hg/00changelog.i' rejected by configuration
  (see 'hg help config.hggit.invalidpaths for details)
  [255]
  $ rm -rf hg
  $ hg clone --config hggit.invalidpaths=keep git hg
  importing 1 git commits
  warning: path 'nested/.hg/00changelog.i' contains an invalid path component
  warning: path 'nested/.hg/requires' contains an invalid path component
  warning: path 'nested/.hg/store/requires' contains an invalid path component (?)
  new changesets [0-9a-f]{12,12} \(1 drafts\) (re)
  warning: path 'nested/.hg/store/requires' is within a nested repository, which Mercurial cannot check out. (?)
  updating to bookmark master
  abort: path 'nested/.hg/00changelog.i' is inside nested repo 'nested'
  [10]
  $ rm -rf hg
  $ hg clone git hg
  importing 1 git commits
  warning: skipping invalid path 'nested/.hg/00changelog.i'
  warning: skipping invalid path 'nested/.hg/requires'
  warning: skipping invalid path 'nested/.hg/store/requires' (?)
  new changesets 3ea18a67c0e6 (1 drafts)
  updating to bookmark master
  0 files updated, 0 files merged, 0 files removed, 0 files unresolved
  $ cd ..

Now check a Git repository containing paths with carriage return and
newline, which Mercurial expressly forbids
(see https://bz.mercurial-scm.org/show_bug.cgi?id=352)

  $ rm -rf hg git
  $ git init -q git
  $ cd git
  $ fn_touch_escaped Icon\\r the\\nfile
  $ git add .
  $ fn_git_commit -m 'add files disallowed by mercurial'
  $ cd ..
  $ hg clone --config hggit.invalidpaths=abort git hg
  importing 1 git commits
  abort: invalid path 'Icon\r' rejected by configuration
  (see 'hg help config.hggit.invalidpaths for details)
  [255]
  $ hg clone --config hggit.invalidpaths=keep git hg
  importing 1 git commits
  warning: skipping invalid path 'Icon\r'
  warning: skipping invalid path 'the\nfile'
  new changesets 8354c06a5842 (1 drafts)
  updating to bookmark master
  0 files updated, 0 files merged, 0 files removed, 0 files unresolved
  $ rm -rf hg
  $ hg clone git hg
  importing 1 git commits
  warning: skipping invalid path 'Icon\r'
  warning: skipping invalid path 'the\nfile'
  new changesets 8354c06a5842 (1 drafts)
  updating to bookmark master
  0 files updated, 0 files merged, 0 files removed, 0 files unresolved

