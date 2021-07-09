#!/usr/bin/env python3
#
# Wrapper for dulwich.web that forks a web server in a subprocess and
# saves the PID.
#

import os
import subprocess
import sys


proc = subprocess.Popen(
    [
        sys.executable,
        "-m",
        "dulwich.web",
    ] + sys.argv[1:],
    stderr=subprocess.DEVNULL,
)

with open(os.getenv("DAEMON_PIDS"), "a") as fp:
    fp.write("%d\n" % proc.pid)
