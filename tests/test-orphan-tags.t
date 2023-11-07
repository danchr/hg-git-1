Load commonly used test logic
  $ . "$TESTDIR/testutil"

This test verifies that outgoing with orphaned annotated tags, and
that actually pushing such a tag works.

Initialize the bare repository

  $ mkdir repo.git
  $ cd repo.git
  $ git init -q --bare
  $ cd ..

Populate the git repository

  $ git clone -q repo.git gitrepo
  warning: You appear to have cloned an empty repository.
  $ cd gitrepo
  $ touch foo1
  $ git add foo1
  $ fn_git_commit -m initial
  $ touch foo2
  $ git add foo2
  $ fn_git_commit -m "add foo2"

Create a temporary branch and tag

  $ git checkout -qb the_branch
  $ touch foo3
  $ git add foo3
  $ fn_git_commit -m "add foo3"

  $ fn_git_tag the_tag -m "Tag message"
  $ git tag -ln
  the_tag         Tag message
  $ git push --quiet --set-upstream origin the_branch
  Branch 'the_branch' set up to track remote branch 'the_branch' from 'origin'. (?)
  $ git push --tags
  To $TESTTMP/repo.git
   * [new tag]         the_tag -> the_tag

Continue the master branch

  $ git checkout -q master
  $ touch foo4
  $ git add foo4
  $ fn_git_commit -m "add foo4"
  $ git push
  To $TESTTMP/repo.git
   * [new branch]      master -> master

Delete the temporary branch

  $ git branch -D the_branch
  Deleted branch the_branch (was e128523).
  $ git push --delete origin the_branch
  To $TESTTMP/repo.git
   - [deleted]         the_branch
  $ cd ..

Create a Mercurial clone

  $ hg clone -U repo.git hgrepo
  importing 4 git commits
  new changesets b8e77484829b:387d03400596 (4 drafts)
  $ hg outgoing -R hgrepo
  comparing with $TESTTMP/repo.git
  searching for changes
  no changes found
  [1]
  $ hg push --debug -R hgrepo | grep -e reference -e found
  unchanged reference default::refs/heads/master => GIT:996e5084
  unchanged reference default::refs/tags/the_tag => GIT:e4338156
  no changes found

Verify that we can push this tag, and that outgoing doesn't report
them (#358)

  $ cd gitrepo
  $ git tag --delete the_tag
  Deleted tag 'the_tag' (was e433815)
  $ git push --delete origin the_tag
  To $TESTTMP/repo.git
   - [deleted]         the_tag
  $ cd ../hgrepo
  $ hg outgoing
  comparing with $TESTTMP/repo.git
  searching for changes
  changeset:   2:7b35eb0afb3f
  tag:         the_tag
  user:        test <test@example.org>
  date:        Mon Jan 01 00:00:12 2007 +0000
  summary:     add foo3
  
  $ hg push --debug
  pushing to $TESTTMP/repo.git
  finding unexported changesets
  saving git map to $TESTTMP/hgrepo/.hg/git-mapfile
  searching for changes
  remote: counting objects: 5, done. (dulwich0210 !)
  1 commits found
  list of commits:
  e12852326ef72772e9696b008ad6546b5266ff13
  adding objects
  remote: counting objects: 5, done. (dulwich0210 !)
  remote: found 0 deltas to reuse (dulwich0210 !)
  added 1 commits with 1 trees and 0 blobs
  unchanged reference default::refs/heads/master => GIT:996e5084
  adding reference default::refs/tags/the_tag => GIT:e4338156
  $ cd ../gitrepo
  $ git fetch
  From $TESTTMP/repo
   * [new tag]         the_tag    -> the_tag
  $ git tag -ln
  the_tag         Tag message
