Hg-Git Mercurial Plugin
=======================

Homepage:
  https://wiki.mercurial-scm.org/HgGit
Repository:
  https://foss.heptapod.net/mercurial/hg-git
Old homepage, no longer maintained:
  https://hg-git.github.io/
Discussion:
  `hg-git@googlegroups.com <mailto:hg-git@googlegroups.com>`_ (`Google
  Group <https://groups.google.com/g/hg-git>`_) and
  `#hg-git:matrix.org <https://matrix.to/#/#hg-git:matrix.org>`_

This is the Hg-Git plugin for Mercurial, adding the ability to push and
pull to/from a Git server repository from Hg. This means you can
collaborate on Git based projects from Hg, or use a Git server as a
collaboration point for a team with developers using both Git and Hg.

The Hg-Git plugin can convert commits/changesets losslessly from one
system to another, so you can push via a Mercurial repository and another Hg
client can pull it and their changeset node ids will be identical -
Mercurial data does not get lost in translation. It is intended that Hg
users may wish to use this to collaborate even if no Git users are
involved in the project, and it may even provide some advantages if
you're using Bookmarks (see below).

Dependencies
============

This plugin is implemented entirely in Python — there are no Git
binary dependencies, and you do not need to have Git installed on your
system. The only dependencies are:

* Mercurial 6.1
* Dulwich 0.20.11
* Python 3.8

Please note that these are the earliest versions known to work; later
versions generally work better.

Installing
==========

We recommend installing the plugin using your a package manager, such
as pip::

  python -m pip install hg-git

Alternatively, you can clone this repository somewhere and install it
from the directory::

  hg clone https://foss.heptapod.net/mercurial/hg-git/
  cd hg-git
  python -m pip install .

And enable it from somewhere in your ``$PYTHONPATH``::

   [extensions]
   hggit =

Contributing
============

The primary development location for Hg-Git is `Heptapod
<http://foss.heptapod.net/mercurial/hg-git/>`_, and you can follow
their guide on `how to contribute patches
<https://heptapod.net/pages/quick-start-guide.html>`_.

Alternatively, you can follow the `guide on how to contribute to
Mercurial itself
<https://www.mercurial-scm.org/wiki/ContributingChanges>`_, and send
patches to `the list <https://groups.google.com/g/hg-git>`_.

Usage
=====

You can clone a Git repository from Mercurial by running
``hg clone <url> [dest]``. For example, if you were to run::

   $ hg clone git://github.com/hg-git/hg-git.git

Hg-Git would clone the repository and convert it to a Mercurial
repository for you. Other protocols are also supported, see ``hg help
git`` for details.

If you are starting from an existing Mercurial repository, you have to set up a
Git repository somewhere that you have push access to, add a path entry
for it in your .hg/hgrc file, and then run ``hg push [name]`` from
within your repository. For example::

   $ cd hg-git # (a Mercurial repository)
   $ # edit .hg/hgrc and add the target git url in the paths section
   $ hg push

This will convert all your Mercurial data into Git objects and push them to the
Git server.

Now that you have a Mercurial repository that can push/pull to/from a Git
repository, you can fetch updates with ``hg pull``::

   $ hg pull

That will pull down any commits that have been pushed to the server in
the meantime and give you a new head that you can merge in.

Hg-Git pushes your bookmarks up to the Git server as branches and will
pull Git branches down and set them up as bookmarks.

Hg-Git can also be used to convert a Mercurial repository to Git. You
can use a local repository or a remote repository accessed via SSH, HTTP
or HTTPS. Use the following commands to convert the repository, it
assumes you're running this in ``$HOME``::

   $ mkdir git-repo; cd git-repo; git init; cd ..
   $ cd hg-repo
   $ hg bookmarks hg
   $ hg push ../git-repo

The ``hg`` bookmark is necessary to prevent problems as otherwise
hg-git pushes to the currently checked out branch, confusing Git. The
snippet above will create a branch named ``hg`` in the Git repository.
To get the changes in ``master`` use the following command (only
necessary in the first run, later just use ``git merge`` or ``git
rebase``).

::

   $ cd git-repo
   $ git checkout -b master hg

To import new changesets into the Git repository just rerun the ``hg
push`` command and then use ``git merge`` or ``git rebase`` in your Git
repository.

``.gitignore`` and ``.hgignore``
--------------------------------

If present, ``.gitignore`` will be taken into account provided that there is
no ``.hgignore``. In the latter case, the rules from ``.hgignore`` apply,
regardless of what ``.gitignore`` prescribes.

Please note that Mercurial doesn't support exclusion patterns, so any
``.gitignore`` pattern starting with ``!`` will trigger a warning.

This has been so since version 0.5.0, released in 2013.

Further reading
===============

See ``hg help -e hggit`` and ``hg help hggit-config``.

Alternatives
============

Since version 5.4, Mercurial includes an extension called ``git``. It
interacts with a Git repository directly, avoiding the intermediate
conversion. This has certain advantages:

 * Each commit only has one node ID, which is the Git hash.
 * Data is stored only once, so the on-disk footprint is much lower.

The extension has certain drawbacks, however:

 * It cannot handle all Git repositories. In particular, it cannot
   handle `octopus merges`_, i.e. merge commits with more than two
   parents. If any such commit is included in the history, conversion
   will fail.
 * You cannot interact with Mercurial repositories.

.. _octopus merges: https://git-scm.com/docs/git-merge

Another extension packaged with Mercurial, the ``convert`` extension,
also has Git support.

Other alternatives exist for Git users wanting to access Mercurial
repositories, such as `git-remote-hg`_.

.. _git-remote-hg: https://pypi.org/project/git-remote-hg/
