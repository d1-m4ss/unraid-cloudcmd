# cloudcmd

[Cloud Commander](https://github.com/coderaiser/cloudcmd) (MIT) in a container for Unraid. Host port 8765 (8000 inside), config in `/mnt/user/appdata/cloudcmd`.

- Access: login and password are set by the owner in the Cloud Commander settings (F10) and saved in `appdata/cloudcmd/.cloudcmd.json`. Do not set `CLOUDCMD_AUTH` in `.env`: the variable overrides the saved configuration.
- Mounted: `/mnt/user`, `/mnt/disks`, `/mnt/remotes` (read-only). `/mnt/diskN` and `/mnt/cache` are intentionally not mounted.
- Keys: Right enters a folder, Left goes to the parent. Implemented by `appdata/cloudcmd/patch/user-keys.js` plus a copy of the image's `dist/index.html` with an extra `<script>` tag (see the repository README, step 1). After an image update recreate the copy. After changing `user-keys.js` bump `?v=` in `patch/index.html` (browser cache).
- F5/F6 inside the frame on the Unraid Main page are server-side copy/move jobs (rsync as `nobody:users`): see the plugin `cloudcmd.main`. In a separate tab (`:8765`) F5/F6 work the stock way, without saved progress.
- Job definitions: `/boot/config/plugins/cloudcmd.main/jobs/<id>.json`, runtime state in RAM: `/var/local/cloudcmd.main/jobs/<id>/` (outside `/mnt/user`, unreachable from the container).
- Icon: the project logo (MIT).
