"""Packing support for when exporting to Git"""

import multiprocessing
import queue
import threading
import typing

from dulwich.object_store import PackBasedObjectStore
from mercurial import ui as uimod


class Worker(threading.Thread):
    """Worker thread that we can stop.

    Deliberately not a deamon thread so that we avoid leaking threads
    for long-running processes such as TortoiseHg.

    """

    # Check for shutdown at this interval

    def __init__(self, task_queue: queue.Queue):
        super().__init__()
        self.shutdown_flag = threading.Event()
        self.task_queue = task_queue

    def run(self):
        while not self.shutdown_flag.is_set():
            try:
                ui, object_store, shas = self.task_queue.get(
                    block=True,
                    timeout=0.1,
                )
            except queue.Empty:
                continue

            try:
                _process_batch(ui, object_store, shas)
            except:
                ui.traceback()
                ui.warn(b'warning: fail to pack %d loose objects\n' % len(shas))
            finally:
                self.task_queue.task_done()

    def shutdown(self):
        """Stop the worker"""
        self.shutdown_flag.set()


def _process_batch(ui, object_store, shas):
    ui.note(b'packing %d loose objects...\n' % len(shas))
    objects = {(object_store._get_loose_object(sha), None) for sha in shas}

    # some progress would be nice here, but the API isn't conductive
    # to it
    object_store.add_objects(list(objects))

    for obj, path in objects:
        object_store._remove_loose_object(obj.id)

    ui.debug(b'packed %d loose objects!\n' % len(shas))


class GCPacker:
    """Pack loose objects into packs. Normally, Git will run a
    detached gc on regular intervals. This does _some_ of that work by
    packing loose objects into individual packs.

    As packing is mostly an I/O and compression-bound operation, we
    use a queue to schedule the operations for worker threads,
    allowing us some actual concurrency.

    Please note that all methods in class are executed on the calling
    thread; any actual threading happens in the worker class.

    """

    ui: uimod.ui
    object_store: PackBasedObjectStore
    queue: typing.Optional[queue.Queue]
    seen: typing.Set[bytes]

    def __init__(self, ui: uimod.ui, object_store: PackBasedObjectStore):
        self.ui = ui
        self.object_store = object_store
        self.seen = set()

        threads = ui.configint(b'hggit', b'threads', -1)

        if threads < 0:
            # some systems have a _lot_ of cores, and it seems
            # unlikely we need all of them; four seems a suitable
            # default, so that we can have up to three worker threads
            # concurrently packing; one seems to suffice in most cases
            threads = min(multiprocessing.cpu_count(), 4)

        if threads == 1:
            # synchronous operation
            self.queue = None
            self.workers = []
        else:
            self.queue = queue.Queue(0)

            # we know that there's a conversion going on in the main
            # thread, so the worker count is one less than the thread
            # count
            self.workers = [Worker(self.queue) for _ in range(threads - 1)]

            for thread in self.workers:
                thread.start()

    def pack(self, synchronous=False):
        # remove any objects already scheduled for packing, as we
        # perform packing asynchronously, and we may have other
        # threads concurrently packing
        all_loose = set(self.object_store._iter_loose_objects())
        todo = all_loose - self.seen
        self.seen |= todo

        if synchronous or self.queue is None:
            _process_batch(self.ui, self.object_store, todo)
        else:
            self.queue.put((self.ui, self.object_store, todo))

    def __enter__(self):
        return self

    def __exit__(self, exc_type, exc_value, traceback):
        if self.queue is not None:
            self.queue.join()

        for worker in self.workers:
            worker.shutdown()

        for worker in self.workers:
            worker.join()
