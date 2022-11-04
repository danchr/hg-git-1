Load commonly used test logic
  $ . "$TESTDIR/testutil"

  $ cat >> $HGRCPATH <<EOF
  > [templates]
  > info =
  >   commit:  {rev}:{node|short}  {desc|fill68}
  >   added:   {file_adds}
  >   removed: {file_dels}\n
  > EOF

Create a Git upstream

  $ git init --quiet --bare repo.git


Create a Mercurial repository with a .gitmodules file:

  $ hg clone repo.git hgrepo
  updating to branch default
  0 files updated, 0 files merged, 0 files removed, 0 files unresolved
  $ cd hgrepo
  $ hg book master
  $ touch this
  $ fn_hg_commit -A -m 'add this'
  $ cat > .gitmodules <<EOF
  > [submodule "subrepo"]
  > 	path = subrepo
  > 	url = ../gitsubrepo
  > EOF
  $ hg add .gitmodules
  $ fn_hg_commit -m "add .gitmodules file"
  $ cd ..

What happens if we push that to Git?

  $ hg -R hgrepo push
  pushing to $TESTTMP/repo.git
  warning: ignoring modifications to '.gitmodules' file; please use '.hgsub' instead
  searching for changes
  adding objects
  remote: found 0 deltas to reuse (dulwich0210 !)
  added 2 commits with 1 trees and 1 blobs
  adding reference refs/heads/master

But we don't get a warning if we don't touch .gitmodules:

  $ cd hgrepo
  $ touch that
  $ fn_hg_commit -A -m 'add that'
  $ hg push
  pushing to $TESTTMP/repo.git
  searching for changes
  adding objects
  remote: found 0 deltas to reuse (dulwich0210 !)
  added 1 commits with 1 trees and 0 blobs
  updating reference refs/heads/master
  $ cd ..

Check that it didn't silenty come through, or something:

  $ git clone repo.git gitrepo
  Cloning into 'gitrepo'...
  done.
  $ ls -A gitrepo
  .git
  that
  this
