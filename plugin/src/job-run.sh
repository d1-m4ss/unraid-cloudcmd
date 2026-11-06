#!/bin/bash
# cloudcmd.main job runner: rsync copy/move with persistent status.json.
# Started by jobs.php as nobody:users (setsid + setpriv). Usage: job-run.sh <rundir> [start-pct]
# <rundir> is root-owned; only <rundir>/w is writable here.
J="$1"
START_PCT="${2:-0}"

# Do not keep the webGUI's inherited descriptors (sockets, scripts).
for f in /proc/$$/fd/*; do
    n=${f##*/}
    if [ "$n" -gt 2 ] 2>/dev/null && [ "$n" -lt 255 ]; then eval "exec $n>&-"; fi
done

[ -d "$J/w" ] && cd "$J/w" || exit 1

op=$(jq -r .op ../job.json)
src=$(jq -r .src ../job.json)
dst=$(jq -r .dst ../job.json)
mapfile -d '' -t names < <(jq -j '.names[] | (., "\u0000")' ../job.json)

write() { # state pct bytes rate eta msg
    jq -n --arg s "$1" --argjson p "${2:-0}" --argjson b "${3:-0}" --arg r "${4:-}" --arg e "${5:-}" --arg m "${6:-}" \
        --argjson pid "$$" --argjson t "$(date +%s)" \
        '{state:$s,pct:$p,bytes:$b,rate:$r,eta:$e,msg:$m,pid:$pid,updated:$t}' > status.tmp && mv -f status.tmp status.json
}

write queued "$START_PCT"
exec 9< ../../.lock
flock 9
if [ -e ../cancel ]; then write cancelled "$START_PCT" 0 "" "" "cancelled while queued"; exit 0; fi

# On resume of a move the already moved names are gone: skip them.
srcs=()
for n in "${names[@]}"; do
    if [ -e "$src/$n" ] || [ -L "$src/$n" ]; then srcs+=("$src/$n"); fi
done
if [ ${#srcs[@]} -eq 0 ]; then write "done" 100 0 "" "" "nothing left to transfer"; exit 0; fi

write running "$START_PCT" 0
args=(-aH --partial --no-inc-recursive --info=progress2 --no-human-readable -s)
# Move: never trust the size+mtime quick-check, a source is only removed after it was really transferred.
# Exception: "copied" is written below when a previous run transferred everything and only the removal of
# source files was refused; then the retry may skip what is already in place and just remove the sources.
if [ "$op" = move ]; then
    args+=(--remove-source-files)
    [ -e copied ] || args+=(--ignore-times)
fi

last=0
rsync "${args[@]}" -- "${srcs[@]}" "$dst/" 2> rsync.err | while IFS= read -r -d $'\r' line || [ -n "$line" ]; do
    line=${line//,/}
    if [[ $line =~ ^[[:space:]]*([0-9]+)[[:space:]]+([0-9]+)%[[:space:]]+([^[:space:]]+)[[:space:]]+([0-9:]+) ]]; then
        now=$(date +%s)
        if (( now != last )); then
            last=$now
            write running "${BASH_REMATCH[2]}" "${BASH_REMATCH[1]}" "${BASH_REMATCH[3]}" "${BASH_REMATCH[4]}"
        fi
    fi
done
rc=${PIPESTATUS[0]}

pct=$(jq -r '.pct // 0' status.json 2>/dev/null || echo 0)
if [ "$rc" -eq 0 ]; then
    if [ "$op" = move ]; then
        for s in "${srcs[@]}"; do
            if [ -d "$s" ] && [ ! -L "$s" ]; then find "$s" -depth -type d -empty -delete; fi
        done
    fi
    rm -f copied
    write "done" 100 0 "" "" ""
elif [ -e ../cancel ]; then
    write cancelled "$pct" 0 "" "" "cancelled"
else
    nrem=$(grep -c 'sender failed to remove' rsync.err)
    nother=$(grep -v -e 'sender failed to remove' -e '^rsync error: some files/attrs were not transferred' -e '^$' rsync.err | wc -l)
    if [ "$op" = move ] && [ "$rc" -eq 23 ] && [ "$nrem" -gt 0 ] && [ "$nother" -eq 0 ]; then
        # Everything was copied; only deleting some sources was refused (files/folders owned by another user, e.g. root).
        : > copied
        write failed 100 0 "" "" "copied, but $nrem source file(s) could not be removed: no permission (owned by another user, e.g. root). On the server run: chown -R nobody:users '$src' and press Resume (the copy is not repeated)."
        exit 0
    fi
    write failed "$pct" 0 "" "" "rsync exit $rc: $(tail -n 3 rsync.err | tr '\n' ' ')"
fi
