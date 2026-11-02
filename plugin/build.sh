#!/bin/bash
# Assemble cloudcmd.main.plg from src/ (inlines the files as CDATA).
set -euo pipefail
cd "$(dirname "$0")"
VERSION="${1:?usage: build.sh <version>}"
for f in src/*; do ! grep -q ']]>' "$f" || { echo "']]>' found in $f" >&2; exit 1; }; done
{
cat <<HDR
<?xml version='1.0' standalone='yes'?>
<!DOCTYPE PLUGIN [
<!ENTITY name "cloudcmd.main">
<!ENTITY author "d1-m4ss">
<!ENTITY version "$VERSION">
<!ENTITY launch "Main">
]>
<PLUGIN name="&name;" author="&author;" version="&version;" launch="&launch;" min="6.12.0" icon="columns">

<CHANGES>
$(cat CHANGES.txt)
</CHANGES>
HDR
emit() { # path mode
    printf '\n<FILE Name="/usr/local/emhttp/plugins/&name;/%s" Mode="%s">\n<INLINE>\n<![CDATA[' "$1" "$2"
    cat "src/$1"
    printf ']]>\n</INLINE>\n</FILE>\n'
}
emit CloudCommander.page 0644
emit jobs.php 0644
emit job-run.sh 0755
cat <<'PERM'

<FILE Run="/bin/bash">
<INLINE>
chmod 755 /usr/local/emhttp/plugins/&name;
</INLINE>
</FILE>
PERM
cat <<'FTR'

<FILE Run="/bin/bash" Method="remove">
<INLINE>
rm -rf /usr/local/emhttp/plugins/&name;
</INLINE>
</FILE>

</PLUGIN>
FTR
} > cloudcmd.main.plg
xmllint --noout cloudcmd.main.plg && echo "built cloudcmd.main.plg $VERSION"
