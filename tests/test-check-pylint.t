#require test-repo pylint hg10

Run pylint for known rules we care about.
-----------------------------------------

There should be no recorded failures; fix the codebase before introducing a
new check.

Current checks:
- W0102: no mutable default argument
- C0321: more than one statement on a single line

Unique to hg-git:
- W1401: anomalous backslash in string
- W1402: anomalous unicode escape in string

  $ touch $TESTTMP/fakerc
  $ $PYTHON -m pylint --rcfile=$TESTTMP/fakerc --disable=all \
  >   --enable=W0102,C0321,W1401,W1402 \
  >   --reports=no \
  >   $TESTDIR/../hggit | sed 's/\r$//'
  Using config file *fakerc (glob) (?)
   (?)
  ------------------------------------* (glob) (?)
  Your code has been rated at 10.00/10* (glob) (?)
   (?)
