FROM alpine:3.12

# "--no-cache" is new in Alpine 3.3 and it avoid using
# "--update + rm -rf /var/cache/apk/*" (to remove cache)
RUN apk add --no-cache \
  openssh git-daemon cgit nginx spawn-fcgi fcgiwrap

# SSH autorun
# RUN rc-update add sshd

WORKDIR /git-server/

# -D flag avoids password generation
# -s flag changes user's shell
RUN mkdir /git-server/keys \
  && adduser -h /git-server -D -s /usr/bin/git-shell git \
  && passwd -u git

# This is a login shell for SSH accounts to provide restricted Git access.
# It permits execution only of server-side Git commands implementing the
# pull/push functionality, plus custom commands present in a subdirectory
# named git-shell-commands in the user’s home directory.
# More info: https://git-scm.com/docs/git-shell
COPY git-shell-commands /home/git/git-shell-commands

# sshd_config file is edited to enable key access and disable access password
COPY ssh/ssh* /etc/ssh/
RUN chmod 600 /etc/ssh/ssh_host_*_key

COPY start.sh start.sh

# add the default key
COPY ssh/id_ed25519.pub /git-server/.ssh/authorized_keys
RUN chmod 755 /git-server/.ssh
RUN chmod 644 /git-server/.ssh/authorized_keys
RUN chown -R git /git-server/.ssh

# setup nginx
RUN mkdir /run/nginx
COPY htpasswd /git-server/htpasswd
COPY nginx.conf /git-server/nginx.conf

# create an empty repository
RUN git init --bare --shared /srv/repo.git
RUN chown -R git /srv/repo.git

EXPOSE 22
EXPOSE 80
EXPOSE 9418

CMD ["sh", "start.sh"]
