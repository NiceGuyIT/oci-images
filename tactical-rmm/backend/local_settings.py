"""Load Django settings from the mounted conf directory.

Baked into the image at api/tacticalrmm/local_settings.py, replacing the file the
upstream init block used to write. The real settings live in TACTICAL_CONF_DIR,
which is a mounted volume, so operator edits survive a container restart and the
Django tree itself stays read-only.

generated_settings.py is rewritten by tactical-init from the environment;
local_settings.py is seeded once and owned by the operator, so it is loaded last
and wins. settings_env.py applies TRMM_SETTING_* after both.

Indentation is 4 spaces, not the repo default of tabs: this file is copied into
the upstream black-formatted Django tree.
"""

import os as _os
from pathlib import Path as _Path

_conf_dir = _Path(_os.getenv("TACTICAL_CONF_DIR", "/opt/tactical/conf"))

# exec rather than import: the files live outside the package, and a missing one
# is normal (generated_settings.py does not exist until tactical-init runs).
for _name in ("generated_settings.py", "local_settings.py"):
    _path = _conf_dir / _name
    if _path.is_file():
        exec(compile(_path.read_text(), str(_path), "exec"))
