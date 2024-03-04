from dulwich.refs import LOCAL_BRANCH_PREFIX
from mercurial import (
    bundlerepo,
    discovery,
    error,
    exchange,
    exthelper,
    hg,
    pycompat,
    wireprotov1peer,
)
from mercurial.interfaces import repository
from mercurial.utils import urlutil

from . import util

eh = exthelper.exthelper()


class gitrepo(repository.peer):
    def __init__(self, ui, path=None, create=False, intents=None, **kwargs):
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

    @util.makebatchable
    def lookup(self, key):
        assert isinstance(key, bytes)
        # FIXME: this method is supposed to return a 20-byte node hash
        return key

    def local(self):
        if not self.path:
            raise error.RepoError

    def filtered(self, name: bytes):
        assert name == b'visible'

        return self

    @util.makebatchable
    def heads(self):
        return []

    @util.makebatchable
    def listkeys(self, namespace):
        if namespace == b'namespaces':
            return {b'bookmarks': b''}
        elif namespace == b'bookmarks':
            if self.localrepo is not None:
                handler = self.localrepo.githandler
                result = handler.fetch_pack(self.path, heads=[])
                # map any git shas that exist in hg to hg shas
                stripped_refs = {
                    ref[len(LOCAL_BRANCH_PREFIX) :]: handler.map_hg_get(val)
                    or val
                    for ref, val in result.refs.items()
                    if ref.startswith(LOCAL_BRANCH_PREFIX)
                }
                return stripped_refs
        return {}

    @util.makebatchable
    def pushkey(self, namespace, key, old, new):
        return False

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

    def peer(self, path=None, remotehidden=False):
        return self

    def stream_out(self):
        raise NotImplementedError

    def unbundle(self):
        raise NotImplementedError

    def commandexecutor(self):
        return wireprotov1peer.peerexecutor(self)

    def _submitbatch(self, req):
        for op, argsdict in req:
            yield None

    def _submitone(self, op, args):
        return None


instance = gitrepo


def islocal(path):
    if util.isgitsshuri(path):
        return True

    u = urlutil.url(path)
    return not u.scheme or u.scheme == b'file'


# defend against tracebacks if we specify -r in 'hg pull'
@eh.wrapfunction(hg, 'addbranchrevs')
def safebranchrevs(orig, lrepo, otherrepo, branches, revs, **kwargs):
    revs, co = orig(lrepo, otherrepo, branches, revs, **kwargs)
    if isinstance(otherrepo, gitrepo):
        # FIXME: Unless it's None, the 'co' result is passed to the lookup()
        # remote command. Since our implementation of the lookup() remote
        # command is incorrect, we set it to None to avoid a crash later when
        # the incorect result of the lookup() remote command would otherwise be
        # used. This can, in undocumented corner-cases, result in that a
        # different revision is updated to when passing both -u and -r to
        # 'hg pull'. An example of such case is in tests/test-addbranchrevs.t
        # (for the non-hg-git case).
        co = None
    return revs, co


@eh.wrapfunction(discovery, 'findcommonoutgoing')
def findcommonoutgoing(orig, repo, other, *args, **kwargs):
    if isinstance(other, gitrepo):
        heads = repo.githandler.get_refs(other.path)[0]
        kw = {}
        kw.update(kwargs)
        for val, k in zip(
            args, ('onlyheads', 'force', 'commoninc', 'portable')
        ):
            kw[k] = val
        force = kw.get('force', False)
        commoninc = kw.get('commoninc', None)
        if commoninc is None:
            commoninc = discovery.findcommonincoming(
                repo, other, heads=heads, force=force
            )
            kw['commoninc'] = commoninc
        return orig(repo, other, **kw)
    return orig(repo, other, *args, **kwargs)


@eh.wrapfunction(bundlerepo, 'getremotechanges')
def getremotechanges(orig, ui, repo, other, onlyheads, *args, **opts):
    if isinstance(other, gitrepo):
        return repo.githandler.getremotechanges(other, onlyheads)
    return orig(ui, repo, other, onlyheads, *args, **opts)


@eh.wrapfunction(exchange, 'pull')
@util.transform_notgit
def exchangepull(
    orig, repo, remote, heads=None, force=False, bookmarks=(), **kwargs
):
    if isinstance(remote, gitrepo):
        pullop = exchange.pulloperation(
            repo, remote, heads, force, bookmarks=bookmarks
        )
        pullop.trmanager = exchange.transactionmanager(
            repo, b'pull', remote.url()
        )

        with repo.wlock(), repo.lock(), pullop.trmanager:
            pullop.cgresult = repo.githandler.fetch(remote, heads)
            return pullop
    else:
        return orig(
            repo,
            remote,
            heads=heads,
            force=force,
            bookmarks=bookmarks,
            **kwargs,
        )


# TODO figure out something useful to do with the newbranch param
@eh.wrapfunction(exchange, 'push')
@util.transform_notgit
def exchangepush(
    orig,
    repo,
    remote,
    force=False,
    revs=None,
    newbranch=False,
    bookmarks=(),
    opargs=None,
    **kwargs
):
    if isinstance(remote, gitrepo):
        pushop = exchange.pushoperation(
            repo,
            remote,
            force,
            revs,
            newbranch,
            bookmarks,
            **pycompat.strkwargs(opargs or {}),
        )
        pushop.cgresult = repo.githandler.push(
            remote.path, revs, bookmarks, force
        )
        return pushop
    else:
        return orig(
            repo,
            remote,
            force,
            revs,
            newbranch,
            bookmarks=bookmarks,
            opargs=opargs,
            **kwargs,
        )


def make_peer(
    ui, path, create, intents=None, createopts=None, remotehidden=False
):
    return gitrepo(ui, path, create)
