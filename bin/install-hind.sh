#!/bin/sh -eu

# sets up HinD, passing on any extra CLI optional arguments xxx

export HOST_UNAME=$(uname)
export FQDN=$(hostname -f)
export FIRST=; #xxx
export TOK_C=; #xxx
export TOK_N=; #xxx

(
  set -x
  mkdir -p -m777 /pv/CERTS # xxx
  mkdir -p -m777 /opt/nomad/data/alloc # xxx
  podman run --net=host --privileged --cgroupns=host \
    -v /var/lib/containers:/var/lib/containers \
    -e FQDN  -e HOST_UNAME  -e FIRST  -e TOK_C  -e TOK_N \
    -v /pv/CERTS:/pv/CERTS \
    --rm --name hind --pull=always "$@" ghcr.io/internetarchive/hind:podman
    # xxx :main -- also change GH Pages to build from main branch when merge podman => main
)

# now run the new docker image in the background
# NOTE: the *SECOND LINE* is what differs here -- the other lines need to stay the same/matched
if [ "$HOST_UNAME" = Darwin ]; then
  (
    set -x
    podman run --privileged --cgroupns=host \
      -p 6000:4646 -p 8000:80 -p 4000:443 -v /sys/fs/cgroup:/sys/fs/cgroup:rw \
      -v /var/lib/containers:/var/lib/containers \
      -v /opt/nomad/data/alloc:/opt/nomad/data/alloc \
      --restart=unless-stopped --name hindup -v /pv/CERTS:/root/.local/share/caddy -d hind >/dev/null
  )
else
  (
    set -x
    podman run --privileged --cgroupns=host \
      --net=host \
      -v /var/lib/containers:/var/lib/containers \
      -v /opt/nomad/data/alloc:/opt/nomad/data/alloc \
      --restart=unless-stopped --name hindup -v /pv/CERTS:/root/.local/share/caddy -d hind >/dev/null
  )
fi

if [ ! $FIRST ]; then
  echo '
  Congratulations!

  In a few seconds, you should be able to access your nomad cluster, eg:
    nomad status

  by setting these environment variables
  (inside or outside the running container or from a home machine --
  anywhere you have downloaded a `nomad` binary):
    '
  podman run --rm hind sh -c 'cat $CONFIG'
else
  echo '

  SUCCESS!

  '
fi
