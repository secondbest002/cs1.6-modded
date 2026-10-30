#include <amxmodx>
#include <amxmisc>
#include <cstrike>
#include <fakemeta>
#include <hamsandwich>
#include <engine>
#include <xs>

#define PLUGIN  "CS2 E-Key Weapon Pickup"
#define VERSION "1.0.0"
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
    pCvar_Radius = register_cvar("amx_cs2_epickup_radius", "96.0");
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

    if (!is_user_alive(id))
        return FMRES_IGNORED;

    new iButtons = get_uc(uc_handle, UC_Buttons);
    new iOldButtons = g_iOldButtons[id];
    g_iOldButtons[id] = iButtons;

    // Check if player is holding or just pressed E (IN_USE)
    if (!(iButtons & IN_USE))
        return FMRES_IGNORED;

    new Float:flRadius = get_pcvar_float(pCvar_Radius);
    if (flRadius <= 0.0) flRadius = 96.0;

    // Find weapon entity currently aligned with crosshair within pickup radius
    new weaponEnt = FindCrosshairWeapon(id, flRadius);
    if (!pev_valid(weaponEnt))
        return FMRES_IGNORED;

    // Priority Check: If CT is aiming at planted C4 (to defuse) or hostage, do not intercept!
    if (IsDefuseOrHostageTarget(id, weaponEnt))
        return FMRES_IGNORED;

    // A valid weapon is in crosshair range!
    // Strip IN_USE bit so func_buyzone NEVER opens the Shop menu!
    iButtons &= ~IN_USE;
    set_uc(uc_handle, UC_Buttons, iButtons);

    // Only trigger actual pickup on rising edge (first button press, not while holding)
    new bool:bJustPressedUse = ((iButtons | IN_USE) & IN_USE) && !(iOldButtons & IN_USE);
    new Float:flGameTime = get_gametime();

    if (bJustPressedUse && flGameTime >= g_flLastPickup[id])
    {
        g_flLastPickup[id] = flGameTime + 0.3;

        // CS:GO / CS2 Weapon Swap Logic:
        // If ground weapon is Primary or Secondary, and player already possesses
        // a weapon in that slot, drop player's current weapon first to swap!
        new targetSlot = GetGroundWeaponSlot(weaponEnt);
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
    new Float:vEyes[3], Float:vViewOfs[3], Float:vAngles[3], Float:vForward[3], Float:vEnd[3];
    pev(id, pev_origin, vEyes);
    pev(id, pev_view_ofs, vViewOfs);
    xs_vec_add(vEyes, vViewOfs, vEyes);

    pev(id, pev_v_angle, vAngles);
    angle_vector(vAngles, ANGLEVECTOR_FORWARD, vForward);

    // 1. First priority: Direct TraceLine (crosshair exactly on weapon bounding box)
    xs_vec_mul_scalar(vForward, maxRadius, vEnd);
    xs_vec_add(vEyes, vEnd, vEnd);

    new tr;
    engfunc(EngFunc_TraceLine, vEyes, vEnd, DONT_IGNORE_MONSTERS, id, tr);
    new pHit = get_tr2(tr, TR_pHit);

    if (IsValidWeaponGroundEntity(pHit))
    {
        return pHit;
    }

    // 2. Second priority: Closest to crosshair center within pickup radius
    new bestEnt = 0;
    new Float:bestDot = 0.65; // Within crosshair alignment cone

    new ent = -1;
    while ((ent = engfunc(EngFunc_FindEntityInSphere, ent, vEyes, maxRadius)) > 0)
    {
        if (!IsValidWeaponGroundEntity(ent))
            continue;

        new Float:vEntOrigin[3];
        pev(ent, pev_origin, vEntOrigin);

        // Check line of sight: ensure no wall/door blocking weapon
        new tr2;
        engfunc(EngFunc_TraceLine, vEyes, vEntOrigin, IGNORE_MONSTERS, id, tr2);
        new Float:flFraction;
        get_tr2(tr2, TR_flFraction, flFraction);
        if (flFraction < 1.0)
        {
            new hitEnt = get_tr2(tr2, TR_pHit);
            if (hitEnt != ent)
                continue; // Obstructed by map architecture
        }

        // Calculate angle between aim vector and direction to weapon
        new Float:vDirToEnt[3];
        xs_vec_sub(vEntOrigin, vEyes, vDirToEnt);
        xs_vec_normalize(vDirToEnt, vDirToEnt);

        new Float:flDot = xs_vec_dot(vForward, vDirToEnt);
        if (flDot > bestDot)
        {
            bestDot = flDot;
            bestEnt = ent;
        }
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
    {
        return true;
    }

    // 2. Ground spawn weapon entity
    if (equal(classname, "armoury_entity"))
    {
        return true;
    }

    // 3. Custom dropped grenade entity from cs2_modern_utility
    if (equal(classname, "cs2_dropped_nade"))
    {
        return true;
    }

    // 4. Custom dropped rifle entity from bot_savage_ai
    if (equal(classname, "cs2_dropped_rifle"))
    {
        return true;
    }

    // 5. Loose weapon_* entities on the ground
    if (containi(classname, "weapon_") == 0)
    {
        new owner = pev(ent, pev_owner);
        if (owner <= 0 || owner > 32)
        {
            return true;
        }
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

stock GetGroundWeaponSlot(ent)
{
    if (!pev_valid(ent))
        return 0;

    new classname[32];
    pev(ent, pev_classname, classname, charsmax(classname));

    if (equal(classname, "weaponbox"))
    {
        // 1. Check weapon entities packed inside weaponbox (offset 34 + slot)
        for (new slot = 1; slot <= 2; slot++)
        {
            new item = get_pdata_cbase(ent, 34 + slot, 4);
            if (pev_valid(item))
            {
                return slot;
            }
        }

        // 2. Fallback to model name check
        new model[64];
        pev(ent, pev_model, model, charsmax(model));
        if (containi(model, "w_deagle") != -1 || containi(model, "w_usp") != -1 ||
            containi(model, "w_glock") != -1 || containi(model, "w_p228") != -1 ||
            containi(model, "w_elite") != -1 || containi(model, "w_fiveseven") != -1)
        {
            return 2;
        }
        else if (containi(model, "w_c4") != -1)
        {
            return 5;
        }
        else
        {
            // All other weaponbox models are primary weapons
            return 1;
        }
    }
    else if (equal(classname, "cs2_dropped_rifle"))
    {
        return 1;
    }
    else if (equal(classname, "cs2_dropped_nade"))
    {
        return 4;
    }
    else if (equal(classname, "armoury_entity"))
    {
        new itemType = cs_get_armoury_type(ent);
        return GetWeaponSlot(itemType);
    }
    else if (containi(classname, "weapon_") == 0)
    {
        new wpnId = get_weaponid(classname);
        return GetWeaponSlot(wpnId);
    }

    return 0;
}

stock DropPlayerSlot(id, slot)
{
    new curClip, curAmmo;
    new curWpn = get_user_weapon(id, curClip, curAmmo);
    new curSlot = GetWeaponSlot(curWpn);
    new szCurWpn[32];

    if (curSlot == slot && curWpn > 0)
    {
        get_weaponname(curWpn, szCurWpn, charsmax(szCurWpn));
        engclient_cmd(id, "drop", szCurWpn);
        return;
    }

    new const g_PrimaryNames[][] = {
        "weapon_ak47", "weapon_m4a1", "weapon_awp", "weapon_scout",
        "weapon_galil", "weapon_famas", "weapon_aug", "weapon_sg552",
        "weapon_sg550", "weapon_g3sg1", "weapon_m3", "weapon_xm1014",
        "weapon_m249", "weapon_mp5navy", "weapon_ump45", "weapon_p90",
        "weapon_mac10", "weapon_tmp"
    };
    new const g_SecondaryNames[][] = {
        "weapon_deagle", "weapon_usp", "weapon_glock18", "weapon_p228",
        "weapon_elite", "weapon_fiveseven"
    };

    if (slot == 1)
    {
        for (new i = 0; i < sizeof(g_PrimaryNames); i++)
        {
            new ent = find_ent_by_owner(-1, g_PrimaryNames[i], id);
            if (pev_valid(ent))
            {
                engclient_cmd(id, g_PrimaryNames[i]);
                engclient_cmd(id, "drop", g_PrimaryNames[i]);
                return;
            }
        }
    }
    else if (slot == 2)
    {
        for (new i = 0; i < sizeof(g_SecondaryNames); i++)
        {
            new ent = find_ent_by_owner(-1, g_SecondaryNames[i], id);
            if (pev_valid(ent))
            {
                engclient_cmd(id, g_SecondaryNames[i]);
                engclient_cmd(id, "drop", g_SecondaryNames[i]);
                return;
            }
        }
    }
}
