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

  $ cd ..

  $ hg clone gitrepo hgrepo
  importing 2 git commits
  new changesets ff7a2f2d8d70:7fe02317c63d (2 drafts)
  updating to bookmark master
  2 files updated, 0 files merged, 0 files removed, 0 files unresolved
  $ hg -R hgrepo log --graph
  @  changeset:   1:7fe02317c63d
  |  bookmark:    master
  |  tag:         default/master
  |  tag:         tip
  |  user:        test <test@example.org>
  |  date:        Mon Jan 01 00:00:11 2007 +0000
  |  summary:     add beta
  |
  o  changeset:   0:ff7a2f2d8d70
     user:        test <test@example.org>
     date:        Mon Jan 01 00:00:10 2007 +0000
     summary:     add alpha
  

we should have some bookmarks
  $ hg -R hgrepo book
   * master                    1:7fe02317c63d
  $ hg -R hgrepo gverify
  verifying rev 7fe02317c63d against git commit 9497a4ee62e16ee641860d7677cdb2589ea15554

test for ssh vulnerability

  $ cat >> $HGRCPATH << EOF
  > [ui]
  > ssh = ssh -o ConnectTimeout=1
  > EOF

  $ hg clone -q 'git+ssh://-oProxyCommand=rm${IFS}nonexistent/path'
  abort: potentially unsafe hostname: '-oProxyCommand=rm${IFS}nonexistent'
  [255]
  $ hg clone -q 'git+ssh://%2DoProxyCommand=rm${IFS}nonexistent/path'
  abort: potentially unsafe hostname: '-oProxyCommand=rm${IFS}nonexistent'
  [255]
  $ hg clone -q 'git+ssh://fakehost|rm${IFS}nonexistent/path'
  ssh: * fakehost%7?rm%24%7????%7?nonexistent* (glob)
  abort: git remote error: The remote server unexpectedly closed the connection.
  [255]
  $ hg clone -q 'git+ssh://fakehost%7Crm${IFS}nonexistent/path'
  ssh: * fakehost%7?rm%24%7????%7?nonexistent* (glob)
  abort: git remote error: The remote server unexpectedly closed the connection.
  [255]
