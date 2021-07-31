from __future__ import generator_stop

from os.path import dirname, join

try:
    from setuptools import setup
except:
    from distutils.core import setup


def get_file(relpath):
    root = dirname(__file__)
    with open(join(root, relpath)) as fp:
        return fp.read().strip()


def get_version(relpath):
    for line in get_file(relpath).splitlines():
            line = line
            if '__version__' in line:
                return line.split("'")[1]


setup(
    name='hg-git',
    version=get_version('hggit/__init__.py'),
    author='The hg-git Authors',
    maintainer='Kevin Bullock',
    maintainer_email='kbullock+mercurial@ringworld.org',
    url='http://foss.heptapod.net/mercurial/hg-git',
    description='push to and pull from a Git repository using Mercurial',
    long_description=get_file("README.rst"),
    keywords='hg git mercurial',
    license='GPLv2',
    packages=['hggit'],
    include_package_data=True,
    zip_safe=True,
    python_requires='>=3.6',
    install_requires=[
        'dulwich>=0.19.3',
    ],
)
