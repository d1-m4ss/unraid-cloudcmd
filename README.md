# Cloud Commander for Unraid

[Русская версия](README.ru.md)

A two-pane file manager ([Cloud Commander](https://github.com/coderaiser/cloudcmd), MIT) inside the Unraid web GUI. It has two parts:

1. **A container** `cloudcmd` (a stack for the Compose Manager plugin).
2. **A GUI plugin** `cloudcmd.main`: a "Cloud Commander" section on the **Main** tab, right before Boot Device. It is collapsed by default so nothing gets moved or deleted by accident. Copy and move (F5/F6) run on the server as background jobs with progress, cancel and resume.

Tested on Unraid 7.3.4. Requirements: Docker, the Compose Manager plugin, rsync (part of Unraid).

## What you get

- A section on Main between the pools and Boot Device. **Open Cloud Commander** creates the frame, **Collapse** destroys it.
- Keys: Up/Down, **Right** enters a folder, **Left** goes to the parent, F3 view, F4 edit, F7 new folder, F8 delete, F9 menu, F10 settings.
- **F5/F6 inside the frame** start server-side jobs (rsync as `nobody:users`). The job list is shown on Main and survives closing the tab. Buttons: Cancel, Resume, Remove, Clear finished. Jobs run one at a time.
- If the destination already has items with the same names, the page asks separately whether to overwrite/merge.

## Install

Run on the Unraid server (SSH) from a checkout of this repository. `P` is the Compose Manager project directory.

### 1. Container

```bash
P=/boot/config/plugins/compose.manager/projects/cloudcmd
mkdir -p $P /mnt/user/appdata/cloudcmd/patch
cp compose/docker-compose.yml compose/docker-compose.override.yml compose/description compose/icon_url \
   compose/name compose/project_name compose/autostart compose/profiles compose/README.md $P/
cp compose/.env.example $P/.env        # set TZ in it
chown -R 99:100 /mnt/user/appdata/cloudcmd
```

Interface patch (the key script and one `<script>` tag in `index.html`; mounted into the container read-only):

```bash
A=/mnt/user/appdata/cloudcmd/patch
docker run --rm --entrypoint cat coderaiser/cloudcmd:latest /usr/src/cloudcmd/dist/index.html > $A/index.html
sed -i 's#<script src="{{ prefix }}/dist/cloudcmd.js"></script>#&<script src="{{ prefix }}/dist/user-keys.js?v=1"></script>#' $A/index.html
cp compose/user-keys.js $A/user-keys.js
chown 99:100 $A/*; chmod 644 $A/*
```

Start (or use Compose Up in Docker → Compose):

```bash
cd $P && docker compose -p cloudcmd --project-directory $P -f docker-compose.yml -f docker-compose.override.yml --env-file .env up -d
```

The host port is **8765** (8000 inside the container), config lives in `/mnt/user/appdata/cloudcmd`. Mounted: `/mnt/user`, `/mnt/disks`, `/mnt/remotes` (read-only). Individual disks (`/mnt/diskN`) and `/mnt/cache` are intentionally not mounted: do not mix user shares and disks.

### 2. Password

Without a password the container opens write access to your shares to the whole network. Open `http://IP:8765/`, press **F10**, enable Auth, set a login and password, save. The password is stored hashed in `/mnt/user/appdata/cloudcmd/.cloudcmd.json`. Do not set `CLOUDCMD_AUTH` in `.env`: the variable overrides the saved configuration.

### 3. GUI plugin

```bash
cp plugin/cloudcmd.main.plg /boot/config/plugins/cloudcmd.main.plg
plugin install /boot/config/plugins/cloudcmd.main.plg
```

If the same version is already installed, `plugin install` does nothing: run `plugin remove cloudcmd.main.plg` first (keep a copy of the file outside `/boot/config/plugins`), then install again. The plugin is installed again from `/boot/config/plugins` on every boot.

The `.plg` is built from `plugin/src/` by `plugin/build.sh <version>` (needs bash and xmllint).

## Usage

1. Open **Main**, the Cloud Commander section. **The first time**, click "Open in new tab" and log in: browsers do not show a login prompt inside a frame from another port. After logging in in a new tab the browser usually remembers the login for that port and the frame opens.
2. Click **Open Cloud Commander**, then click inside the frame. Tab switches panels, Right/Left walk through folders.
3. Select files (Insert or Space) and press **F5** (copy) or **F6** (move) in the active panel. The target is the folder in the other panel. Confirm. A job row appears under the bar.
4. A job can be cancelled and resumed later: rsync continues where it stopped. Finished jobs are removed with Remove or Clear finished.
5. Delete (F8) and rename apply immediately, there is no recycle bin.

Good to know:

- If you open Cloud Commander in its own tab (`:8765`), F5/F6 work the stock way without saved progress: the progress window lives only in the tab.
- If Unraid is opened over HTTPS (for example through Tailscale), the browser will not embed the HTTP frame. The page shows a hint, use "Open in new tab".
- Move really copies the data (`--ignore-times`) and removes the source only after a successful transfer.
- Operations run as `nobody:users` (99:100): files this user cannot read are not copied.

## Where state is kept

| What | Where |
| --- | --- |
| Job definitions (survive a reboot) | `/boot/config/plugins/cloudcmd.main/jobs/<id>.json` |
| Runtime state, progress, rsync log (RAM) | `/var/local/cloudcmd.main/jobs/<id>/` |
| Cloud Commander config and password | `/mnt/user/appdata/cloudcmd/.cloudcmd.json` |
| Interface patch | `/mnt/user/appdata/cloudcmd/patch/` |

State is intentionally kept outside `/mnt/user`: the container can write to the shares and must not be able to swap files that root-run plugin code works with. After an Unraid reboot a running copy is interrupted; the job is shown as `interrupted` without a percentage and Resume continues it.

## Changing settings

- **Port:** `ports` in `docker-compose.yml` and `$cc_port` in `plugin/src/CloudCommander.page`, then `plugin/build.sh <new version>` and reinstall the plugin.
- **New image version:** `docker compose ... pull && up -d`. Recreate the `patch/index.html` copy with the commands from step 1, otherwise the old page is used.
- **Changed `user-keys.js`:** bump the number in `?v=` in `patch/index.html`, otherwise the browser keeps the old cached script.
- **Time zone:** `TZ` in `.env`.

## Tests

`tests/jobs-smoke.sh` is a smoke test of the job backend. Run it as root on an Unraid server with the plugin installed:

```bash
bash tests/jobs-smoke.sh            # SMOKE_BIG_MB=1200 by default
```

It creates a temporary folder under `/mnt/user/appdata`, exercises validation, copy, move, overwrite, cancel/resume, kill -9 and a simulated restart, and removes everything it created.

## Uninstall

```bash
plugin remove cloudcmd.main.plg
cd $P && docker compose -p cloudcmd --project-directory $P -f docker-compose.yml -f docker-compose.override.yml down
rm -rf $P /mnt/user/appdata/cloudcmd /boot/config/plugins/cloudcmd.main /var/local/cloudcmd.main
```

## Troubleshooting

- **The frame is empty or white:** log in in a new tab (`http://IP:8765/`), check `docker ps`, hard-refresh (Ctrl+F5).
- **F5/F6 do nothing special, copy works the old way:** the browser holds an old `user-keys.js`. Bump `?v=`, restart the container, hard-refresh.
- **A job sits in `interrupted`:** the process was stopped (container restart, reboot, kill). Press Resume. Log: `/var/local/cloudcmd.main/jobs/<id>/w/rsync.err`.
- **A job is `failed`:** the message is shown in the job row and its tooltip (rsync error, permissions, disk space).
- **The section is missing on Main:** `ls /usr/local/emhttp/plugins/cloudcmd.main`, the directory must be mode `755`, then `plugin install`.

## Repository layout

```
compose/      docker-compose.yml, override with labels and icon, Compose Manager metadata,
              user-keys.js (arrows, F5/F6), .env.example
plugin/       cloudcmd.main.plg (built), build.sh, CHANGES.txt
plugin/src/   CloudCommander.page (the Main section), jobs.php (job API), job-run.sh (rsync runner)
tests/        jobs-smoke.sh
```

## Security

- A login and password are required. The container has write access to `/mnt/user` and the Cloud Commander console is enabled.
- `jobs.php` runs as root inside the webGUI and only answers requests with an Unraid session and a CSRF token. Paths are checked against a list of roots, names with control characters are rejected, rsync gets `--` and absolute paths, the runner starts as `nobody:users` with no privileges.
- The page accepts messages only from its own frame (source and origin are checked).

## License

MIT, see [LICENSE](LICENSE). Cloud Commander itself is MIT, see [NOTICE.md](NOTICE.md).
