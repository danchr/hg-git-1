Load commonly used test logic
  $ . "$TESTDIR/testutil"


  $ cat >> "$HGRCPATH" << EOF
  > [ui]
  > merge = :merge3
  > EOF

init

  $ hg init repo
  $ cd repo

commit

  $ cat <<EOF > a
  > a
  > a
  > EOF
  $ hg add a
  $ fn_hg_commit -m 1
  $ cat <<EOF > a
  > a
  > a
  > a
  > EOF
  $ fn_hg_commit -m 2
  $ cat <<EOF > a
  > a
  > b
  > a
  > EOF
  $ fn_hg_commit -m 3

annotate multiple files

  $ hg annotate a
  0: a
  2: b
  1: a

  $ hg annotate --skip 1 a
  0: a
  2: b
  0* a

  $ hg gexport
  $ hg log -T '{rev}:{node} {gitnode}\n'
  2:beb139b96eec386addc02d48db524b7646ef1605 19388575d02e71e917e7013aa854d4a21c509819
  1:a9a255d66663f9216bdcf8dda69211d7280f7278 debec50a14cc4830584dd4fa1507c51cce1c098f
  0:8d4731bd0f4a57e123a79463b5294325be6cf8f0 88f28c06a1ede9a70852ab1bf9818150fabaaaa9

  $ cat <<EOF > .git-blame-ignore-revs
  > # this is a comment, and the next line should be ignored
  > # 19388575d02e71e917e7013aa854d4a21c509819
  > debec50a14cc4830584dd4fa1507c51cce1c098f
  > b4145d431a9fc5712ffe35f30b631eab89f7cb7f
  > EOF

  $ hg annotate a
  0: a
  2: b
  1: a
  $ hg annotate a \
  > --debug \
  > --config git.blame.ignoreRevsFile=.git-blame-ignore-revs
  skipping debec50a14cc -> a9a255d66663
  0: a
  2: b
  0* a
  $ hg add .git-blame-ignore-revs
  $ hg annotate a \
  > --debug \
  > --config git.blame.ignoreRevsFile=.git-blame-ignore-revs
  skipping debec50a14cc -> a9a255d66663
  0: a
  2: b
  0* a
  $ hg annotate a \
  > --config git.blame.ignoreRevsFile=badfile
  0: a
  2: b
  1: a
  $ hg annotate -T'{lines % "{rev}:{node|short} {gitnode|short}: {line}"}' a
  0:8d4731bd0f4a 88f28c06a1ed: a
  2:beb139b96eec 19388575d02e: b
  1:a9a255d66663 debec50a14cc: a

  $ cd ..
  $ hg -R repo annotate repo/a \
  > --debug \
  > --config git.blame.ignoreRevsFile=.git-blame-ignore-revs
  skipping debec50a14cc -> a9a255d66663
  0: a
  2: b
  0* a
