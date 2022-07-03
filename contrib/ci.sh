#!/bin/sh

set -x

git version
hg debuginstall --config extensions.hggit=./hggit
hg version -v --config extensions.hggit=./hggit

exec python$PYTHON tests/run-tests.py \
     --color=always \
     --cover \
     --xunit $PWD/tests-$CI_JOB_ID.xml
