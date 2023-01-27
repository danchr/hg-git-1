This test checks our behaviour when commits “disappear” from Git. In
particular, we do the converstion incrementally, and assume that the
Git commit corresponding to parents of exported commits actually
exists in the Git repository. But what happens if it doesn't?

Load commonly used test logic
  $ . "$TESTDIR/testutil"

set up a git repo with one commit

  $ git init -q gitrepo
  $ cd gitrepo
  $ echo something >> thefile
  $ git add thefile
  $ fn_git_commit -m 'add thefile'
  $ cd ..

push it to a bare repository so that we can safely push to it afterwards

  $ git clone --bare --quiet gitrepo repo.git

clone it and create a commit building on the git history

  $ hg clone -U repo.git hgrepo
  importing 1 git commits
  new changesets fb68c5a534ce (1 drafts)
  $ cd hgrepo
  $ hg up -q master
  $ echo other > thefile
  $ fn_hg_commit -m 'change thefile'
  $ cd ..

now remove the git commit from the cache repository used internally by
hg-git — actually, changing `git.intree` is equivalent to this, and how
a user noticed it in #376.

  $ rm -rf hgrepo/.hg/git

what happens when we push it?

  $ hg -R hgrepo push
  pushing to $TESTTMP/repo.git
  warning: created new git repository at $TESTTMP/hgrepo/.hg/git
  abort: cannot push git commit 533d4e670a8b as it is not present locally
  (please try pulling first, or as a fallback run git-cleanup to re-export the missing commits)
  [255]

try to follow the hint:

(and just to see that the warning is useful, try re-resetting first)

  $ rm -rf hgrepo/.hg/git hgrepo/.git
  $ hg -R hgrepo pull
  pulling from $TESTTMP/repo.git
  warning: created new git repository at $TESTTMP/hgrepo/.hg/git
  no changes found
  not updating diverged bookmark master
  $ hg -R hgrepo push
  pushing to $TESTTMP/repo.git
  searching for changes
  adding objects
  remote: found 0 deltas to reuse (dulwich0210 !)
  added 1 commits with 1 trees and 1 blobs
  updating reference refs/heads/master

and as an extra test, what if we want to push a commit that's
converted, but gone?

simply pushing doesn't suffice:

  $ cd hgrepo
  $ rm -rf .hg/git
  $ hg push
  pushing to $TESTTMP/repo.git
  warning: created new git repository at $TESTTMP/hgrepo/.hg/git
  searching for changes
  no changes found
  [1]
  $ cd ..

but we can't create another commit building on the git history, export
it, and push:

  $ cd hgrepo
  $ echo not that > thefile
  $ fn_hg_commit -m 'change thefile again'
  $ hg gexport
  $ rm -rf .hg/git
  $ hg push
  pushing to $TESTTMP/repo.git
  warning: created new git repository at $TESTTMP/hgrepo/.hg/git
  searching for changes
  abort: cannot push git commit 61619410916a as it is not present locally
  (please try pulling first, or as a fallback run git-cleanup to re-export the missing commits)
  [255]
  $ cd ..
