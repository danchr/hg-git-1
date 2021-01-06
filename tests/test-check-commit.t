#require test-repo py3

Load commonly used test logic
  $ . "$TESTDIR/testutil"

Enable obsolescence to avoid the warning issue when obsmarker are found

  $ . "$TESTDIR/helpers-testrepo.sh"

We might be running the tests as a different user than checked out the
code

  $ cat >> $HGRCPATH <<EOF
  > [trusted]
  > users = *
  > groups = *
  > EOF

Go back in the hg repo

  $ cd $TESTDIR/..

  $ REVSET='not public() and ::. and not desc("# no-check-commit")'

  $ mkdir "$TESTTMP/p"
  $ REVS=`testrepohg log -r "$REVSET" -T.`
  $ if [ -n "$REVS" ] ; then
  >   testrepohg export --git -o "$TESTTMP/p/%n-%h" -r "$REVSET"
  >   for f in `ls "$TESTTMP/p"`; do
  >      contrib/check-commit < "$TESTTMP/p/$f" > "$TESTTMP/check-commit.out"
  >      if [ $? -ne 0 ]; then
  >          node="${f##*-}"
  >          echo "Revision $node does not comply with rules"
  >          echo '------------------------------------------------------'
  >          cat ${TESTTMP}/check-commit.out
  >          echo
  >     fi
  >   done
  > fi
