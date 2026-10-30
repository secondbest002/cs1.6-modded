#include <amxmodx>
#include <amxmisc>
#include <cstrike>
#include <fakemeta>
#include <hamsandwich>
#include <engine>
#include <xs>

#define PLUGIN  "CS2 E-Key Weapon Pickup"
#define VERSION "1.1.0"
#define AUTHOR  "Antigravity"

// CVars
new pCvar_Enable;
new pCvar_Radius;
new pCvar_Sound;

// Button Tracking for Rising Edge
new g_iOldButtons[33];
new Float:g_flLastPickup[33];

// Weapon Bitmasks
const PRIMARY_WEAPONS_BIT_SUM = (1<<CSW_SCOUT)|(1<<CSW_XM1014)|(1<<CSW_MAC10)|(1<<CSW_AUG)|(1<<CSW_UMP45)|(1<<CSW_SG550)|(1<<CSW_GALIL)|(1<<CSW_FAMAS)|(1<<CSW_AWP)|(1<<CSW_MP5NAVY)|(1<<CSW_M249)|(1<<CSW_M3)|(1<<CSW_M4A1)|(1<<CSW_TMP)|(1<<CSW_G3SG1)|(1<<CSW_SG552)|(1<<CSW_AK47)|(1<<CSW_P90);
const SECONDARY_WEAPONS_BIT_SUM = (1<<CSW_P228)|(1<<CSW_ELITE)|(1<<CSW_FIVESEVEN)|(1<<CSW_USP)|(1<<CSW_GLOCK18)|(1<<CSW_DEAGLE);

// Sound
new const SND_PICKUP[] = "items/gunpickup2.wav";

public plugin_init()
{
    register_plugin(PLUGIN, VERSION, AUTHOR);

    pCvar_Enable = register_cvar("amx_cs2_epickup", "1");
    pCvar_Radius = register_cvar("amx_cs2_epickup_radius", "105.0");
    pCvar_Sound  = register_cvar("amx_cs2_epickup_sound", "1");

    // Hook usercmd on every frame to intercept E key (IN_USE)
    register_forward(FM_CmdStart, "OnCmdStart");
}

public plugin_precache()
{
    precache_sound(SND_PICKUP);
}

public client_putinserver(id)
{
    g_iOldButtons[id] = 0;
    g_flLastPickup[id] = 0.0;
}

public client_disconnected(id)
{
    g_iOldButtons[id] = 0;
    g_flLastPickup[id] = 0.0;
}

public OnCmdStart(id, uc_handle, seed)
{
    if (!get_pcvar_num(pCvar_Enable))
        return FMRES_IGNORED;

    if (!is_user_alive(id) || is_user_bot(id))
        return FMRES_IGNORED;

    new iButtons = get_uc(uc_handle, UC_Buttons);
    new iOldButtons = g_iOldButtons[id];
    g_iOldButtons[id] = iButtons;

    // Check if player is pressing or holding E (IN_USE)
    if (!(iButtons & IN_USE))
        return FMRES_IGNORED;

    new Float:flRadius = get_pcvar_float(pCvar_Radius);
    if (flRadius <= 0.0) flRadius = 105.0;

    // Find weapon entity strictly aligned with crosshair within pickup radius
    new weaponEnt = FindCrosshairWeapon(id, flRadius);
    if (!pev_valid(weaponEnt))
        return FMRES_IGNORED; // Crosshair not on weapon: NEVER drop or modify weapons!

    // Priority Check: If CT is aiming at planted C4 (to defuse) or hostage, do not intercept!
    if (IsDefuseOrHostageTarget(id, weaponEnt))
        return FMRES_IGNORED;

    // A valid weapon is in crosshair range!
    // Strip IN_USE bit so func_buyzone NEVER opens the Shop menu!
    iButtons &= ~IN_USE;
    set_uc(uc_handle, UC_Buttons, iButtons);

    new bool:bJustPressedUse = !(iOldButtons & IN_USE);
    new Float:flGameTime = get_gametime();

    if (bJustPressedUse && flGameTime >= g_flLastPickup[id])
    {
        g_flLastPickup[id] = flGameTime + 0.3;

        new targetSlot = 0, targetWpnId = 0;
        GetGroundWeaponInfo(weaponEnt, targetSlot, targetWpnId);

        // CS:GO / CS2 Weapon Swap Logic:
        // Only drop player's current weapon if player actually possesses a weapon in that specific slot!
        if (targetSlot == 1)
        {
            if (pev(id, pev_weapons) & PRIMARY_WEAPONS_BIT_SUM)
            {
                DropPlayerSlot(id, 1);
            }
        }
        else if (targetSlot == 2)
        {
            if (pev(id, pev_weapons) & SECONDARY_WEAPONS_BIT_SUM)
            {
                DropPlayerSlot(id, 2);
            }
        }

        // Ensure FL_ONGROUND is present so engine CWeaponBox::Touch doesn't reject it
        if (pev_valid(weaponEnt))
        {
            set_pev(weaponEnt, pev_flags, pev(weaponEnt, pev_flags) | FL_ONGROUND);
        }

        // Perform pickup safely through engine Touch handler
        ExecuteHamB(Ham_Touch, weaponEnt, id);

        if (get_pcvar_num(pCvar_Sound))
        {
            emit_sound(id, CHAN_ITEM, SND_PICKUP, 0.9, ATTN_NORM, 0, PITCH_NORM);
        }
    }

    return FMRES_HANDLED;
}

stock FindCrosshairWeapon(id, Float:maxRadius)
{
    new Float:vEyes[3], Float:vViewOfs[3], Float:vAngles[3], Float:vForward[3];
    pev(id, pev_origin, vEyes);
    pev(id, pev_view_ofs, vViewOfs);
    xs_vec_add(vEyes, vViewOfs, vEyes);

    pev(id, pev_v_angle, vAngles);
    angle_vector(vAngles, ANGLEVECTOR_FORWARD, vForward);

    new bestEnt = 0;
    // Crosshair aim ray must pass within 20.0 units of the weapon center (strictly aligned!)
    new Float:flBestDistToLine = 20.0;

    new ent = -1;
    while ((ent = engfunc(EngFunc_FindEntityInSphere, ent, vEyes, maxRadius)) > 0)
    {
        if (!IsValidWeaponGroundEntity(ent))
            continue;

        if (!pev_valid(ent) || (pev(ent, pev_flags) & FL_KILLME))
            continue;

        // Verify the ground entity actually contains a valid weapon before targeting
        new groundSlot = 0, groundWpnId = 0;
        GetGroundWeaponInfo(ent, groundSlot, groundWpnId);
        if (groundSlot <= 0)
            continue; // Not a valid weapon pickup

        new Float:vEntOrigin[3];
        pev(ent, pev_origin, vEntOrigin);

        // Vector from player eyes to weapon origin
        new Float:vDirToEnt[3];
        xs_vec_sub(vEntOrigin, vEyes, vDirToEnt);

        // Distance along crosshair aim ray
        new Float:flDistAlongRay = xs_vec_dot(vDirToEnt, vForward);

        // Must be in front of player and within reach distance
        if (flDistAlongRay < 10.0 || flDistAlongRay > maxRadius)
            continue;

        // Direction dot product: must be within tight crosshair cone (>= 0.90 ~ 25 degrees)
        new Float:flDistTotal = get_distance_f(vEyes, vEntOrigin);
        if (flDistTotal > 0.0)
        {
            new Float:flDot = flDistAlongRay / flDistTotal;
            if (flDot < 0.90)
                continue;
        }

        // Closest point on the crosshair line of sight to the weapon center
        new Float:vClosestOnRay[3];
        xs_vec_mul_scalar(vForward, flDistAlongRay, vClosestOnRay);
        xs_vec_add(vEyes, vClosestOnRay, vClosestOnRay);

        // Perpendicular distance from crosshair line to weapon center
        new Float:flDistToLine = get_distance_f(vEntOrigin, vClosestOnRay);

        if (flDistToLine > flBestDistToLine)
            continue; // Not close enough to crosshair center

        // Check line of sight: ensure no wall/door blocking weapon
        new tr;
        engfunc(EngFunc_TraceLine, vEyes, vEntOrigin, IGNORE_MONSTERS, id, tr);
        new Float:flFraction;
        get_tr2(tr, TR_flFraction, flFraction);
        if (flFraction < 1.0)
        {
            new hitEnt = get_tr2(tr, TR_pHit);
            if (hitEnt != ent)
                continue; // Obstructed by map architecture
        }

        // The entity closest to the exact center of crosshair wins
        flBestDistToLine = flDistToLine;
        bestEnt = ent;
    }

    return bestEnt;
}

stock bool:IsValidWeaponGroundEntity(ent)
{
    if (!pev_valid(ent))
        return false;

    new classname[32];
    pev(ent, pev_classname, classname, charsmax(classname));

    // 1. Standard CS 1.6 dropped weapon container
    if (equal(classname, "weaponbox"))
        return true;

    // 2. Ground spawn weapon entity
    if (equal(classname, "armoury_entity"))
        return true;

    // 3. Custom dropped grenade entity from cs2_modern_utility
    if (equal(classname, "cs2_dropped_nade"))
        return true;

    // 4. Custom dropped rifle entity from bot_savage_ai
    if (equal(classname, "cs2_dropped_rifle"))
        return true;

    // 5. Loose weapon_* entities on the ground
    if (containi(classname, "weapon_") == 0)
    {
        new owner = pev(ent, pev_owner);
        if (owner <= 0 || owner > 32)
            return true;
    }

    return false;
}

stock bool:IsDefuseOrHostageTarget(id, weaponEnt)
{
    // Don't intercept if player is a CT defusing or escorting hostage
    if (cs_get_user_team(id) == CS_TEAM_CT)
    {
        new classname[32];
        pev(weaponEnt, pev_classname, classname, charsmax(classname));
        if (equal(classname, "hostage_entity"))
            return true;

        // Check if CT is aiming at planted C4 (grenade entity with c4 model)
        new Float:vEyes[3], Float:vAngles[3], Float:vForward[3], Float:vEnd[3];
        pev(id, pev_origin, vEyes);
        pev(id, pev_view_ofs, vAngles);
        xs_vec_add(vEyes, vAngles, vEyes);
        pev(id, pev_v_angle, vAngles);
        angle_vector(vAngles, ANGLEVECTOR_FORWARD, vForward);

        xs_vec_mul_scalar(vForward, 128.0, vEnd);
        xs_vec_add(vEyes, vEnd, vEnd);

        new tr;
        engfunc(EngFunc_TraceLine, vEyes, vEnd, DONT_IGNORE_MONSTERS, id, tr);
        new pHit = get_tr2(tr, TR_pHit);
        if (pev_valid(pHit))
        {
            pev(pHit, pev_classname, classname, charsmax(classname));
            if (equal(classname, "grenade"))
            {
                new model[32];
                pev(pHit, pev_model, model, charsmax(model));
                if (containi(model, "c4") != -1)
                    return true;
            }
        }
    }
    return false;
}

stock GetWeaponSlot(wpnId)
{
    if ((1 << wpnId) & PRIMARY_WEAPONS_BIT_SUM)
        return 1;
    if ((1 << wpnId) & SECONDARY_WEAPONS_BIT_SUM)
        return 2;
    if (wpnId == CSW_KNIFE)
        return 3;
    if (wpnId == CSW_HEGRENADE || wpnId == CSW_FLASHBANG || wpnId == CSW_SMOKEGRENADE)
        return 4;
    if (wpnId == CSW_C4)
        return 5;
    return 0;
}

stock GetGroundWeaponInfo(ent, &slot, &weaponId)
{
    slot = 0;
    weaponId = 0;

    if (!pev_valid(ent))
        return;

    new classname[32];
    pev(ent, pev_classname, classname, charsmax(classname));

    if (equal(classname, "weaponbox"))
    {
        // CWeaponBox::m_rgpPlayerItems base offset: 34 (Windows), extra linux diff: 4
        // Slot 1 (Primary)   : offset 34 + 1 = 35
        // Slot 2 (Secondary) : offset 34 + 2 = 36
        // Slot 3 (Knife)     : offset 34 + 3 = 37
        // Slot 4 (Grenades)  : offset 34 + 4 = 38
        // Slot 5 (C4)        : offset 34 + 5 = 39
        const OFFSET_WEAPONBOX_ITEMS = 34;
        const XO_CWEAPONBOX = 4;

        for (new s = 1; s <= 5; s++)
        {
            new item = get_pdata_cbase(ent, OFFSET_WEAPONBOX_ITEMS + s, XO_CWEAPONBOX);
            if (pev_valid(item))
            {
                weaponId = cs_get_weapon_id(item);
                if (weaponId == 0)
                {
                    new itemClass[32];
                    pev(item, pev_classname, itemClass, charsmax(itemClass));
                    weaponId = get_weaponid(itemClass);
                }

                new resolvedSlot = GetWeaponSlot(weaponId);
                slot = (resolvedSlot > 0) ? resolvedSlot : s;
                return;
            }
        }

        // Model-based fallback inspection
        new model[64];
        pev(ent, pev_model, model, charsmax(model));

        // Secondary pistols
        if (containi(model, "w_deagle") != -1)    { slot = 2; weaponId = CSW_DEAGLE; return; }
        if (containi(model, "w_usp") != -1)       { slot = 2; weaponId = CSW_USP; return; }
        if (containi(model, "w_glock") != -1)     { slot = 2; weaponId = CSW_GLOCK18; return; }
        if (containi(model, "w_p228") != -1 || containi(model, "w_p250") != -1) { slot = 2; weaponId = CSW_P228; return; }
        if (containi(model, "w_elite") != -1)     { slot = 2; weaponId = CSW_ELITE; return; }
        if (containi(model, "w_fiveseven") != -1) { slot = 2; weaponId = CSW_FIVESEVEN; return; }

        // C4
        if (containi(model, "w_c4") != -1)        { slot = 5; weaponId = CSW_C4; return; }

        // Primary weapons
        if (containi(model, "w_ak47") != -1)      { slot = 1; weaponId = CSW_AK47; return; }
        if (containi(model, "w_m4a1") != -1 || containi(model, "w_m4a4") != -1) { slot = 1; weaponId = CSW_M4A1; return; }
        if (containi(model, "w_awp") != -1)       { slot = 1; weaponId = CSW_AWP; return; }
        if (containi(model, "w_scout") != -1 || containi(model, "w_ssg08") != -1) { slot = 1; weaponId = CSW_SCOUT; return; }
        if (containi(model, "w_galil") != -1)     { slot = 1; weaponId = CSW_GALIL; return; }
        if (containi(model, "w_famas") != -1)     { slot = 1; weaponId = CSW_FAMAS; return; }
        if (containi(model, "w_aug") != -1)       { slot = 1; weaponId = CSW_AUG; return; }
        if (containi(model, "w_sg552") != -1)     { slot = 1; weaponId = CSW_SG552; return; }
        if (containi(model, "w_mp5") != -1)       { slot = 1; weaponId = CSW_MP5NAVY; return; }
        if (containi(model, "w_ump45") != -1)     { slot = 1; weaponId = CSW_UMP45; return; }
        if (containi(model, "w_p90") != -1)       { slot = 1; weaponId = CSW_P90; return; }
        if (containi(model, "w_m3") != -1)        { slot = 1; weaponId = CSW_M3; return; }
        if (containi(model, "w_xm1014") != -1)    { slot = 1; weaponId = CSW_XM1014; return; }
        if (containi(model, "w_m249") != -1)      { slot = 1; weaponId = CSW_M249; return; }
        if (containi(model, "w_g3sg1") != -1)     { slot = 1; weaponId = CSW_G3SG1; return; }
        if (containi(model, "w_sg550") != -1 || containi(model, "w_scar20") != -1) { slot = 1; weaponId = CSW_SG550; return; }
        if (containi(model, "w_mac10") != -1)     { slot = 1; weaponId = CSW_MAC10; return; }
        if (containi(model, "w_tmp") != -1 || containi(model, "w_mp9") != -1) { slot = 1; weaponId = CSW_TMP; return; }
    }
    else if (equal(classname, "cs2_dropped_rifle"))
    {
        weaponId = pev(ent, pev_iuser1);
        slot = GetWeaponSlot(weaponId);
    }
    else if (equal(classname, "cs2_dropped_nade"))
    {
        slot = 4;
    }
    else if (equal(classname, "armoury_entity"))
    {
        weaponId = cs_get_armoury_type(ent);
        slot = GetWeaponSlot(weaponId);
    }
    else if (containi(classname, "weapon_") == 0)
    {
        weaponId = get_weaponid(classname);
        slot = GetWeaponSlot(weaponId);
    }
}

stock DropPlayerSlot(id, slot)
{
    new curClip, curAmmo;
    new curWpn = get_user_weapon(id, curClip, curAmmo);
    new curSlot = GetWeaponSlot(curWpn);
    new szCurWpn[32];

    // If currently holding weapon in this slot, drop directly
    if (curSlot == slot && curWpn > 0)
    {
        get_weaponname(curWpn, szCurWpn, charsmax(szCurWpn));
        engclient_cmd(id, "drop", szCurWpn);
        return;
    }

    // Otherwise find the weapon in player's inventory matching the slot
    new weapons[32], numWeapons;
    get_user_weapons(id, weapons, numWeapons);
    for (new i = 0; i < numWeapons; i++)
    {
        new wpn = weapons[i];
        if (GetWeaponSlot(wpn) == slot)
        {
            new szWeapon[32];
            get_weaponname(wpn, szWeapon, charsmax(szWeapon));
            engclient_cmd(id, szWeapon);
            engclient_cmd(id, "drop", szWeapon);
            return;
        }
    }
}
