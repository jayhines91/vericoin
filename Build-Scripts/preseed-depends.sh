#!/bin/bash
# Preseed depends for Vericoin — delegates to shared monorepo preseed.
exec "$(cd "$(dirname "$0")/../.." && pwd)/shared/depends-preseed/preseed-depends.sh" \
  "$(cd "$(dirname "$0")/.." && pwd)" "$@"
