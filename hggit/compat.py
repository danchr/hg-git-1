import os
import typing

from dulwich import file as dul_file
from dulwich import object_store
from dulwich import refs

# dulwich 0.21 removed find_missing_objects() and made MissingObjectFinder a
# proper iterable
if not hasattr(object_store.MissingObjectFinder, '__iter__'):

    class MissingObjectFinder(object_store.MissingObjectFinder):
        def __iter__(self):
            return iter(self.next, None)

else:
    MissingObjectFinder = object_store.MissingObjectFinder


# dulwich 0.21 added a module-level function and deprecated the
# instance method
try:
    peel_sha = object_store.peel_sha
except AttributeError:

    def peel_sha(store, sha):
        return store[sha], store.peel_sha(sha)


# changed in Mercurial 6.4
def get_push_location(path):
    if hasattr(path, 'is_push_variant'):
        return path.get_push_variant().loc
    else:
        return path.pushloc or path.loc


try:
    add_packed_refs = refs.DiskRefsContainer.add_packed_refs
except AttributeError:
    # added in dulwich 0.20.51
    def add_packed_refs(
        container: refs.DiskRefsContainer, new_refs: typing.Dict[bytes, bytes]
    ):
        """Add the given refs as packed refs.

        Args:
          new_refs: A mapping of ref names to targets; if a target is None that
            means remove the ref
        """
        if not new_refs:
            return

        path = os.path.join(container.path, b"packed-refs")

        with dul_file.GitFile(path, "wb") as f:
            # reread cached refs from disk, while holding the lock
            packed_refs = container.get_packed_refs().copy()

            for ref, target in new_refs.items():
                # sanity check
                if ref == b'HEAD':
                    raise ValueError("cannot pack HEAD")

                # remove any loose refs pointing to this one -- please
                # note that this bypasses remove_if_equals as we don't
                # want to affect packed refs in here
                try:
                    os.remove(container.refpath(ref))
                except OSError:
                    pass

                if target is not None:
                    packed_refs[ref] = target
                else:
                    packed_refs.pop(ref, None)

            refs.write_packed_refs(f, packed_refs, container._peeled_refs)

            container._packed_refs = packed_refs
