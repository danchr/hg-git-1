#!/usr/bin/env python3
#
# Call another command and save its pid
#

import os
import subprocess
import sys

with open(sys.argv[1], "xb") as outf:
    proc = subprocess.Popen(
        [sys.executable] + sys.argv[2:],
        stdout=outf,
        stderr=outf,
        close_fds=True,
        start_new_session=True,
    )

with open(os.getenv("DAEMON_PIDS"), "a") as fp:
    fp.write(f"{proc.pid}\n")
