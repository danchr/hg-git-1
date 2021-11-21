#!/bin/sh

set -x

pip install coverage pygments

exec python$PYTHON tests/run-tests.py \
     --verbose --color=always \
     --cover \
     --xunit $PWD/tests-$CI_JOB_ID.xml
