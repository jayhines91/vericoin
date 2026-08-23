#!/bin/bash
# Verify macOS release binaries only link allowlisted system libraries.
#
# Usage:
#   source Build-Scripts/verify-static-macos.sh
#   verify_static_macos_binary /path/to/vericoin-qt
set -euo pipefail

find_macos_otool() {
  if [ -n "${OTOOL:-}" ] && [ -x "$OTOOL" ]; then
    printf '%s\n' "$OTOOL"
    return 0
  fi
  local candidate
  for candidate in \
    otool \
    "$(command -v otool 2>/dev/null || true)" \
    "$(find "${ROOT:-.}" -path '*/depends/*/native/bin/*-otool' -type f 2>/dev/null | head -1)" \
    "$(find "${ROOT:-.}" -path '*/depends/*/native/bin/otool' -type f 2>/dev/null | head -1)" \
    "$(find "${ROOT:-.}" -path '*/depends/native/bin/otool' -type f 2>/dev/null | head -1)"; do
    if [ -n "$candidate" ] && [ -x "$candidate" ]; then
      printf '%s\n' "$candidate"
      return 0
    fi
  done
  return 1
}

static_macos_dep_allowed() {
  local dep="$1"
  case "$dep" in
    /usr/lib/libSystem.B.dylib) return 0 ;;
    /usr/lib/libc++.*.dylib|/usr/lib/libobjc.*.dylib) return 0 ;;
    @executable_path/*|@loader_path/*|@rpath/*) return 0 ;;
    /System/Library/Frameworks/*) return 0 ;;
    /System/Library/PrivateFrameworks/*) return 0 ;;
    *) return 1 ;;
  esac
}

verify_static_macos_binary() {
  local bin="$1"
  local otool name dep

  if [ ! -f "$bin" ]; then
    echo "ERROR: missing binary: $bin" >&2
    return 1
  fi

  otool="$(find_macos_otool)" || {
    echo "ERROR: otool not found (set OTOOL= to depends native otool)" >&2
    return 1
  }

  name="$(basename "$bin")"
  while IFS= read -r dep; do
    [ -n "$dep" ] || continue
    if static_macos_dep_allowed "$dep"; then
      continue
    fi
    echo "ERROR: ${name} dynamically links non-allowlisted library: ${dep}" >&2
    "$otool" -L "$bin" >&2 || true
    return 1
  done < <("$otool" -L "$bin" 2>/dev/null | awk 'NR>1 && NF {print $1}' || true)
}

verify_static_macos_binaries() {
  local bin
  for bin in "$@"; do
    verify_static_macos_binary "$bin"
  done
}
