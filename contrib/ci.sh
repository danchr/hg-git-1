#!/bin/sh

set -x

exec python$PYTHON tests/run-tests.py \
     --verbose --color=always \
     --xunit $PWD/tests-$PYTHON-$HG.xml
