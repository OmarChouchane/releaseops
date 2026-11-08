#!/bin/sh
set -eu

REPO=/data/releaseops.git
if [ ! -d "$REPO" ]; then
  git init --bare --initial-branch=main "$REPO"
  git -C "$REPO" config http.receivepack true       # allow anonymous push (local demo only)
  git -C "$REPO" config receive.denyNonFastForwards false
fi

# Smart-HTTP backend: nginx -> fcgiwrap -> git http-backend
rm -f /tmp/fcgi.sock
spawn-fcgi -s /tmp/fcgi.sock -M 0660 -- /usr/bin/fcgiwrap
exec nginx -g 'daemon off;'
