Load commonly used test logic
  $ . "$TESTDIR/testutil"

Create a Git repository

  $ git init -q --bare repo.git

Create a Mercurial repository

  $ hg clone repo.git hgrepo
  updating to branch default
  0 files updated, 0 files merged, 0 files removed, 0 files unresolved
  $ cd hgrepo
  $ hg book master

Configure an author map

  $ touch authors.txt
  $ cat >> $HGRCPATH <<EOF
  > [git]
  > authors = $TESTTMP/authors.txt
  > EOF

Create a commit user that maps to a fully valid user

  $ cat >> $TESTTMP/authors.txt <<EOF
  > user1 = User no. 1 <user1@example.com>
  > EOF
  $ touch alpha
  $ hg add alpha
  $ fn_hg_commit -m alpha -u user1

And one that maps to an email address

  $ cat >> $TESTTMP/authors.txt <<EOF
  > user2@example.com = user2
  > EOF
  $ touch beta
  $ hg add beta
  $ fn_hg_commit -m beta -u user2@example.com

And one that maps to a "simple" user

  $ cat >> $TESTTMP/authors.txt <<EOF
  > User #3 <user3@example.com> = user3@example.com
  > EOF
  $ touch gamma
  $ hg add gamma
  $ fn_hg_commit -m gamma -u "User #3 <user3@example.com>"

And one that maps to nothing

  $ cat >> $TESTTMP/authors.txt <<EOF
  > user4 =
  > EOF
  $ touch delta
  $ hg add delta
  $ fn_hg_commit -m delta -u user4

And one that doesn't map

  $ touch epsilon
  $ hg add epsilon
  $ fn_hg_commit -m epsilon -u "User #5 <user5@example.com>"

Check the test default

  $ touch zeta
  $ hg add zeta
  $ fn_hg_commit -m zeta

Push it!

  $ hg push
  pushing to $TESTTMP/repo.git
  searching for changes
  adding objects
  remote: found 0 deltas to reuse (dulwich0210 !)
  added 6 commits with 6 trees and 1 blobs
  adding reference refs/heads/master

Check the results:

  $ hg log --template='Commit: {gitnode}\nAuthor: {author}\n---\n'
  Commit: 869e310765d5d7ad92f83bf036e12b0341922a65
  Author: test
  ---
  Commit: b5c0fcb75f876b158ece64859400d36b07570ce9
  Author: User #5 <user5@example.com>
  ---
  Commit: 2833824a870810915f7a7a27c05cccad0448bfd7
  Author: user4
  ---
  Commit: fe63bf29ef0bd4af50e85b8aec8d2fbeff255845
  Author: User #3 <user3@example.com>
  ---
  Commit: eba936dd13172a2f17936785e3604845aed9170d
  Author: user2@example.com
  ---
  Commit: 796162e5747a7ba57f31fb828b88319caf7b1f7b
  Author: user1
  ---
  $ cd ../repo.git
  $ cat $TESTTMP/authors.txt
  user1 = User no. 1 <user1@example.com>
  user2@example.com = user2
  User #3 <user3@example.com> = user3@example.com
  user4 =
  $ git log --pretty='tformat:Commit: %H%nAuthor:    %an <%ae>%nCommitter: %cn <%ce>%n---'
  Commit: 869e310765d5d7ad92f83bf036e12b0341922a65
  Author:    test <none@none>
  Committer: test <none@none>
  ---
  Commit: b5c0fcb75f876b158ece64859400d36b07570ce9
  Author:    User #5 <user5@example.com>
  Committer: User #5 <user5@example.com>
  ---
  Commit: 2833824a870810915f7a7a27c05cccad0448bfd7
  Author:     <none@none>
  Committer:  <none@none>
  ---
  Commit: fe63bf29ef0bd4af50e85b8aec8d2fbeff255845
  Author:    user3@example.com <user3@example.com>
  Committer: user3@example.com <user3@example.com>
  ---
  Commit: eba936dd13172a2f17936785e3604845aed9170d
  Author:    user2 <none@none>
  Committer: user2 <none@none>
  ---
  Commit: 796162e5747a7ba57f31fb828b88319caf7b1f7b
  Author:    User no. 1 <user1@example.com>
  Committer: User no. 1 <user1@example.com>
  ---
  $ cd ..
