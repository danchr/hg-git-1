Test that extra metadata (renames, copies, and other extra metadata) roundtrips
across from hg to git
  $ . "$TESTDIR/testutil"

  $ git init -q gitrepo
  $ cd gitrepo
  $ touch a
  $ git add a
  $ fn_git_commit -ma
  $ git checkout -b not-master 2>&1 | sed s/\'/\"/g
  Switched to a new branch "not-master"

  $ cd ..
  $ hg clone gitrepo hgrepo
  importing 1 git commits
  new changesets aa9eb6424386 (1 drafts)
  updating to bookmark not-master
  1 files updated, 0 files merged, 0 files removed, 0 files unresolved
  $ cd hgrepo
  $ hg mv a b
  $ fn_hg_commit -mb
  $ hg up 0
  1 files updated, 0 files merged, 1 files removed, 0 files unresolved
  (leaving bookmark not-master)
  $ touch c
  $ hg add c
  $ fn_hg_commit -mc

Rebase will add a rebase_source

  $ hg --config extensions.rebase= rebase -s 1 -d 2
  rebasing 1:4c7da7adf18b * (glob)
  saved backup bundle to $TESTTMP/*.hg (glob)
  $ hg up 2
  1 files updated, 0 files merged, 1 files removed, 0 files unresolved

Add a commit with multiple extra fields
  $ hg bookmark b1
  $ touch d
  $ hg add d
  $ fn_hg_commitextra --field zzzzzzz=datazzz --field aaaaaaa=dataaaa
  $ hg log --graph --template "{rev} {node} {desc|firstline}\n{join(extras, ' ')}\n\n"
  @  3 f01651cfcc9337fbd9700d5018ca637a2911ed28
  |  aaaaaaa=dataaaa branch=default zzzzzzz=datazzz
  |
  o  2 03f4cf3c429050e2204fb2bda3a0f93329bdf4fd b
  |  branch=default rebase_source=4c7da7adf18b785726a7421ef0d585bb5762990d
  |
  o  1 a735dc0cd7cc0ccdbc16cfa4326b19c707c360f4 c
  |  branch=default
  |
  o  0 aa9eb6424386df2b0638fe6f480c3767fdd0e6fd a
     branch=default hg-git-rename-source=git
  

  $ hg push -r b1
  pushing to $TESTTMP/gitrepo
  searching for changes
  adding objects
  remote: found 0 deltas to reuse
  added 3 commits with 3 trees and 0 blobs
  adding reference refs/heads/b1

  $ hg bookmark b2
  $ hg mv c c2
  $ hg mv d d2
  $ fn_hg_commitextra --field yyyyyyy=datayyy --field bbbbbbb=databbb

Test some nutty filenames
  $ hg book b3
#if windows
  $ hg mv c2 'c2 => c3'
  abort: filename contains '>', which is reserved on Windows: "c2 => c3"
  [255]
  $ hg mv c2 c3
  $ fn_hg_commit -m 'dummy commit'
  $ hg mv c3 c4
  $ fn_hg_commit -m 'dummy commit'
#else
  $ hg mv c2 'c2 => c3'
  warning: filename contains '>', which is reserved on Windows: 'c2 => c3'
  $ fn_hg_commit -m 'test filename with arrow'
  $ hg mv 'c2 => c3' 'c3 => c4'
  warning: filename contains '>', which is reserved on Windows: 'c3 => c4'
  $ fn_hg_commit -m 'test filename with arrow 2'
  $ hg log --graph --template "{rev} {node} {desc|firstline}\n{join(extras, ' ')}\n\n" -l 3 --config "experimental.graphstyle.missing=|"
  @  6 bca4ba69a6844c133b069e227dfa043d41e3c197 test filename with arrow 2
  |  branch=default
  |
  o  5 864caad1f3493032f8d06f44a89dc9f1c039b09f test filename with arrow
  |  branch=default
  |
  o  4 58f855ae26f4930ce857e648d3dd949901cce817
  |  bbbbbbb=databbb branch=default yyyyyyy=datayyy
  |
#endif
  $ hg push -r b2 -r b3
  pushing to $TESTTMP/gitrepo
  searching for changes
  adding objects
  remote: found 0 deltas to reuse
  added 3 commits with 3 trees and 0 blobs
  adding reference refs/heads/b2
  adding reference refs/heads/b3

  $ cd ../gitrepo
  $ git cat-file commit b1
  tree 1b773a2eb70f29397356f8069c285394835ff85a
  parent 54776dace5849bdf273fb26737a48ef64804909d
  author test <none@none> 1167609613 +0000
  committer test <none@none> 1167609613 +0000
  HG:extra aaaaaaa:dataaaa
  HG:extra zzzzzzz:datazzz
  
  

  $ git cat-file commit b2
  tree 34ad62c6d6ad9464bfe62db5b3d2fa16aaa9fa9e
  parent 15beadd92324c9b88060a4ec4ffb350f988d7075
  author test <none@none> 1167609614 +0000
  committer test <none@none> 1167609614 +0000
  HG:rename c:c2
  HG:rename d:d2
  HG:extra bbbbbbb:databbb
  HG:extra yyyyyyy:datayyy
  
  

#if no-windows
  $ git cat-file commit b3
  tree e63df52695f9b06e54b37e7ef60d0c43994de620
  parent 5cafe2555a0666fcf661a3943277a9812a694a98
  author test <none@none> 1167609616 +0000
  committer test <none@none> 1167609616 +0000
  HG:rename c2%20%3D%3E%20c3:c3%20%3D%3E%20c4
  
  test filename with arrow 2
#endif
  $ cd ../gitrepo
  $ git checkout b1
  Switched to branch 'b1'
  $ commit_sha=$(git rev-parse HEAD)
  $ tree_sha=$(git rev-parse HEAD^{tree})

There's no way to create a Git repo with extra metadata via the CLI. Dulwich
lets you do that, though.

  >>> from dulwich.objects import Commit
  >>> from dulwich.porcelain import open_repo
  >>> repo = open_repo('.')
  >>> c = Commit()
  >>> c.author = b'test <test@example.org>'
  >>> c.author_time = 0
  >>> c.author_timezone = 0
  >>> c.committer = c.author
  >>> c.commit_time = 0
  >>> c.commit_timezone = 0
  >>> c.parents = [b'$commit_sha']
  >>> c.tree = b'$tree_sha'
  >>> c.message = b'extra commit\n'
  >>> c.extra.extend([(b'zzz:zzz', b'data:zzz'), (b'aaa:aaa', b'data:aaa'),
  ...                 (b'HG:extra', b'hgaaa:dataaaa'),
  ...                 (b'HG:extra', b'hgzzz:datazzz')])
  >>> repo.object_store.add_object(c)
  >>> repo.refs.set_if_equals(b'refs/heads/master', None, c.id)
  True

  $ git cat-file commit master
  tree 1b773a2eb70f29397356f8069c285394835ff85a
  parent 15beadd92324c9b88060a4ec4ffb350f988d7075
  author test <test@example.org> 0 +0000
  committer test <test@example.org> 0 +0000
  zzz:zzz data:zzz
  aaa:aaa data:aaa
  HG:extra hgaaa:dataaaa
  HG:extra hgzzz:datazzz
  
  extra commit

  $ cd ..
  $ hg clone -qU gitrepo hgrepo2
  $ cd hgrepo2
  $ hg log -G -r :5 -T "{rev} {node} {desc|firstline}\n{join(extras, ' ')}\n\n"
  o  5 58f855ae26f4930ce857e648d3dd949901cce817
  |  bbbbbbb=databbb branch=default yyyyyyy=datayyy
  |
  | o  4 90acc8c23fcfaeb0930c03c849923a696fd9013c extra commit
  |/   GIT0-zzz%3Azzz=data%3Azzz GIT1-aaa%3Aaaa=data%3Aaaa branch=default hgaaa=dataaaa hgzzz=datazzz
  |
  o  3 f01651cfcc9337fbd9700d5018ca637a2911ed28
  |  aaaaaaa=dataaaa branch=default zzzzzzz=datazzz
  |
  o  2 03f4cf3c429050e2204fb2bda3a0f93329bdf4fd b
  |  branch=default rebase_source=4c7da7adf18b785726a7421ef0d585bb5762990d
  |
  o  1 a735dc0cd7cc0ccdbc16cfa4326b19c707c360f4 c
  |  branch=default
  |
  o  0 aa9eb6424386df2b0638fe6f480c3767fdd0e6fd a
     branch=default hg-git-rename-source=git
  
