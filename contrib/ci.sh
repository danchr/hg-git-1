#!/bin/sh

set -x

exec python$PYTHON tests/run-tests.py \
     --verbose --color=always --timeout 300 \
     --xunit $PWD/tests-$PYTHON-$HG.xml
