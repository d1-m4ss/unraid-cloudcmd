# Cloud Commander for Unraid

[Русская версия](README.ru.md)

A two-pane file manager ([Cloud Commander](https://github.com/coderaiser/cloudcmd), MIT) inside the Unraid web GUI.

- A **"Cloud Commander" section on the Main tab**, right before Boot Device. It is collapsed by default so nothing gets moved or deleted by accident.
- **F5 / F6 (copy / move) run on the server** as background jobs: progress list on Main, cancel, resume, survive closing the tab.
- Keys: Up/Down, **Right** enters a folder, **Left** goes to the parent, Tab switches panels, F3 view, F4 edit, F7 new folder, F8 delete, F10 settings.

Tested on Unraid 7.3.4. Needs the **Compose Manager** plugin (Community Applications) and rsync (part of Unraid).

## Quick start

**1. Plugin** (Plugins → Install Plugin → paste the link → Install):

```
https://raw.githubusercontent.com/d1-m4ss/unraid-cloudcmd/main/plugin/cloudcmd.main.plg
```

**2. Container** (Docker → Compose → Add New Stack, name `cloudcmd`, paste the whole file, Save, **Compose Up**):

[`compose/docker-compose.yml`](compose/docker-compose.yml) — one self-contained file, nothing else to download. Before the first start you may change `TZ` (time zone), the port `8765` and the mounted folders inside it. If you change the port, change `$cc_port` in the plugin too (see "Settings").

**3. Password.** Without one, anyone on your network can write to your shares. Main → Cloud Commander → **Open in new tab**, press **F10**, enable Auth, set a login and password, save. Browsers do not show a login prompt inside a frame from another port, so log in in that new tab first: the browser usually remembers the login for the port and the frame on Main then opens.

Then open **Main**, press **Open Cloud Commander**.

## Usage

1. Click **Open Cloud Commander** and click inside the frame. Tab switches panels, Right/Left walk through folders.
2. Select files (Insert or Space) and press **F5** (copy) or **F6** (move). The target is the folder shown in the other panel. Confirm. A job row appears under the bar.
3. A job can be cancelled and resumed later: rsync continues where it stopped. Finished jobs go away with Remove or Clear finished.
4. If the destination already has items with the same names, you are asked separately whether to overwrite/merge.
5. Delete (F8) and rename apply immediately, there is no recycle bin.

Good to know:

- In a separate browser tab (`http://IP:8765/`) F5/F6 work the stock way, without saved progress.
- Over HTTPS (for example through Tailscale) browsers do not embed the HTTP frame. The page shows a hint, use "Open in new tab".
- Move really copies the data and removes the source only after a successful transfer.
- Operations run as `nobody:users` (99:100): files this user cannot read are not copied.
- Mounted: `/mnt/user`, `/mnt/disks`, `/mnt/remotes` (read-only). `/mnt/diskN` and `/mnt/cache` are intentionally not mounted: do not mix user shares and disks.

## How the container file works

`cloudcmd-init` is a one-shot helper that runs on every Compose Up: it prepares `/mnt/user/appdata/cloudcmd`, takes the `index.html` of the *current* image, adds one `<script>` tag and stores it with the key script in `appdata/cloudcmd/patch/`. `cloudcmd` mounts those two files read-only. So updating the image (`Update Stack`) keeps the patch in sync automatically. It shows as an "exited" container, that is normal.

## Settings

- **Port:** `ports` in the YAML and `$cc_port` in `plugin/src/CloudCommander.page`, then `plugin/build.sh <new version>` and reinstall the plugin.
- **Time zone:** `TZ` in the YAML.
- **Plugin updates:** the plugin carries its own update URL, so Plugins → Check for Updates works.

## Where state is kept

| What | Where |
| --- | --- |
| Job definitions (survive a reboot) | `/boot/config/plugins/cloudcmd.main/jobs/<id>.json` |
| Runtime state, progress, rsync log (RAM) | `/var/local/cloudcmd.main/jobs/<id>/` |
| Cloud Commander config and password hash | `/mnt/user/appdata/cloudcmd/.cloudcmd.json` |
| Generated page patch | `/mnt/user/appdata/cloudcmd/patch/` |

State is intentionally kept outside `/mnt/user`: the container can write to the shares and must not be able to swap files that root-run plugin code works with. After an Unraid reboot a running copy is interrupted; the job is shown as `interrupted` and Resume continues it.

## Troubleshooting

- **The frame is empty or white:** log in in a new tab (`http://IP:8765/`), check that the stack is up, hard-refresh (Ctrl+F5).
- **F5/F6 do nothing special, copy works the old way:** the browser holds an old script. Compose Up again (the script address carries a version) and hard-refresh.
- **A job sits in `interrupted`:** the process was stopped (container restart, reboot). Press Resume. Log: `/var/local/cloudcmd.main/jobs/<id>/w/rsync.err`.
- **A job is `failed`:** the message is shown in the job row and its tooltip (rsync error, permissions, disk space).
- **The section is missing on Main:** `ls -ld /usr/local/emhttp/plugins/cloudcmd.main` must exist and be mode `755`; reinstall the plugin.

## Uninstall

Compose Down and delete the stack in the Compose tab, `plugin remove cloudcmd.main.plg`, then delete `/mnt/user/appdata/cloudcmd`, `/boot/config/plugins/cloudcmd.main` and `/var/local/cloudcmd.main` if you want to remove all data.

## Development

```
compose/      docker-compose.template.yml + user-keys.js  ->  build-compose.sh  ->  docker-compose.yml
plugin/       cloudcmd.main.plg (built by build.sh from plugin/src/), CHANGES.txt
plugin/src/   CloudCommander.page (the Main section), jobs.php (job API), job-run.sh (rsync runner)
tests/        jobs-smoke.sh
```

After editing `user-keys.js` or the template run `compose/build-compose.sh`; after editing `plugin/src/*` run `plugin/build.sh <version>` (needs bash and xmllint). The smoke test of the job backend runs as root on an Unraid server with the plugin installed: `bash tests/jobs-smoke.sh` (`SMOKE_BIG_MB=1200` by default); it uses a temporary folder and removes everything it created.

## Security

- A login and password are required. The container has write access to `/mnt/user` and the Cloud Commander console is enabled.
- `jobs.php` runs as root inside the webGUI and only answers requests with an Unraid session and a CSRF token. Paths are checked against a list of roots, names with control characters are rejected, rsync gets `--` and absolute paths, the runner starts as `nobody:users` with no privileges.
- The page accepts messages only from the frame or the pop-up window it opened itself (window identity and origin are both checked). The address of Cloud Commander is validated as an http(s) URL on write and again on read.

## License

MIT, see [LICENSE](LICENSE). Cloud Commander itself is MIT, see [NOTICE.md](NOTICE.md).
