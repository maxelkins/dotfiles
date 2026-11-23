#!/usr/bin/env bash
# End-to-end Linux test: set up a fresh Ubuntu container as a non-root sudo user.
#
# Usage: tests/linux/run.sh [command ...]
#
# Each command runs in its own fresh login shell (bash -lc) as that user, in a
# copy of this working tree, so later commands see the PATH hook written by
# earlier ones. Default: './dot setup' then './dot check'.
#
# Environment: DOT_LINUX_TEST_IMAGE (default ubuntu:24.04),
#              DOT_LINUX_TEST_PLATFORM (e.g. linux/amd64; default: the daemon's),
#              DOT_LINUX_TEST_KEEP=1 to keep the container for debugging.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
IMAGE="${DOT_LINUX_TEST_IMAGE:-ubuntu:24.04}"
TEST_USER=agent
REPO_DIR="/home/${TEST_USER}/dotfiles"

if (( $# == 0 )); then
  set -- './dot setup' './dot check'
fi

log() {
  printf '\n==> %s\n' "$*"
}

platform_args=()
if [[ -n "${DOT_LINUX_TEST_PLATFORM:-}" ]]; then
  platform_args=(--platform "$DOT_LINUX_TEST_PLATFORM")
fi

container="$(docker run -d ${platform_args[@]+"${platform_args[@]}"} "$IMAGE" sleep infinity)"
cleanup() {
  if [[ "${DOT_LINUX_TEST_KEEP:-0}" == 1 ]]; then
    printf 'Kept container %s\n' "$container" >&2
  else
    docker rm -f "$container" >/dev/null
  fi
}
trap cleanup EXIT

log "Bootstrapping ${IMAGE} with git and sudo only"
docker exec -e DEBIAN_FRONTEND=noninteractive "$container" bash -euc '
  apt-get update -qq
  apt-get install -y -qq --no-install-recommends git sudo >/dev/null
  useradd --create-home --shell /bin/bash "$1"
  printf "%s ALL=(ALL) NOPASSWD:ALL\n" "$1" >"/etc/sudoers.d/$1"
  chmod 0440 "/etc/sudoers.d/$1"
' _ "$TEST_USER"

# Stream the working tree (tracked and untracked, not ignored) into the
# container. Streaming works with remote Docker daemons, unlike bind mounts.
log "Copying the working tree to ${REPO_DIR}"
docker exec "$container" install -d -o "$TEST_USER" -g "$TEST_USER" "$REPO_DIR"
git -C "$ROOT" ls-files -z --cached --others --exclude-standard |
  while IFS= read -r -d '' path; do
    [[ -e "${ROOT}/${path}" ]] && printf '%s\0' "$path"
  done |
  COPYFILE_DISABLE=1 tar -C "$ROOT" --null -T - -cf - |
  docker exec -i -u "$TEST_USER" "$container" tar --warning=no-unknown-keyword -x -C "$REPO_DIR"

# dot expects a Git checkout (hooks config, upgrade cleanliness checks).
docker exec -u "$TEST_USER" -w "$REPO_DIR" "$container" bash -euc '
  git init -q -b main
  git add -A
  git -c user.name=dot-test -c user.email=dot-test@localhost commit -qm "test snapshot"
'

for command in "$@"; do
  log "Running as ${TEST_USER}: ${command}"
  docker exec -u "$TEST_USER" -w "$REPO_DIR" -e TERM=dumb "$container" bash -lc "$command"
done

log "All commands passed"
