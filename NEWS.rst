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
