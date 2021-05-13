Load commonly used test logic
  $ . "$TESTDIR/testutil"

This test verifies that outgoing with orphaned annotated tags, and
that actually pushing such a tag works.

Initialize the bare repository

  $ mkdir git.bare
  $ cd git.bare
  $ git init --bare
  Initialized empty Git repository in $TESTTMP/git.bare/
  $ cd ..

Populate the git repository

  $ git clone -q git.bare git
  warning: You appear to have cloned an empty repository.
  $ cd git
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
  $ git push --set-upstream origin the_branch
  To $TESTTMP/git.bare
   * [new branch]      the_branch -> the_branch
  Branch 'the_branch' set up to track remote branch 'the_branch' from 'origin'.
  $ git push --tags
  To $TESTTMP/git.bare
   * [new tag]         the_tag -> the_tag

Continue the master branch

  $ git checkout -q master
  $ touch foo4
  $ git add foo4
  $ fn_git_commit -m "add foo4"
  $ git push
  To $TESTTMP/git.bare
   * [new branch]      master -> master

Delete the temporary branch

  $ git branch -D the_branch
  Deleted branch the_branch (was e128523).
  $ git push --delete origin the_branch
  To $TESTTMP/git.bare
   - [deleted]         the_branch
  $ cd ..

Create a Mercurial clone

  $ hg clone -U git.bare hg
  importing git objects into hg
  $ hg outgoing -R hg
  comparing with $TESTTMP/git.bare
  searching for changes
  no changes found
  [1]
  $ hg push --debug -R hg | grep -e reference -e found
  unchanged reference default::refs/heads/master => GIT:996e5084
  unchanged reference default::refs/tags/the_tag => GIT:e4338156
  no changes found

Verify that we can push this tag, and that outgoing doesn't report
them (#358)

  $ cd git
  $ git tag --delete the_tag
  Deleted tag 'the_tag' (was e433815)
  $ git push --delete origin the_tag
  To $TESTTMP/git.bare
   - [deleted]         the_tag
  $ cd ../hg
  $ hg outgoing
  comparing with $TESTTMP/git.bare
  searching for changes
  changeset:   2:7b35eb0afb3f
  tag:         the_tag
  user:        test <test@example.org>
  date:        Mon Jan 01 00:00:12 2007 +0000
  summary:     add foo3
  
  $ hg push --debug | grep -e reference -e commits
  finding hg commits to export
  1 commits found
  list of commits:
  added 1 commits with 1 trees and 0 blobs
  unchanged reference default::refs/heads/master => GIT:996e5084
  adding reference default::refs/tags/the_tag => GIT:e4338156
  $ cd ../git
  $ git fetch
  From $TESTTMP/git.bare
   * [new tag]         the_tag    -> the_tag
  $ git tag -ln
  the_tag         Tag message
