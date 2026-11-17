#!/usr/bin/env bash
# setup.sh: the steps of action.yml. One script serves Linux, macOS and
# Windows (Git Bash on the hosted runners).
#
#   setup.sh resolve   versions and digests that name the cache
#   setup.sh install   xlings, then mcpp, then the requested toolchains
#
# Inputs arrive as SETUP_MCPP_* environment variables (action.yml).
set -euo pipefail

version="${SETUP_MCPP_VERSION:-latest}"
version="${version#v}"
xlings_version="${SETUP_MCPP_XLINGS_VERSION:-latest}"
xlings_version="${xlings_version#v}"
mirror="${SETUP_MCPP_MIRROR:-GLOBAL}"
toolchains="${SETUP_MCPP_TOOLCHAINS:-}"

case "$(uname -s)" in
  MINGW* | MSYS* | CYGWIN*) windows=1; home="$USERPROFILE"; exe=.exe ;;
  *)                        windows=0; home="$HOME";        exe=   ;;
esac
# Git Bash converts a POSIX path in an argument for a native program (curl,
# xlings, mcpp); a workflow may turn that off for its own steps, and this
# script's paths (mktemp's /tmp/...) then reach curl unconverted and cannot be
# written. The conversion is this script's convention, whatever the caller's.
if [ "$windows" = 1 ]; then unset MSYS_NO_PATHCONV MSYS2_ARG_CONV_EXCL; fi
bin="$home/.xlings/subos/current/bin"
xlings="$bin/xlings$exe"

out() { echo "$1=$2" >> "$GITHUB_OUTPUT"; }
log() { echo "setup-mcpp: $*"; }
die() { echo "::error::setup-mcpp: $*"; exit 1; }

# Highest release tag (vYYYY.M.D.N) of a GitHub repository. `git ls-remote`
# needs no API token and is not rate limited.
latest_tag() {
  git ls-remote --tags --refs "https://github.com/$1" \
    | sed -n 's#.*refs/tags/v\([0-9][0-9.]*\)$#\1#p' \
    | sort -t. -k1,1n -k2,2n -k3,3n -k4,4n | tail -1
}

# Runs "$@" up to three times, thirty seconds apart.
retry() {
  local n
  for n in 1 2 3; do
    "$@" && return 0
    [ "$n" = 3 ] || { log "attempt $n failed; retrying"; sleep 30; }
  done
  return 1
}

resolve() {
  local mv="$version" xv="$xlings_version"
  [ "$mv" != latest ] || mv="$(latest_tag mcpp-community/mcpp)"
  [ "$xv" != latest ] || xv="$(latest_tag openxlings/xlings)"
  [ -n "$mv" ] && [ -n "$xv" ] || die "cannot resolve the latest release tags"
  out mcpp "$mv"
  out xlings "$xv"
  # The toolchain list belongs to the cache: a cache saved before a line was
  # added would never gain that toolchain.
  out toolchains "$(printf '%s' "$toolchains" | git hash-object --stdin | cut -c1-12)"
}

install_xlings() {
  if [ -x "$xlings" ]; then
    local have
    have="$("$xlings" --version 2>/dev/null | head -1 | awk '{print $2}')"
    if [ "$xlings_version" = latest ] || [ "$have" = "$xlings_version" ]; then
      log "xlings $have present"
      return 0
    fi
  fi
  local tmp script
  tmp="$(mktemp -d)"
  if [ "$xlings_version" = latest ]; then export XLINGS_VERSION=; else export XLINGS_VERSION="$xlings_version"; fi
  export XLINGS_NON_INTERACTIVE=1
  if [ "$windows" = 1 ]; then
    script="$tmp/quick_install.ps1"
    retry curl -fsSL -o "$script" https://raw.githubusercontent.com/openxlings/xlings/main/tools/other/quick_install.ps1
    retry pwsh -NoProfile -ExecutionPolicy Bypass -File "$(cygpath -w "$script")"
  else
    script="$tmp/quick_install.sh"
    retry curl -fsSL -o "$script" https://raw.githubusercontent.com/openxlings/xlings/main/tools/other/quick_install.sh
    retry bash "$script" < /dev/null
  fi
  [ -x "$xlings" ] || die "xlings is not at $xlings after installation"
}

# The index is refreshed before every attempt but the first of a pinned
# version; the third attempt reads the CN mirror (GitCode), the fourth fetches
# the index with git. The requested mirror is restored afterwards.
install_mcpp() {
  local spec=mcpp attempt
  [ "$version" = latest ] || spec="mcpp@$version"
  "$xlings" config --mirror "$mirror" > /dev/null
  for attempt in 1 2 3 4; do
    case "$attempt" in
      1) [ "$version" != latest ] || "$xlings" update || true ;;
      2) "$xlings" update || true ;;
      3) "$xlings" config --mirror CN > /dev/null; "$xlings" update || true ;;
      4) XLINGS_INDEX_SOURCE=git "$xlings" update || true ;;
    esac
    if "$xlings" install "$spec" -y -u -g; then
      "$xlings" config --mirror "$mirror" > /dev/null
      return 0
    fi
    sleep $((attempt * 15))
  done
  "$xlings" config --mirror "$mirror" > /dev/null
  die "xlings could not install $spec"
}

install() {
  install_xlings
  export PATH="$bin:$PATH"
  if [ "$windows" = 1 ]; then cygpath -w "$bin"; else echo "$bin"; fi >> "$GITHUB_PATH"
  install_mcpp

  local mcpp="$bin/mcpp$exe" have
  have="$("$mcpp" --version | head -1 | awk '{print $2}')"
  [ "$version" = latest ] || [ "$have" = "$version" ] \
    || die "mcpp $version was requested, $have is active"
  "$mcpp" self config --mirror "$mirror"

  local line
  while IFS= read -r line || [ -n "$line" ]; do
    line="${line%%#*}"
    # shellcheck disable=SC2086  # each line is one argument list
    set -- $line
    [ "$#" -gt 0 ] || continue
    log "mcpp toolchain install $*"
    retry "$mcpp" toolchain install "$@"
  done <<< "$toolchains"

  out version "$have"
  log "mcpp $have ready"
}

case "${1:-}" in
  resolve) resolve ;;
  install) install ;;
  *) die "usage: setup.sh resolve|install" ;;
esac
