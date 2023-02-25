#!/usr/bin/env python3
#
# Wrapper for dulwich.web that forks a web server in a subprocess and
# saves the PID.
#

import os
import sys

from dulwich import log_utils
from dulwich import repo
from dulwich import server
from dulwich import web

import dulwich


class DirBackend(server.Backend):
    def open_repository(self, path):
        return repo.Repo(path[1:])


gitdir = os.getcwd()
port = int(sys.argv[1])

log_utils.default_logging_config()
log_utils.getLogger().info(
    f"serving {gitdir} on port {port} using dulwich v"
    + ".".join(map(str, dulwich.__version__))
)

backend = DirBackend()
app = web.make_wsgi_chain(backend)
server = web.make_server(
    "localhost",
    port,
    app,
    handler_class=web.WSGIRequestHandlerLogger,
    server_class=web.WSGIServerLogger,
)
server.serve_forever()
