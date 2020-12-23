Load commonly used test logic
  $ . "$TESTDIR/testutil"

We assume the git server is unavailable elsewhere.

  $ if test -z "$CI_TEST_GIT_NETWORKING"
  > then
  >   echo 'requires CI networking'
  >   exit 80
  > fi

Create a silly SSH configuration:

  $ cat >> $HGRCPATH << EOF
  > [auth]
  > # alas, not supported :(
  > git.prefix = http://git-server/
  > git.username = git
  > git.password = git
  > [ui]
  > ssh = ssh -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no -i $TESTTMP/id_ed25519
  > EOF
  $ cp $RUNTESTDIR/../contrib/docker/git-server/ssh/id_ed25519 $TESTTMP
  $ chmod 0600 $TESTTMP/id_ed25519

Clone using the git protocol:

  $ hg clone git://git-server/repo.git repo-git
  updating to branch default
  0 files updated, 0 files merged, 0 files removed, 0 files unresolved

..and HTTP:

  $ hg clone http://git:git@git-server/repo.git repo-http
  updating to branch default
  0 files updated, 0 files merged, 0 files removed, 0 files unresolved

Fix up authentication:
  $ cat > repo-http/.hg/hgrc <<EOF
  > [paths]
  > default = http://git:git@git-server/repo.git
  > EOF

..and finally SSH:

  $ hg clone git@git-server:/srv/repo.git repo-ssh
  Warning: Permanently added * (glob)
  updating to branch default
  0 files updated, 0 files merged, 0 files removed, 0 files unresolved

So, that went well; now push...

  $ cd repo-ssh
  $ echo thefile > thefile
  $ hg add thefile
  $ fn_hg_commit -m 'add the file'
  $ hg book -r tip master
  $ hg push
  Warning: Permanently added * (glob) (?)
  pushing to git@git-server:/srv/repo.git
  Warning: Permanently added * (glob) (?)
  searching for changes
  adding objects
  added 1 commits with 1 trees and 1 blobs
  adding reference refs/heads/master
  $ cd ..

And finally, pull the new commit:

  $ hg -R repo-git pull -u
  pulling from git://git-server/repo.git
  importing git objects into hg
  1 files updated, 0 files merged, 0 files removed, 0 files unresolved
  $ hg -R repo-http pull -u
  pulling from http://git:***@git-server/repo.git
  importing git objects into hg
  1 files updated, 0 files merged, 0 files removed, 0 files unresolved
