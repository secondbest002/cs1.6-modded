"""
Independent verification script for AMXX line-ending preservation.
"""
from pathlib import Path
import sys

# Ensure project root is in sys.path
proj_root = Path(__file__).resolve().parents[3]
if str(proj_root) not in sys.path:
    sys.path.insert(0, str(proj_root))

import tempfile
from tools.cs16_mod_hub.core.amxx_adapter import AmxxAdapter

with tempfile.TemporaryDirectory() as td:
    tdp = Path(td)
    cfg_dir = tdp / "cstrike" / "addons" / "amxmodx" / "configs"
    cfg_dir.mkdir(parents=True)

    # 1. Test CRLF plugins.ini
    p_ini = cfg_dir / "plugins.ini"
    original_crlf = (
        b"; AMX Mod X plugins\r\n"
        b"\r\n"
        b"admin.amxx\t\t; admin base\r\n"
        b"team_weapon_skins.amxx\t; Per-team weapon skin switcher\r\n"
        b";csgo_usps_silencer.amxx\t; Silencer lock\r\n"
    )
    p_ini.write_bytes(original_crlf)

    adapter = AmxxAdapter(game_root=tdp)
    status_before = adapter.get_plugin_status("team_weapon_skins")
    print(f"Status before: {status_before}")

    # Disable plugin
    ok = adapter.set_plugin_status("team_weapon_skins", False)
    print(f"Set plugin status result: {ok}")

    raw_after = p_ini.read_bytes()
    print("Raw bytes after disable:")
    print(raw_after)

    has_crlf = b"\r\n" in raw_after
    print(f"Contains CRLF: {has_crlf}")

    # Count CRLF vs naked LF
    crlf_count = raw_after.count(b"\r\n")
    lf_count = raw_after.count(b"\n")
    naked_lf_count = lf_count - crlf_count
    print(f"CRLF count: {crlf_count}, Naked LF count: {naked_lf_count}")

    if not has_crlf or naked_lf_count > 0:
        print("FAIL: Line endings corrupted! CRLF was converted to LF.")
        sys.exit(1)
    else:
        print("PASS: CRLF preserved!")
        sys.exit(0)
