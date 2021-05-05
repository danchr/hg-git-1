from __future__ import absolute_import, print_function

from .util import isgitsshuri
from mercurial import (
    error,
)

from . import compat

peerapi = False
try:
    from mercurial.interfaces.repository import peer as peerrepository
    peerapi = True
except ImportError:
    try:
        from mercurial.repository import peer as peerrepository
        peerapi = True
    except ImportError:
        from mercurial.peer import peerrepository


class basegitrepo(peerrepository):
    def __init__(self, ui, path, create, intents=None, **kwargs):
        if create:  # pragma: no cover
            raise error.Abort(b'Cannot create a git repository.')
        self._ui = ui
        self.path = path
        self.localrepo = None

    _peercapabilities = [b'lookup']

    def _capabilities(self):
        return self._peercapabilities

    def capabilities(self):
        return self._peercapabilities

    @property
    def ui(self):
        return self._ui

    def url(self):
        return self.path

    def lookup(self, key):
        assert isinstance(key, bytes)
        # FIXME: this method is supposed to return a 20-byte node hash
        return key

    def local(self):
        if not self.path:
            raise error.RepoError

    def heads(self):
        return []

    def listkeys(self, namespace):
        if namespace == b'namespaces':
            return {b'bookmarks': b''}
        elif namespace == b'bookmarks':
            if self.localrepo is not None:
                handler = self.localrepo.githandler
                result = handler.fetch_pack(self.path, heads=[])
                # map any git shas that exist in hg to hg shas
                stripped_refs = {
                    ref[11:]: handler.map_hg_get(val) or val
                    for ref, val in compat.iteritems(result.refs)
                    if ref.startswith(b'refs/heads/')
                }
                return stripped_refs
        return {}

    def pushkey(self, namespace, key, old, new):
        return False

    if peerapi:
        def branchmap(self):
            raise NotImplementedError

        def canpush(self):
            return True

        def close(self):
            pass

        def debugwireargs(self):
            raise NotImplementedError

        def getbundle(self):
            raise NotImplementedError

        def iterbatch(self):
            raise NotImplementedError

        def known(self):
            raise NotImplementedError

        def peer(self):
            return self

        def stream_out(self):
            raise NotImplementedError

        def unbundle(self):
            raise NotImplementedError

try:
    from mercurial.wireprotov1peer import (
        batchable,
        future,
        peerexecutor,
    )
except ImportError:
    # compat with <= hg-4.8
    gitrepo = basegitrepo
else:
    class gitrepo(basegitrepo):

        @batchable
        def lookup(self, key):
            f = future()
            yield {}, f
            yield super(gitrepo, self).lookup(key)

        @batchable
        def heads(self):
            f = future()
            yield {}, f
            yield super(gitrepo, self).heads()

        @batchable
        def listkeys(self, namespace):
            f = future()
            yield {}, f
            yield super(gitrepo, self).listkeys(namespace)

        @batchable
        def pushkey(self, namespace, key, old, new):
            f = future()
            yield {}, f
            yield super(gitrepo, self).pushkey(key, old, new)

        def commandexecutor(self):
            return peerexecutor(self)

        def _submitbatch(self, req):
            for op, argsdict in req:
                yield None

        def _submitone(self, op, args):
            return None

instance = gitrepo


def islocal(path):
    if isgitsshuri(path):
        return True

    u = compat.url(path)
    return not u.scheme or u.scheme == b'file'
