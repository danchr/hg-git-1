commit hooks can see env vars
(and post-transaction one are run unlocked)

  $ . testutil


  $ fn_commit() {
  >   echo $2 > $2
  >   $1 add $2
  >   fn_${1}_commit -m $2
  > }
  $ hg init hgrepo
  $ cd hgrepo
  $ cat > .hg/hgrc <<EOF
  > [hooks]
  > gitimport = python:testlib.hooks.showargs
  > gitexport = python:testlib.hooks.showargs
  > pretxncommit = echo : pretxncommit
  > preoutgoing = python:testlib.hooks.showargs
  > prechangegroup = python:testlib.hooks.showargs
  > changegroup = python:testlib.hooks.showargs
  > incoming = python:testlib.hooks.showargs
  > EOF
  $ fn_commit hg a
  $ hg book master

  $ git init -q --bare ../repo.git
  $ cat >> .hg/hgrc <<EOF
  > [paths]
  > default = $TESTTMP/repo.git
  > EOF

Test pushing a single commit:

(The order of outgoing isn't stable, so only try it here.)

  $ hg push --config hooks.outgoing=python:testlib.hooks.showargs
  pushing to $TESTTMP/repo.git
  | preoutgoing.git=True
  | preoutgoing.source=push
  | preoutgoing.url=$TESTTMP/repo.git
  | gitexport.nodes=[b'cc0ffa47c67ebcb08dc50f69afaecb5d622cc777']
  | gitexport.git=True
  searching for changes
  | prechangegroup.source=push
  | prechangegroup.git=True
  | prechangegroup.url=$TESTTMP/repo.git
  | outgoing.source=push
  | outgoing.git=True
  | outgoing.url=$TESTTMP/repo.git
  | outgoing.node=cc0ffa47c67ebcb08dc50f69afaecb5d622cc777
  | outgoing.git_node=681fb452693218a33986174228560272a6fad87a
  adding objects
  remote: found 0 deltas to reuse (dulwich0210 !)
  added 1 commits with 1 trees and 1 blobs
  adding reference refs/heads/master

  $ git clone -q ../repo.git ../gitrepo
  $ cd ../gitrepo
  $ fn_commit git b
  $ fn_commit git c
  $ git push
  To $TESTTMP/hgrepo/../repo.git
     681fb45..1dab31e  master -> master
  $ cd ../hgrepo

Hooks on pull?

  $ hg pull -u
  pulling from $TESTTMP/repo.git
  | gitimport.source=pull
  | gitimport.git=True
  | gitimport.names=[b'default']
  | gitimport.refs={b'HEAD': b'1dab31e7bc9691ba42a2fe7b14680694770bc527', b'refs/heads/master': b'1dab31e7bc9691ba42a2fe7b14680694770bc527'}
  | gitimport.heads=None
  importing 2 git commits
  : pretxncommit
  | incoming.git=True
  | incoming.source=pull
  | incoming.node=382ad5fa1d7727210384d40fa1539af52ca632c5
  | incoming.git_node=92150d1529ccaea34a6b36fe4144993193080499
  : pretxncommit
  | incoming.git=True
  | incoming.source=pull
  | incoming.node=892115eea5c32152e09ae4013c9a119d7b534049
  | incoming.git_node=1dab31e7bc9691ba42a2fe7b14680694770bc527
  updating bookmark master
  | changegroup.source=push
  | changegroup.git=True
  | changegroup.node=382ad5fa1d7727210384d40fa1539af52ca632c5
  | changegroup.node_last=892115eea5c32152e09ae4013c9a119d7b534049
  new changesets 382ad5fa1d77:892115eea5c3 (2 drafts)
  updating to active bookmark master
  2 files updated, 0 files merged, 0 files removed, 0 files unresolved

Hooks on push?

  $ fn_commit hg d
  $ fn_commit hg e
  $ hg push
  pushing to $TESTTMP/repo.git
  | preoutgoing.git=True
  | preoutgoing.source=push
  | preoutgoing.url=$TESTTMP/repo.git
  | gitexport.nodes=[b'cc6164a17449d58d7811ff3918f33f89c2c83fa5', b'46737f6a4c9d8307b681cbb2e9e2e5419cc87f82']
  | gitexport.git=True
  searching for changes
  | prechangegroup.source=push
  | prechangegroup.git=True
  | prechangegroup.url=$TESTTMP/repo.git
  adding objects
  remote: found 0 deltas to reuse (dulwich0210 !)
  added 2 commits with 2 trees and 2 blobs
  updating reference refs/heads/master


And what does Mercurial do?

  $ cat >> .hg/hgrc <<EOF
  > [hooks]
  > outgoing = python:testlib.hooks.showargs
  > EOF

On push:

  $ hg init ../hgrepo-copy
  $ hg push ../hgrepo-copy
  pushing to ../hgrepo-copy
  searching for changes
  | preoutgoing.source=push
  | outgoing.node=cc0ffa47c67ebcb08dc50f69afaecb5d622cc777
  | outgoing.source=push
  adding changesets
  adding manifests
  adding file changes
  added 5 changesets with 5 changes to 5 files

With more than one head:

  $ rm -r ../hgrepo-copy
  $ hg init ../hgrepo-copy
  $ hg book -i
  $ hg branch -q abranch
  $ fn_commit hg x
  $ hg up -q default
  $ hg branch -q alsoabranch
  $ fn_commit hg y
  $ hg push ../hgrepo-copy
  pushing to ../hgrepo-copy
  searching for changes
  | preoutgoing.source=push
  | outgoing.node=cc0ffa47c67ebcb08dc50f69afaecb5d622cc777
  | outgoing.source=push
  adding changesets
  adding manifests
  adding file changes
  added 7 changesets with 7 changes to 7 files (+1 heads)

On pull:

  $ hg debugstrip --no-backup tip
  0 files updated, 0 files merged, 1 files removed, 0 files unresolved
  $ hg pull ../hgrepo-copy
  pulling from ../hgrepo-copy
  searching for changes
  | prechangegroup.txnname=pull
  file://$TESTTMP/hgrepo-copy
  | prechangegroup.source=pull
  | prechangegroup.url=file:$TESTTMP/hgrepo-copy
  adding changesets
  adding manifests
  adding file changes
  added 1 changesets with 1 changes to 1 files (+1 heads)
  new changesets d4097d98a390
  | changegroup.txnname=pull
  file://$TESTTMP/hgrepo-copy
  | changegroup.source=pull
  | changegroup.url=file:$TESTTMP/hgrepo-copy
  | changegroup.node=d4097d98a3905be88e8a566039b1fdcca06e0d2e
  | changegroup.node_last=d4097d98a3905be88e8a566039b1fdcca06e0d2e
  | incoming.txnname=pull
  file://$TESTTMP/hgrepo-copy
  | incoming.source=pull
  | incoming.url=file:$TESTTMP/hgrepo-copy
  | incoming.node=d4097d98a3905be88e8a566039b1fdcca06e0d2e
  (run 'hg heads' to see heads)
