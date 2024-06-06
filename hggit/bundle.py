import io

from mercurial import bundle2
from mercurial import exchange
from mercurial import exthelper

from mercurial.node import bin, hex


eh = exthelper.exthelper()

CAPABILITY_MAP = b'exp-hg-git-map'
CAPABILITY_TAGS = b'exp-hg-git-tags'
BUNDLEPART_MAP = b'exp-hg-git-map'
BUNDLEPART_TAGS = b'exp-hg-git-tags'


@eh.wrapfunction(bundle2, 'getrepocaps')
def getrepocaps(orig, repo, **kwargs):
    caps = orig(repo, **kwargs)

    if repo.ui.configbool(b'experimental', b'hg-git-serve'):
        caps[CAPABILITY_MAP] = ()
        caps[CAPABILITY_TAGS] = ()

    return caps


def addpartrevgitmap(repo, bundler, outgoing):
    if repo.githandler:
        # this is different from what we store in the repository,
        # and uses binary node ids: <20 bytes> <20 bytes>
        repo.ui.debug(b'bundling git map\n')

        chunks = (
            bin(repo.githandler._map_hg[hex(hgnode)]) + hgnode
            for hgnode in outgoing.missing
            if hex(hgnode) in repo.githandler._map_hg
        )

        bundler.newpart(BUNDLEPART_MAP, data=chunks, mandatory=False)


def addpartrevgittags(repo, bundler, outgoing):
    if repo.githandler.tags:
        # this is consistent with the format used in the repository:
        # <40 hex digits> <space> <tag name> <newline>
        repo.ui.debug(b'bundling git tags\n')

        chunks = (
            b"%s %s\n" % (sha, name)
            for name, sha in sorted(repo.githandler.tags.items())
            if bin(sha) in outgoing.missing
        )

        bundler.newpart(BUNDLEPART_TAGS, data=chunks, mandatory=False)


@eh.wrapfunction(bundle2, '_addpartsfromopts')
def _addpartsfromopts(orig, ui, repo, bundler, source, outgoing, opts):
    orig(ui, repo, bundler, source, outgoing, opts)

    if opts.get(CAPABILITY_MAP, False) or ui.configbool(
        b'experimental', b'hg-git-bundle'
    ):
        addpartrevgitmap(repo, bundler, outgoing)

    if opts.get(CAPABILITY_TAGS, False) or ui.configbool(
        b'experimental', b'hg-git-bundle'
    ):
        addpartrevgittags(repo, bundler, outgoing)


@eh.extsetup
def install_server_support(ui):
    @bundle2.parthandler(BUNDLEPART_MAP)
    def handlebundlemap(op, inpart):
        ui.debug(b'unbundling git map\n')

        while not inpart.consumed:
            # this is different from what we store in the repository,
            # and uses binary node ids: <20 bytes> <20 bytes>
            gitsha = hex(inpart.read(20))
            hgsha = hex(inpart.read(20))

            if gitsha and hgsha:
                op.repo.githandler.map_set(gitsha, hgsha)

        op.repo.githandler.save_map()

    @exchange.getbundle2partsgenerator(BUNDLEPART_MAP)
    def gitmapbundle(
        bundler, repo, source, bundlecaps=None, b2caps=None, **kwargs
    ):
        if b2caps is None or CAPABILITY_MAP not in b2caps:
            return

        ui.debug(b'bundling git map\n')

        outgoing = exchange._computeoutgoing(
            repo,
            kwargs['heads'],
            kwargs['common'],
        )

        addpartrevgitmap(repo, bundler, outgoing)

    @bundle2.parthandler(BUNDLEPART_TAGS)
    def handlebundletags(op, inpart):
        with io.BytesIO() as buf:
            while not inpart.consumed:
                buf.write(inpart.read())

            buf.seek(0)

            # we're consistent, and always load everything, so just
            # let the handler do its thing
            op.repo.githandler._read_tags_from(buf)

        op.repo.githandler.save_tags()

    @exchange.getbundle2partsgenerator(BUNDLEPART_TAGS)
    def gittagbundle(
        bundler, repo, source, bundlecaps=None, b2caps=None, **kwargs
    ):
        if b2caps is None or CAPABILITY_TAGS not in b2caps:
            return

        outgoing = exchange._computeoutgoing(
            repo,
            kwargs['heads'],
            kwargs['common'],
        )

        addpartrevgittags(repo, bundler, outgoing)
