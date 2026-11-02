#!/bin/bash
# Generate docker-compose.yml (self-contained) from docker-compose.template.yml and user-keys.js.
set -euo pipefail
cd "$(dirname "$0")"
ver=$(shasum -a 256 user-keys.js | cut -c1-8)
keys=$(sed -e 's/\$/$$/g' -e 's/^/      /' user-keys.js)
{
  while IFS= read -r line; do
    case "$line" in
      '@@KEYS@@') printf '%s\n' "$keys" ;;
      *) printf '%s\n' "${line//@@KEYSVER@@/$ver}" ;;
    esac
  done < docker-compose.template.yml
} > docker-compose.yml
echo "built docker-compose.yml (keys version $ver)"
