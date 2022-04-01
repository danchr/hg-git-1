#require black

run black on all sources; configuration should match development setup

  $ cd "$TESTDIR"/..
  $ $PYTHON -m black --check --quiet .
