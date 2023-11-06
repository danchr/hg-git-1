import os
import stat
import re
import errno

from mercurial import (
    dirstate,
    error,
    exthelper,
    match as matchmod,
    pathutil,
    pycompat,
    util,
)

from mercurial.i18n import _

from . import git_handler
from . import gitrepo

eh = exthelper.exthelper()


def gignorepats(orig, lines, root=None):
    '''parse lines (iterable) of .gitignore text, returning a tuple of
    (patterns, parse errors). These patterns should be given to compile()
    to be validated and converted into a match function.'''
    syntaxes = {b're': b'relre:', b'regexp': b'relre:', b'glob': b'relglob:'}
    syntax = b'glob:'

    patterns = []
    warnings = []

    for line in lines:
        if b"#" in line:
            _commentre = re.compile(br'((^|[^\\])(\\\\)*)#.*')
            # remove comments prefixed by an even number of escapes
            line = _commentre.sub(br'\1', line)
            # fixup properly escaped comments that survived the above
            line = line.replace(b"\\#", b"#")
        line = line.rstrip()
        if not line:
            continue

        if line.startswith(b'!'):
            warnings.append(_(b"unsupported ignore pattern '%s'") % line)
            continue
        if re.match(br'(:?.*/)?\.hg(:?/|$)', line):
            continue
        rootprefix = b'%s/' % root if root else b''
        if line and line[0] in br'\/':
            line = line[1:]
            rootsuffixes = [b'']
        else:
            rootsuffixes = [b'', b'**/']
        for rootsuffix in rootsuffixes:
            pat = syntax + rootprefix + rootsuffix + line
            for s, rels in syntaxes.items():
                if line.startswith(rels):
                    pat = line
                    break
                elif line.startswith(s + b':'):
                    pat = rels + line[len(s) + 1 :]
                    break
            patterns.append(pat)

    return patterns, warnings


def gignore(root, files, ui, extrapatterns=None):
    allpats = []
    pats = [(f, [b'include:%s' % f]) for f in files]
    for f, patlist in pats:
        allpats.extend(patlist)

    if extrapatterns:
        allpats.extend(extrapatterns)
    if not allpats:
        return util.never
    try:
        ignorefunc = matchmod.match(root, b'', [], allpats)
    except error.Abort:
        ui.traceback()
        for f, patlist in pats:
            matchmod.match(root, b'', [], patlist)
        if extrapatterns:
            matchmod.match(root, b'', [], extrapatterns)
    return ignorefunc


class gitdirstate(dirstate.dirstate):
    @dirstate.rootcache(b'.hgignore')
    def _ignore(self):
        files = [self._join(b'.hgignore')]
        for name, path in self._ui.configitems(b"ui"):
            if name == b'ignore' or name.startswith(b'ignore.'):
                files.append(util.expandpath(path))
        patterns = []
        # Only use .gitignore if there's no .hgignore
        if not os.access(files[0], os.R_OK):
            for fn in self._finddotgitignores():
                d = os.path.dirname(fn)
                fn = self.pathto(fn)
                if not os.path.exists(fn):
                    continue
                fp = open(fn, 'rb')
                pats, warnings = gignorepats(None, fp, root=d)
                for warning in warnings:
                    self._ui.warn(b"%s: %s\n" % (fn, warning))
                patterns.extend(pats)
        return gignore(self._root, files, self._ui, extrapatterns=patterns)

    def _finddotgitignores(self):
        """A copy of dirstate.walk. This is called from the new _ignore method,
        which is called by dirstate.walk, which would cause infinite recursion,
        except _finddotgitignores calls the superclass _ignore directly."""
        match = matchmod.match(
            self._root, self.getcwd(), [b'relglob:.gitignore']
        )
        # TODO: need subrepos?
        subrepos = []
        unknown = True
        ignored = False

        def fwarn(f, msg):
            self._ui.warn(
                b'%s: %s\n'
                % (
                    self.pathto(f),
                    pycompat.sysbytes(msg),
                )
            )
            return False

        ignore = super()._ignore
        dirignore = self._dirignore
        if ignored:
            ignore = util.never
            dirignore = util.never
        elif not unknown:
            # if unknown and ignored are False, skip step 2
            ignore = util.always
            dirignore = util.always

        matchfn = match.matchfn
        matchalways = match.always()
        matchtdir = match.traversedir
        dmap = self._map
        lstat = os.lstat
        dirkind = stat.S_IFDIR
        regkind = stat.S_IFREG
        lnkkind = stat.S_IFLNK
        join = self._join

        exact = skipstep3 = False
        if matchfn == match.exact:  # match.exact
            exact = True
            dirignore = util.always  # skip step 2
        elif match.files() and not match.anypats():  # match.match, no patterns
            skipstep3 = True

        if not exact and self._checkcase:
            normalize = self._normalize
            skipstep3 = False
        else:
            normalize = None

        # step 1: find all explicit files
        results, work, dirsnotfound = self._walkexplicit(match, subrepos)

        skipstep3 = skipstep3 and not (work or dirsnotfound)
        work = [nd for nd, d in work if not dirignore(d)]
        wadd = work.append

        # step 2: visit subdirectories
        while work:
            nd = work.pop()
            skip = None
            if nd != b'':
                skip = b'.hg'
            try:
                entries = util.listdir(join(nd), stat=True, skip=skip)
            except OSError as inst:
                if inst.errno in (errno.EACCES, errno.ENOENT):
                    fwarn(nd, inst.strerror)
                    continue
                raise
            for f, kind, st in entries:
                if normalize:
                    nf = normalize(nd and (nd + b"/" + f) or f, True, True)
                else:
                    nf = nd and (nd + b"/" + f) or f
                if nf not in results:
                    if kind == dirkind:
                        if not ignore(nf):
                            if matchtdir:
                                matchtdir(nf)
                            wadd(nf)
                        if nf in dmap and (matchalways or matchfn(nf)):
                            results[nf] = None
                    elif kind == regkind or kind == lnkkind:
                        if nf in dmap:
                            if matchalways or matchfn(nf):
                                results[nf] = st
                        elif (matchalways or matchfn(nf)) and not ignore(nf):
                            results[nf] = st
                    elif nf in dmap and (matchalways or matchfn(nf)):
                        results[nf] = None

        for s in subrepos:
            del results[s]
        del results[b'.hg']

        # step 3: report unseen items in the dmap hash
        if not skipstep3 and not exact:
            if not results and matchalways:
                visit = dmap.keys()
            else:
                visit = [f for f in dmap if f not in results and matchfn(f)]
            visit.sort()

            if unknown:
                # unknown == True means we walked the full directory tree
                # above. So if a file is not seen it was either a) not matching
                # matchfn b) ignored, c) missing, or d) under a symlink
                # directory.
                audit_path = pathutil.pathauditor(self._root)

                for nf in iter(visit):
                    # Report ignored items in the dmap as long as they are not
                    # under a symlink directory.
                    if audit_path.check(nf):
                        try:
                            results[nf] = lstat(join(nf))
                        except OSError:
                            # file doesn't exist
                            results[nf] = None
                    else:
                        # It's either missing or under a symlink directory
                        results[nf] = None
            else:
                # We may not have walked the full directory tree above,
                # so stat everything we missed.
                nf = next(iter(visit))
                for st in util.statfiles([join(i) for i in visit]):
                    results[nf()] = st
        return results.keys()

    def _rust_status(self, *args, **kwargs):
        # intercept a rust status call and force the fallback,
        # otherwise our patching won't work
        if not os.path.lexists(self._join(b'.hgignore')):
            self._ui.debug(b'suppressing rust status to intercept gitignores\n')
            raise dirstate.rustmod.FallbackError
        else:
            return super()._rust_status(*args, **kwargs)


@eh.reposetup
def reposetup(ui, repo):
    if isinstance(repo, gitrepo.gitrepo):
        return

    if git_handler.has_gitrepo(repo):
        dirstate.dirstate = gitdirstate
