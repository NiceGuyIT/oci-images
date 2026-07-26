"""Apply TRMM_SETTING_* environment variables as Django settings.

tactical-init deletes and regenerates local_settings.py on every run, so
environment variables are the only durable override surface in the container
stack. settings.py imports this at end of file so these values win over both
local_settings.py and every upstream assignment.

Indentation is 4 spaces, not the repo default of tabs: this file is copied into
the upstream black-formatted Django tree.
"""

import json
import os

PREFIX = "TRMM_SETTING_"


def _parse(raw):
    """Parse as JSON for real types; anything JSON rejects stays a string."""
    try:
        return json.loads(raw)
    except ValueError:
        return raw


def env_settings():
    """Return {setting_name: value} for every TRMM_SETTING_* variable."""
    overrides = {}
    for key, raw in sorted(os.environ.items()):
        if not key.startswith(PREFIX) or key == PREFIX:
            continue
        name = key[len(PREFIX) :]
        value = _parse(raw)
        overrides[name] = value
        # Printed so a mistyped name or an unintended type is visible in
        # docker logs at startup instead of at agent checkin.
        print(f"settings_env: {name} = {value!r} ({type(value).__name__})")
    return overrides
