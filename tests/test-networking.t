Load commonly used test logic
  $ . "$TESTDIR/testutil"

We assume the git server is unavailable elsewhere.

  $ if test -z "$CI_TEST_GIT_NETWORKING"
  > then
  >   echo 'requires CI networking'
  >   exit 80
  > fi

Allow password prompts without a TTY:

  $ cat << EOF > get_pass.py
  > from __future__ import print_function, absolute_import
  > import getpass, os, sys
  > def newgetpass(args):
  >     try:
  >       passwd = os.environb.get(b'PASSWD', b'nope')
  >       print(passwd.encode())
  >     except AttributeError: # python 2.7
  >       passwd = os.environ.get('PASSWD', 'nope')
  >       print(passwd)
  >     sys.stdout.flush()
  >     return passwd
  > getpass.getpass = newgetpass
  > EOF
  $ cat >> $HGRCPATH << EOF
  > [extensions]
  > getpass = $TESTTMP/get_pass.py
  > EOF

Create a silly SSH configuration:

  $ cat >> $HGRCPATH << EOF
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

  $ hg clone http://git-server/repo.git repo-http
  abort: http authorization required for http://git-server/repo.git
  [255]
  $ hg clone --config ui.interactive=yes \
  >    --config ui.interactive=yes \
  >    --config auth.git.prefix=http://git-server \
  >    --config auth.git.username=git \
  >    http://git-server/repo.git repo-http
  http authorization required for http://git-server/repo.git
  realm: Git (no-dulwich0203 !)
  realm: Git Access (dulwich0203 !)
  user: git
  password: nope
  abort: authorization failed
  [255]
  $ PASSWD=git hg clone --config ui.interactive=yes \
  >          http://git-server/repo.git repo-http <<EOF
  > git
  > EOF
  http authorization required for http://git-server/repo.git
  realm: Git (no-dulwich0203 !)
  realm: Git Access (dulwich0203 !)
  user: git
  password: git
  updating to branch default
  0 files updated, 0 files merged, 0 files removed, 0 files unresolved

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
  $ hg path default
  git@git-server:/srv/repo.git
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
  importing git objects into hg
  1 files updated, 0 files merged, 0 files removed, 0 files unresolved

#if dulwich0200
Try using git credentials, only supported on Dulwich 0.20+

NB: the use of printf is deliberate; otherwise the test fails due to
dulwich considering the newline part of the url

  $ printf http://git:git@git-server > $TESTTMP/.git-credentials
  $ hg -R repo-http pull
  pulling from http://git-server/repo.git
  no changes found
  $ rm -f $TESTTMP/.git-credentials
#endif
