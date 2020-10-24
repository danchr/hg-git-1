PYTHON=python
TESTFLAGS ?= $(shell echo $$HGTESTFLAGS)

help:
	@echo 'Commonly used make targets:'
	@echo '  tests              - run all tests in the automatic test suite'
	@echo '  all-version-tests  - run all tests against many hg versions'
	@echo '  tests-%s           - run all tests in the specified hg version'

all: help

tests:
	cd tests && $(PYTHON) run-tests.py --with-hg=`which hg` $(TESTFLAGS)

test-%:
	cd tests && $(PYTHON) run-tests.py --with-hg=`which hg` $(TESTFLAGS) $@

tests-%:
	@echo "Path to crew repo is $(CREW) - set this with CREW= if needed."
	hg -R $(CREW) checkout $$(echo $@ | sed s/tests-//) && \
	(cd $(CREW) ; $(MAKE) clean local) && \
	cd tests && $(PYTHON) run-tests.py --with-hg=$(CREW)/hg $(TESTFLAGS)

# This is intended to be the authoritative list of versions of
# Mercurial that this extension is tested with. Versions prior to the
# version that ships in the latest Ubuntu LTS release (2.8.2 for
# 14.04; 3.7.3 for 16.04; 4.5.3 for 18.04; 5.3.1 for 20.04) may be
# dropped if they interfere with new development. The latest released
# minor version should be listed for each major version; earlier minor
# versions are not needed.

all-version-tests: tests-4.3.3 tests-4.4.2 tests-4.5.3 tests-4.6.2 \
  tests-4.7.2 tests-4.8.2 tests-4.9.1 tests-5.0.2 tests-5.1.2 tests-5.2.2 \
  tests-5.3.2 tests-5.4.2 tests-5.5.2 tests-@

release:
	$(PYTHON) setup.py sdist

.PHONY: tests all-version-tests
