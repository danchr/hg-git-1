# this is hack to make sure no escape characters are inserted into the output


import doctest
import os
import re
import subprocess
import sys

# add hggit/ to sys.path
sys.path.insert(0, os.path.join(os.environ["TESTDIR"], ".."))

if 'TERM' in os.environ:
    del os.environ['TERM']


class py3docchecker(doctest.OutputChecker):
    def check_output(self, want, got, optionflags):
        want2 = re.sub(r'''\bu(['"])(.*?)\1''', r'\1\2\1', want)  # py2: u''
        got2 = re.sub(r'''\bb(['"])(.*?)\1''', r'\1\2\1', got)  # py3: b''
        # py3: <exc.name>: b'<msg>' -> <name>: <msg>
        #      <exc.name>: <others> -> <name>: <others>
        got2 = re.sub(
            r'''^mercurial\.\w+\.(\w+): (['"])(.*?)\2''',
            r'\1: \3',
            got2,
            re.MULTILINE,
        )
        got2 = re.sub(r'^mercurial\.\w+\.(\w+): ', r'\1: ', got2, re.MULTILINE)
        return any(
            doctest.OutputChecker.check_output(self, w, g, optionflags)
            for w, g in [(want, got), (want2, got2)]
        )


def testmod(name, optionflags=0, testtarget=None):
    __import__(name)
    mod = sys.modules[name]
    if testtarget is not None:
        mod = getattr(mod, testtarget)

    # minimal copy of doctest.testmod()
    finder = doctest.DocTestFinder()
    checker = py3docchecker()
    runner = doctest.DocTestRunner(checker=checker, optionflags=optionflags)
    for test in finder.find(mod, name):
        runner.run(test)
    runner.summarize()


DONT_RUN = []

# Exceptions to the defaults for a given detected module. The value for each
# module name is a list of dicts that specify the kwargs to pass to testmod.
# testmod is called once per item in the list, so an empty list will cause the
# module to not be tested.
testmod_arg_overrides = {}

fileset = 'set:(**.py)'

cwd = os.path.dirname(os.environ["TESTDIR"])

if not os.path.isdir(os.path.join(cwd, ".hg")):
    sys.exit(0)

files = subprocess.check_output(
    "hg files --print0 \"%s\"" % fileset,
    shell=True,
    cwd=cwd,
    stderr=subprocess.DEVNULL,
).split(b'\0')

if sys.version_info[0] >= 3:
    cwd = os.fsencode(cwd)

mods_tested = set()
for f in files:
    if not f:
        continue

    with open(os.path.join(cwd, f), "rb") as fh:
        if not re.search(br'\n\s*>>>', fh.read()):
            continue

    f = f.decode()

    modname = f.replace('.py', '').replace('\\', '.').replace('/', '.')

    # Third-party modules aren't our responsibility to test, and the modules in
    # contrib generally do not have doctests in a good state, plus they're hard
    # to import if this test is running with py2, so we just skip both for now.
    if modname.startswith('mercurial.thirdparty.') or modname.startswith(
        'contrib.'
    ):
        continue

    for kwargs in testmod_arg_overrides.get(modname, [{}]):
        mods_tested.add((modname, '%r' % (kwargs,)))
        if modname.startswith('tests.'):
            # On py2, we can't import from tests.foo, but it works on both py2
            # and py3 with the way that PYTHONPATH is setup to import without
            # the 'tests.' prefix, so we do that.
            modname = modname[len('tests.') :]

        testmod(modname, **kwargs)

# Meta-test: let's make sure that we actually ran what we expected to, above.
# Each item in the set is a 2-tuple of module name and stringified kwargs passed
# to testmod.
expected_mods_tested = set(
    [
        ('hggit.git_handler', '{}'),
        ('hggit.util', '{}'),
    ]
)

unexpectedly_run = mods_tested.difference(expected_mods_tested)
not_run = expected_mods_tested.difference(mods_tested)

if unexpectedly_run:
    print('Unexpectedly ran (probably need to add to list):')
    for r in sorted(unexpectedly_run):
        print('  %r' % (r,))
if not_run:
    print('Expected to run, but was not run (doctest removed?):')
    for r in sorted(not_run):
        print('  %r' % (r,))
