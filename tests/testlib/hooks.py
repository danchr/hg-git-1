import pprint

from mercurial import pycompat

def showargs(ui, repo, hooktype, **kwargs):
    if not kwargs:
        ui.write(b'| %s\n' % hooktype)

    for k, v in pycompat.byteskwargs(kwargs).items():
        if k in (b"txnid", b"changes"):
            # ignore these; they are either unstable or too verbose
            continue
        if not isinstance(v, bytes):
            v = repr(v).encode('ascii', errors='backslashreplace')
        ui.write(b'| %s.%s=%s\n' % (hooktype, k, v))

