import subprocess

from dulwich.client import SSHGitClient, SubprocessWrapper

from mercurial import pycompat
from mercurial.utils import procutil


class SSHVendor(object):
    """Parent class for ui-linked Vendor classes."""


def generate_ssh_vendor(ui):
    """
    Allows dulwich to use hg's ui.ssh config. The dulwich.client.get_ssh_vendor
    property should point to the return value.
    """

    class _Vendor(SSHVendor):
        def run_command(
            self, host, command, username=None, port=None, **kwargs
        ):
            assert isinstance(command, str)
            command = command.encode(SSHGitClient.DEFAULT_ENCODING)
            sshcmd = ui.config(b"ui", b"ssh", b"ssh")
            args = procutil.sshargs(
                sshcmd, pycompat.bytesurl(host), username, port
            )
            cmd = b'%s %s %s' % (sshcmd, args, procutil.shellquote(command))
            # consistent with mercurial
            ui.debug(b'running %s\n' % cmd)
            # we cannot use Mercurial's procutil.popen4() since it
            # always redirects stderr into a pipe
            proc = subprocess.Popen(
                procutil.tonativestr(cmd),
                shell=True,
                bufsize=0,
                stdin=subprocess.PIPE,
                stdout=subprocess.PIPE,
            )
            return SubprocessWrapper(proc)

    return _Vendor
