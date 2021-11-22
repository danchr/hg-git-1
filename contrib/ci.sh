#!/bin/sh

set -x

exec python$PYTHON tests/run-tests.py \
     --verbose --color=always --timeout 300 \
     --xunit $PWD/tests-$CI_JOB_ID.xml
