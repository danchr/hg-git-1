# git.py - git server bridge
#
# Copyright 2008 Scott Chacon <schacon at gmail dot com>
#   also some code (and help) borrowed from durin42
#
# This software may be used and distributed according to the terms
# of the GNU General Public License, incorporated herein by reference.

r'''push and pull from a Git server

This extension lets you communicate (push and pull) with a Git server.
This way you can use Git hosting for your project or collaborate with a
project that is in Git. A bridger of worlds, this plugin be.

Try :hg:`clone git+https://github.com/dulwich/dulwich` or :hg:`clone
git+ssh://example.com/repo.git`.

Basic Use
---------

You can clone a Git repository from Mercurial by running :hg:`clone
<url> [dest]`. For example, if you were to run::

 $ hg clone git://github.com/schacon/hg-git.git

Hg-Git would clone the repository and convert it to a Mercurial repository for
you. There are a number of different protocols that can be used for Git
repositories. Examples of Git repository URLs include::

  git+https://github.com/hg-git/hg-git.git
  git+http://github.com/hg-git/hg-git.git
  git+ssh://git@github.com/hg-git/hg-git.git
  git://github.com/hg-git/hg-git.git
  file:///path/to/hg-git
  ../hg-git (local file path)

These also work::

  git+ssh://git@github.com:hg-git/hg-git.git
  git@github.com:hg-git/hg-git.git

Please note that you need to prepend HTTP, HTTPS, and SSH URLs with
``git+`` in order differentiate them from Mercurial URLs. For example,
an HTTPS URL would start with ``git+https://``. Also, note that Git
doesn't require the specification of the protocol for SSH, but
Mercurial does. Hg-Git automatically detects whether file paths should
be treated as Git repositories by their contents.

If you are starting from an existing Mercurial repository, you have to
set up a Git repository somewhere that you have push access to, add a
path entry for it in your .hg/hgrc file, and then run :hg:`push
[name]` from within your repository. For example::

 $ cd hg-git # (a Mercurial repository)
 $ # edit .hg/hgrc and add the target Git URL in the paths section
 $ hg push

This will convert all your Mercurial changesets into Git objects and push
them to the Git server.

Pulling new revisions into a repository is the same as from any other
Mercurial source. Within the earlier examples, the following commands are
all equivalent::

 $ hg pull
 $ hg pull default
 $ hg pull git://github.com/hg-git/hg-git.git

Git branches are exposed in Mercurial as bookmarks, while Git remote
branches are exposed as unchangable Mercurial local tags. See
:hg:`help bookmarks` and :hg:`help tags` for further information.

Finding and displaying Git revisions
------------------------------------

For displaying the Git revision ID, Hg-Git provides a template keyword:

  :gitnode: String.  The Git changeset identification hash, as a 40 hexadecimal
    digit string.

For example::

  $ hg log --template='{rev}:{node|short}:{gitnode|short} {desc}\n'
  $ hg log --template='hg: {node}\ngit: {gitnode}\n{date|isodate} {author}\n{desc}\n\n'

For finding changesets from Git, Hg-Git extends revsets to provide two new
selectors:

  :fromgit: Select changesets that originate from Git. Takes no arguments.
  :gitnode: Select changesets that originate in a specific Git revision. Takes
    a revision argument.

For example::

  $ hg log -r 'fromgit()'
  $ hg log -r 'gitnode(84f75b909fc3)'

Revsets are accepted by several Mercurial commands for specifying
revisions. See :hg:`help revsets` for details.


Creating Git tags
-----------------

You can create a lightweight Git tag using using :hg:`tag --git`.
Please note that this requires an explicit -r/--rev, and does not
support any of the other flags for :hg:`hg tag`.

Support for Git tags is somewhat minimal. The Git documentation
heavily discourages changing tags once pushed, and suggests that users
always create a new one instead. (Unlike Mercurial, Git does not track
and version its tags within the repository.) As result, there's no
support for removing and changing preexisting tags. Similarly, there's
no support for annotated tags, i.e. tags with messages, nor for
signing tags. For those, either use Git directly or use the integrated
web interface for tags and releases offered by most hosting solutions,
including GitHub and GitLab.

Invalid and dangerous paths
---------------------------

Both Mercurial and Git consider paths as just bytestrings internally,
and allow almost anything. The difference, however, is in the _almost_
part. For example, many Git servers will reject a push for security
reasons if it contains a nested Git repository. Similarly, Mercurial
cannot checkout commits with a nested repository, and it cannot even
store paths containing an embedded newline or carrage return
character.

The default is to issue a warning and skip these paths. You can
change this by setting ``hggit.invalidpaths`` in :hg:`config`::

  [hggit]
  invalidpaths = keep

Possible values are ``keep``, ``skip`` or ``abort``.

Ignoring files
--------------

In addition to the regular :hg:`help hgignore` support, ``hg-git``
adds fallback support for Git ignore files. If no ``.hgignore`` file
exists at the root of the repository, Mercurial will then read any
``.gitignore`` files that exist.

Please note that Mercurial doesn't support exclusion patterns, so any
``.gitignore`` pattern starting with ``!`` will trigger a warning.

'''

import dulwich

from mercurial import (
    demandimport,
    exthelper,
    pycompat,
)

from . import commands
from . import config
from . import debugcommands
from . import gitdirstate
from . import gitrepo
from . import hgrepo
from . import overlay
from . import revsets
from . import schemes
from . import templates


demandimport.IGNORES |= {
    b'collections',
}

testedwith = b'6.1 6.2 6.3 6.4 6.5 6.6 6.7 6.8'
minimumhgversion = b'6.1'
buglink = b'https://foss.heptapod.net/mercurial/hg-git/issues'

eh = exthelper.exthelper()

cmdtable = eh.cmdtable
configtable = eh.configtable
filesetpredicate = eh.filesetpredicate
revsetpredicate = eh.revsetpredicate
templatekeyword = eh.templatekeyword
uisetup = eh.finaluisetup
extsetup = eh.finalextsetup
reposetup = eh.finalreposetup
uipopulate = eh.finaluipopulate

for _mod in (
    commands,
    config,
    debugcommands,
    gitdirstate,
    gitrepo,
    hgrepo,
    overlay,
    revsets,
    templates,
    schemes,
):
    eh.merge(_mod.eh)


def getversion():
    """return version with dependencies for hg --version -v"""
    # first, try to get a built version
    try:
        from .__version__ import version
    except ImportError:
        version = None

    # if that fails, try to determine the version from the checkout
    if version is None:
        try:
            from setuptools_scm import get_version

            version = get_version(
                root='..',
                relative_to=__file__,
                version_scheme="release-branch-semver",
            )
        except:
            # something went wrong, but we need to provide something
            version = "unknown"

    # include the dulwich version, as it's fairly important for the
    # level of functionality
    dulver = '.'.join(map(str, dulwich.__version__))

    return pycompat.sysbytes("%s (dulwich %s)" % (version, dulver))
