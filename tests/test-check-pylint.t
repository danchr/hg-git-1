#require test-repo pylint hg10

Run pylint for known rules we care about.
-----------------------------------------

There should be no recorded failures; fix the codebase before introducing a
new check.

See the rc file for a list of checks.

  $ $PYTHON -m pylint --rcfile=$TESTDIR/../pyproject.toml \
  >   $TESTDIR/../hggit | sed 's/\r$//'
  Using config file *pyproject.toml (glob) (?)
   (?)
  ------------------------------------* (glob) (?)
  Your code has been rated at 10.00/10* (glob) (?)
   (?)
