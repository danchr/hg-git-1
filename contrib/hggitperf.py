# hggitperf.py - performance test routines
'''helper extension to measure performance of hg-git operations

This requires both the hggit and hggitperf extensions to be enabled and
available.
'''

from __future__ import generator_stop

from mercurial import cmdutil
import time, os, tempfile
import functools

cmdtable = {}
command = cmdutil.command(cmdtable)

# the timer functions are copied from mercurial/contrib/perf.py
def gettimer(ui, opts=None):
    """return a timer function and formatter: (timer, formatter)

    This functions exist to gather the creation of formatter in a single
    place instead of duplicating it in all performance command."""

    # enforce an idle period before execution to counteract power management
    time.sleep(ui.configint(b"perf", b"presleep", 1))

    if opts is None:
        opts = {}
    # redirect all to stderr
    ui = ui.copy()
    ui.fout = ui.ferr
    # get a formatter
    fm = ui.formatter(b'perf', opts)
    return functools.partial(_timer, fm), fm


def _timer(fm, func, title=None):
    results = []
    begin = time.time()
    count = 0
    while True:
        ostart = os.times()
        cstart = time.time()
        r = func()
        cstop = time.time()
        ostop = os.times()
        count += 1
        a, b = ostart, ostop
        results.append((cstop - cstart, b[0] - a[0], b[1] - a[1]))
        if cstop - begin > 3 and count >= 100:
            break
        if cstop - begin > 10 and count >= 3:
            break

    fm.startitem()

    if title:
        fm.write(b'title', b'! %s\n', title)
    if r:
        fm.write(b'result', b'! result: %s\n', r)
    m = min(results)
    fm.plain(b'!')
    fm.write(b'wall', b' wall %f', m[0])
    fm.write(b'comb', b' comb %f', m[1] + m[2])
    fm.write(b'user', b' user %f', m[1])
    fm.write(b'sys', b' sys %f', m[2])
    fm.write(b'count', b' (best of %d)', count)
    fm.plain(b'\n')


@command(b'perfgitloadmap')
def perfgitloadmap(ui, repo):
    timer, fm = gettimer(ui)
    timer(repo.githandler.load_map)
    fm.end()


@command(b'perfgitsavemap')
def perfgitsavemap(ui, repo):
    timer, fm = gettimer(ui)
    repo.githandler.load_map()
    fd, f = tempfile.mkstemp(prefix=b'.git-mapfile-', dir=repo.path)
    basename = os.path.basename(f)
    try:
        timer(lambda: repo.githandler.save_map(basename))
    finally:
        os.unlink(f)
    fm.end()
