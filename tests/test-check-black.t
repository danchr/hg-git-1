#require test-repo black hg10

Load commonly used test logic
  $ . "$TESTDIR/testutil"
  $ . "$TESTDIR/helpers-testrepo.sh"

run black on all tracked files ending in .py or without a file ending
(skipping binary file random-seed)

black's output isn't stable:

  $ $PYTHON -c 'import black; print(black.__version__)'
  21.12b0

  $ cd "$TESTDIR"/..
  $ $PYTHON -m black --check --quiet .
