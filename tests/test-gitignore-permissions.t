#require no-windows

Load commonly used test logic
  $ . "$TESTDIR/testutil"

  $ hg init repo
  $ cd repo

  $ if test `whoami` = root
  > then
  >   echo "skipped: must run as unprivileged user, not root"
  >   exit 80
  > fi

Create a commit and export it to Git

  $ touch thefile
  $ hg add thefile
  $ hg ci -A -m commit
  $ hg gexport

Create a file that we can ignore

  $ touch nothingtoseehere

And something we can't read

  $ mkdir not_readable
  $ chmod 000 not_readable

Add a .gitignore, and to make sure that we're using it, make it ignore
something.

  $ echo nothingtoseehere > .gitignore
  $ hg status
  not_readable: Permission denied
  not_readable: Permission denied
  ? .gitignore

And notice that we really did ignore it!

For comparison, how does a normal status handle this?

  $ hg status --config extensions.hggit=!
  not_readable: Permission denied
  ? .gitignore
  ? nothingtoseehere

So the duplicated output is actually a bug...
