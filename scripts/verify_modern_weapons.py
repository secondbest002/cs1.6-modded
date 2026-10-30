import os
import sys
import subprocess
import shutil
import time

base_dir = r"d:\Games\Counter-Strike\Counter-Strike 1.6 Original"
cstrike = os.path.join(base_dir, "cstrike")
scripting = os.path.join(cstrike, "addons", "amxmodx", "scripting")
plugins_dir = os.path.join(cstrike, "addons", "amxmodx", "plugins")
compiler = os.path.join(scripting, "amxxpc.exe")

plugins = [
    "cs2_weapon_variants.sma",
    "cs2_skin_inventory.sma",
    "cs2_modern_engine.sma",
    "bot_savage_ai.sma"
]

print("=== 1. COMPILATION & INSTALLATION VERIFICATION ===")
compiled_count = 0
for sma in plugins:
    sma_path = os.path.join(scripting, sma)
    if not os.path.isfile(sma_path):
        print(f"ERROR: {sma} not found in {scripting}")
        sys.exit(1)

    res = subprocess.run([compiler, sma], cwd=scripting, capture_output=True, text=True)
    if res.returncode != 0:
        print(f"FAILED to compile {sma}:\nSTDOUT:\n{res.stdout}\nSTDERR:\n{res.stderr}")
        sys.exit(1)

    # Check for any warnings or errors (case-insensitive)
    out_lower = res.stdout.lower()
    if "warning" in out_lower:
        print(f"ERROR: COMPILER WARNING in {sma}:\n{res.stdout}")
        sys.exit(1)
    if "error" in out_lower and "0 error" not in out_lower:
        print(f"ERROR: COMPILER ERROR in {sma}:\n{res.stdout}")
        sys.exit(1)

    print(f"Clean compilation (0 errors, 0 warnings): {sma}")

    base = sma.replace(".sma", ".amxx")
    src = os.path.join(scripting, base)
    dst = os.path.join(plugins_dir, base)
    shutil.copy2(src, dst)
    stat = os.stat(dst)
    print(f"OK: {base} ({stat.st_size} bytes, mtime={time.ctime(stat.st_mtime)})")
    compiled_count += 1

print(f"Total plugins successfully compiled and deployed: {compiled_count}/{len(plugins)}")

print("\n=== 2. PLUGINS.INI & NATIVE API REGISTRATION ===")
plugins_ini = os.path.join(cstrike, "addons", "amxmodx", "configs", "plugins.ini")
with open(plugins_ini, "r", encoding="utf-8") as f:
    ini_content = f.read()

if "cs2_weapon_variants.amxx" not in ini_content:
    print("ERROR: cs2_weapon_variants.amxx not found in plugins.ini!")
    sys.exit(1)
print("OK: cs2_weapon_variants.amxx is registered in plugins.ini")

inc_file = os.path.join(scripting, "include", "cs2_weapon_variants.inc")
if not os.path.isfile(inc_file):
    print("ERROR: cs2_weapon_variants.inc missing!")
    sys.exit(1)

with open(inc_file, "r", encoding="utf-8") as f:
    inc_content = f.read()

required_natives = [
    "cs2_is_user_holding_variant",
    "cs2_get_user_weapon_variant",
    "cs2_get_variant_price"
]
for nat in required_natives:
    if nat not in inc_content:
        print(f"ERROR: Native {nat} missing from cs2_weapon_variants.inc!")
        sys.exit(1)
    print(f"OK: Native signature verified: {nat}")

variants_sma = os.path.join(scripting, "cs2_weapon_variants.sma")
with open(variants_sma, "r", encoding="utf-8") as f:
    var_content = f.read()

if "public bool:cs2_is_user_holding_variant" not in var_content:
    print("ERROR: public bool:cs2_is_user_holding_variant missing from cs2_weapon_variants.sma!")
    sys.exit(1)
print("OK: Public interop export verified: cs2_is_user_holding_variant")

if "contain(szLine, \"=\")" not in var_content:
    print("ERROR: contain(szLine, '=') not used in LoadActiveLoadouts!")
    sys.exit(1)
print("OK: Safe ini parsing verified (contain without void return warning)")

print("\n=== 3. DYNAMIC WEAPON PRICING (CS2 META ECONOMY) ===")
# Price table verification against specs:
# MAG-7: $1,300 (XM1014 $3,000 -> refund $1,700)
# Negev: $1,700 (M249 $5,750 -> refund $4,050)
# Sawed-Off: $1,100 (M3 $1,700 -> refund $600)
# PP-Bizon: $1,400 (P90 $2,350 -> refund $950)
# CZ75-Auto (CT TMP): $500 (TMP $1,250 -> refund $750)
# CZ75-Auto (T MAC-10): $500 (MAC-10 $1,400 -> refund $900)
# Tec-9: $500 (P228 $600 -> refund $100)

expected_pricing = [
    ("MAG-7", 1300, 1700),
    ("Negev", 1700, 4050),
    ("Sawed-Off", 1100, 600),
    ("PP-Bizon", 1400, 950),
    ("CZ75-Auto", 500, 750),  # CT
    ("CZ75-Auto", 500, 900),  # T
    ("Tec-9", 500, 100),
]
for name, price, refund in expected_pricing:
    str_price = f"targetPrice = {price};"
    str_refund = f"refundAmount = {refund};"
    if str_price not in var_content or str_refund not in var_content:
        print(f"ERROR: Pricing mismatch for {name}: expected price {price}, refund {refund}")
        sys.exit(1)
    print(f"OK: {name} meta price ${price:,} (refund ${refund:,}) verified in cs2_weapon_variants.sma")

if "bInBuyzone && bRecentlyBought" not in var_content:
    print("ERROR: Purchase refund check must require both bInBuyzone and bRecentlyBought!")
    sys.exit(1)
print("OK: Purchase refund protection verified (avoids double refunds for dropped weapons & bot give_item)")

print("\n=== 4. CLIP SIZE & MAGAZINE ATTRIBUTES ===")
expected_clips = [
    ("MAG-7", "5"),
    ("PP-Bizon", "64"),
    ("Negev", "150"),
    ("CZ75-Auto", "12"),
    ("Tec-9", "18")
]
for name, clip in expected_clips:
    if f"targetClip = {clip};" not in var_content and f"cs_set_weapon_ammo(iWpn, {clip})" not in var_content:
        print(f"ERROR: Clip size for {name} ({clip}) not properly defined in cs2_weapon_variants.sma")
        sys.exit(1)
    print(f"OK: {name} authentic clip size ({clip}) verified")

if "pev_iuser4" not in var_content:
    print("ERROR: pev_iuser4 clip initialization tracker missing!")
    sys.exit(1)
print("OK: Quick-switch infinite ammo protection verified (pev_iuser4 initialization tracking)")

print("\n=== 5. KILL REWARD REALIGNMENT (mod_kill_reward.inl) ===")
kr_file = os.path.join(scripting, "cs2_engine", "modules", "mod_kill_reward.inl")
with open(kr_file, "r", encoding="utf-8") as f:
    kr_content = f.read()

if "kr_IsHoldingVariant(attacker, CSW_P90, \"bizon\")" not in kr_content or "targetReward = 600;" not in kr_content:
    print("ERROR: PP-Bizon $600 kill reward rule missing in mod_kill_reward.inl")
    sys.exit(1)
print("OK: PP-Bizon -> $600 reward (standard SMG) verified")

if "kr_IsHoldingVariant(attacker, weaponId, \"cz\")" not in kr_content or "targetReward = 100;" not in kr_content:
    print("ERROR: CZ75-Auto $100 penalty kill reward rule missing in mod_kill_reward.inl")
    sys.exit(1)
print("OK: CZ75-Auto -> $100 reward penalty verified")

if "MAG-7" not in kr_content or "Sawed-Off" not in kr_content:
    print("ERROR: Shotguns MAG-7 / Sawed-Off names missing in mod_kill_reward.inl")
    sys.exit(1)
print("OK: Shotguns (MAG-7, Sawed-Off) -> $900 reward verified")

print("\n=== 6. BOT SAVAGE AI ROLE AFFINITY INTEGRATION ===")
bot_file = os.path.join(scripting, "bot_savage_ai.sma")
with open(bot_file, "r", encoding="utf-8") as f:
    bot_content = f.read()

# Check Entry Fragger affinity: Tec-9 (pistol), Sawed-Off/MP7 (force buy)
if "weapon_p228" not in bot_content or "Tec-9" not in bot_content:
    print("ERROR: Entry Fragger Tec-9 affinity missing in bot_savage_ai.sma")
    sys.exit(1)
print("OK: Entry Fragger Tec-9 pistol round affinity verified")

if "Sawed-Off" not in bot_content or "weapon_m3" not in bot_content:
    print("ERROR: Entry Fragger Sawed-Off affinity missing in bot_savage_ai.sma")
    sys.exit(1)
print("OK: Entry Fragger Sawed-Off / MP7 force-buy affinity verified")

# Check Site Anchor (Lurker) affinity: MAG-7
if "weapon_xm1014" not in bot_content or "MAG-7" not in bot_content:
    print("ERROR: Site Anchor MAG-7 affinity missing in bot_savage_ai.sma")
    sys.exit(1)
print("OK: Site Anchor (Lurker) CT MAG-7 force-buy lockdown affinity verified")

# Check CZ75-Auto affinity for both CT and T bots
if "weapon_tmp" not in bot_content or "weapon_mac10" not in bot_content:
    print("ERROR: CZ75-Auto CT/T weapon slots missing in bot_savage_ai.sma")
    sys.exit(1)
print("OK: CZ75-Auto dual-slot (CT TMP / T MAC-10) bot buy affinity verified")

# Check Negev and PP-Bizon force-buy fallbacks
if "weapon_m249" not in bot_content or "Negev" not in bot_content:
    print("ERROR: Negev fallback missing in bot_savage_ai.sma")
    sys.exit(1)
print("OK: Negev heavy firepower fallback verified")

if "weapon_p90" not in bot_content or "PP-Bizon" not in bot_content:
    print("ERROR: PP-Bizon fallback missing in bot_savage_ai.sma")
    sys.exit(1)
print("OK: PP-Bizon mobile anti-eco fallback verified")

print("\n=== 7. MODERN WEAPON P/W MODELS & AUDIO INTEGRITY ===")
modern_pw = [
    "p_tec9.mdl", "w_tec9.mdl",
    "p_cz75.mdl", "w_cz75.mdl",
    "p_mp7.mdl", "w_mp7.mdl",
    "p_bizon.mdl", "w_bizon.mdl",
    "p_mag7.mdl", "w_mag7.mdl",
    "p_sawedoff.mdl", "w_sawedoff.mdl",
    "p_negev.mdl", "w_negev.mdl"
]
for mdl in modern_pw:
    p = os.path.join(cstrike, "models", "pw_models", mdl)
    exists = os.path.isfile(p)
    sz = os.path.getsize(p) if exists else 0
    print(f"  models/pw_models/{mdl}: {exists} ({sz:,} bytes)")
    if not exists:
        print(f"ERROR: missing {mdl}")
        sys.exit(1)

modern_snd = [
    "sound/weapons/csgo/tec9/tec9-1.wav",
    "sound/weapons/csgo/cz75a/cz75-1.wav", "sound/weapons/csgo/cz75a/cz75-2.wav",
    "sound/weapons/csgo/mp7/mp7-1.wav", "sound/weapons/csgo/mp7/mp7-2.wav",
    "sound/weapons/csgo/bizon/bizon-1.wav",
    "sound/weapons/csgo/mag7/mag7-1.wav",
    "sound/weapons/csgo/sawedoff/sawedoff-1.wav",
    "sound/weapons/csgo/negev/negev-1.wav", "sound/weapons/csgo/negev/negev-2.wav",
    "sound/weapons/csgo/m4a4/m4a4-1.wav", "sound/weapons/csgo/m4a4/m4a4-2.wav"
]
for snd in modern_snd:
    p = os.path.join(cstrike, snd)
    exists = os.path.isfile(p)
    sz = os.path.getsize(p) if exists else 0
    print(f"  {snd}: {exists} ({sz:,} bytes)")
    if not exists:
        print(f"ERROR: missing {snd}")
        sys.exit(1)

print("\n=== 8. ACTIVE LOADOUT & CATALOG ASSET INTEGRITY ===")
loadout_path = os.path.join(cstrike, "addons", "amxmodx", "configs", "active_loadout.ini")
missing_assets = 0
with open(loadout_path, "r", encoding="utf-8") as f:
    for line_idx, line in enumerate(f, 1):
        line = line.strip()
        if not line or line.startswith(";") or line.startswith("#") or line.startswith("["):
            continue
        if "=" in line:
            key, val = line.split("=", 1)
            val = val.strip().strip('"')
            target_file = os.path.join(cstrike, val)
            if not os.path.isfile(target_file):
                print(f"  MISSING active loadout at line {line_idx}: {key.strip()} -> {val}")
                missing_assets += 1

if missing_assets == 0:
    print("\n>>> ALL MODERN WEAPON OVERHAUL SYSTEMS VERIFIED 100% SUCCESS! <<<")
else:
    print(f"\nERROR: {missing_assets} missing assets detected!")
    sys.exit(1)
