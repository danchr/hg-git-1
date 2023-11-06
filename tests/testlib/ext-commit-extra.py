'''test helper extension to create commits with multiple extra fields'''

from mercurial import cmdutil, commands, pycompat, scmutil

cmdtable = {}
try:
    from mercurial import registrar
    command = registrar.command(cmdtable)
except (ImportError, AttributeError):
    command = cmdutil.command(cmdtable)
testedwith = b'internal'

@command(b'commitextra',
         [(b'', b'field', [],
           b'extra data to store', b'FIELD=VALUE'),
          ] + commands.commitopts + commands.commitopts2,
         b'commitextra')
def commitextra(ui, repo, *pats, **opts):
    '''make a commit with extra fields'''
    fields = opts.get('field')
    extras = {}
    for field in fields:
        k, v = field.split(b'=', 1)
        extras[k] = v
    message = cmdutil.logmessage(ui, pycompat.byteskwargs(opts))
    repo.commit(message, opts.get('user'), opts.get('date'),
                match=scmutil.match(repo[None], pats,
                                    pycompat.byteskwargs(opts)),
                extra=extras)
    return 0
