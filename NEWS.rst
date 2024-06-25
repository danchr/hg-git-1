hg-git 1.1.3 (2024-06-25)
=========================

This is a minor release, focusing on bugs and compatibility.

* Mark Dulwich 0.22.0 and 0.22.1 as unsupported.  The compatibility
  hack didn't work in practice.
* Mark Mercurial 6.8 as tested and supported.

hg-git 1.1.2 (2024-06-06)
=========================

This is a minor release, focusing on bugs and compatibility.

* Always advance ``draft`` phase, even if pulling from an explicit URL
  that isn't a named path.
* Always save Git tags into the local, cached Git repository.
* Add support for Dulwich 0.22.

hg-git 1.1.1 (2024-03-06)
=========================

This is a minor release, focusing on bugs and compatibility. It
includes all changes from 1.0.5 as well as the following:

* Fix pulling after marking the ``tip`` as obsolete.
* Mark Mercurial 6.7 as supported.

hg-git 1.0.5 (2024-03-06)
=========================

This is a minor release, focusing on bugs and compatibility.

* Fix ``--publish`` when topics extension is enabled.

Thanks to @av6 for contributing changes to the release!

hg-git 1.1.0 (2024-01-13)
=========================

This is a feature release that contains changes all changes from
1.1.0b1 and 1.0.4, as well as the following minor change:

* Remove some compatibility for now-unsupported versions of Dulwich.

This release requires Mercurial 6.1, or later, Dulwich 0.20.11 or
later and Python 3.8 or later.

hg-git 1.0.4 (2024-01-13)
=========================

This is a minor release, focusing on bugs and compatibility.

* Address regression with Mercurial 6.4 and later where remote tags
  weren't updated on push.

hg-git 1.1.0b1 (2023-11-08)
===========================

This is a preview of an upcoming feature release that contains changes
to user-facing behaviour.

Changes to behaviour:

* The ``gclear`` command is inherently dangerous, and has been
  replaced with a debug command instead.
* The ``.hgsub`` and ``.gitmodules`` files are no longer retained when
  pushing to or pulling from Git, respectively. Instead, changes to
  each will be applied during the conversion.

Enhancements:

* Minor adjustments to categorisation of internal commands, and ensure
  that they all start with ``git-*``.
* Move configuration from the ``README`` file to contained within the
  extension, so that it is now self-documenting like Mercurial.
* The ``-B/--bookmark`` flag for ``push`` will now restrict bookmarks
  by name rather than revision. (Please note that this is unsupported
  when the ``git.branch_bookmark_suffix`` configuration option is
  set.)
* Pushing an unknown bookmark with the ``-B/--bookmark`` option now
  has the same effect as when pushing to a Mercurial repository, and
  will delete the remote Git branch.
* You can now specify what to publish with the ``paths`` section. For
  example::

    [paths]
    default = https://github.com/example/test
    default:pushurl = git+ssh://git@github.com/example
    default:hg-git.publish = yes
* Pushing and pulling from Git now triggers ``incoming``, ``outgoing``
  and ``changegroup`` hooks, along with the corresponding ``pre*``
  hooks. In addition, the ``gitexport`` and ``gitimport`` hooks allow
  intercepting when commits are converted. As a result, you can now
  use the ``notify`` extension when interacting with Git repositories.
  (#402)
* Git subrepositories will now be pushed as Git submodules.

This release requires Mercurial 6.1, or later, Dulwich 0.20.11 or
later and Python 3.8 or later.

hg-git 1.0.3 (2023-11-07)
=========================

This is a minor release, focusing on bugs and compatibility.

* Fix tests with Mercurial 6.5
* Handle failures to save refs, such as when they use characters
  forbidden by the file system; this is most easily noticed on Windows
  and macOS. (#397)
* Fix pulling annotated tags with ``-r``/``--rev``.

hg-git 1.0.2 (2023-03-03)
=========================

This is a minor release, focusing on bugs and compatibility.

* Fix ``--source``/``-s`` argument to ``transplant`` with Hg-Git
  enabled. (#392)
* Fix cloning repositories using the old static HTTP support with
  Hg-Git enabled.
* Handle pushing tags to Git that cannot be stored as references such
  as double-quotes on Windows. (#397)
* Avoid converting unrelated refs on pull, such as Github PR-related refs. (#386)
* Fix tests with GNU Grep 3.8 and later, by avoiding the ``egrep``
  alias (#400)
* Support reading remote refs even if packed.
* Add support for Dulwich 0.21 and later.
* Mark Mercurial 6.4 as supported and tested.
* Address slowness when pulling large repositories, caused by writing
  unchanged references. (#401)

Thanks to @icp1994 and @jmb for contributing changes to the release!

hg-git 1.0.1 (2022-11-04)
=========================

This is a minor release, focusing on bugs and compatibility.

* Ignore any ``GIT_SSH_COMMAND`` environment variable, rather than
  dying with an error. (#369)
* Fix bug with unusual progress lines from Azure Repo (#391)
* Fix incorrect use of localisation APIs (#387)
* Fix pushing with Dulwich 0.2.49 or later.
* Fix tests with Git 2.37.
* Fix bug with tags or remote refs in the local Git repository that
  point to missing commits.
* Mark Mercurial 6.2 and 6.3 as supported and tested.

Thanks to Pierre Augier and Aay Jay Chan for contributing to this
release!

hg-git 1.0.0 (2022-04-01)
=========================

This is the first stable release in the 1.0 series. In addition to all
the features and fixes in the betas, it includes:

* Handle errors in ``.gitmodules`` gracefully, allowing the conversion
  to continue. (#329)
* Don't die with an error when ``.hgsub`` contains comments. (#128)
* Suppress errors on export related to history editing of certain
  commits with unusual authorship and messages. (#383)
* Fix tests with Git 2.35.

Other changes:

* Increase test coverage by using different versions of Alpine Linux
  and Dulwich.

This release requires Mercurial 5.2 or later and Python 3.6 or later.

hg-git 1.0b2 (2022-03-10)
=========================

This is a follow-up to the previous beta, that fixes the following
bugs:

* Fix tests with Mercurial 6.1.
* Avoid prompting for authentication after a successful push, by
  storing the authenticated client. (#379)

This release requires Mercurial 5.2 or later and Python 3.6 or later.

hg-git 1.0b1 (2022-01-26)
=========================

This is a preview of an upcoming major release that contains changes
to user-facing behaviour, as well as a fair amount of internal
changes. The primary focus is on adjusting the user experience to be
more intuitive and consistent with Git and Mercurial. The internal
changes are mainly refactoring to make the code more consistent and
maintainable. Performance should also be much better; a simple clone
of a medium-sized repository is about 40% faster.

This release requires Mercurial 5.2 or later and Python 3.6 or later.

Changes to behaviour:

* When a pull detects that a Git remote branch vanishes, it will
  remove the corresponding local tags, such as ``default/branch``.
  This is equivalent to using ``git fetch --prune``, and adjustable
  using the ``git.pull-prune-remote-branches`` configuration option.
* Similarly, delete the actual bookmarks corresponding to a remote
  branch, unless the bookmarks was moved since the last pull from Git.
  This is enabled by default and adjustable using the
  ``git.pull-prune-bookmarks`` configuration option.
* Speed up ``pull`` by using a single transaction per map save
  interval.
* Similarly, speed up ``hg clone`` by always using a single
  transaction and map save interval, as Mercurial will delete the
  repository on errors.
* Change the default ``hggit.mapsavefrequency`` to 1,000 commits rather
  than just saving at the end.
* Abort with a helpful error when a user attempts to push to Git from
  a Mercurial repository without any bookmarks nor tags. Previously,
  that would either invent a bookmark —— *once* — or just report that
  nothing was found.
* Only update e.g. ``default/master`` when actually pulling from
  ``default``.

Enhancements:

* Add a ``gittag()`` revset.
* Print a message describing which bookmarks changed during a pull.
* Let Mercurial report on the incoming changes once each transaction
  is saved, similar to when pulling from a regular repository.
* Remove some unnecessary caching in an attempt to decrease memory
  footprint.
* Advance phases during the pull rather than at the end.
* With ``hggit.usephases``, allow publishing tags and specific remotes
  on pull, as well as publishing the remote ``HEAD`` on push.
* Change defaults to drop illegal paths rather than aborting the
  conversion; this is adjustable using the ``hggit.invalidpaths``
  configuration option.
* Allow updating bookmarks from obsolete commits to their successors.

Bug fixes:

* Adjust publishing of branches to correspond to the documentation.
  Previously, e.g. listing ``master`` would publish a local bookmark
  even if diverged from the remote.
* Handle corrupt repositories gracefully in the ``gverify`` command,
  and allow checking repository integrity.
* Only apply extension wrappers when the extension is actually
  enabled rather than just loaded.
* Fix pulling with ``phases.new-commit`` set to ``secret``. (#266)
* Detect divergence with a branch bookmark suffix.
* Fix flawed handling of remote messages on pull and push, which
  caused most such messages to be discarded.
* Report a helpful error when attempting to push or convert with
  commits missing in the Git repository. Also, issue a warning when
  creating a new Git repository with a non-empty map, as that may lead
  to the former.
* Ensure that ``gimport`` also synchronises tags.
* Address a bug where updating bookmarks might fail with certain
  obsolete commits.
* Handle missing Git commits gracefully. (#376)

Other changes:

* Require ``setuptools`` for building, and use ``setuptools_scm`` for
  determining the version of the extension.
* Refactoring and reformatting of the code base.

hg-git 0.10.4 (2022-01-26)
==========================

This is a minor release, focusing on bugs and compatibility.

Bug fixes:

* Fix compatibility with the ``mercurial_keyring`` extension. (#360)
* Add missing test files to the source archive. (#375)
* Fix tests with Git 2.34.

hg-git 0.10.3 (2021-11-16)
==========================

This is a minor release, focusing on bugs and compatibility.

Enhancements:

* Add support for Mercurial 6.0.

hg-git 0.10.2 (2021-07-31)
==========================

This is a minor release, focusing on bugs and compatibility.

Enhancements:

* Add support for Mercurial 5.9.

Bug fixes:

* Fix the ``git.authors`` configuration option, broken in Python 3.

hg-git 0.10.1 (2021-05-12)
==========================

This is a minor release, focusing on bugs and compatibility.

Enhancements:

* Add support for Mercurial 5.8.

Bug fixes:

* Fix some documentation issues.
* Don't overwrite annotated tags on push.
* Fix an issue where pushing a repository without any bookmarks would
  push secret changesets.

hg-git 0.10.0 (2021-02-01)
==========================

The 0.10.x series will be the last one supporting Python 2.7 and
Python 3.5. Future feature releases will only support Python 3.6 and
later and Mercurial 5.2 or later.

Enhancements:

* Add support for proper HTTP authentication, using either
  ``~/.git-credentials`` or just as with any other Mercurial remote
  repository. Previously, the only place to specify credentials was in
  the URL.
* Add ``--git`` option to ``hg tag`` for creating lightweight Git tags.
* Always show Git tags and remotes in ``hg log``, even if marked as
  obsolete.
* Support ``{gitnode}`` keyword in templates for incoming changes.
* Support HTTP authentication using either the Mercurial
  configuration, ``git-credentials`` or a user prompt.
* Support accessing Git repositories using ``file://`` URIs.
* Optimise writing the map between Mercurial and Git commits.
* Add ``debuggitdir`` command that prints the path to the cached Git
  repository.

Bug fixes:

* Fix pulling changes that build on obsoleted changesets.
* Fix using ``git-cleanup`` from a shared repository.
* Fix scp-style “URIs” on Windows.
* Fix ``hg status`` crashing when using ``.gitignore`` and a directory
  is not readable.
* Fix support for ``.gitignore`` from shared repositories and when
  using a Mercurial built with Rust extensions.
* Add ``brotli`` to list of modules ignored by Mercurial's
  ``demandimport``, so ``urllib3`` can detect its absence on Python 2.7.
* Fix the ``git`` protocol on Python 3.
* Address a deprecation in Dulwich 0.20.6 when pushing to Git.
* Fix configuration path sub-options such as ``remote:pushurl``.
* Fix pushing to Git when invalid references exist by disregarding
  them.
* Always save the commit map after an import.
* Add support for using Python 3 on Windows.
* Mark ``gimport``, ``gexport`` and ``gclear`` as advanced as they are
  either complicated to understand or dangerous.
* Handle backslashes in ``.gitignore`` correctly on Windows.
* Fix path auditing on Windows, so that e.g. ``.hg`` and ``.git``
  trigger the appropriate behaviour.

Other changes:

* More robust tests and CI infrastructure.
* Drop support for Mercurial 4.3.
* Updated documentation.
