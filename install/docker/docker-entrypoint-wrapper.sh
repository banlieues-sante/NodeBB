#!/bin/sh
set -e

echo "[entrypoint] Rendering config.json from environment..."
node /usr/src/app/install/docker/env-config-file.js

exec entrypoint.sh "$@"
