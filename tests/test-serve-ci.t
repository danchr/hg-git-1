Load commonly used test logic
  $ . "$TESTDIR/testutil"

We assume the git server is unavailable elsewhere.

  $ if test -z "$CI_TEST_GIT_NETWORKING"
  > then
  >   echo 'requires CI networking'
  >   exit 80
  > fi

Allow password prompts without a TTY:

  $ cat >> $HGRCPATH << EOF
  > [extensions]
  > getpass = $TESTDIR/testlib/ext-get-password-from-env.py
  > EOF

Create a silly SSH configuration:

  $ cat >> $HGRCPATH << EOF
  > [ui]
  > ssh = ssh -o UserKnownHostsFile=$TESTDIR/known_hosts -o StrictHostKeyChecking=no -i $TESTTMP/id_ed25519
  > EOF
  $ cp $RUNTESTDIR/../contrib/docker/git-server/ssh/id_ed25519 $TESTTMP
  $ chmod 0600 $TESTTMP/id_ed25519

Clone using the git protocol:

  $ hg clone git://git-server/repo.git repo-git
  updating to branch default
  0 files updated, 0 files merged, 0 files removed, 0 files unresolved

..and HTTP:

  $ hg clone http://git-server/repo.git repo-http
  abort: http authorization required for http://git-server/repo.git
  [255]
  $ hg clone --config ui.interactive=yes \
  >    --config ui.interactive=yes \
  >    --config auth.git.prefix=http://git-server \
  >    --config auth.git.username=git \
  >    http://git-server/repo.git repo-http
  http authorization required for http://git-server/repo.git
  realm: Git Access
  user: git
  password: nope
  abort: authorization failed
  [255]
  $ PASSWD=git hg clone --config ui.interactive=yes \
  >          http://git-server/repo.git repo-http <<EOF
  > git
  > EOF
  http authorization required for http://git-server/repo.git
  realm: Git Access
  user: git
  password: git
  updating to branch default
  0 files updated, 0 files merged, 0 files removed, 0 files unresolved

..and finally SSH:

  $ hg clone git@git-server:/srv/repo.git repo-ssh
  Warning: Permanently added * (glob)
  updating to branch default
  0 files updated, 0 files merged, 0 files removed, 0 files unresolved

..but also try SSH with GIT_SSH_COMMAND, which we just ignore:

  $ GIT_SSH_COMMAND="ignored" \
  > hg clone git@git-server:/srv/repo.git repo-ssh-2
  updating to branch default
  0 files updated, 0 files merged, 0 files removed, 0 files unresolved
  $ rm -rf repo-ssh-2

So, that went well; now push...

  $ cd repo-ssh
  $ echo thefile > thefile
  $ hg add thefile
  $ fn_hg_commit -m 'add the file'
  $ hg book -r tip master
  $ hg path default
  git@git-server:/srv/repo.git
  $ hg push
  pushing to git@git-server:/srv/repo.git
  searching for changes
  adding objects
  remote: found 0 deltas to reuse (dulwich0210 !)
  added 1 commits with 1 trees and 1 blobs
  adding reference refs/heads/master
  $ cd ..

And finally, pull the new commit:

  $ hg -R repo-git pull -u
  pulling from git://git-server/repo.git
  remote: warning: unable to access '/root/.config/git/attributes': Permission denied
  importing 1 git commits
  adding bookmark master
  new changesets fa22339f4ab8 (1 drafts)
  1 files updated, 0 files merged, 0 files removed, 0 files unresolved

Straight HTTP doesn't work:

  $ hg -R repo-http pull -u
  pulling from http://git-server/repo.git
  abort: http authorization required for http://git-server/repo.git
  [255]

But we can specify authentication in the configuration:

  $ hg -R repo-http \
  >    --config auth.git.prefix=http://git-server \
  >    --config auth.git.username=git \
  >    --config auth.git.password=git \
  >    pull -u
  pulling from http://git-server/repo.git
  remote: warning: unable to access '/root/.config/git/attributes': Permission denied
  importing 1 git commits
  adding bookmark master
  new changesets fa22339f4ab8 (1 drafts)
  1 files updated, 0 files merged, 0 files removed, 0 files unresolved

Try using git credentials:

NB: the use of printf is deliberate; otherwise the test fails due to
dulwich considering the newline part of the url

  $ printf http://git:git@git-server > $TESTTMP/.git-credentials
  $ hg -R repo-http pull
  pulling from http://git-server/repo.git
  no changes found
  $ rm -f $TESTTMP/.git-credentials
