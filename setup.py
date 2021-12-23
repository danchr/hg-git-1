import setuptools

try:
    import setuptools_scm

    assert setuptools_scm  # silence pyflakes
except ImportError:
    pass

setuptools.setup()
