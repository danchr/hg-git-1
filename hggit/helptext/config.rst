``git``
-------

Control how the Hg-Git extension interacts with Git.

``authors``
  Git uses a strict convention for "author names" when representing
  changesets, using the form ``[realname] [email address]``. Mercurial
  encourages this convention as well but is not as strict, so it's not
  uncommon for a Mercurial repository to have authors listed as, for example,
  simple usernames. hg-git by default will attempt to translate Mercurial
  usernames using the following rules:

  -  If the Mercurial username fits the pattern ``NAME <EMAIL>``, the Git
     name will be set to NAME and the email to EMAIL.
  -  If the Mercurial username looks like an email (if it contains an
     ``@``), the Git name and email will both be set to that email.
  -  If the Mercurial username consists of only a name, the email will be
     set to ``none@none``.
  -  Illegal characters (stray ``<``\ s or ``>``\ s) will be stripped out,
     and for ``NAME <EMAIL>`` usernames, any content after the
     right-bracket (for example, a second ``>``) will be turned into a
     url-encoded sigil like ``ext:(%3E)`` in the Git author name.

  Since these default behaviors may not be what you want (``none@none``,
  for example, shows up unpleasantly on GitHub as "illegal email
  address"), the ``git.authors`` option provides for an "authors
  translation file" that will be used during outgoing transfers from
  Mercurial to Git only, by modifying ``hgrc`` as such:

  ::

     [git]
     authors = authors.txt

  Where ``authors.txt`` is the name of a text file containing author name
  translations, one per each line, using the following format:

  ::

     johnny = John Smith <jsmith@foo.com>
     dougie = Doug Johnson <dougiej@bar.com>

  Empty lines and lines starting with a ``#`` are ignored.

  It should be noted that this translation is in *the Mercurial to Git
  direction only*. Changesets coming from Git back to Mercurial will not
  translate back into Mercurial usernames, so it's best that the same
  username/email combination be used on both the Mercurial and Git sides; the
  author file is mostly useful for translating legacy changesets.

``branch_bookmark_suffix``
  Hg-Git does not convert between Mercurial named branches and git
  branches as the two are conceptually different; instead, it uses
  Mercurial bookmarks to represent the concept of a Git branch.
  Therefore, when translating a Mercurial repository over to Git, you
  typically need to create bookmarks to mirror all the named branches
  that you'd like to see transferred over to Git. The major caveat with
  this is that you can't use the same name for your bookmark as that of
  the named branch, and furthermore there's no feasible way to rename a
  branch in Mercurial. For the use case where one would like to transfer
  a Mercurial repository over to Git, and maintain the same named
  branches as are present on the hg side, the ``branch_bookmark_suffix``
  might be all that's needed. This presents a string "suffix" that will
  be recognized on each bookmark name, and stripped off as the bookmark
  is translated to a Git branch:

  ::

     [git]
     branch_bookmark_suffix=_bookmark

  Above, if a Mercurial repository had a named branch called
  ``release_6_maintenance``, you could then link it to a bookmark called
  ``release_6_maintenance_bookmark``. hg-git will then strip off the
  ``_bookmark`` suffix from this bookmark name, and create a Git branch
  called ``release_6_maintenance``. When pulling back from Git to hg, the
  ``_bookmark`` suffix is then applied back, if and only if a Mercurial named
  branch of that name exists. E.g., when changes to the
  ``release_6_maintenance`` branch are checked into Git, these will be
  placed into the ``release_6_maintenance_bookmark`` bookmark on hg. But
  if a new branch called ``release_7_maintenance`` were pulled over to hg,
  and there was not a ``release_7_maintenance`` named branch already, the
  bookmark will be named ``release_7_maintenance`` with no usage of the
  suffix.

  The ``branch_bookmark_suffix`` option is, like the ``authors`` option,
  intended for migrating legacy hg named branches. Going forward, a Mercurial
  repository that is to be linked with a Git repository should only use bookmarks for
  named branching.

``findcopiesharder``
  Whether to consider unmodified files as copy sources. This is a very
  expensive operation for large projects, so use it with caution. Similar
  to ``git diff``'s --find-copies-harder option.

``intree``
  Hg-Git keeps a Git repository clone for reading and updating. By
  default, the Git clone is the subdirectory ``git`` in your local
  Mercurial repository. If you would like this Git clone to be at the same
  level of your Mercurial repository instead (named ``.git``), add the
  following to your ``hgrc``:

  ::

     [git]
     intree = True

  Please note that changing this setting in an existing repository
  doesn't move the local Git repository. You will either have to do so
  yourself, or issue an :hg:`pull` after the fact to repopulate the new
  location.

``mindate``
  If set, branches where the latest commit's commit time is older than
  this will not be imported. Accepts any date formats that Mercurial does
  -- see :hg:`help dates` for more.


``public``
  A list of Git branches that should be considered "published", and
  therefore converted to Mercurial in the 'public' phase. This is only
  used if ``hggit.usephases`` is set.

``pull-prune-remote-branches``
  Before fetching, remove any remote-tracking references, or
  pseudo-tags, that no longer exist on the remote. This is equivalent to
  the ``--prune`` option to ``git fetch``, and means that pseudo-tags
  for remotes -- such as ``default/master`` -- always actually reflect
  what's on the remote.

  This option is enabled by default.

``pull-prune-bookmarks``
  On pull, delete any unchanged bookmarks removed on the remote. In
  other words, if e.g. the ``thebranch`` bookmark remains at
  ``default/thebranch``, and the branch is deleted in Git, pulling
  deletes the bookmark.

  This option is enabled by default.

``renamelimit``
  The number of files to consider when performing the copy/rename
  detection. Detection is disabled if the number of files modified in a
  commit is above the limit. Detection is O(N^2) in the number of files
  modified, so be sure not to set the limit too high. Similar to Git's
  ``diff.renameLimit`` config. The default is "400", the same as Git.

``similarity``
  Specify how similar files modified in a Git commit must be to be
  imported as Mercurial renames or copies, as a percentage between "0"
  (disabled) and "100" (files must be identical). For example, "90" means
  that a delete/add pair will be imported as a rename if more than 90% of
  the file has stayed the same. The default is "0" (disabled).


``hggit``
---------

Control behavior of the Hg-Git extension.

``mapsavefrequency``
  By default, hg-git only saves the results of a conversion at the end.
  Use this option to enable resuming long-running pulls and pushes. Set
  this to a number greater than 0 to allow resuming after converting
  that many commits. This can help when the conversion encounters an
  error partway through a large batch of changes. Otherwise, an error or
  interruption will roll back the transaction, similar to regular
  Mercurial.

  Defaults to 1000.

  Please note that this is disregarded for an initial clone, as any
  error or interruption will delete the destination. So instead of
  cloning a large Git repository, you might want to pull instead:

  ::

    $ hg init linux
    $ cd linux
    $ echo "[paths]\ndefault = https://github.com/torvalds/linux" > .hg/hgrc
    $ hg pull

  ...and be extremely patient. Please note that converting very large
  repositories may take *days* rather than mere *hours*, and may run
  into issues with available memory for very long running clones. Even
  any small, undiscovered leak will build up when processing hundreds of
  thousands of files and commits. Cloning the Linux kernel is likely a
  pathological case, but other storied repositories such as CPython do
  work well, even if the initial clone requires a some patience.

``usephases``
  When converting Git revisions to Mercurial, place them in the 'public'
  phase as appropriate. Namely, revisions that are reachable from the
  remote Git repository's default branch, or ``HEAD``, will be marked
  *public*. For most repositories, this means the remote ``master``
  branch will be converted as public. The same applies to any commits
  tagged in the remote.

  To restrict publishing to specific branches or tags, use the
  ``git.public`` option.

  Publishing commits prevents their modification, and speeds up many
  local Mercurial operations, such as :hg:`shelve`.

``fetchbuffer``
  Data fetched from Git is buffered in memory, unless it exceeds the
  given limit, in megabytes. By default, flush the buffer to disk when
  it exceeds 100MB.

``retries``
  Interacting with a remote Git repository may require authentication.
  Normally, this will trigger a prompt and a retry, and this option
  restricts the amount of retries. Defaults to 3.

``invalidpaths``
  Both Mercurial and Git consider paths as just bytestrings internally,
  and allow almost anything. The difference, however, is in the _almost_
  part. For example, many Git servers will reject a push for security
  reasons if it contains a nested Git repository. Similarly, Mercurial
  cannot checkout commits with a nested repository, and it cannot even
  store paths containing an embedded newline or carrage return
  character.

  The default is to issue a warning and skip these paths. You can
  change this by setting ``hggit.invalidpaths`` in ``.hgrc``:

  ::

    [hggit]
    invalidpaths = keep

  Possible values are ``keep``, ``skip`` or ``abort``. Prior to 1.0,
  the default was ``abort``.
