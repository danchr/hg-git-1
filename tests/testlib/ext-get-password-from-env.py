#
# small dummy extension that obtains passwords from an environment
# variable
#

import getpass
import os
import sys


def newgetpass(args):
    try:
      passwd = os.environb.get(b'PASSWD', b'nope')
      print(passwd.encode())
    except AttributeError: # python 2.7
      passwd = os.environ.get('PASSWD', 'nope')
      print(passwd)
    sys.stdout.flush()
    return passwd

getpass.getpass = newgetpass
