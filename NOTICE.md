# Third-party notices

This repository does not contain Cloud Commander itself. It configures and extends the upstream project:

- **Cloud Commander** (https://github.com/coderaiser/cloudcmd), MIT License, Copyright (c) coderaiser.
  The container image `coderaiser/cloudcmd` is pulled from Docker Hub at install time, and the project logo is referenced
  by URL from the upstream repository (`compose/icon_url`).
- `patch/index.html` described in the README is a copy of the image's own `dist/index.html` with one extra `<script>` tag,
  created on the user's machine during installation; it is not distributed here.
- **rsync** and **jq** are used from the Unraid base system.
