from __future__ import absolute_import, print_function

from dulwich.client import SSHGitClient, SubprocessWrapper
import subprocess
from . import compat


class SSHVendor(object):
    """Parent class for ui-linked Vendor classes."""


def generate_ssh_vendor(ui):
    """
    Allows dulwich to use hg's ui.ssh config. The dulwich.client.get_ssh_vendor
    property should point to the return value.
    """

    class _Vendor(SSHVendor):
        def run_command(self, host, command, username=None, port=None):
            assert isinstance(command, compat.unicode)
            command = command.encode(SSHGitClient.DEFAULT_ENCODING)
            sshcmd = ui.config(b"ui", b"ssh", b"ssh")
            args = compat.sshargs(sshcmd, host, username, port)
            cmd = b'%s %s %s' % (sshcmd, args, compat.shellquote(command))
            ui.debug(b'calling ssh: %s\n' % cmd)
            proc = subprocess.Popen(compat.quotecommand(cmd), shell=True,
                                    bufsize=0,
                                    stdin=subprocess.PIPE,
                                    stdout=subprocess.PIPE)
            return SubprocessWrapper(proc)

    return _Vendor
