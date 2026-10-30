// ==============================================================================
// CS2 MODERN ENGINE - SUB-MODULE: MODERN UTILITY & GRENADES
// 3-Way Throw Strength, Smoke Tracer Dispersion, Drop Grenades, Buy Sellback Refund
// ==============================================================================

#if defined _mod_modern_utility_included
    #endinput
#endif
#define _mod_modern_utility_included

// Sound Paths
new const util_SND_DISPERSE[] = "cs2_utility/smoke_disperse.wav";
new const util_SND_REFUND[]   = "cs2_utility/refund.wav";
new const util_SND_PICKUP[]   = "items/gunpickup2.wav";

// Models & Sprites
new const util_MDL_W_HE[]    = "models/w_hegrenade.mdl";
new const util_MDL_W_FLASH[] = "models/w_flashbang.mdl";
new const util_MDL_W_SMOKE[] = "models/w_smokegrenade.mdl";
new util_SprWave;
new util_SprTracer;
new util_SprPuff;

// CVars
new util_pCvar_DropNades;
new util_pCvar_BuyRefund;
new util_pCvar_SmokeDisperse;
new util_pCvar_ReloadRefund;
new util_pCvar_ThrowStrength;
new util_pCvar_SmokeBullets;

// CS2 3-Way Throw Strength
enum {
    UTIL_THROW_FULL = 0,
    UTIL_THROW_SHORT,
    UTIL_THROW_MEDIUM
};
new util_iThrowMode[33];
new Float:util_flLastStrengthHint[33];

// CS2 Smoke Bullet Tracers Tracking
#define UTIL_MAX_ACTIVE_SMOKES 16
new Float:util_ActiveSmokes[UTIL_MAX_ACTIVE_SMOKES][3];
new Float:util_ActiveSmokeExpire[UTIL_MAX_ACTIVE_SMOKES];
new util_ActiveSmokeCount = 0;
new Float:util_flLastSmokeTracer[33];

// Freeze Time & Buy Period State
new bool:util_FreezeTimeActive = false;
new Float:util_flBuyTimeEnd = 0.0;
new util_iOldButtonsReload[33];

#define UTIL_MAX_BUY_HISTORY 16

enum UtilItemCategory {
    UTIL_CAT_NONE = 0,
    UTIL_CAT_WEAPON,         // Primary or secondary weapon
    UTIL_CAT_GRENADE,        // HE, Flash, Smoke
    UTIL_CAT_ARMOR_KEVLAR,   // Kevlar vest (100 armor, no helmet)
    UTIL_CAT_ARMOR_HELMET,   // Full Kevlar + Helmet
    UTIL_CAT_ARMOR_UPGRADE,  // Helmet upgrade
    UTIL_CAT_DEFUSER,        // Defusal kit
    UTIL_CAT_NVG             // Nightvision goggles
};

enum _:UtilBuyHistoryEntry {
    UtilItemCategory:ubCategory,
    ubWeaponId,
    ubCost,
    ubPrevArmorVal,
    CsArmorType:ubPrevArmorType
};

new util_BuyHistory[33][UTIL_MAX_BUY_HISTORY][UtilBuyHistoryEntry];
new util_BuyCount[33];
new util_LastMoney[33];

// Inventory Snapshot Tracking
new util_TrackWeapons[33];
new util_TrackArmor[33];
new CsArmorType:util_TrackArmorType[33];
new util_TrackDefuse[33];
new util_TrackNVG[33];
new util_TrackNades[33][3];
new bool:util_StartedWithPistol[33];
new util_DefaultPistolWpn[33];

// Bot Squad Retrieval Tracking
new util_BotRetrieveEnt[33];
new Float:util_BotRetrieveExpire[33];

// -------------------------------------------------------------
// Lifecycle Hooks
// -------------------------------------------------------------
public Mod_ModernUtility_Init()
{
    // CVars
    util_pCvar_DropNades     = register_cvar("amx_cs2_drop_nades", "1");
    util_pCvar_BuyRefund     = register_cvar("amx_cs2_buy_refund", "1");
    util_pCvar_SmokeDisperse = register_cvar("amx_cs2_smoke_disperse", "1");
    util_pCvar_ReloadRefund  = register_cvar("amx_cs2_refund_on_r", "1");
    util_pCvar_ThrowStrength = register_cvar("amx_cs2_throw_strength", "1");
    util_pCvar_SmokeBullets  = register_cvar("amx_cs2_smoke_bullets", "1");

    // Commands
    register_clcmd("drop", "util_Cmd_DropWeapon");
    register_clcmd("say /refund", "util_Cmd_Refund");
    register_clcmd("say_team /refund", "util_Cmd_Refund");
    register_clcmd("say /sellback", "util_Cmd_Refund");
    register_clcmd("say_team /sellback", "util_Cmd_Refund");
    register_clcmd("refund", "util_Cmd_Refund");
    register_clcmd("sellback", "util_Cmd_Refund");
    register_clcmd("amx_refund", "util_Cmd_Refund");

    register_clcmd("say /refundmenu", "util_Cmd_RefundMenu");
    register_clcmd("say_team /refundmenu", "util_Cmd_RefundMenu");
    register_clcmd("refundmenu", "util_Cmd_RefundMenu");

    // Events
    register_event("Money", "util_Event_Money", "b");
    register_event("CurWeapon", "util_Event_CurWeapon", "be", "1=1");

    // Ham Hooks
    RegisterHam(Ham_Touch, "info_target", "util_OnDroppedNadeTouch");
    RegisterHam(Ham_Think, "info_target", "util_OnDroppedNadeThink");
    RegisterHam(Ham_Think, "grenade", "util_OnGrenadeThink");

    util_RegisterFirearmHooks();

    // Fakemeta Hooks
    register_forward(FM_CmdStart, "util_OnCmdStart");
    register_forward(FM_SetModel, "util_OnSetModel_Post", 1);
}

public Mod_ModernUtility_Precache()
{
    precache_sound(util_SND_DISPERSE);
    precache_sound(util_SND_REFUND);
    precache_sound(util_SND_PICKUP);

    precache_model(util_MDL_W_HE);
    precache_model(util_MDL_W_FLASH);
    precache_model(util_MDL_W_SMOKE);

    util_SprWave   = precache_model("sprites/glow01.spr");
    util_SprTracer = precache_model("sprites/laserbeam.spr");
    util_SprPuff   = precache_model("sprites/smokepuff.spr");
}

public Mod_ModernUtility_PutInServer(id)
{
    util_BuyCount[id] = 0;
    util_BotRetrieveEnt[id] = 0;
    util_BotRetrieveExpire[id] = 0.0;
    util_TrackWeapons[id] = 0;
    util_TrackArmor[id] = 0;
    util_TrackArmorType[id] = CS_ARMOR_NONE;
    util_TrackDefuse[id] = 0;
    util_TrackNVG[id] = 0;
    util_TrackNades[id][0] = 0;
    util_TrackNades[id][1] = 0;
    util_TrackNades[id][2] = 0;
    util_StartedWithPistol[id] = false;
    util_DefaultPistolWpn[id] = 0;
    util_iOldButtonsReload[id] = 0;
    util_iThrowMode[id] = UTIL_THROW_FULL;
    util_flLastStrengthHint[id] = 0.0;
    util_flLastSmokeTracer[id] = 0.0;
    util_LastMoney[id] = 0;
}

public Mod_ModernUtility_Disconnect(id)
{
    remove_task(TASK_UTIL_BUY_OFFSET + id);
    util_BuyCount[id] = 0;
    util_LastMoney[id] = 0;
    util_BotRetrieveEnt[id] = 0;
    util_BotRetrieveExpire[id] = 0.0;
    util_iOldButtonsReload[id] = 0;
    util_iThrowMode[id] = UTIL_THROW_FULL;
    util_flLastStrengthHint[id] = 0.0;
    util_flLastSmokeTracer[id] = 0.0;
}

public Mod_ModernUtility_Spawn(id)
{
    if (is_user_bot(id))
        return;

    remove_task(TASK_UTIL_BUY_OFFSET + id);
    util_BuyCount[id] = 0;
    util_iThrowMode[id] = UTIL_THROW_FULL;
    util_LastMoney[id] = cs_get_user_money(id);
    util_SnapshotPlayerInventory(id);
}

public Mod_ModernUtility_NewRound()
{
    new freezeDuration = get_cvar_num("mp_freezetime");
    if (freezeDuration > 0)
    {
        util_FreezeTimeActive = true;
        remove_task(TASK_UTIL_FREEZETIME);
        set_task(float(freezeDuration), "util_Task_FreezeTimeOver", TASK_UTIL_FREEZETIME);
    }
    else
    {
        util_FreezeTimeActive = false;
        remove_task(TASK_UTIL_FREEZETIME);
    }

    new Float:flBuyTimeMins = get_cvar_float("mp_buytime");
    new Float:flBuyTimeSecs = (flBuyTimeMins > 0.0) ? (flBuyTimeMins * 60.0) : 27.0;
    util_flBuyTimeEnd = get_gametime() + float(freezeDuration) + flBuyTimeSecs;

    // Reset active smokes
    util_ActiveSmokeCount = 0;
    for (new s = 0; s < UTIL_MAX_ACTIVE_SMOKES; s++)
    {
        util_ActiveSmokeExpire[s] = 0.0;
    }

    for (new i = 1; i <= 32; i++)
    {
        remove_task(TASK_UTIL_BUY_OFFSET + i);
        util_BuyCount[i] = 0;
        util_BotRetrieveEnt[i] = 0;
        util_BotRetrieveExpire[i] = 0.0;
        util_iThrowMode[i] = UTIL_THROW_FULL;
        util_flLastStrengthHint[i] = 0.0;
        util_flLastSmokeTracer[i] = 0.0;

        if (is_user_connected(i) && !is_user_bot(i) && is_user_alive(i))
        {
            util_SnapshotPlayerInventory(i);
        }
        else
        {
            util_LastMoney[i] = 0;
        }
    }
}

public Mod_ModernUtility_RoundEnd()
{
    util_FreezeTimeActive = false;
    remove_task(TASK_UTIL_FREEZETIME);

    util_ActiveSmokeCount = 0;
    for (new s = 0; s < UTIL_MAX_ACTIVE_SMOKES; s++)
    {
        util_ActiveSmokeExpire[s] = 0.0;
    }

    for (new i = 1; i <= 32; i++)
    {
        remove_task(TASK_UTIL_BUY_OFFSET + i);
        util_BotRetrieveEnt[i] = 0;
        util_BotRetrieveExpire[i] = 0.0;
    }
}

public util_Task_FreezeTimeOver()
{
    util_FreezeTimeActive = false;
}

stock bool:util_IsPlayerInBuyPeriod(id)
{
    if (!is_user_connected(id) || !is_user_alive(id) || is_user_bot(id))
        return false;

    if (util_FreezeTimeActive)
        return true;

    if (cs_get_user_buyzone(id) && get_gametime() <= util_flBuyTimeEnd)
        return true;

    return false;
}

// -------------------------------------------------------------
// 1. Drop Grenades System
// -------------------------------------------------------------
public util_Cmd_DropWeapon(id)
{
    if (!get_pcvar_num(pCvar_MasterEnable) || !get_pcvar_num(util_pCvar_DropNades))
        return PLUGIN_CONTINUE;

    if (!is_user_alive(id))
        return PLUGIN_CONTINUE;

    new clip, ammo;
    new weaponId = get_user_weapon(id, clip, ammo);

    if (weaponId != CSW_HEGRENADE && weaponId != CSW_FLASHBANG && weaponId != CSW_SMOKEGRENADE)
        return PLUGIN_CONTINUE;

    new currentAmmo = cs_get_user_bpammo(id, weaponId);
    if (currentAmmo <= 0)
        return PLUGIN_HANDLED;

    new Float:vOrigin[3], Float:vViewOfs[3], Float:vAngles[3], Float:vForward[3], Float:vVelocity[3];
    pev(id, pev_origin, vOrigin);
    pev(id, pev_view_ofs, vViewOfs);
    xs_vec_add(vOrigin, vViewOfs, vOrigin);

    pev(id, pev_v_angle, vAngles);
    angle_vector(vAngles, ANGLEVECTOR_FORWARD, vForward);

    vOrigin[0] += vForward[0] * 24.0;
    vOrigin[1] += vForward[1] * 24.0;
    vOrigin[2] += vForward[2] * 24.0;

    vVelocity[0] = vForward[0] * 120.0;
    vVelocity[1] = vForward[1] * 120.0;
    vVelocity[2] = 40.0;

    new ent = engfunc(EngFunc_CreateNamedEntity, engfunc(EngFunc_AllocString, "info_target"));
    if (!pev_valid(ent))
        return PLUGIN_HANDLED;

    set_pev(ent, pev_classname, "cs2_dropped_nade");
    set_pev(ent, pev_origin, vOrigin);
    set_pev(ent, pev_velocity, vVelocity);
    set_pev(ent, pev_movetype, MOVETYPE_TOSS);
    set_pev(ent, pev_solid, SOLID_TRIGGER);
    set_pev(ent, pev_gravity, 1.0);
    set_pev(ent, pev_friction, 0.9);
    set_pev(ent, pev_owner, id);
    set_pev(ent, pev_iuser1, weaponId);
    set_pev(ent, pev_fuser1, get_gametime() + 1.2);

    new Float:mins[3] = {-30.0, -30.0, -20.0};
    new Float:maxs[3] = {30.0, 30.0, 30.0};
    engfunc(EngFunc_SetSize, ent, mins, maxs);

    set_pev(ent, pev_nextthink, get_gametime() + 0.1);

    new nadeName[24];
    switch (weaponId)
    {
        case CSW_HEGRENADE:
        {
            engfunc(EngFunc_SetModel, ent, util_MDL_W_HE);
            copy(nadeName, charsmax(nadeName), "HE Grenade");
        }
        case CSW_FLASHBANG:
        {
            engfunc(EngFunc_SetModel, ent, util_MDL_W_FLASH);
            copy(nadeName, charsmax(nadeName), "Flashbang");
        }
        case CSW_SMOKEGRENADE:
        {
            engfunc(EngFunc_SetModel, ent, util_MDL_W_SMOKE);
            copy(nadeName, charsmax(nadeName), "Smoke Grenade");
        }
    }

    cs_set_user_bpammo(id, weaponId, currentAmmo - 1);

    if (currentAmmo - 1 <= 0)
    {
        util_StripWeaponSafe(id, weaponId);
        util_TrackWeapons[id] &= ~(1 << weaponId);
    }
    util_UpdateTrackNade(id, weaponId, currentAmmo - 1);

    client_print(id, print_center, "Dropped %s", nadeName);

    new nearestBot = util_FindNearestBotForNade(id, weaponId);
    if (nearestBot > 0)
    {
        util_BotRetrieveEnt[nearestBot] = ent;
        util_BotRetrieveExpire[nearestBot] = get_gametime() + 10.0;

        new botName[32];
        get_user_name(nearestBot, botName, charsmax(botName));
        client_print(0, print_chat, "^x04[Squad AI]^x03 %s:^x01 Roger! Moving to pick up the dropped %s.", botName, nadeName);
        client_cmd(id, "spk radio/roger.wav");
    }

    return PLUGIN_HANDLED;
}

public util_OnDroppedNadeThink(ent)
{
    if (!pev_valid(ent))
        return HAM_IGNORED;

    new classname[32];
    pev(ent, pev_classname, classname, charsmax(classname));
    if (!equal(classname, "cs2_dropped_nade"))
        return HAM_IGNORED;

    new flags = pev(ent, pev_flags);
    new Float:vVel[3];
    pev(ent, pev_velocity, vVel);

    if ((flags & FL_ONGROUND) || xs_vec_len(vVel) < 25.0)
    {
        set_pev(ent, pev_velocity, Float:{0.0, 0.0, 0.0});
        set_pev(ent, pev_movetype, MOVETYPE_NONE);
        return HAM_IGNORED;
    }

    set_pev(ent, pev_nextthink, get_gametime() + 0.1);
    return HAM_IGNORED;
}

public util_OnDroppedNadeTouch(ent, toucher)
{
    if (!pev_valid(ent))
        return HAM_IGNORED;

    new classname[32];
    pev(ent, pev_classname, classname, charsmax(classname));
    if (!equal(classname, "cs2_dropped_nade"))
        return HAM_IGNORED;

    if (!is_user_alive(toucher))
        return HAM_IGNORED;

    new owner = pev(ent, pev_owner);
    new Float:pickupCooldown;
    pev(ent, pev_fuser1, pickupCooldown);
    if (toucher == owner && get_gametime() < pickupCooldown)
    {
        return HAM_IGNORED;
    }

    if (util_GiveGrenadeToPlayer(toucher, ent))
        return HAM_HANDLED;

    return HAM_IGNORED;
}

stock bool:util_GiveGrenadeToPlayer(toucher, ent)
{
    if (!pev_valid(ent) || !is_user_alive(toucher))
        return false;

    new weaponId = pev(ent, pev_iuser1);
    if (weaponId != CSW_HEGRENADE && weaponId != CSW_FLASHBANG && weaponId != CSW_SMOKEGRENADE)
        return false;

    new currentAmmo = cs_get_user_bpammo(toucher, weaponId);
    new maxLimit = (weaponId == CSW_FLASHBANG) ? 2 : 1;
    if (currentAmmo >= maxLimit)
        return false;

    new weaponName[32];
    get_weaponname(weaponId, weaponName, charsmax(weaponName));
    if (!weaponName[0])
        return false;

    if (currentAmmo == 0)
    {
        give_item(toucher, weaponName);
        cs_set_user_bpammo(toucher, weaponId, 1);
        util_TrackWeapons[toucher] |= (1 << weaponId);
        util_UpdateTrackNade(toucher, weaponId, 1);
    }
    else
    {
        cs_set_user_bpammo(toucher, weaponId, currentAmmo + 1);
        util_UpdateTrackNade(toucher, weaponId, currentAmmo + 1);
    }

    emit_sound(toucher, CHAN_ITEM, util_SND_PICKUP, 0.9, ATTN_NORM, 0, PITCH_NORM);

    new owner = pev(ent, pev_owner);
    new ownerName[32];
    if (is_user_connected(owner))
        get_user_name(owner, ownerName, charsmax(ownerName));
    else
        copy(ownerName, charsmax(ownerName), "Teammate");

    client_print(toucher, print_center, "Picked up grenade from %s", ownerName);

    set_pev(ent, pev_solid, SOLID_NOT);
    set_pev(ent, pev_flags, pev(ent, pev_flags) | FL_KILLME);
    dllfunc(DLLFunc_Think, ent);
    return true;
}

public util_OnCmdStart(id, uc_handle, seed)
{
    if (!get_pcvar_num(pCvar_MasterEnable))
        return FMRES_IGNORED;

    if (!is_user_alive(id))
        return FMRES_IGNORED;

    // 1. Intercept 'R' (+reload) key for Human Players during Freeze Time / Buy Period
    if (!is_user_bot(id))
    {
        new buttons = get_uc(uc_handle, UC_Buttons);
        new oldbuttons = util_iOldButtonsReload[id];
        util_iOldButtonsReload[id] = buttons;

        if (util_IsPlayerInBuyPeriod(id) && get_pcvar_num(util_pCvar_ReloadRefund) && get_pcvar_num(util_pCvar_BuyRefund))
        {
            if ((buttons & IN_RELOAD) && !(oldbuttons & IN_RELOAD))
            {
                set_uc(uc_handle, UC_Buttons, buttons & ~IN_RELOAD);
                util_Cmd_Refund(id);
                return FMRES_HANDLED;
            }
        }

        // 2. CS2 3-Way Variable Throw Strength Engine
        if (get_pcvar_num(util_pCvar_ThrowStrength))
        {
            new clip, ammo;
            new weaponId = get_user_weapon(id, clip, ammo);
            if (weaponId == CSW_HEGRENADE || weaponId == CSW_FLASHBANG || weaponId == CSW_SMOKEGRENADE)
            {
                if ((buttons & IN_ATTACK) && (buttons & IN_ATTACK2))
                {
                    util_iThrowMode[id] = UTIL_THROW_MEDIUM;
                    set_uc(uc_handle, UC_Buttons, buttons & ~IN_ATTACK2);
                    new Float:now = get_gametime();
                    if (now - util_flLastStrengthHint[id] > 0.4)
                    {
                        client_print(id, print_center, "✦ [CS2] Medium Throw [Left+Right Click] (65%) ✦");
                        util_flLastStrengthHint[id] = now;
                    }
                }
                else if (buttons & IN_ATTACK2)
                {
                    util_iThrowMode[id] = UTIL_THROW_SHORT;
                    set_uc(uc_handle, UC_Buttons, (buttons & ~IN_ATTACK2) | IN_ATTACK);
                    new Float:now = get_gametime();
                    if (now - util_flLastStrengthHint[id] > 0.4)
                    {
                        client_print(id, print_center, "✦ [CS2] Short Underhand Lob [Right Click] (35%) ✦");
                        util_flLastStrengthHint[id] = now;
                    }
                }
                else if (buttons & IN_ATTACK)
                {
                    util_iThrowMode[id] = UTIL_THROW_FULL;
                }
            }
        }

        return FMRES_IGNORED;
    }

    // Bot Squad AI Navigation
    new Float:flGameTime = get_gametime();
    new targetEnt = util_BotRetrieveEnt[id];
    if (targetEnt > 0 && flGameTime < util_BotRetrieveExpire[id])
    {
        if (pev_valid(targetEnt))
        {
            new Float:vBotOrigin[3], Float:vNadeOrigin[3], Float:vDiff[3];
            pev(id, pev_origin, vBotOrigin);
            pev(targetEnt, pev_origin, vNadeOrigin);
            xs_vec_sub(vNadeOrigin, vBotOrigin, vDiff);
            new Float:flDist = xs_vec_len(vDiff);

            if (flDist <= 55.0)
            {
                util_GiveGrenadeToPlayer(id, targetEnt);
                util_BotRetrieveEnt[id] = 0;
            }
            else if (flDist <= 1800.0 && pev(id, pev_enemy) <= 0)
            {
                new Float:vAimAngles[3];
                vector_to_angle(vDiff, vAimAngles);
                util_ClampAngles(vAimAngles);

                set_uc(uc_handle, UC_ViewAngles, vAimAngles);
                set_uc(uc_handle, UC_ForwardMove, 280.0);
            }
        }
        else
        {
            util_BotRetrieveEnt[id] = 0;
        }
    }

    return FMRES_IGNORED;
}

stock util_FindNearestBotForNade(id, weaponId)
{
    new CsTeams:myTeam = cs_get_user_team(id);
    new Float:vPlayerOrigin[3];
    pev(id, pev_origin, vPlayerOrigin);

    new bestBot = 0;
    new Float:bestDist = 1800.0;
    new maxLimit = (weaponId == CSW_FLASHBANG) ? 2 : 1;

    for (new bot = 1; bot <= 32; bot++)
    {
        if (is_user_alive(bot) && is_user_bot(bot) && cs_get_user_team(bot) == myTeam)
        {
            if (cs_get_user_bpammo(bot, weaponId) < maxLimit)
            {
                new Float:vBotOrigin[3];
                pev(bot, pev_origin, vBotOrigin);
                new Float:dist = get_distance_f(vPlayerOrigin, vBotOrigin);
                if (dist < bestDist)
                {
                    bestDist = dist;
                    bestBot = bot;
                }
            }
        }
    }
    return bestBot;
}

stock util_ClampAngles(Float:angles[3])
{
    while (angles[0] > 89.0)  angles[0] -= 180.0;
    while (angles[0] < -89.0) angles[0] += 180.0;
    while (angles[1] > 180.0)  angles[1] -= 360.0;
    while (angles[1] < -180.0) angles[1] += 360.0;
    angles[2] = 0.0;
}

stock util_StripWeaponSafe(id, weaponId)
{
    if (!is_user_alive(id))
        return 0;

    new weaponName[32];
    get_weaponname(weaponId, weaponName, charsmax(weaponName));
    if (!weaponName[0])
        return 0;

    new ent = 0;
    while ((ent = engfunc(EngFunc_FindEntityByString, ent, "classname", weaponName)) > 0)
    {
        if (pev(ent, pev_owner) == id)
        {
            new activeItem = get_pdata_cbase(id, m_pActiveItem, extra_offset_player);
            if (activeItem == ent)
            {
                ExecuteHamB(Ham_Item_Holster, ent, 0);

                new knife = -1;
                while ((knife = engfunc(EngFunc_FindEntityByString, knife, "classname", "weapon_knife")) > 0)
                {
                    if (pev(knife, pev_owner) == id && knife != ent)
                        break;
                }

                if (pev_valid(knife) && knife != ent)
                {
                    set_pdata_cbase(id, m_pActiveItem, knife, extra_offset_player);
                    ExecuteHamB(Ham_Item_Deploy, knife);
                }
                else
                {
                    set_pdata_cbase(id, m_pActiveItem, 0, extra_offset_player);
                }
            }

            ExecuteHamB(Ham_RemovePlayerItem, id, ent);
            set_pev(id, pev_weapons, pev(id, pev_weapons) & ~(1 << weaponId));
            set_pev(ent, pev_flags, pev(ent, pev_flags) | FL_KILLME);
            dllfunc(DLLFunc_Think, ent);

            return 1;
        }
    }
    return 0;
}

// -------------------------------------------------------------
// 2. Buy Refund (Sellback) System
// -------------------------------------------------------------
public util_Event_Money(id)
{
    if (!get_pcvar_num(pCvar_MasterEnable) || !get_pcvar_num(util_pCvar_BuyRefund))
        return;

    if (id < 1 || id > 32 || !is_user_connected(id) || is_user_bot(id) || !is_user_alive(id) || !util_IsPlayerInBuyPeriod(id))
        return;

    new currentMoney = read_data(1);
    new diff = util_LastMoney[id] - currentMoney;

    if (diff > 0)
    {
        remove_task(TASK_UTIL_BUY_OFFSET + id);
        set_task(0.02, "util_Task_DetectBuy", TASK_UTIL_BUY_OFFSET + id);
    }
    else
    {
        util_LastMoney[id] = currentMoney;
    }
}

public util_Task_DetectBuy(taskId)
{
    new id = taskId - TASK_UTIL_BUY_OFFSET;
    if (id < 1 || id > 32 || !is_user_connected(id) || is_user_bot(id) || !is_user_alive(id) || !util_IsPlayerInBuyPeriod(id))
        return;

    new currentMoney = cs_get_user_money(id);
    new totalSpent = util_LastMoney[id] - currentMoney;
    if (totalSpent <= 0)
    {
        util_LastMoney[id] = currentMoney;
        return;
    }

    new curWeapons = pev(id, pev_weapons);
    new newWeapons = curWeapons & ~util_TrackWeapons[id];

    newWeapons &= ~(1 << CSW_C4);
    newWeapons &= ~(1 << CSW_KNIFE);

    // Grenades
    new curHE = cs_get_user_bpammo(id, CSW_HEGRENADE);
    if (curHE > util_TrackNades[id][0])
    {
        util_PushBuyEntry(id, UTIL_CAT_GRENADE, CSW_HEGRENADE, 300, 0, CS_ARMOR_NONE);
        util_TrackNades[id][0] = curHE;
        newWeapons &= ~(1 << CSW_HEGRENADE);
    }

    new curFlash = cs_get_user_bpammo(id, CSW_FLASHBANG);
    while (curFlash > util_TrackNades[id][1])
    {
        util_PushBuyEntry(id, UTIL_CAT_GRENADE, CSW_FLASHBANG, 200, 0, CS_ARMOR_NONE);
        util_TrackNades[id][1]++;
        newWeapons &= ~(1 << CSW_FLASHBANG);
    }

    new curSmoke = cs_get_user_bpammo(id, CSW_SMOKEGRENADE);
    if (curSmoke > util_TrackNades[id][2])
    {
        util_PushBuyEntry(id, UTIL_CAT_GRENADE, CSW_SMOKEGRENADE, 300, 0, CS_ARMOR_NONE);
        util_TrackNades[id][2] = curSmoke;
        newWeapons &= ~(1 << CSW_SMOKEGRENADE);
    }

    // Firearms
    for (new wpn = 1; wpn <= 30; wpn++)
    {
        if (newWeapons & (1 << wpn))
        {
            new price = util_GetWeaponPrice(wpn);
            if (price > 0)
            {
                util_PushBuyEntry(id, UTIL_CAT_WEAPON, wpn, price, 0, CS_ARMOR_NONE);
            }
        }
    }

    // Armor
    new CsArmorType:curArmorType;
    new curArmor = cs_get_user_armor(id, curArmorType);
    if (curArmor > util_TrackArmor[id] || curArmorType > util_TrackArmorType[id])
    {
        if (curArmorType == CS_ARMOR_VESTHELM)
        {
            if (util_TrackArmorType[id] == CS_ARMOR_KEVLAR)
            {
                util_PushBuyEntry(id, UTIL_CAT_ARMOR_UPGRADE, 0, 350, util_TrackArmor[id], util_TrackArmorType[id]);
            }
            else
            {
                util_PushBuyEntry(id, UTIL_CAT_ARMOR_HELMET, 0, 1000, util_TrackArmor[id], util_TrackArmorType[id]);
            }
        }
        else if (curArmorType == CS_ARMOR_KEVLAR && util_TrackArmorType[id] == CS_ARMOR_NONE)
        {
            util_PushBuyEntry(id, UTIL_CAT_ARMOR_KEVLAR, 0, 650, util_TrackArmor[id], util_TrackArmorType[id]);
        }
        util_TrackArmor[id] = curArmor;
        util_TrackArmorType[id] = curArmorType;
    }

    // Defusal Kit
    new curDefuse = cs_get_user_defuse(id);
    if (curDefuse && !util_TrackDefuse[id])
    {
        util_PushBuyEntry(id, UTIL_CAT_DEFUSER, 0, 200, 0, CS_ARMOR_NONE);
        util_TrackDefuse[id] = 1;
    }

    // Nightvision
    new curNVG = cs_get_user_nvg(id);
    if (curNVG && !util_TrackNVG[id])
    {
        util_PushBuyEntry(id, UTIL_CAT_NVG, 0, 1250, 0, CS_ARMOR_NONE);
        util_TrackNVG[id] = 1;
    }

    util_TrackWeapons[id] = curWeapons;
    util_LastMoney[id] = currentMoney;
}

stock util_PushBuyEntry(id, UtilItemCategory:cat, wpnId, cost, prevArmorVal, CsArmorType:prevArmorType)
{
    if (util_BuyCount[id] >= UTIL_MAX_BUY_HISTORY)
        return;

    new idx = util_BuyCount[id];
    util_BuyHistory[id][idx][ubCategory] = cat;
    util_BuyHistory[id][idx][ubWeaponId] = wpnId;
    util_BuyHistory[id][idx][ubCost] = cost;
    util_BuyHistory[id][idx][ubPrevArmorVal] = prevArmorVal;
    util_BuyHistory[id][idx][ubPrevArmorType] = prevArmorType;
    util_BuyCount[id]++;
}

public util_Cmd_Refund(id)
{
    if (!get_pcvar_num(pCvar_MasterEnable) || !get_pcvar_num(util_pCvar_BuyRefund))
        return PLUGIN_CONTINUE;

    if (!is_user_alive(id))
        return PLUGIN_HANDLED;

    if (!util_IsPlayerInBuyPeriod(id))
    {
        client_print(id, print_chat, "^x04[CS2 Refund]^x01 Refund is only available during Freeze Time or in Buyzone during Buy Time!");
        return PLUGIN_HANDLED;
    }

    if (task_exists(TASK_UTIL_BUY_OFFSET + id))
    {
        remove_task(TASK_UTIL_BUY_OFFSET + id);
        util_Task_DetectBuy(TASK_UTIL_BUY_OFFSET + id);
    }

    if (util_BuyCount[id] <= 0)
    {
        client_print(id, print_chat, "^x04[CS2 Refund]^x01 No purchases to refund this round.");
        return PLUGIN_HANDLED;
    }

    while (util_BuyCount[id] > 0)
    {
        new lastIdx = util_BuyCount[id] - 1;
        if (util_ExecuteRefundItem(id, lastIdx))
        {
            return PLUGIN_HANDLED;
        }
    }

    client_print(id, print_chat, "^x04[CS2 Refund]^x01 No refundable items remaining in inventory.");
    return PLUGIN_HANDLED;
}

public util_Cmd_RefundMenu(id)
{
    if (!get_pcvar_num(pCvar_MasterEnable) || !get_pcvar_num(util_pCvar_BuyRefund))
        return PLUGIN_CONTINUE;

    if (!is_user_alive(id))
        return PLUGIN_HANDLED;

    if (!util_IsPlayerInBuyPeriod(id))
    {
        client_print(id, print_chat, "^x04[CS2 Refund]^x01 Sellback menu is only available during Freeze Time or in Buyzone during Buy Time!");
        return PLUGIN_HANDLED;
    }

    if (task_exists(TASK_UTIL_BUY_OFFSET + id))
    {
        remove_task(TASK_UTIL_BUY_OFFSET + id);
        util_Task_DetectBuy(TASK_UTIL_BUY_OFFSET + id);
    }

    if (util_BuyCount[id] <= 0)
    {
        client_print(id, print_chat, "^x04[CS2 Refund]^x01 No purchases to refund this round.");
        return PLUGIN_HANDLED;
    }

    new menu = menu_create("\y[CS2 Sellback Menu] \wSelect Item to Refund:", "util_HandleRefundMenu");

    for (new i = util_BuyCount[id] - 1; i >= 0; i--)
    {
        new UtilItemCategory:cat = util_BuyHistory[id][i][ubCategory];
        new wpnId = util_BuyHistory[id][i][ubWeaponId];
        new cost = util_BuyHistory[id][i][ubCost];

        new itemName[32];
        util_GetItemFriendlyName(cat, wpnId, itemName, charsmax(itemName));

        new bool:eligible = util_IsItemEligibleForRefund(id, cat, wpnId);

        new itemText[64];
        if (eligible)
        {
            formatex(itemText, charsmax(itemText), "%s \y(+$%d)", itemName, cost);
        }
        else
        {
            formatex(itemText, charsmax(itemText), "\d%s [Dropped/Used]", itemName);
        }

        new itemData[8];
        num_to_str(i, itemData, charsmax(itemData));
        menu_additem(menu, itemText, itemData);
    }

    menu_setprop(menu, MPROP_EXIT, MEXIT_ALL);
    menu_display(id, menu, 0);

    return PLUGIN_HANDLED;
}

public util_HandleRefundMenu(id, menu, item)
{
    if (item == MENU_EXIT || !is_user_alive(id))
    {
        menu_destroy(menu);
        return PLUGIN_HANDLED;
    }

    if (!util_IsPlayerInBuyPeriod(id))
    {
        client_print(id, print_chat, "^x04[CS2 Refund]^x01 Refund is only available during Freeze Time or in Buyzone during Buy Time!");
        menu_destroy(menu);
        return PLUGIN_HANDLED;
    }

    new data[8], szName[64], access, callback;
    menu_item_getinfo(menu, item, access, data, charsmax(data), szName, charsmax(szName), callback);
    menu_destroy(menu);

    new idx = str_to_num(data);
    if (idx < 0 || idx >= util_BuyCount[id])
    {
        return PLUGIN_HANDLED;
    }

    new UtilItemCategory:cat = util_BuyHistory[id][idx][ubCategory];
    new wpnId = util_BuyHistory[id][idx][ubWeaponId];

    new itemName[32];
    util_GetItemFriendlyName(cat, wpnId, itemName, charsmax(itemName));

    if (!util_IsItemEligibleForRefund(id, cat, wpnId))
    {
        client_print(id, print_chat, "^x04[CS2 Refund]^x01 Cannot refund ^x03%s^x01: item is no longer in your inventory!", itemName);
        util_RemoveBuyHistoryIndex(id, idx);
        if (util_BuyCount[id] > 0)
        {
            util_Cmd_RefundMenu(id);
        }
        return PLUGIN_HANDLED;
    }

    util_ExecuteRefundItem(id, idx);

    if (util_BuyCount[id] > 0)
    {
        util_Cmd_RefundMenu(id);
    }

    return PLUGIN_HANDLED;
}

stock bool:util_ExecuteRefundItem(id, idx)
{
    new UtilItemCategory:cat = util_BuyHistory[id][idx][ubCategory];
    new wpnId = util_BuyHistory[id][idx][ubWeaponId];
    new cost = util_BuyHistory[id][idx][ubCost];

    new itemName[32];
    util_GetItemFriendlyName(cat, wpnId, itemName, charsmax(itemName));

    switch (cat)
    {
        case UTIL_CAT_WEAPON:
        {
            if (!(pev(id, pev_weapons) & (1 << wpnId)))
            {
                client_print(id, print_chat, "^x04[CS2 Refund]^x01 Cannot refund ^x03%s^x01 (weapon has been dropped or discarded).", itemName);
                util_RemoveBuyHistoryIndex(id, idx);
                return false;
            }

            util_StripWeaponSafe(id, wpnId);
            cs_set_user_bpammo(id, wpnId, 0);
            util_TrackWeapons[id] &= ~(1 << wpnId);

            if (util_IsSecondaryPistol(wpnId) && !util_HasSecondaryWeapon(id) && util_StartedWithPistol[id])
            {
                util_RestoreStarterPistol(id);
            }

            util_ProcessRefundSuccess(id, cost, itemName);
            util_RemoveBuyHistoryIndex(id, idx);
            return true;
        }
        case UTIL_CAT_GRENADE:
        {
            new curAmmo = cs_get_user_bpammo(id, wpnId);
            if (curAmmo <= 0)
            {
                client_print(id, print_chat, "^x04[CS2 Refund]^x01 Cannot refund ^x03%s^x01 (grenade has been thrown or dropped).", itemName);
                util_RemoveBuyHistoryIndex(id, idx);
                return false;
            }

            cs_set_user_bpammo(id, wpnId, curAmmo - 1);
            if (curAmmo - 1 <= 0)
            {
                util_StripWeaponSafe(id, wpnId);
                util_TrackWeapons[id] &= ~(1 << wpnId);
            }
            util_UpdateTrackNade(id, wpnId, curAmmo - 1);

            util_ProcessRefundSuccess(id, cost, itemName);
            util_RemoveBuyHistoryIndex(id, idx);
            return true;
        }
        case UTIL_CAT_ARMOR_KEVLAR, UTIL_CAT_ARMOR_HELMET:
        {
            new CsArmorType:curType;
            new curArmor = cs_get_user_armor(id, curType);
            if (curArmor <= 0)
            {
                client_print(id, print_chat, "^x04[CS2 Refund]^x01 Cannot refund ^x03%s^x01 (no armor found).", itemName);
                util_RemoveBuyHistoryIndex(id, idx);
                return false;
            }

            cs_set_user_armor(id, util_BuyHistory[id][idx][ubPrevArmorVal], util_BuyHistory[id][idx][ubPrevArmorType]);
            util_TrackArmor[id] = util_BuyHistory[id][idx][ubPrevArmorVal];
            util_TrackArmorType[id] = util_BuyHistory[id][idx][ubPrevArmorType];

            util_ProcessRefundSuccess(id, cost, itemName);
            util_RemoveBuyHistoryIndex(id, idx);
            return true;
        }
        case UTIL_CAT_ARMOR_UPGRADE:
        {
            cs_set_user_armor(id, 100, CS_ARMOR_KEVLAR);
            util_TrackArmor[id] = 100;
            util_TrackArmorType[id] = CS_ARMOR_KEVLAR;

            util_ProcessRefundSuccess(id, cost, itemName);
            util_RemoveBuyHistoryIndex(id, idx);
            return true;
        }
        case UTIL_CAT_DEFUSER:
        {
            if (!cs_get_user_defuse(id))
            {
                client_print(id, print_chat, "^x04[CS2 Refund]^x01 Cannot refund ^x03Defusal Kit^x01 (not equipped).");
                util_RemoveBuyHistoryIndex(id, idx);
                return false;
            }

            cs_set_user_defuse(id, 0);
            util_TrackDefuse[id] = 0;

            util_ProcessRefundSuccess(id, cost, itemName);
            util_RemoveBuyHistoryIndex(id, idx);
            return true;
        }
        case UTIL_CAT_NVG:
        {
            if (!cs_get_user_nvg(id))
            {
                client_print(id, print_chat, "^x04[CS2 Refund]^x01 Cannot refund ^x03Nightvision^x01 (not equipped).");
                util_RemoveBuyHistoryIndex(id, idx);
                return false;
            }

            cs_set_user_nvg(id, 0);
            util_TrackNVG[id] = 0;

            util_ProcessRefundSuccess(id, cost, itemName);
            util_RemoveBuyHistoryIndex(id, idx);
            return true;
        }
    }
    return false;
}

stock util_RemoveBuyHistoryIndex(id, idx)
{
    for (new i = idx; i < util_BuyCount[id] - 1; i++)
    {
        util_BuyHistory[id][i][ubCategory] = util_BuyHistory[id][i + 1][ubCategory];
        util_BuyHistory[id][i][ubWeaponId] = util_BuyHistory[id][i + 1][ubWeaponId];
        util_BuyHistory[id][i][ubCost] = util_BuyHistory[id][i + 1][ubCost];
        util_BuyHistory[id][i][ubPrevArmorVal] = util_BuyHistory[id][i + 1][ubPrevArmorVal];
        util_BuyHistory[id][i][ubPrevArmorType] = util_BuyHistory[id][i + 1][ubPrevArmorType];
    }
    util_BuyCount[id]--;
}

stock util_ProcessRefundSuccess(id, cost, const itemName[])
{
    new newMoney = min(16000, cs_get_user_money(id) + cost);
    cs_set_user_money(id, newMoney, 1);
    util_LastMoney[id] = newMoney;

    client_cmd(id, "spk %s", util_SND_REFUND);
    client_print(id, print_chat, "^x04[CS2 Refund]^x01 Sold back ^x03%s^x01! Returned ^x04+$%d^x01 (New balance: $%d)", itemName, cost, newMoney);
}

stock bool:util_IsItemEligibleForRefund(id, UtilItemCategory:cat, wpnId)
{
    if (!is_user_alive(id))
        return false;

    switch (cat)
    {
        case UTIL_CAT_WEAPON:
            return (pev(id, pev_weapons) & (1 << wpnId)) ? true : false;
        case UTIL_CAT_GRENADE:
            return (cs_get_user_bpammo(id, wpnId) > 0);
        case UTIL_CAT_ARMOR_KEVLAR, UTIL_CAT_ARMOR_HELMET, UTIL_CAT_ARMOR_UPGRADE:
        {
            new CsArmorType:type;
            return (cs_get_user_armor(id, type) > 0);
        }
        case UTIL_CAT_DEFUSER:
            return (cs_get_user_defuse(id) > 0);
        case UTIL_CAT_NVG:
            return (cs_get_user_nvg(id) > 0);
    }
    return false;
}

stock util_SnapshotPlayerInventory(id)
{
    if (!is_user_alive(id))
        return;

    util_TrackWeapons[id] = pev(id, pev_weapons);
    util_TrackArmor[id] = cs_get_user_armor(id, util_TrackArmorType[id]);
    util_TrackDefuse[id] = cs_get_user_defuse(id);
    util_TrackNVG[id] = cs_get_user_nvg(id);
    util_TrackNades[id][0] = cs_get_user_bpammo(id, CSW_HEGRENADE);
    util_TrackNades[id][1] = cs_get_user_bpammo(id, CSW_FLASHBANG);
    util_TrackNades[id][2] = cs_get_user_bpammo(id, CSW_SMOKEGRENADE);
    util_LastMoney[id] = cs_get_user_money(id);

    new CsTeams:team = cs_get_user_team(id);
    if (team == CS_TEAM_CT && (util_TrackWeapons[id] & (1 << CSW_USP)))
    {
        util_StartedWithPistol[id] = true;
        util_DefaultPistolWpn[id] = CSW_USP;
    }
    else if (team == CS_TEAM_T && (util_TrackWeapons[id] & (1 << CSW_GLOCK18)))
    {
        util_StartedWithPistol[id] = true;
        util_DefaultPistolWpn[id] = CSW_GLOCK18;
    }
    else
    {
        util_StartedWithPistol[id] = false;
        util_DefaultPistolWpn[id] = 0;
    }
}

stock util_RestoreStarterPistol(id)
{
    new CsTeams:team = cs_get_user_team(id);
    if (team == CS_TEAM_CT)
    {
        give_item(id, "weapon_usp");
        cs_set_user_bpammo(id, CSW_USP, 24);
        util_TrackWeapons[id] |= (1 << CSW_USP);
    }
    else if (team == CS_TEAM_T)
    {
        give_item(id, "weapon_glock18");
        cs_set_user_bpammo(id, CSW_GLOCK18, 40);
        util_TrackWeapons[id] |= (1 << CSW_GLOCK18);
    }
}

stock bool:util_IsSecondaryPistol(wpnId)
{
    return bool:(CSW_ALL_PISTOLS & (1 << wpnId));
}

stock bool:util_HasSecondaryWeapon(id)
{
    return bool:(pev(id, pev_weapons) & CSW_ALL_PISTOLS);
}

stock util_UpdateTrackNade(id, weaponId, newAmount)
{
    switch (weaponId)
    {
        case CSW_HEGRENADE:    util_TrackNades[id][0] = newAmount;
        case CSW_FLASHBANG:    util_TrackNades[id][1] = newAmount;
        case CSW_SMOKEGRENADE: util_TrackNades[id][2] = newAmount;
    }
}

stock util_GetWeaponPrice(weaponId)
{
    switch (weaponId)
    {
        case CSW_P228:         return 600;
        case CSW_GLOCK18:      return 400;
        case CSW_SCOUT:        return 2750;
        case CSW_HEGRENADE:    return 300;
        case CSW_XM1014:       return 3000;
        case CSW_MAC10:        return 1400;
        case CSW_AUG:          return 3500;
        case CSW_SMOKEGRENADE: return 300;
        case CSW_ELITE:        return 800;
        case CSW_FIVESEVEN:    return 750;
        case CSW_UMP45:        return 1700;
        case CSW_SG550:        return 4200;
        case CSW_GALIL:        return 2000;
        case CSW_FAMAS:        return 2250;
        case CSW_USP:          return 500;
        case CSW_AWP:          return 4750;
        case CSW_MP5NAVY:      return 1500;
        case CSW_M249:         return 5750;
        case CSW_M3:           return 1700;
        case CSW_M4A1:         return 3100;
        case CSW_TMP:          return 1250;
        case CSW_G3SG1:        return 5000;
        case CSW_FLASHBANG:    return 200;
        case CSW_DEAGLE:       return 650;
        case CSW_SG552:        return 3500;
        case CSW_AK47:         return 2500;
        case CSW_P90:          return 2350;
    }
    return 0;
}

stock util_GetItemFriendlyName(UtilItemCategory:cat, wpnId, name[], maxlen)
{
    switch (cat)
    {
        case UTIL_CAT_ARMOR_KEVLAR:   copy(name, maxlen, "Kevlar Vest");
        case UTIL_CAT_ARMOR_HELMET:   copy(name, maxlen, "Kevlar + Helmet");
        case UTIL_CAT_ARMOR_UPGRADE:  copy(name, maxlen, "Helmet Upgrade");
        case UTIL_CAT_DEFUSER:        copy(name, maxlen, "Defusal Kit");
        case UTIL_CAT_NVG:            copy(name, maxlen, "Nightvision Goggles");
        case UTIL_CAT_GRENADE:
        {
            switch (wpnId)
            {
                case CSW_HEGRENADE:    copy(name, maxlen, "HE Grenade");
                case CSW_FLASHBANG:    copy(name, maxlen, "Flashbang");
                case CSW_SMOKEGRENADE: copy(name, maxlen, "Smoke Grenade");
                default:               copy(name, maxlen, "Grenade");
            }
        }
        case UTIL_CAT_WEAPON:
        {
            switch (wpnId)
            {
                case CSW_P228:        copy(name, maxlen, "P228");
                case CSW_GLOCK18:     copy(name, maxlen, "Glock-18");
                case CSW_SCOUT:       copy(name, maxlen, "Scout");
                case CSW_XM1014:      copy(name, maxlen, "XM1014");
                case CSW_MAC10:       copy(name, maxlen, "MAC-10");
                case CSW_AUG:         copy(name, maxlen, "AUG");
                case CSW_ELITE:       copy(name, maxlen, "Dual Elites");
                case CSW_FIVESEVEN:   copy(name, maxlen, "Five-Seven");
                case CSW_UMP45:       copy(name, maxlen, "UMP-45");
                case CSW_SG550:       copy(name, maxlen, "SG-550");
                case CSW_GALIL:       copy(name, maxlen, "Galil");
                case CSW_FAMAS:       copy(name, maxlen, "FAMAS");
                case CSW_USP:         copy(name, maxlen, "USP-S");
                case CSW_AWP:         copy(name, maxlen, "AWP");
                case CSW_MP5NAVY:     copy(name, maxlen, "MP5");
                case CSW_M249:        copy(name, maxlen, "M249");
                case CSW_M3:          copy(name, maxlen, "M3 Shotgun");
                case CSW_M4A1:        copy(name, maxlen, "M4A1");
                case CSW_TMP:         copy(name, maxlen, "TMP");
                case CSW_G3SG1:       copy(name, maxlen, "G3SG1");
                case CSW_DEAGLE:      copy(name, maxlen, "Desert Eagle");
                case CSW_SG552:       copy(name, maxlen, "SG-552");
                case CSW_AK47:        copy(name, maxlen, "AK-47");
                case CSW_P90:         copy(name, maxlen, "P90");
                default:              copy(name, maxlen, "Weapon");
            }
        }
        default: copy(name, maxlen, "Item");
    }
}

// -------------------------------------------------------------
// 3. Smoke Dispersion & Registration
// -------------------------------------------------------------
public util_OnGrenadeThink(ent)
{
    if (!pev_valid(ent))
        return HAM_IGNORED;

    new model[32];
    pev(ent, pev_model, model, charsmax(model));

    new Float:dmgtime;
    pev(ent, pev_dmgtime, dmgtime);
    new Float:now = get_gametime();

    if (equal(model, util_MDL_W_SMOKE))
    {
        if (dmgtime > 0.0 && dmgtime <= now)
        {
            if (pev(ent, pev_iuser3) != 1337)
            {
                set_pev(ent, pev_iuser3, 1337);
                new Float:vSmokeOrigin[3];
                pev(ent, pev_origin, vSmokeOrigin);
                util_RegisterActiveSmoke(vSmokeOrigin);
            }
        }
    }

    if (equal(model, util_MDL_W_HE) && get_pcvar_num(pCvar_MasterEnable) && get_pcvar_num(util_pCvar_SmokeDisperse))
    {
        if (dmgtime > 0.0 && dmgtime <= now)
        {
            new Float:vHeOrigin[3];
            pev(ent, pev_origin, vHeOrigin);

            new smokeEnt = 0;
            while ((smokeEnt = engfunc(EngFunc_FindEntityByString, smokeEnt, "classname", "grenade")) > 0)
            {
                if (smokeEnt == ent) continue;

                new smokeModel[32];
                pev(smokeEnt, pev_model, smokeModel, charsmax(smokeModel));

                if (equal(smokeModel, util_MDL_W_SMOKE))
                {
                    new Float:vSmokeOrigin[3];
                    pev(smokeEnt, pev_origin, vSmokeOrigin);

                    if (get_distance_f(vHeOrigin, vSmokeOrigin) <= 260.0)
                    {
                        util_TriggerSmokeDispersion(vSmokeOrigin);
                        break;
                    }
                }
            }
        }
    }

    return HAM_IGNORED;
}

stock util_TriggerSmokeDispersion(Float:vOrigin[3])
{
    new Float:now = get_gametime();
    for (new i = 0; i < util_ActiveSmokeCount; i++)
    {
        if (util_ActiveSmokeExpire[i] > now)
        {
            if (get_distance_f(util_ActiveSmokes[i], vOrigin) <= 260.0)
            {
                util_ActiveSmokeExpire[i] = 0.0;
            }
        }
    }

    emit_sound(0, CHAN_AUTO, util_SND_DISPERSE, 1.0, ATTN_NORM, 0, PITCH_NORM);

    message_begin(MSG_BROADCAST, SVC_TEMPENTITY);
    write_byte(TE_BEAMCYLINDER);
    write_coord(floatround(vOrigin[0]));
    write_coord(floatround(vOrigin[1]));
    write_coord(floatround(vOrigin[2] + 15.0));
    write_coord(floatround(vOrigin[0]));
    write_coord(floatround(vOrigin[1]));
    write_coord(floatround(vOrigin[2] + 280.0));
    write_short(util_SprWave);
    write_byte(0);
    write_byte(0);
    write_byte(10);
    write_byte(40);
    write_byte(0);
    write_byte(230);
    write_byte(230);
    write_byte(230);
    write_byte(200);
    write_byte(0);
    message_end();

    client_print(0, print_center, "★ [CS2] Smoke cleared by HE grenade explosion! ★");
}

// -------------------------------------------------------------
// 4. 3-Way Throw Strength Controller (FM_SetModel)
// -------------------------------------------------------------
public util_OnSetModel_Post(ent, const model[])
{
    if (!pev_valid(ent))
        return FMRES_IGNORED;

    if (!get_pcvar_num(pCvar_MasterEnable) || !get_pcvar_num(util_pCvar_ThrowStrength))
        return FMRES_IGNORED;

    if (!equal(model, util_MDL_W_HE) && !equal(model, util_MDL_W_FLASH) && !equal(model, util_MDL_W_SMOKE))
        return FMRES_IGNORED;

    new classname[32];
    pev(ent, pev_classname, classname, charsmax(classname));
    if (!equal(classname, "grenade"))
        return FMRES_IGNORED;

    new id = pev(ent, pev_owner);
    if (id < 1 || id > 32 || !is_user_connected(id))
        return FMRES_IGNORED;

    new Float:vVel[3];
    pev(ent, pev_velocity, vVel);

    if (util_iThrowMode[id] == UTIL_THROW_SHORT)
    {
        vVel[0] *= 0.35;
        vVel[1] *= 0.35;
        vVel[2] = (vVel[2] * 0.35) + 125.0;
        set_pev(ent, pev_velocity, vVel);
        client_print(id, print_center, "★ [CS2] Short Underhand Lob (35%) ★");
        util_iThrowMode[id] = UTIL_THROW_FULL;
    }
    else if (util_iThrowMode[id] == UTIL_THROW_MEDIUM)
    {
        vVel[0] *= 0.65;
        vVel[1] *= 0.65;
        vVel[2] = (vVel[2] * 0.65) + 75.0;
        set_pev(ent, pev_velocity, vVel);
        client_print(id, print_center, "★ [CS2] Medium Throw (65%) ★");
        util_iThrowMode[id] = UTIL_THROW_FULL;
    }
    else
    {
        util_iThrowMode[id] = UTIL_THROW_FULL;
    }

    return FMRES_IGNORED;
}

public util_Event_CurWeapon(id)
{
    if (!is_user_alive(id))
        return;

    new wpnId = read_data(2);
    if (wpnId != CSW_HEGRENADE && wpnId != CSW_FLASHBANG && wpnId != CSW_SMOKEGRENADE)
    {
        util_iThrowMode[id] = UTIL_THROW_FULL;
    }
}

// -------------------------------------------------------------
// 5. Smoke Bullet Tracers
// -------------------------------------------------------------
stock util_RegisterFirearmHooks()
{
    new const szWeapons[][] = {
        "weapon_p228", "weapon_scout", "weapon_xm1014", "weapon_mac10", "weapon_aug",
        "weapon_elite", "weapon_fiveseven", "weapon_ump45", "weapon_sg550", "weapon_galil",
        "weapon_famas", "weapon_usp", "weapon_glock18", "weapon_awp", "weapon_mp5navy",
        "weapon_m249", "weapon_m3", "weapon_m4a1", "weapon_tmp", "weapon_g3sg1",
        "weapon_deagle", "weapon_sg552", "weapon_ak47", "weapon_p90"
    };

    for (new i = 0; i < sizeof(szWeapons); i++)
    {
        RegisterHam(Ham_Weapon_PrimaryAttack, szWeapons[i], "util_OnFirearmPrimaryAttack_Post", 1);
    }
}

public util_OnFirearmPrimaryAttack_Post(weapon_ent)
{
    if (!get_pcvar_num(pCvar_MasterEnable) || !get_pcvar_num(util_pCvar_SmokeBullets))
        return HAM_IGNORED;

    if (!pev_valid(weapon_ent))
        return HAM_IGNORED;

    new attacker = pev(weapon_ent, pev_owner);
    if (attacker < 1 || attacker > 32 || !is_user_alive(attacker))
        return HAM_IGNORED;

    new Float:now = get_gametime();
    if (now - util_flLastSmokeTracer[attacker] < 0.08)
        return HAM_IGNORED;

    if (util_ActiveSmokeCount <= 0)
        return HAM_IGNORED;

    new Float:vStart[3], Float:vViewOfs[3], Float:vAngles[3], Float:vForward[3], Float:vEnd[3];
    pev(attacker, pev_origin, vStart);
    pev(attacker, pev_view_ofs, vViewOfs);
    xs_vec_add(vStart, vViewOfs, vStart);

    pev(attacker, pev_v_angle, vAngles);
    angle_vector(vAngles, ANGLEVECTOR_FORWARD, vForward);
    xs_vec_mul_scalar(vForward, 8192.0, vForward);
    xs_vec_add(vStart, vForward, vEnd);

    new tr;
    engfunc(EngFunc_TraceLine, vStart, vEnd, DONT_IGNORE_MONSTERS, attacker, tr);
    get_tr2(tr, TR_vecEndPos, vEnd);

    new Float:vClosest[3];
    for (new i = 0; i < util_ActiveSmokeCount; i++)
    {
        if (util_ActiveSmokeExpire[i] > now)
        {
            if (util_RayIntersectsSphere(vStart, vEnd, util_ActiveSmokes[i], 145.0, vClosest))
            {
                util_flLastSmokeTracer[attacker] = now;

                new Float:vP1[3], Float:vP2[3], Float:vDir[3];
                xs_vec_sub(vEnd, vStart, vDir);
                xs_vec_normalize(vDir, vDir);

                xs_vec_mul_scalar(vDir, -70.0, vP1);
                xs_vec_add(vClosest, vP1, vP1);

                xs_vec_mul_scalar(vDir, 70.0, vP2);
                xs_vec_add(vClosest, vP2, vP2);

                message_begin(MSG_BROADCAST, SVC_TEMPENTITY);
                write_byte(TE_BEAMPOINTS);
                write_coord(floatround(vP1[0]));
                write_coord(floatround(vP1[1]));
                write_coord(floatround(vP1[2]));
                write_coord(floatround(vP2[0]));
                write_coord(floatround(vP2[1]));
                write_coord(floatround(vP2[2]));
                write_short(util_SprTracer);
                write_byte(0);
                write_byte(0);
                write_byte(8);
                write_byte(6);
                write_byte(0);
                write_byte(230);
                write_byte(235);
                write_byte(245);
                write_byte(210);
                write_byte(0);
                message_end();

                message_begin(MSG_BROADCAST, SVC_TEMPENTITY);
                write_byte(TE_SMOKE);
                write_coord(floatround(vClosest[0]));
                write_coord(floatround(vClosest[1]));
                write_coord(floatround(vClosest[2]));
                write_short(util_SprPuff);
                write_byte(12);
                write_byte(15);
                message_end();

                break;
            }
        }
    }

    return HAM_IGNORED;
}

stock bool:util_RayIntersectsSphere(const Float:vRayStart[3], const Float:vRayEnd[3], const Float:vSphereCenter[3], Float:flRadius, Float:vClosestPoint[3])
{
    new Float:vRayDir[3], Float:vToCenter[3];
    xs_vec_sub(vRayEnd, vRayStart, vRayDir);
    new Float:flRayLen = xs_vec_len(vRayDir);
    if (flRayLen <= 0.001) return false;

    xs_vec_normalize(vRayDir, vRayDir);
    xs_vec_sub(vSphereCenter, vRayStart, vToCenter);

    new Float:t = xs_vec_dot(vToCenter, vRayDir);
    if (t < 0.0) t = 0.0;
    else if (t > flRayLen) t = flRayLen;

    xs_vec_mul_scalar(vRayDir, t, vClosestPoint);
    xs_vec_add(vRayStart, vClosestPoint, vClosestPoint);

    new Float:flDist = get_distance_f(vSphereCenter, vClosestPoint);
    return (flDist <= flRadius);
}

stock util_RegisterActiveSmoke(const Float:vOrigin[3])
{
    new Float:flNow = get_gametime();
    for (new i = 0; i < util_ActiveSmokeCount; i++)
    {
        if (util_ActiveSmokeExpire[i] > flNow)
        {
            if (get_distance_f(util_ActiveSmokes[i], vOrigin) < 60.0)
                return;
        }
    }

    new slot = -1;
    for (new i = 0; i < UTIL_MAX_ACTIVE_SMOKES; i++)
    {
        if (util_ActiveSmokeExpire[i] <= flNow)
        {
            slot = i;
            break;
        }
    }

    if (slot == -1)
    {
        if (util_ActiveSmokeCount < UTIL_MAX_ACTIVE_SMOKES)
        {
            slot = util_ActiveSmokeCount++;
        }
        else
        {
            slot = 0;
        }
    }
    else if (slot >= util_ActiveSmokeCount)
    {
        util_ActiveSmokeCount = slot + 1;
    }

    util_ActiveSmokes[slot][0] = vOrigin[0];
    util_ActiveSmokes[slot][1] = vOrigin[1];
    util_ActiveSmokes[slot][2] = vOrigin[2];
    util_ActiveSmokeExpire[slot] = flNow + 18.0;
}
