import setuptools

# don't guard this with a try; users should use pip for
# installing/building hg-git, as it ensures the proper dependencies
# are present
import setuptools_scm

assert setuptools_scm  # silence pyflakes

setuptools.setup()
