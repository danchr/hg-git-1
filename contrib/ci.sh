#!/bin/sh

set -x

exec python$PYTHON tests/run-tests.py \
     --color=always \
     --cover \
     --xunit $PWD/tests-$CI_JOB_ID.xml
