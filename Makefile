PYTHON=python
HG=$(shell which hg)
HGPYTHON=$(shell $(HG) debuginstall -T '{pythonexe}')
TESTFLAGS ?= $(shell echo $$HGTESTFLAGS)

help:
	@echo 'Commonly used make targets:'
	@echo '  tests              - run all tests in the automatic test suite'
	@echo '  all-version-tests  - run all tests against many hg versions'
	@echo '  tests-%s           - run all tests in the specified hg version'

all: help

tests:
	cd tests && $(HGPYTHON) run-tests.py --with-hg=$(HG) $(TESTFLAGS)

test-%:
	@+$(MAKE) tests TESTFLAGS="$(strip $(TESTFLAGS) $@)"

release:
	$(PYTHON) setup.py sdist

.PHONY: help all tests release
