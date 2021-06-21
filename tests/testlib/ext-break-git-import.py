"""This is a small custom extension that allows stopping a hg-git
conversion after a specific number of commits.

Configure it using the following environment variables:

- ABORT_AFTER
- EXIT_AFTER

"""

import os
from mercurial import error, extensions

counter = 0

hggit = extensions.find(b"hggit")


def wrap(orig, *args, **kwargs):
    global counter

    counter += 1

    try:
        return orig(*args, **kwargs)
    finally:
        abort_after = int(os.getenv("ABORT_AFTER", "0"))
        exit_after = int(os.getenv("EXIT_AFTER", "0"))

        if abort_after and counter > abort_after:
            raise error.Abort(b"aborted after %d commits!" % abort_after)
        elif exit_after and counter > exit_after:
            raise KeyboardInterrupt


extensions.wrapfunction(hggit.git_handler.GitHandler, "export_hg_commit", wrap)
extensions.wrapfunction(
    hggit.git_handler.GitHandler,
    "import_git_commit",
    wrap,
)
