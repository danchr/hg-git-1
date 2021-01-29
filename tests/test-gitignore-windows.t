#require windows

Load commonly used test logic
  $ . "$TESTDIR/testutil"

Even though its documentation says otherwise, Git does accept \ in
.gitignore

  $ hg init repo
  $ cd repo
  $ touch thefile
  $ hg ci -qAm thefile
  $ hg gexport

  $ touch ignored-file
  $ mkdir ignored-dir
  $ touch ignored-dir/also-ignored-file
  $ hg status
  ? ignored-dir/also-ignored-file
  ? ignored-file
  $ cat >> .gitignore <<EOF
  > \ignored-file
  > ignored-dir\\
  > \.directory
  > EOF
  $ hg status
  ? .gitignore
