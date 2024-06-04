#testcases secret draft

Load commonly used test logic
  $ . "$TESTDIR/testutil"

  $ cat >> $HGRCPATH <<EOF
  > [templates]
  > p = {rev}|{phase}|{bookmarks}|{tags}\n
  > EOF

#if secret
The phases setting should not affect hg-git
  $ cat >> $HGRCPATH <<EOF
  > [phases]
  > new-commit = secret
  > EOF
#endif

set up a git repo with some commits, branches and a tag
  $ git init -q gitrepo
  $ cd gitrepo
  $ echo alpha > alpha
  $ git add alpha
  $ fn_git_commit -m 'add alpha'
  $ git tag t_alpha
  $ git checkout -qb beta
  $ echo beta > beta
  $ git add beta
  $ fn_git_commit -m 'add beta'
  $ git checkout -qb delta master
  $ echo delta > delta
  $ git add delta
  $ fn_git_commit -m 'add delta'
  $ cd ..

pull without a name
  $ hg init hgrepo
  $ cd hgrepo
  $ hg pull ../gitrepo
  pulling from ../gitrepo
  importing 3 git commits
  adding bookmark beta
  adding bookmark delta
  adding bookmark master
  new changesets ff7a2f2d8d70:678ebee93e38 (3 drafts)
  (run 'hg heads' to see heads, 'hg merge' to merge)
  $ git --git-dir .hg/git for-each-ref
  7eeab2ea75ec1ac0ff3d500b5b6f8a3447dd7c03 commit	refs/tags/t_alpha
  $ hg log -Tp
  2|draft|delta|tip
  1|draft|beta|
  0|draft|master|t_alpha
  $ cd ..
  $ rm -rf hgrepo

pull with an implied name
  $ hg init hgrepo
  $ cd hgrepo
  $ echo "[paths]" >> .hg/hgrc
  $ echo "default=$TESTTMP/gitrepo" >> .hg/hgrc
  $ hg pull ../gitrepo
  pulling from ../gitrepo
  importing 3 git commits
  adding bookmark beta
  adding bookmark delta
  adding bookmark master
  new changesets ff7a2f2d8d70:678ebee93e38 (3 drafts)
  (run 'hg heads' to see heads, 'hg merge' to merge)
  $ git --git-dir .hg/git for-each-ref
  9497a4ee62e16ee641860d7677cdb2589ea15554 commit	refs/remotes/default/beta
  8cbeb817785fe2676ab0eda570534702b6b6f9cf commit	refs/remotes/default/delta
  7eeab2ea75ec1ac0ff3d500b5b6f8a3447dd7c03 commit	refs/remotes/default/master
  7eeab2ea75ec1ac0ff3d500b5b6f8a3447dd7c03 commit	refs/tags/t_alpha
  $ hg log -Tp
  2|draft|delta|default/delta tip
  1|draft|beta|default/beta
  0|draft|master|default/master t_alpha
  $ cd ..
  $ rm -rf hgrepo

pull with an explicit name
  $ hg init hgrepo
  $ cd hgrepo
  $ echo "[paths]" >> .hg/hgrc
  $ echo "default=$TESTTMP/gitrepo" >> .hg/hgrc
  $ hg pull
  pulling from $TESTTMP/gitrepo
  importing 3 git commits
  adding bookmark beta
  adding bookmark delta
  adding bookmark master
  new changesets ff7a2f2d8d70:678ebee93e38 (3 drafts)
  (run 'hg heads' to see heads, 'hg merge' to merge)
  $ git --git-dir .hg/git for-each-ref
  9497a4ee62e16ee641860d7677cdb2589ea15554 commit	refs/remotes/default/beta
  8cbeb817785fe2676ab0eda570534702b6b6f9cf commit	refs/remotes/default/delta
  7eeab2ea75ec1ac0ff3d500b5b6f8a3447dd7c03 commit	refs/remotes/default/master
  7eeab2ea75ec1ac0ff3d500b5b6f8a3447dd7c03 commit	refs/tags/t_alpha
  $ hg log -Tp
  2|draft|delta|default/delta tip
  1|draft|beta|default/beta
  0|draft|master|default/master t_alpha
  $ cd ..
  $ rm -rf hgrepo

pull a tag
  $ hg init hgrepo
  $ echo "[paths]" >> hgrepo/.hg/hgrc
  $ echo "default=$TESTTMP/gitrepo" >> hgrepo/.hg/hgrc
  $ hg -R hgrepo pull -r t_alpha
  pulling from $TESTTMP/gitrepo
  importing 1 git commits
  adding bookmark master
  new changesets ff7a2f2d8d70 (1 drafts)
  (run 'hg update' to get a working copy)
  $ hg -R hgrepo update t_alpha
  1 files updated, 0 files merged, 0 files removed, 0 files unresolved
  $ hg log -Tp -R hgrepo
  0|draft|master|default/master t_alpha tip

no-op pull
  $ hg -R hgrepo pull -r t_alpha
  pulling from $TESTTMP/gitrepo
  no changes found

no-op pull with added bookmark
  $ cd gitrepo
  $ git checkout -qb epsilon t_alpha
  $ cd ..
  $ hg -R hgrepo pull -r epsilon
  pulling from $TESTTMP/gitrepo
  no changes found
  adding bookmark epsilon

pull something that doesn't exist
  $ hg -R hgrepo pull -r kaflaflibob
  pulling from $TESTTMP/gitrepo
  abort: unknown revision 'kaflaflibob'!? (re)
  [10]

pull an ambiguous reference
  $ GIT_DIR=gitrepo/.git git branch t_alpha t_alpha
  $ hg -R hgrepo pull -r t_alpha
  pulling from $TESTTMP/gitrepo
  abort: ambiguous reference t_alpha: refs/heads/t_alpha, refs/tags/t_alpha!? (re)
  [10]
  $ GIT_DIR=gitrepo/.git git branch -qD t_alpha

pull a branch
  $ hg -R hgrepo pull -r beta
  pulling from $TESTTMP/gitrepo
  importing 1 git commits
  adding bookmark beta
  new changesets 7fe02317c63d (1 drafts)
  (run 'hg update' to get a working copy)
  $ hg -R hgrepo log --graph --template=phases
  o  changeset:   1:7fe02317c63d
  |  bookmark:    beta
  |  tag:         default/beta
  |  tag:         tip
  |  phase:       draft
  |  user:        test <test@example.org>
  |  date:        Mon Jan 01 00:00:11 2007 +0000
  |  summary:     add beta
  |
  @  changeset:   0:ff7a2f2d8d70
     bookmark:    epsilon
     bookmark:    master
     tag:         default/epsilon
     tag:         default/master
     tag:         t_alpha
     phase:       draft
     user:        test <test@example.org>
     date:        Mon Jan 01 00:00:10 2007 +0000
     summary:     add alpha
  

no-op pull should affect phases
  $ hg -R hgrepo phase -fs beta
  $ hg -R hgrepo pull -r beta
  pulling from $TESTTMP/gitrepo
  no changes found
  $ hg -R hgrepo phase beta
  1: draft


add another commit and tag to the git repo
  $ cd gitrepo
  $ git checkout -q beta
  $ git tag t_beta
  $ git checkout -q master
  $ echo gamma > gamma
  $ git add gamma
  $ fn_git_commit -m 'add gamma'
  $ cd ..

pull everything else
  $ hg -R hgrepo pull
  pulling from $TESTTMP/gitrepo
  importing 2 git commits
  adding bookmark delta
  updating bookmark master
  new changesets 678ebee93e38:6f898ad1f3e1 (2 drafts)
  (run 'hg heads' to see heads, 'hg merge' to merge)
  $ hg -R hgrepo log --graph --template=phases
  o  changeset:   3:6f898ad1f3e1
  |  bookmark:    master
  |  tag:         default/master
  |  tag:         tip
  |  phase:       draft
  |  parent:      0:ff7a2f2d8d70
  |  user:        test <test@example.org>
  |  date:        Mon Jan 01 00:00:13 2007 +0000
  |  summary:     add gamma
  |
  | o  changeset:   2:678ebee93e38
  |/   bookmark:    delta
  |    tag:         default/delta
  |    phase:       draft
  |    parent:      0:ff7a2f2d8d70
  |    user:        test <test@example.org>
  |    date:        Mon Jan 01 00:00:12 2007 +0000
  |    summary:     add delta
  |
  | o  changeset:   1:7fe02317c63d
  |/   bookmark:    beta
  |    tag:         default/beta
  |    tag:         t_beta
  |    phase:       draft
  |    user:        test <test@example.org>
  |    date:        Mon Jan 01 00:00:11 2007 +0000
  |    summary:     add beta
  |
  @  changeset:   0:ff7a2f2d8d70
     bookmark:    epsilon
     tag:         default/epsilon
     tag:         t_alpha
     phase:       draft
     user:        test <test@example.org>
     date:        Mon Jan 01 00:00:10 2007 +0000
     summary:     add alpha
  
add a merge to the git repo, and delete the branch
  $ cd gitrepo
  $ git merge -q -m "Merge branch 'beta'" beta
  $ git show --oneline
  8642e88 Merge branch 'beta'
  
  $ git branch -d beta
  Deleted branch beta (was 9497a4e).
  $ cd ..

pull the merge
  $ hg -R hgrepo tags | grep default/beta
  default/beta                       1:7fe02317c63d
  $ hg -R hgrepo pull --config git.pull-prune-remote-branches=false
  pulling from $TESTTMP/gitrepo
  importing 1 git commits
  updating bookmark master
  deleting bookmark beta
  new changesets a02330f767a4 (1 drafts)
  (run 'hg update' to get a working copy)
  $ hg -R hgrepo tags | grep default/beta
  default/beta                       1:7fe02317c63d
  $ hg -R hgrepo pull
  pulling from $TESTTMP/gitrepo
  no changes found
  $ hg -R hgrepo tags | grep default/beta
  [1]
  $ hg -R hgrepo log --graph
  o    changeset:   4:a02330f767a4
  |\   bookmark:    master
  | |  tag:         default/master
  | |  tag:         tip
  | |  parent:      3:6f898ad1f3e1
  | |  parent:      1:7fe02317c63d
  | |  user:        test <test@example.org>
  | |  date:        Mon Jan 01 00:00:13 2007 +0000
  | |  summary:     Merge branch 'beta'
  | |
  | o  changeset:   3:6f898ad1f3e1
  | |  parent:      0:ff7a2f2d8d70
  | |  user:        test <test@example.org>
  | |  date:        Mon Jan 01 00:00:13 2007 +0000
  | |  summary:     add gamma
  | |
  | | o  changeset:   2:678ebee93e38
  | |/   bookmark:    delta
  | |    tag:         default/delta
  | |    parent:      0:ff7a2f2d8d70
  | |    user:        test <test@example.org>
  | |    date:        Mon Jan 01 00:00:12 2007 +0000
  | |    summary:     add delta
  | |
  o |  changeset:   1:7fe02317c63d
  |/   tag:         t_beta
  |    user:        test <test@example.org>
  |    date:        Mon Jan 01 00:00:11 2007 +0000
  |    summary:     add beta
  |
  @  changeset:   0:ff7a2f2d8d70
     bookmark:    epsilon
     tag:         default/epsilon
     tag:         t_alpha
     user:        test <test@example.org>
     date:        Mon Jan 01 00:00:10 2007 +0000
     summary:     add alpha
  
pull with wildcards
  $ cd gitrepo
  $ git checkout -qb releases/v1 master
  $ echo zeta > zeta
  $ git add zeta
  $ fn_git_commit -m 'add zeta'
  $ git checkout -qb releases/v2 master
  $ echo eta > eta
  $ git add eta
  $ fn_git_commit -m 'add eta'
  $ git checkout -qb notreleases/v1 master
  $ echo theta > theta
  $ git add theta
  $ fn_git_commit -m 'add theta'

ensure that releases/v1 and releases/v2 are pulled but not notreleases/v1
  $ cd ..
  $ hg -R hgrepo pull -r 'releases/*'
  pulling from $TESTTMP/gitrepo
  importing 2 git commits
  adding bookmark releases/v1
  adding bookmark releases/v2
  new changesets 218b2d0660d3:a3f95e150b0a (2 drafts)
  (run 'hg heads .' to see heads, 'hg merge' to merge)
  $ hg -R hgrepo log --graph
  o  changeset:   6:a3f95e150b0a
  |  bookmark:    releases/v2
  |  tag:         default/releases/v2
  |  tag:         tip
  |  parent:      4:a02330f767a4
  |  user:        test <test@example.org>
  |  date:        Mon Jan 01 00:00:15 2007 +0000
  |  summary:     add eta
  |
  | o  changeset:   5:218b2d0660d3
  |/   bookmark:    releases/v1
  |    tag:         default/releases/v1
  |    user:        test <test@example.org>
  |    date:        Mon Jan 01 00:00:14 2007 +0000
  |    summary:     add zeta
  |
  o    changeset:   4:a02330f767a4
  |\   bookmark:    master
  | |  tag:         default/master
  | |  parent:      3:6f898ad1f3e1
  | |  parent:      1:7fe02317c63d
  | |  user:        test <test@example.org>
  | |  date:        Mon Jan 01 00:00:13 2007 +0000
  | |  summary:     Merge branch 'beta'
  | |
  | o  changeset:   3:6f898ad1f3e1
  | |  parent:      0:ff7a2f2d8d70
  | |  user:        test <test@example.org>
  | |  date:        Mon Jan 01 00:00:13 2007 +0000
  | |  summary:     add gamma
  | |
  | | o  changeset:   2:678ebee93e38
  | |/   bookmark:    delta
  | |    tag:         default/delta
  | |    parent:      0:ff7a2f2d8d70
  | |    user:        test <test@example.org>
  | |    date:        Mon Jan 01 00:00:12 2007 +0000
  | |    summary:     add delta
  | |
  o |  changeset:   1:7fe02317c63d
  |/   tag:         t_beta
  |    user:        test <test@example.org>
  |    date:        Mon Jan 01 00:00:11 2007 +0000
  |    summary:     add beta
  |
  @  changeset:   0:ff7a2f2d8d70
     bookmark:    epsilon
     tag:         default/epsilon
     tag:         t_alpha
     user:        test <test@example.org>
     date:        Mon Jan 01 00:00:10 2007 +0000
     summary:     add alpha
  

add old and new commits to the git repo -- make sure we're using the commit date
and not the author date
  $ cat >> $HGRCPATH <<EOF
  > [git]
  > mindate = 2014-01-02 00:00:00 +0000
  > EOF
  $ cd gitrepo
  $ git checkout -q master
  $ echo oldcommit > oldcommit
  $ git add oldcommit
  $ GIT_AUTHOR_DATE="2014-03-01 00:00:00 +0000" \
  > GIT_COMMITTER_DATE="2009-01-01 00:00:00 +0000" \
  > git commit -m oldcommit > /dev/null || echo "git commit error"
also add an annotated tag
  $ git checkout -q master^
  $ echo oldtag > oldtag
  $ git add oldtag
  $ GIT_AUTHOR_DATE="2014-03-01 00:00:00 +0000" \
  > GIT_COMMITTER_DATE="2009-01-01 00:00:00 +0000" \
  > git commit -m oldtag > /dev/null || echo "git commit error"
  $ GIT_COMMITTER_DATE="2009-02-01 00:00:00 +0000" \
  > git tag -a -m 'tagging oldtag' oldtag
  $ cd ..

Master is now filtered, so it's just stays there:

  $ hg -R hgrepo pull --config git.pull-prune-bookmarks=no
  pulling from $TESTTMP/gitrepo
  no changes found
  $ hg -R hgrepo pull
  pulling from $TESTTMP/gitrepo
  no changes found
  $ hg -R hgrepo log -r master
  changeset:   4:a02330f767a4
  bookmark:    master
  tag:         default/master
  parent:      3:6f898ad1f3e1
  parent:      1:7fe02317c63d
  user:        test <test@example.org>
  date:        Mon Jan 01 00:00:13 2007 +0000
  summary:     Merge branch 'beta'
  

  $ cd gitrepo
  $ git checkout -q master
  $ echo newcommit > newcommit
  $ git add newcommit
  $ GIT_AUTHOR_DATE="2014-01-01 00:00:00 +0000" \
  > GIT_COMMITTER_DATE="2014-01-02 00:00:00 +0000" \
  > git commit -m newcommit > /dev/null || echo "git commit error"
  $ git checkout -q refs/tags/oldtag
  $ GIT_COMMITTER_DATE="2014-01-02 00:00:00 +0000" \
  > git tag -a -m 'tagging newtag' newtag
  $ cd ..
  $ hg -R hgrepo pull
  pulling from $TESTTMP/gitrepo
  importing 3 git commits
  updating bookmark master
  new changesets 49713da8f665:e103a73f33be (3 drafts)
  (run 'hg heads .' to see heads, 'hg merge' to merge)
  $ hg -R hgrepo heads
  changeset:   9:e103a73f33be
  bookmark:    master
  tag:         default/master
  tag:         tip
  user:        test <test@example.org>
  date:        Wed Jan 01 00:00:00 2014 +0000
  summary:     newcommit
  
  changeset:   7:49713da8f665
  tag:         newtag
  tag:         oldtag
  parent:      4:a02330f767a4
  user:        test <test@example.org>
  date:        Sat Mar 01 00:00:00 2014 +0000
  summary:     oldtag
  
  changeset:   6:a3f95e150b0a
  bookmark:    releases/v2
  tag:         default/releases/v2
  parent:      4:a02330f767a4
  user:        test <test@example.org>
  date:        Mon Jan 01 00:00:15 2007 +0000
  summary:     add eta
  
  changeset:   5:218b2d0660d3
  bookmark:    releases/v1
  tag:         default/releases/v1
  user:        test <test@example.org>
  date:        Mon Jan 01 00:00:14 2007 +0000
  summary:     add zeta
  
  changeset:   2:678ebee93e38
  bookmark:    delta
  tag:         default/delta
  parent:      0:ff7a2f2d8d70
  user:        test <test@example.org>
  date:        Mon Jan 01 00:00:12 2007 +0000
  summary:     add delta
  

test for ssh vulnerability

  $ cat >> $HGRCPATH << EOF
  > [ui]
  > ssh = ssh -o ConnectTimeout=1
  > EOF

  $ hg init a
  $ cd a
  $ hg pull -q 'git+ssh://-oProxyCommand=rm${IFS}nonexistent/path'
  abort: potentially unsafe hostname: '-oProxyCommand=rm${IFS}nonexistent'
  [255]
  $ hg pull -q 'git+ssh://-oProxyCommand=rm%20nonexistent/path'
  abort: potentially unsafe hostname: '-oProxyCommand=rm nonexistent'
  [255]
  $ hg pull -q 'git+ssh://fakehost|shellcommand/path'
  ssh: * fakehost%7?shellcommand* (glob)
  abort: git remote error: The remote server unexpectedly closed the connection.
  [255]
  $ hg pull -q 'git+ssh://fakehost%7Cshellcommand/path'
  ssh: * fakehost%7?shellcommand* (glob)
  abort: git remote error: The remote server unexpectedly closed the connection.
  [255]
