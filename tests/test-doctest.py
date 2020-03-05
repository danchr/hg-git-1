# this is hack to make sure no escape characters are inserted into the output

from __future__ import absolute_import, print_function

import doctest
import os
import re
import sys

ispy3 = (sys.version_info[0] >= 3)

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
        got2 = re.sub(r'''^hggit\.\w+\.(\w+): (['"])(.*?)\2''', r'\1: \3',
                      got2, re.MULTILINE)
        got2 = re.sub(r'^hggit\.\w+\.(\w+): ', r'\1: ', got2, re.MULTILINE)
        return any(doctest.OutputChecker.check_output(self, w, g, optionflags)
                   for w, g in [(want, got), (want2, got2)])

def testmod(name, optionflags=0, testtarget=None):
    __import__(name)
    mod = sys.modules[name]
    if testtarget is not None:
        mod = getattr(mod, testtarget)

    # minimal copy of doctest.testmod()
    finder = doctest.DocTestFinder()
    checker = None
    if ispy3:
        checker = py3docchecker()
    runner = doctest.DocTestRunner(checker=checker, optionflags=optionflags)
    for test in finder.find(mod, name):
        runner.run(test)
    runner.summarize()

testmod('hggit.compat')
testmod('hggit.hg2git')
testmod('hggit.util')
testmod('hggit.git_handler')
