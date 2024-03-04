Load commonly used test logic
  $ . "$TESTDIR/testutil"

  $ hg init test
  $ cd test
  $ cat >>afile <<EOF
  > 0
  > EOF
  $ hg add afile
  $ fn_hg_commit -m "0.0"
  $ cat >>afile <<EOF
  > 1
  > EOF
  $ fn_hg_commit -m "0.1"
  $ cat >>afile <<EOF
  > 2
  > EOF
  $ fn_hg_commit -m "0.2"
  $ cat >>afile <<EOF
  > 3
  > EOF
  $ fn_hg_commit -m "0.3"
  $ hg update -C 0
  1 files updated, 0 files merged, 0 files removed, 0 files unresolved
  $ cat >>afile <<EOF
  > 1
  > EOF
  $ fn_hg_commit -m "1.1"
  $ cat >>afile <<EOF
  > 2
  > EOF
  $ fn_hg_commit -m "1.2"
  $ cat >fred <<EOF
  > a line
  > EOF
  $ cat >>afile <<EOF
  > 3
  > EOF
  $ hg add fred
  $ fn_hg_commit -m "1.3"
  $ hg mv afile adifferentfile
  $ fn_hg_commit -m "1.3m"
  $ hg update -C 3
  1 files updated, 0 files merged, 2 files removed, 0 files unresolved
  $ hg mv afile anotherfile
  $ fn_hg_commit -m "0.3m"
  $ cd ..
  $ for i in 0 1 2 3 4 5 6 7 8; do
  >    mkdir test-"$i"
  >    hg --cwd test-"$i" init
  >    hg -R test push -r "$i" test-"$i"
  >    cd test-"$i"
  >    hg verify
  >    cd ..
  > done
  pushing to test-0
  searching for changes
  adding changesets
  adding manifests
  adding file changes
  added 1 changesets with 1 changes to 1 files
  checking changesets
  checking manifests
  crosschecking files in changesets and manifests
  checking files
  checking dirstate (?)
  checked 1 changesets with 1 changes to 1 files
  pushing to test-1
  searching for changes
  adding changesets
  adding manifests
  adding file changes
  added 2 changesets with 2 changes to 1 files
  checking changesets
  checking manifests
  crosschecking files in changesets and manifests
  checking files
  checking dirstate (?)
  checked 2 changesets with 2 changes to 1 files
  pushing to test-2
  searching for changes
  adding changesets
  adding manifests
  adding file changes
  added 3 changesets with 3 changes to 1 files
  checking changesets
  checking manifests
  crosschecking files in changesets and manifests
  checking files
  checking dirstate (?)
  checked 3 changesets with 3 changes to 1 files
  pushing to test-3
  searching for changes
  adding changesets
  adding manifests
  adding file changes
  added 4 changesets with 4 changes to 1 files
  checking changesets
  checking manifests
  crosschecking files in changesets and manifests
  checking files
  checking dirstate (?)
  checked 4 changesets with 4 changes to 1 files
  pushing to test-4
  searching for changes
  adding changesets
  adding manifests
  adding file changes
  added 2 changesets with 2 changes to 1 files
  checking changesets
  checking manifests
  crosschecking files in changesets and manifests
  checking files
  checking dirstate (?)
  checked 2 changesets with 2 changes to 1 files
  pushing to test-5
  searching for changes
  adding changesets
  adding manifests
  adding file changes
  added 3 changesets with 3 changes to 1 files
  checking changesets
  checking manifests
  crosschecking files in changesets and manifests
  checking files
  checking dirstate (?)
  checked 3 changesets with 3 changes to 1 files
  pushing to test-6
  searching for changes
  adding changesets
  adding manifests
  adding file changes
  added 4 changesets with 5 changes to 2 files
  checking changesets
  checking manifests
  crosschecking files in changesets and manifests
  checking files
  checking dirstate (?)
  checked 4 changesets with 5 changes to 2 files
  pushing to test-7
  searching for changes
  adding changesets
  adding manifests
  adding file changes
  added 5 changesets with 6 changes to 3 files
  checking changesets
  checking manifests
  crosschecking files in changesets and manifests
  checking files
  checking dirstate (?)
  checked 5 changesets with 6 changes to 3 files
  pushing to test-8
  searching for changes
  adding changesets
  adding manifests
  adding file changes
  added 5 changesets with 5 changes to 2 files
  checking changesets
  checking manifests
  crosschecking files in changesets and manifests
  checking files
  checking dirstate (?)
  checked 5 changesets with 5 changes to 2 files
  $ cd test-8
  $ hg pull ../test-7
  pulling from ../test-7
  searching for changes
  adding changesets
  adding manifests
  adding file changes
  added 4 changesets with 2 changes to 3 files (+1 heads)
  new changesets c29287bce33f:e70c8671c3d4 (?)
  (run 'hg heads' to see heads, 'hg merge' to merge)
  $ hg verify
  checking changesets
  checking manifests
  crosschecking files in changesets and manifests
  checking files
  checking dirstate (?)
  checked 9 changesets with 7 changes to 4 files
