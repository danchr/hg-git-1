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

We use a variant of Mercurial's `own contribution guidelines`_. Key
differences are (by rule number):

.. _own contribution guidelines:
   https://www.mercurial-scm.org/wiki/ContributingChanges

2
  You can cross-reference Heptapod issues in the ``#NNN`` format.

To submit a Merge Request, please ask for Developer rights using the
`Request access`_ link. We usually respond to that relatively quickly,
but you can expedite the request by sending a mail to the list. Please
note that we generally do a quick cursory check of people requesting
access to ensure that there's a human at the other end. Then,
following the instructions of the `Heptapod tutorial`_ should be enough.

.. _Request access:
   https://foss.heptapod.net/mercurial/hg-git/-/project_members/request_access
.. _Heptapod tutorial: https://heptapod.net/pages/quick-start-guide.html

If you do a merge request, we're still going to expect you to
provide a clean history, and to be willing to rework history so it's
clean before we push the "merge" button. If you're uncomfortable with
history editing, we'll clean up the commits before merging.

Compatibility policy
--------------------

We generally follow `semantic versioning`_ guidelines: Major releases,
that is ``x.0.0``, are for significant changes to user experience,
especially new features or changes likely to affect workflow. Minor
releases, ``x.y.0``, are for less significant changes or adjustments
to user experience, including bug fixes, but they needn't retain
_exact_ compatibility. Patch releases, ``x.y.z``, are exclusively for
breaking bugs and compatibility.

.. _semantic versioning: https://semver.org

We can drop compatibility for unsupported versions of Python,
Mercurial or Dulwich in anything but patch releases.

There is no fixed policy for which versions of Mercurial and Dulwich
we support, but as loose guideline, versions prior to the version
that ships in the latest Ubuntu LTS release may be dropped if they are
older than a year and interfere with new development. Unfortunately,
due to dropping support for Python 2.7, hg-git does not work on any
shipped Ubuntu LTS, as-is, since 20.04 used 5.3.1 on Python 2.7, but
only shipped Dulwich for Python 3.6. Once 22.04 is out, that will be
our bare minimum.

We commit to supporting any version of Python at least as long as it
receives security updates from ``python.org``, unless it conflicts
with the requirements of a supported Ubuntu LTS.

The authoritative source for dependency requirements is
``.gitlab-ci.yml``, although ``setup.cfg`` and ``hggit/__init__.py``
also list them.
