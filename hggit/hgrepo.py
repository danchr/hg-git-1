from __future__ import absolute_import, print_function

from mercurial import util as hgutil
from mercurial.node import bin

from .git_handler import GitHandler
from .gitrepo import gitrepo
from . import compat
from . import util


def generate_repo_subclass(baseclass):
    class hgrepo(baseclass):
        @util.transform_notgit
        def findoutgoing(self, remote, base=None, heads=None, force=False):
            if isinstance(remote, gitrepo):
                base, heads = self.githandler.get_refs(remote.path)
                out, h = super(hgrepo, self).findoutgoing(remote, base,
                                                          heads, force)
                return out
            else:  # pragma: no cover
                return super(hgrepo, self).findoutgoing(remote, base,
                                                        heads, force)

        def _findtags(self):
            (tags, tagtypes) = super(hgrepo, self)._findtags()

            for tag, rev in compat.iteritems(self.githandler.tags):
                if tag not in tags:
                    assert isinstance(tag, bytes)
                    tags[tag] = bin(rev)
                    tagtypes[tag] = b'git'
            for tag, rev in compat.iteritems(self.githandler.remote_refs):
                assert isinstance(tag, bytes)
                tags[tag] = rev
                tagtypes[tag] = b'git-remote'
            tags.update(self.githandler.remote_refs)
            return (tags, tagtypes)

        @hgutil.propertycache
        def githandler(self):
            '''get the GitHandler for an hg repo

            This only makes sense if the repo talks to at least one git remote.
            '''
            return GitHandler(self, self.ui)

        def tags(self):
            # TODO consider using self._tagscache
            tagscache = super(hgrepo, self).tags()
            tagscache.update(self.githandler.remote_refs)
            for tag, rev in compat.iteritems(self.githandler.tags):
                if tag in tagscache:
                    continue

                tagscache[tag] = bin(rev)

            return tagscache

    return hgrepo
