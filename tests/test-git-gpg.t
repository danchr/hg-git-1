#require gpg

Load commonly used test logic
  $ . "$TESTDIR/testutil"

  $ export GNUPGHOME="$(mktemp -d)"
  $ cp -R "$TESTDIR"/gpg/* "$GNUPGHOME"

Start gpg-agent, which is required by GnuPG v2

#if gpg21
  $ gpg-connect-agent -q --subst /serverpid '/echo ${get serverpid}' /bye \
  > >> $DAEMON_PIDS
#endif

and migrate secret keys

#if gpg2
  $ gpg --no-permission-warning --no-secmem-warning --list-secret-keys \
  > > /dev/null 2>&1
#endif

  $ alias gpg='gpg --no-permission-warning --no-secmem-warning --no-auto-check-trustdb'

Set up two identical git repos.

  $ mkdir gitrepo
  $ cd gitrepo
  $ git init
  Initialized empty Git repository in $TESTTMP/gitrepo/.git/
  $ touch a
  $ git add a
  $ git commit -m "initial commit"
  [master (root-commit) *] initial commit (glob)
   1 file changed, 0 insertions(+), 0 deletions(-)
   create mode 100644 a
  $ cd ..
  $ git clone gitrepo gitrepo2
  Cloning into 'gitrepo2'...
  done.

Add a signed commit to the first clone.

  $ cd gitrepo
  $ git checkout -b signed
  Switched to a new branch 'signed'
  $ touch b
  $ git add b
  $ git commit -m "message" -Shgtest
  [signed *] message (glob)
   1 file changed, 0 insertions(+), 0 deletions(-)
   create mode 100644 b
  $ cd ..

Hg clone it

  $ hg clone gitrepo hgrepo
  importing 2 git commits
  new changesets ab60c5e55bd6:[0-9a-f]{12,12} \(2 drafts\) (re)
  updating to bookmark signed
  2 files updated, 0 files merged, 0 files removed, 0 files unresolved

  $ cd hgrepo
  $ hg push ../gitrepo2 -B signed
  pushing to ../gitrepo2
  searching for changes
  adding objects
  remote: found 0 deltas to reuse (dulwich0210 !)
  added 1 commits with 1 trees and 0 blobs
  adding reference refs/heads/signed
  $ cd ..

Verify the commit

  $ cd gitrepo2
  $ git show --show-signature signed | grep "Good signature from"
  gpg: Good signature from "hgtest" [ultimate]
