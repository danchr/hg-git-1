from __future__ import absolute_import, print_function

from os.path import dirname, join

try:
    from setuptools import setup
except:
    from distutils.core import setup

try:
    extra_req = []
except ImportError:
    extra_req = ['ordereddict>=1.1']


def get_version(relpath):
    root = dirname(__file__)
    for line in open(join(root, relpath), 'rb'):
        line = line.decode('utf-8')
        if '__version__' in line:
            return line.split("'")[1]


setup(
    name='hg-git',
    version=get_version('hggit/__init__.py'),
    author='The hg-git Authors',
    maintainer='Kevin Bullock',
    maintainer_email='kbullock+mercurial@ringworld.org',
    url='https://hg-git.github.io/',
    description='push to and pull from a Git repository using Mercurial',
    long_description="""
This extension lets you communicate (push and pull) with a Git server.
This way you can use Git hosting for your project or collaborate with a
project that is in Git.  A bridger of worlds, this plugin be.
    """.strip(),
    keywords='hg git mercurial',
    license='GPLv2',
    packages=['hggit'],
    package_data={'hggit': ['help/git.rst']},
    include_package_data=True,
    install_requires=['dulwich>=0.19.0'] + extra_req,
)
