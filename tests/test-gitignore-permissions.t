  $ python -c 'from mercurial.dirstate import rootcache' || exit 80

Load commonly used test logic
  $ . "$TESTDIR/testutil"

  $ hg init

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

This fails on Python 3:

  $ hg status 2>&1 | tail -n 1
  TypeError: %b requires a bytes-like object, or an object that implements __bytes__, not 'str'
