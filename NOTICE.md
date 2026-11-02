# Third-party notices

This repository does not contain Cloud Commander itself. It configures and extends the upstream project:

- **Cloud Commander** (https://github.com/coderaiser/cloudcmd), MIT License, Copyright (c) coderaiser.
  The container image `coderaiser/cloudcmd` is pulled from Docker Hub at install time, and the project logo is referenced
  by URL from the upstream repository (`compose/icon_url`).
- The patched `index.html` is generated on the user's server by the `cloudcmd-init` helper from the image's own `dist/index.html`
  plus one extra `<script>` tag; it is not distributed here.
- **rsync** and **jq** are used from the Unraid base system.
