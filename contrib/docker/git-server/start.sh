#!/bin/sh

# for each daemon, we take care to ensure that all logging happens to
# stdout & stderr

# start the fcgi daemon
/usr/bin/spawn-fcgi \
    -u git -U git -n \
    -d /srv \
    -s /run/git.socket \
    /usr/bin/fcgiwrap &

# start the simple daemon
git daemon \
    --export-all \
    --user=git \
    --base-path=/srv \
    /srv &

# start nginx
/usr/sbin/nginx \
    -c /git-server/nginx.conf &

# finally, start ssh
# -D flag avoids executing sshd as a daemon
exec /usr/sbin/sshd -D
