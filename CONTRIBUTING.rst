======================
Contributing to hg-git
======================

The short version:

* Patches should have a good summary line for first line of commit message
* Patch series should be sent primarily as `merge requests`_ or to the
  `Google Group`_ at <hg-git@googlegroups.com>.
* Patch needs to do exactly one thing.
* The test suite passes, as enforced by the continuous integration on
  Heptapod.

.. _merge requests: https://foss.heptapod.net/mercurial/hg-git
.. _Google Group: https://groups.google.com/forum/#!forum/hg-git

Long version
------------

We use a variant of Mercurial's `own contribution system
<https://www.mercurial-scm.org/wiki/ContributingChanges>`_. Key
differences are (by rule number):

1
  For hg-git, we're not strict about the ``topic: a few words`` format
  for the first line, but do insist on a sensible summary as the first
  commit line.

2
  You can cross-reference Heptapod issues in the ``#NNN`` format.

10
  We use mostly pep8 style. The current codebase is a mess, but new
  code should be basically pep8.

To submit a Merge Request, please ask for Developer rights using the
*Request access* link. We usually respond to that relatively quickly,
but you can expedite the request by sending a mail to the list. Then,
following the instructions of the following tutorial should be enough:

https://heptapod.net/pages/quick-start-guide.html

If you do a merge request, we're still going to expect you to
provide a clean history, and to be willing to rework history so it's
clean before we push the "merge" button. If you're uncomfortable with
history editing, we'll clean up the commits before merging.
