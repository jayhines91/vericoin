#!/bin/bash
# Backward-compatible alias for build-linux64-docker.sh
exec "$(dirname "$0")/build-linux64-docker.sh" "$@"
