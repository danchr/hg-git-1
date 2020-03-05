from __future__ import absolute_import, print_function

from dulwich.client import SubprocessWrapper
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
            if isinstance(command, basestring):
                # 0.12.x dulwich sends the raw string
                command = [command]
            elif len(command) > 1:
                # 0.11.x dulwich sends an array of [command arg1 arg2 ...], so
                # we detect that here and reformat it back to what hg-git
                # expects (e.g. "command 'arg1 arg2'")
                command = ["%s '%s'" % (command[0], ' '.join(command[1:]))]
            sshcmd = ui.config("ui", "ssh", "ssh")
            args = compat.sshargs(sshcmd, host, username, port)
            cmd = '%s %s %s' % (sshcmd, args,
                                compat.shellquote(' '.join(command)))
            ui.debug('calling ssh: %s\n' % cmd)
            proc = subprocess.Popen(compat.quotecommand(cmd), shell=True,
                                    stdin=subprocess.PIPE,
                                    stdout=subprocess.PIPE)
            return SubprocessWrapper(proc)

    return _Vendor
