#require serve

Load commonly used test logic
  $ . "$TESTDIR/testutil"

Enable progress debugging:

  $ cat >> $HGRCPATH <<EOF
  > [progress]
  > delay = 0
  > refresh = 0
  > width = 60
  > format = topic unit total number item bar
  > assume-tty = yes
  > EOF

Create a dummy repository and serve it

  $ git init -q test
  $ cd test
  $ echo foo > foo
  $ git add foo
  $ fn_git_commit -m test
  $ echo bar > bar
  $ git add bar
  $ fn_git_commit -m test
  $ git daemon --listen=localhost --port=$HGPORT \
  > --pid-file=$DAEMON_PIDS --detach --export-all --verbose \
  > --base-path=$TESTTMP \
  > || exit 80
  $ cd ..

Make sure that clone over the old git protocol doesn't break

  $ hg clone -U git://localhost:$HGPORT/test copy 2>&1
  \r (no-eol) (esc)
  Counting objects 1/6 [=====>                              ]\r (no-eol) (esc)
  Counting objects 2/6 [===========>                        ]\r (no-eol) (esc)
  Counting objects 3/6 [=================>                  ]\r (no-eol) (esc)
  Counting objects 4/6 [=======================>            ]\r (no-eol) (esc)
  Counting objects 5/6 [=============================>      ]\r (no-eol) (esc)
  Counting objects 6/6 [===================================>]\r (no-eol) (esc)
                                                              \r (no-eol) (esc)
  \r (no-eol) (esc)
  Compressing objects 1/3 [==========>                      ]\r (no-eol) (esc)
  Compressing objects 2/3 [=====================>           ]\r (no-eol) (esc)
  Compressing objects 3/3 [================================>]\r (no-eol) (esc)
                                                              \r (no-eol) (esc)
  \r (no-eol) (esc)
  importing commits 1/2 b23744d34f97         [======>       ]\r (no-eol) (esc)
  importing commits 2/2 3af9773036a9         [=============>]\r (no-eol) (esc)
                                                              \r (no-eol) (esc)
  importing 2 git commits
  new changesets c4d188f6e13d:221dd250e933 (2 drafts)
  $ hg log -T 'HG:{node|short} GIT:{gitnode|short}\n' -R copy
  HG:221dd250e933 GIT:3af9773036a9
  HG:c4d188f6e13d GIT:b23744d34f97
