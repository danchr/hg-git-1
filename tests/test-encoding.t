# -*- coding: utf-8 -*-

Test fails on Windows, it seems, as the messages aren't
latin1-encoded. This may be caused by e.g. environment variables being
Unicode on Python 3, or something else. Just running this test on
POSIX systems should suffice, for now.

(Mercurial generally conforms to the UNIX & Python 2 custom of text
being ASCII-like binary data with an optional encoding. As this is
generally unsuitable for an internationalised UI, Windows and most
other desktop environments enforce a particular encoding. Due to
compatibility, Windows gets weird by having _two_ possible encodings:
an 8-bit codepage or full UTF-16. Way back, this lead to all sorts of
discussions w.r.t. Mercurial, but in this case, we can just skip the
test and hope for the best.)

#require no-windows

Load commonly used test logic
  $ . "$TESTDIR/testutil"

  $ git init gitrepo
  Initialized empty Git repository in $TESTTMP/gitrepo/.git/
  $ cd gitrepo

utf-8 encoded commit message
  $ echo alpha > alpha
  $ git add alpha
  $ fn_git_commit -m 'add älphà'

Create some commits using latin1 encoding
The warning message changed in Git 1.8.0
  $ . $TESTDIR/latin-1-encoding
  Warning: commit message (did|does) not conform to UTF-8. (re)
  You may want to amend it after fixing the message, or set the config
  variable i18n.commit[eE]ncoding to the encoding your project uses. (re)
  Warning: commit message (did|does) not conform to UTF-8. (re)
  You may want to amend it after fixing the message, or set the config
  variable i18n.commit[eE]ncoding to the encoding your project uses. (re)

  $ cd ..
  $ git init -q --bare repo.git

  $ hg clone gitrepo hgrepo
  importing 4 git commits
  new changesets 87cd29b67a91:b8a0ac52f339 (4 drafts)
  updating to bookmark master
  4 files updated, 0 files merged, 0 files removed, 0 files unresolved
  $ cd hgrepo

  $ HGENCODING=utf-8 hg log --graph --debug
  @  changeset:   3:b8a0ac52f339ccd6d5729508bac4aee6e8b489d8
  |  bookmark:    master
  |  tag:         default/master
  |  tag:         tip
  |  phase:       draft
  |  parent:      2:8bc4d64940260d4a1e70b54c099d3a76c83ff41e
  |  parent:      -1:0000000000000000000000000000000000000000
  |  manifest:    3:ea49f93388380ead5601c8fcbfa187516e7c2ed8
  |  user:        tést èncödîng <test@example.org>
  |  date:        Mon Jan 01 00:00:13 2007 +0000
  |  files+:      delta
  |  extra:       author=$ \x90\x01\x01\xe9\x91\x03\x03\x01\xe8\x91\x08\x02\x01\xf6\x91\x0c\x01\x01\xee\x91\x0f\x15
  |  extra:       branch=default
  |  extra:       committer=test <test@example.org> 1167609613 0
  |  extra:       encoding=latin-1
  |  extra:       hg-git-rename-source=git
  |  extra:       message=\x0c\n\x90\x05\x01\xe9\x91\x07\x02\x01\xe0\x91\x0b\x01
  |  description:
  |  add d\xc3\xa9lt\xc3\xa0 (esc)
  |
  |
  o  changeset:   2:8bc4d64940260d4a1e70b54c099d3a76c83ff41e
  |  phase:       draft
  |  parent:      1:f35a3100b78e57a0f5e4589a438f952a14b26ade
  |  parent:      -1:0000000000000000000000000000000000000000
  |  manifest:    2:f580e7da3673c137370da2b931a1dee83590d7b4
  |  user:        t\xc3\xa9st \xc3\xa8nc\xc3\xb6d\xc3\xaeng <test@example.org> (esc)
  |  date:        Mon Jan 01 00:00:12 2007 +0000
  |  files+:      gamma
  |  extra:       branch=default
  |  extra:       committer=test <test@example.org> 1167609612 0
  |  extra:       hg-git-rename-source=git
  |  description:
  |  add g\xc3\xa4mm\xc3\xa2 (esc)
  |
  |
  o  changeset:   1:f35a3100b78e57a0f5e4589a438f952a14b26ade
  |  phase:       draft
  |  parent:      0:87cd29b67a9159eec3b5495b0496ef717b2769f5
  |  parent:      -1:0000000000000000000000000000000000000000
  |  manifest:    1:f0bd6fbafbaebe4bb59c35108428f6fce152431d
  |  user:        t\xc3\xa9st \xc3\xa8nc\xc3\xb6d\xc3\xaeng <test@example.org> (esc)
  |  date:        Mon Jan 01 00:00:11 2007 +0000
  |  files+:      beta
  |  extra:       branch=default
  |  extra:       committer=test <test@example.org> 1167609611 0
  |  extra:       hg-git-rename-source=git
  |  description:
  |  add beta
  |
  |
  o  changeset:   0:87cd29b67a9159eec3b5495b0496ef717b2769f5
     phase:       draft
     parent:      -1:0000000000000000000000000000000000000000
     parent:      -1:0000000000000000000000000000000000000000
     manifest:    0:8b8a0e87dfd7a0706c0524afa8ba67e20544cbf0
     user:        test <test@example.org>
     date:        Mon Jan 01 00:00:10 2007 +0000
     files+:      alpha
     extra:       branch=default
     extra:       hg-git-rename-source=git
     description:
     add \xc3\xa4lph\xc3\xa0 (esc)
  
  

  $ hg debug-remove-hggit-state
  clearing out the git cache data
  $ hg push ../repo.git
  pushing to ../repo.git
  searching for changes
  adding objects
  remote: found 0 deltas to reuse (dulwich0210 !)
  added 4 commits with 4 trees and 4 blobs
  adding reference refs/heads/master

  $ cd ..
  $ git --git-dir=repo.git log --pretty=medium
  commit e85fef6b515d555e45124a5dc39a019cf8db9ff0
  Author: t\xe9st \xe8nc\xf6d\xeeng <test@example.org> (esc)
  Date:   Mon Jan 1 00:00:13 2007 +0000
  
      add d\xe9lt\xe0 (esc)
  
  commit bd576458238cbda49ffcfbafef5242e103f1bc24
  Author: * <test@example.org> (glob)
  Date:   Mon Jan 1 00:00:12 2007 +0000
  
      add g*mm* (glob)
  
  commit 7a7e86fc1b24db03109c9fe5da28b352de59ce90
  Author: * <test@example.org> (glob)
  Date:   Mon Jan 1 00:00:11 2007 +0000
  
      add beta
  
  commit 0530b75d8c203e10dc934292a6a4032c6e958a83
  Author: test <test@example.org>
  Date:   Mon Jan 1 00:00:10 2007 +0000
  
      add älphà

Stashing binary deltas in other extra keys may wasn't the most
forward-looking of choices, as it can lead to weird results if you
edit those keys:

  $ cp -r hgrepo hgrepo-evolve
  $ cd hgrepo-evolve
  $ cat >> .hg/hgrc <<EOF
  > [experimental]
  > evolution = all
  > [extensions]
  > amend =
  > rebase =
  > EOF
  $ hg pull -u
  pulling from $TESTTMP/gitrepo
  importing 1 git commits
  0 files updated, 0 files merged, 0 files removed, 0 files unresolved
  $ hg log --debug -r .
  changeset:   3:b8a0ac52f339ccd6d5729508bac4aee6e8b489d8
  bookmark:    master
  tag:         default/master
  tag:         tip
  phase:       draft
  parent:      2:8bc4d64940260d4a1e70b54c099d3a76c83ff41e
  parent:      -1:0000000000000000000000000000000000000000
  manifest:    3:ea49f93388380ead5601c8fcbfa187516e7c2ed8
  user:        t?st ?nc?d?ng <test@example.org>
  date:        Mon Jan 01 00:00:13 2007 +0000
  files+:      delta
  extra:       author=$ \x90\x01\x01\xe9\x91\x03\x03\x01\xe8\x91\x08\x02\x01\xf6\x91\x0c\x01\x01\xee\x91\x0f\x15
  extra:       branch=default
  extra:       committer=test <test@example.org> 1167609613 0
  extra:       encoding=latin-1
  extra:       hg-git-rename-source=git
  extra:       message=\x0c\n\x90\x05\x01\xe9\x91\x07\x02\x01\xe0\x91\x0b\x01
  description:
  add d?lt?
  
  
  $ hg amend -u 'simple user <test@example.com>' -m 42
  $ hg gexport
  warning: disregarding possibly invalid metadata in ea036eaa4643
  warning: disregarding possibly invalid metadata in ea036eaa4643
  $ cd ..

create a tag with a latin-1 name -- this is horrible, as tags normally
are utf-8, but this allows us to check two things:

1) that tags safely roundtrip regardless of local encoding
2) we can't store such tags on UTF-8 only file systems

The first case isn't actually the case at the moment, but can we store
them? The second case allows us to check issue #397 on macOS and
Linux, i.e. refs we cannot store. That's much easier to run into on
Windows, e.g. with double quotes, but we don't have CI coverage for
that platform.

  $ hg clone -U repo.git hgrepo-tags
  importing 4 git commits
  new changesets 87cd29b67a91:aabeccdc8b1e (4 drafts)
  $ cd hgrepo-tags
  $ hg up tip
  4 files updated, 0 files merged, 0 files removed, 0 files unresolved
  $ fn_hg_tag ascii-tag
  $ "$PYTHON" << EOF
  > with open('.hgtags', 'a', encoding='utf-8') as f:
  >   f.write('aabeccdc8b1e82054dfce21373bda3b2455900e2 uni-täg\n')
  > with open('.hgtags', 'a', encoding='latin1') as f:
  >   f.write('aabeccdc8b1e82054dfce21373bda3b2455900e2 lat-täg\n')
  > EOF
  $ fn_hg_commit --amend -m 'add loads of tags, some good, some bad'
  $ cat .hgtags
  aabeccdc8b1e82054dfce21373bda3b2455900e2 ascii-tag
  aabeccdc8b1e82054dfce21373bda3b2455900e2 uni-t\xc3\xa4g (esc)
  aabeccdc8b1e82054dfce21373bda3b2455900e2 lat-t\xe4g (esc)

#if unicodefs
  $ hg push
  pushing to $TESTTMP/repo.git
  warning: not exporting tag 'uni-t?g' due to invalid name
  warning: not exporting tag 'lat-t?g' due to invalid name
  searching for changes
  remote: found 0 deltas to reuse (dulwich0210 !)
  adding reference refs/tags/ascii-tag
  $ HGENCODING=latin-1 hg push
  pushing to $TESTTMP/repo.git
  warning: failed to save ref refs/tags/lat-t\xe4g (esc)
  warning: failed to save ref refs/tags/uni-t\xe4g (esc)
  searching for changes
  no changes found (ignoring 1 changesets without bookmarks or tags)
  [1]
  $ HGENCODING=utf-8 hg push
  pushing to $TESTTMP/repo.git
  searching for changes
  remote: found 0 deltas to reuse (dulwich0210 !)
  adding reference refs/tags/lat-t\xc3\xa4g (esc)
  adding reference refs/tags/uni-t\xc3\xa4g (esc)
#else
  $ hg push
  pushing to $TESTTMP/repo.git
  warning: not exporting tag 'uni-t?g' due to invalid name
  warning: not exporting tag 'lat-t?g' due to invalid name
  searching for changes
  remote: found 0 deltas to reuse (dulwich0210 !)
  adding reference refs/tags/ascii-tag
  $ HGENCODING=latin-1 hg push
  pushing to $TESTTMP/repo.git
  searching for changes
  remote: found 0 deltas to reuse (dulwich0210 !)
  adding reference refs/tags/lat-t\xe4g (esc)
  adding reference refs/tags/uni-t\xe4g (esc)
  $ HGENCODING=utf-8 hg push
  pushing to $TESTTMP/repo.git
  searching for changes
  remote: found 0 deltas to reuse (dulwich0210 !)
  adding reference refs/tags/lat-t\xc3\xa4g (esc)
  adding reference refs/tags/uni-t\xc3\xa4g (esc)
#endif
