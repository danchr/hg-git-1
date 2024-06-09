from dulwich import object_store

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
