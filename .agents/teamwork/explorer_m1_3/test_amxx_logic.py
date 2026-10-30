import difflib
from pathlib import Path
import re

orig_cfg = Path("cstrike/addons/amxmodx/configs/csgo_competitive.cfg").read_text(encoding="utf-8")

def replace_cvar_in_text(text: str, cvar_name: str, new_val: str) -> tuple[str, bool]:
    lines = text.splitlines(keepends=True)
    re_cvar = re.compile(
        r"^(?P<indent>\s*)(?P<cvar>" + re.escape(cvar_name) + r")\s+(?P<quote>[\"']?)(?P<val>[^\s\"'/]+)(?P=quote)(?P<rest>.*?)(?P<eol>\r?\n)?$",
        re.IGNORECASE
    )
    changed = False
    new_lines = []
    for line in lines:
        stripped = line.strip()
        if stripped.startswith("//") or stripped.startswith(";"):
            new_lines.append(line)
            continue
        m = re_cvar.match(line)
        if m and not changed:
            quote = m.group("quote")
            eol = m.group("eol") or ""
            new_line = f"{m.group('indent')}{m.group('cvar')} {quote}{new_val}{quote}{m.group('rest')}{eol}"
            new_lines.append(new_line)
            changed = True
        else:
            new_lines.append(line)
    
    return "".join(new_lines), changed

cfg1, ch1 = replace_cvar_in_text(orig_cfg, "amx_csgo_maxrounds", "15")
assert ch1
cfg2, ch2 = replace_cvar_in_text(cfg1, "mp_roundtime", "2.00")
assert ch2
cfg_restored, r1 = replace_cvar_in_text(cfg2, "amx_csgo_maxrounds", "12")
assert r1
cfg_restored, r2 = replace_cvar_in_text(cfg_restored, "mp_roundtime", "1.92")
assert r2

assert cfg_restored == orig_cfg, "Roundtrip failed!"
print("SUCCESS: Roundtrip is 100% byte identical!")
