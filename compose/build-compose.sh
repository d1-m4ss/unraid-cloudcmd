#!/bin/bash
# Generate docker-compose.yml (self-contained) from docker-compose.template.yml and user-keys.js.
set -euo pipefail
cd "$(dirname "$0")"
ver=$(shasum -a 256 user-keys.js | cut -c1-8)
b64=$(base64 < user-keys.js | tr -d '\n')
{
  while IFS= read -r line; do
    case "$line" in
      *) line=${line//@@KEYSVER@@/$ver}; printf '%s\n' "${line//@@KEYSB64@@/$b64}" ;;
    esac
  done < docker-compose.template.yml
} > docker-compose.yml
echo "built docker-compose.yml (keys version $ver)"
