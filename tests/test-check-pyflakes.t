#require test-repo pyflakes hg10

Load commonly used test logic
  $ . "$TESTDIR/testutil"
  $ . "$TESTDIR/helpers-testrepo.sh"

run pyflakes on all tracked files ending in .py or without a file ending
(skipping binary file random-seed)

  $ cat > test.py <<EOF
  > print(undefinedname)
  > EOF
  $ "$PYTHON" -m pyflakes test.py 2>/dev/null
  test.py:1:* undefined name 'undefinedname' (glob)
  [1]
  $ cd "`dirname "$TESTDIR"`"

  $ testrepohg files -I 'relglob:*.py' -I 'grep("^#!.*python*")' -X tests \
  > | xargs $PYTHON -m pyflakes 2>/dev/null
