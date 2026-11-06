#!/bin/bash
# Smoke test for the cloudcmd.main job backend (jobs.php + job-run.sh).
# Run as root ON AN UNRAID SERVER with the plugin installed:  bash tests/jobs-smoke.sh
# Needs: php, jq, rsync (all part of Unraid). It creates a temporary folder under /mnt/user/appdata,
# only touches jobs it created itself, and removes everything it made when it exits.
# Env: SMOKE_BIG_MB (default 1200) size of the file used for the cancel/resume/interrupt tests.
set -u

PLUGIN=/usr/local/emhttp/plugins/cloudcmd.main
RUN=/var/local/cloudcmd.main/jobs
DEFS=/boot/config/plugins/cloudcmd.main/jobs
BIG_MB=${SMOKE_BIG_MB:-1200}
PASS=0; FAIL=0; SKIP=0
IDS=$(mktemp)

[ "$(id -u)" = 0 ] && [ -f "$PLUGIN/jobs.php" ] || { echo "run as root on Unraid with the cloudcmd.main plugin installed"; exit 2; }

H=$(mktemp -d /mnt/user/appdata/cloudcmd-smoke.XXXXXX)
C="/user${H#/mnt/user}"          # the same folder as Cloud Commander sees it
cleanup() {
    local id
    mapfile -t JOBS < "$IDS"
    for id in "${JOBS[@]}"; do api "{\"action\":\"dismiss\",\"id\":\"$id\"}" >/dev/null 2>&1; done
    rm -rf "$H" "$IDS"
}
trap cleanup EXIT

api() { # json -> response json (names may be passed as an array, jobs.php wants a JSON string)
    php -r '$_SERVER["REQUEST_METHOD"]="POST"; $_POST=json_decode($argv[1],true);
            if (isset($_POST["names"]) && is_array($_POST["names"])) $_POST["names"]=json_encode($_POST["names"]);
            include "'"$PLUGIN"'/jobs.php";' -- "$1" 2>&1
}
check() { # description, command...
    local d="$1"; shift
    if "$@" >/dev/null 2>&1; then PASS=$((PASS + 1)); echo "ok    $d"; else FAIL=$((FAIL + 1)); echo "FAIL  $d"; fi
}
skip() { SKIP=$((SKIP + 1)); echo "skip  $1"; }
start() { # op src dst names-json [overwrite] -> job id (and registers it for cleanup)
    local r id
    r=$(api "{\"action\":\"start\",\"op\":\"$1\",\"src\":\"$2\",\"dst\":\"$3\",\"names\":$4${5:+,\"overwrite\":\"1\"}}")
    id=$(echo "$r" | jq -r '.id // empty'); [ -n "$id" ] && echo "$id" >> "$IDS"
    echo "$id"
}
state() { api '{"action":"list"}' | jq -r ".jobs[]|select(.id==\"$1\")|.state"; }
jobmsg() { api '{"action":"list"}' | jq -r ".jobs[]|select(.id==\"$1\")|.msg"; }
pct() { api '{"action":"list"}' | jq -r ".jobs[]|select(.id==\"$1\")|.pct"; }
wait_state() { # id regex seconds
    local i
    for ((i = 0; i < ${3:-90}; i++)); do state "$1" | grep -Eq "$2" && return 0; sleep 1; done
    return 1
}
err_is() { echo "$1" | jq -e --arg e "$2" '.ok == false and (.error | contains($e))' >/dev/null; }

mkdir -p "$H"/{src,dst,dst2,dst3,dst4}
mkdir -p "$H/src/dirA/sub"
echo hello > "$H/src/dirA/sub/f.txt"; echo one > "$H/src/file1.txt"
printf 'AAAA' > "$H/src/same"; printf 'BBBB' > "$H/dst3/same"
touch -d '2026-01-01 00:00:00' "$H/src/same" "$H/dst3/same"
dd if=/dev/urandom of="$H/src/big.bin" bs=1M count="$BIG_MB" status=none
chown -R 99:100 "$H"

echo "== validation"
check "destination inside source is rejected" err_is "$(api "{\"action\":\"start\",\"op\":\"copy\",\"src\":\"$C/src\",\"dst\":\"$C/src/dirA\",\"names\":[\"dirA\"]}")" "inside the source"
check "same folder is rejected" err_is "$(api "{\"action\":\"start\",\"op\":\"copy\",\"src\":\"$C/src\",\"dst\":\"$C/src\",\"names\":[\"dirA\"]}")" "same folder"
check "'..' in a name is rejected" err_is "$(api "{\"action\":\"start\",\"op\":\"copy\",\"src\":\"$C/src\",\"dst\":\"$C/dst\",\"names\":[\"..\"]}")" "unsupported item name"
check "control character in a name is rejected" err_is "$(api "{\"action\":\"start\",\"op\":\"copy\",\"src\":\"$C/src\",\"dst\":\"$C/dst\",\"names\":[\"a\\nb\"]}")" "unsupported item name"
check "'..' in a path is rejected" err_is "$(api "{\"action\":\"start\",\"op\":\"copy\",\"src\":\"$C/src/../src\",\"dst\":\"$C/dst\",\"names\":[\"file1.txt\"]}")" "not available"
if [ -d /mnt/remotes ]; then
    check "/remotes as destination is rejected" err_is "$(api "{\"action\":\"start\",\"op\":\"copy\",\"src\":\"$C/src\",\"dst\":\"/remotes\",\"names\":[\"file1.txt\"]}")" "read-only"
    check "move out of /remotes is rejected" err_is "$(api "{\"action\":\"start\",\"op\":\"move\",\"src\":\"/remotes\",\"dst\":\"$C/dst\",\"names\":[\"x\"]}")" "read-only"
else
    skip "/remotes checks (no /mnt/remotes on this host)"
fi
check "missing item is rejected" err_is "$(api "{\"action\":\"start\",\"op\":\"copy\",\"src\":\"$C/src\",\"dst\":\"$C/dst\",\"names\":[\"nope\"]}")" "not found"

echo "== address setting (rejections only, nothing is written)"
check "javascript: address is rejected" err_is "$(api '{"action":"setcfg","url":"javascript:alert(1)"}')" "address must look like"
check "trailing newline in the address is rejected" err_is "$(api '{"action":"setcfg","url":"http://host.example/x\n"}')" "address must look like"
check "over-long address is rejected" err_is "$(api "{\"action\":\"setcfg\",\"url\":\"http://$(printf 'a%.0s' $(seq 1 320)).example/\"}")" "bad address"

echo "== copy"
id=$(start copy "$C/src" "$C/dst" '["dirA","file1.txt"]')
check "copy job starts" test -n "$id"
check "copy job finishes" wait_state "$id" '^done$' 30
check "copied folder is identical" diff -r "$H/src/dirA" "$H/dst/dirA"
check "copied file is identical" cmp "$H/src/file1.txt" "$H/dst/file1.txt"
check "sources are kept after copy" test -e "$H/src/file1.txt" -a -d "$H/src/dirA"
check "files are owned by nobody:users (99:100)" test "$(stat -c %u:%g "$H/dst/file1.txt")" = 99:100
check "runtime dir is root-owned, w/ is the runner's" test "$(stat -c %u "$RUN/$id")" = 0 -a "$(stat -c %u "$RUN/$id/w")" = 99
check "job definition is kept on the flash drive" test -f "$DEFS/$id.json"

echo "== existing destination"
r=$(api "{\"action\":\"start\",\"op\":\"copy\",\"src\":\"$C/src\",\"dst\":\"$C/dst\",\"names\":[\"file1.txt\"]}")
check "existing item gives code=exists" bash -c "echo '$r' | jq -e '.ok==false and .code==\"exists\" and .exists==[\"file1.txt\"]'"

echo "== move"
id=$(start move "$C/src" "$C/dst3" '["same"]' overwrite)
check "move with overwrite finishes" wait_state "$id" '^done$' 30
check "same size+mtime but different content is really replaced" test "$(cat "$H/dst3/same")" = AAAA
check "move removed the source" test ! -e "$H/src/same"

echo "== move of items this user cannot remove (owned by root)"
mkdir -p "$H/src/rootdir/sub"; echo r > "$H/src/rootdir/sub/f"; chown -R 0:0 "$H/src/rootdir"
id=$(start move "$C/src" "$C/dst4" '["rootdir"]')
check "job ends as failed" wait_state "$id" '^failed$' 30
msg_has() { [[ "$(jobmsg "$1")" == "$2"* ]]; }
check "message explains: copied, source not removable" msg_has "$id" "copied, but 1 source file(s) could not be removed"
check "the data was copied" test "$(cat "$H/dst4/rootdir/sub/f" 2>/dev/null)" = r
check "the source is still there" test -f "$H/src/rootdir/sub/f"
chown -R 99:100 "$H/src/rootdir"
api "{\"action\":\"resume\",\"id\":\"$id\"}" >/dev/null
check "after chown, resume finishes" wait_state "$id" '^done$' 30
check "source is removed after resume" test ! -e "$H/src/rootdir"
check "destination is still complete" test "$(cat "$H/dst4/rootdir/sub/f")" = r

echo "== cancel and resume"
id=$(start copy "$C/src" "$C/dst2" '["big.bin"]')
wait_state "$id" '^running$' 15 || true
api "{\"action\":\"cancel\",\"id\":\"$id\"}" >/dev/null
if wait_state "$id" '^cancelled$' 10; then
    api "{\"action\":\"resume\",\"id\":\"$id\"}" >/dev/null
    check "resumed job finishes" wait_state "$id" '^done$' 120
    check "resumed copy is identical" cmp "$H/src/big.bin" "$H/dst2/big.bin"
else
    skip "cancel (job finished before it could be cancelled, raise SMOKE_BIG_MB)"
fi

echo "== runner process"
rm -rf "$H/dst2"; mkdir "$H/dst2"; chown 99:100 "$H/dst2"
id=$(start copy "$C/src" "$C/dst2" '["big.bin"]')
wait_state "$id" '^running$' 15 || true
pid=$(jq -r .pid "$RUN/$id/w/status.json" 2>/dev/null)
if [ -n "$pid" ] && [ -d "/proc/$pid" ]; then
    check "runner runs as uid 99 without capabilities" bash -c "grep -q '^Uid:.99' /proc/$pid/status && grep -q '^CapEff:.0000000000000000' /proc/$pid/status"
    check "runner has no inherited descriptors above 2 (except its lock)" bash -c "[ \$(ls /proc/$pid/fd | grep -Ev '^(0|1|2|9|255)\$' | wc -l) = 0 ]"
    echo "== interrupted (kill -9) and resume"
    kill -9 -- "-$pid" 2>/dev/null; pkill -9 -f "rsync.*cloudcmd-smoke" 2>/dev/null
    check "killed job shows as interrupted" wait_state "$id" '^interrupted$' 15
    api "{\"action\":\"resume\",\"id\":\"$id\"}" >/dev/null
    check "interrupted job resumes and finishes" wait_state "$id" '^done$' 120
    check "result is identical" cmp "$H/src/big.bin" "$H/dst2/big.bin"
    echo "== restart (runtime state lost)"
    rm -rf "${RUN:?}/$id"
    check "job without runtime state shows as interrupted" wait_state "$id" '^interrupted$' 5
    rm -f "$H/dst2/big.bin"
    api "{\"action\":\"resume\",\"id\":\"$id\"}" >/dev/null
    check "job resumes after a simulated restart" wait_state "$id" '^done$' 120
    check "result after restart is identical" cmp "$H/src/big.bin" "$H/dst2/big.bin"
else
    skip "runner checks (job finished before they could run, raise SMOKE_BIG_MB)"
fi

echo "== dismiss"
mapfile -t JOBS < "$IDS"
for j in "${JOBS[@]}"; do api "{\"action\":\"dismiss\",\"id\":\"$j\"}" >/dev/null; done
none_listed() { ! api '{"action":"list"}' | jq -r '.jobs[].id' | grep -qxF -f <(printf '%s\n' "${JOBS[@]}"); }
check "dismissed jobs are gone from the list" none_listed
check "dismissed jobs are gone from the flash drive" bash -c "ls '$DEFS' | grep -qF -f <(printf '%s\n' ${JOBS[*]}) && exit 1 || exit 0"
JOBS=()

echo
echo "passed: $PASS  failed: $FAIL  skipped: $SKIP"
[ "$FAIL" = 0 ]
