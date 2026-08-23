#!/bin/bash
# Verify Linux release binaries only depend on allowlisted glibc runtime libraries.
#
# Usage:
#   source Build-Scripts/verify-static-linux.sh
#   verify_static_linux_binary /path/to/vericoin-qt
set -euo pipefail

static_linux_dep_allowed() {
  local base="$1"
  case "$base" in
    linux-vdso.so.1) return 0 ;;
    ld-linux-x86-64.so.2|ld-linux-aarch64.so.2|ld-linux-armhf.so.3) return 0 ;;
    libc.so.6|libm.so.6|libpthread.so.0|libdl.so.2|librt.so.1) return 0 ;;
    libresolv.so.2|libutil.so.1) return 0 ;;
    *) return 1 ;;
  esac
}

verify_static_linux_binary() {
  local bin="$1"
  local name dep base

  if [ ! -f "$bin" ]; then
    echo "ERROR: missing binary: $bin" >&2
    return 1
  fi

  name="$(basename "$bin")"
  if ! ldd "$bin" >/dev/null 2>&1; then
    echo "ERROR: ldd failed for ${name} (not a dynamic executable?)" >&2
    return 1
  fi

  while IFS= read -r dep; do
    [ -n "$dep" ] || continue
    if [ "$dep" = "not" ] || [ "$dep" = "found" ]; then
      echo "ERROR: ${name} has unresolved dynamic dependency" >&2
      ldd "$bin" >&2 || true
      return 1
    fi
    base="$(basename "$dep")"
    if static_linux_dep_allowed "$base"; then
      continue
    fi
    echo "ERROR: ${name} dynamically links non-allowlisted library: ${dep}" >&2
    ldd "$bin" >&2 || true
    return 1
  done < <(ldd "$bin" 2>/dev/null | awk '/=>/ {print $3}' | grep -v '^$' || true)
}

verify_static_linux_binaries() {
  local bin
  for bin in "$@"; do
    verify_static_linux_binary "$bin"
  done
}
