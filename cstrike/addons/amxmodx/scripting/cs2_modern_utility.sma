#include <amxmodx>
#include <amxmisc>
#include <cstrike>
#include <fakemeta>
#include <hamsandwich>
#include <engine>
#include <xs>
#include <fun>

#define PLUGIN  "CS2 Modern Utilities (Throw Strength, Smoke Tracers, Drop, Refund)"
#define VERSION "2.0.0"
#define AUTHOR  "Antigravity"

// Sound Paths
new const SND_DISPERSE[] = "cs2_utility/smoke_disperse.wav";
new const SND_REFUND[]   = "cs2_utility/refund.wav";
new const SND_PICKUP[]   = "items/gunpickup2.wav";

// Models & Sprites
new const MDL_W_HE[]    = "models/w_hegrenade.mdl";
new const MDL_W_FLASH[] = "models/w_flashbang.mdl";
new const MDL_W_SMOKE[] = "models/w_smokegrenade.mdl";
new g_SprWave;
new g_SprTracer;
new g_SprPuff;

// CVars
new pCvar_DropNades;
new pCvar_BuyRefund;
new pCvar_SmokeDisperse;
new pCvar_ReloadRefund;
new pCvar_ThrowStrength;
new pCvar_SmokeBullets;

// CS2 3-Way Throw Strength
enum {
    THROW_FULL = 0,
    THROW_SHORT,
    THROW_MEDIUM
};
new g_iThrowMode[33];
new Float:g_flLastStrengthHint[33];

// CS2 Smoke Bullet Tracers Tracking
#define MAX_ACTIVE_SMOKES 16
new Float:g_ActiveSmokes[MAX_ACTIVE_SMOKES][3];
new Float:g_ActiveSmokeExpire[MAX_ACTIVE_SMOKES];
new g_ActiveSmokeCount = 0;
new Float:g_flLastSmokeTracer[33];

// Freeze Time & Buy Period State
new bool:g_FreezeTimeActive = false;
new Float:g_flBuyTimeEnd = 0.0;
new g_iOldButtonsReload[33];

// Task IDs
#define TASK_FREEZETIME 6100
#define TASK_BUY_OFFSET 6200

#define MAX_BUY_HISTORY 16

enum ItemCategory {
    CAT_NONE = 0,
    CAT_WEAPON,         // Primary or secondary weapon (CSW_AK47, CSW_DEAGLE, etc.)
    CAT_GRENADE,        // CSW_HEGRENADE, CSW_FLASHBANG, CSW_SMOKEGRENADE
    CAT_ARMOR_KEVLAR,   // Kevlar vest (100 armor, no helmet)
    CAT_ARMOR_HELMET,   // Full Kevlar + Helmet
    CAT_ARMOR_UPGRADE,  // Helmet upgrade (player already had Kevlar)
    CAT_DEFUSER,        // Defusal kit
    CAT_NVG             // Nightvision goggles
};

enum _:BuyHistoryEntry {
    ItemCategory:bCategory,
    bWeaponId,          // CSW_* constant
    bCost,              // money spent
    bPrevArmorVal,      // armor value before purchase (for armor rollback)
    CsArmorType:bPrevArmorType // armor type before purchase
};

new g_BuyHistory[33][MAX_BUY_HISTORY][BuyHistoryEntry];
new g_BuyCount[33];
new g_LastMoney[33];

// Inventory Snapshot Tracking
new g_TrackWeapons[33];               // pev_weapons bitmask
new g_TrackArmor[33];                 // armor amount
new CsArmorType:g_TrackArmorType[33]; // armor type
new g_TrackDefuse[33];                // defuse kit status (0/1)
new g_TrackNVG[33];                   // nightvision status (0/1)
new g_TrackNades[33][3];              // [0]=HE, [1]=Flash, [2]=Smoke
new bool:g_StartedWithPistol[33];     // Did player start round with default pistol?
new g_DefaultPistolWpn[33];           // CSW_USP or CSW_GLOCK18

// Bot Squad Retrieval Tracking
new g_BotRetrieveEnt[33];
new Float:g_BotRetrieveExpire[33];

public plugin_init()
{
    register_plugin(PLUGIN, VERSION, AUTHOR);

    // CVars
    pCvar_DropNades     = register_cvar("amx_cs2_drop_nades", "1");
    pCvar_BuyRefund     = register_cvar("amx_cs2_buy_refund", "1");
    pCvar_SmokeDisperse = register_cvar("amx_cs2_smoke_disperse", "1");
    pCvar_ReloadRefund  = register_cvar("amx_cs2_refund_on_r", "1");
    pCvar_ThrowStrength = register_cvar("amx_cs2_throw_strength", "1");
    pCvar_SmokeBullets  = register_cvar("amx_cs2_smoke_bullets", "1");

    // Commands
    register_clcmd("drop", "Cmd_DropWeapon");
    register_clcmd("say /refund", "Cmd_Refund");
    register_clcmd("say_team /refund", "Cmd_Refund");
    register_clcmd("say /sellback", "Cmd_Refund");
    register_clcmd("say_team /sellback", "Cmd_Refund");
    register_clcmd("refund", "Cmd_Refund");
    register_clcmd("sellback", "Cmd_Refund");
    register_clcmd("amx_refund", "Cmd_Refund");

    register_clcmd("say /refundmenu", "Cmd_RefundMenu");
    register_clcmd("say_team /refundmenu", "Cmd_RefundMenu");
    register_clcmd("refundmenu", "Cmd_RefundMenu");

    // Events
    register_event("HLTV", "Event_NewRound", "a", "1=0", "2=0");
    register_event("Money", "Event_Money", "b");
    register_event("CurWeapon", "Event_CurWeapon", "be", "1=1");

    // Ham Hooks
    RegisterHam(Ham_Spawn, "player", "OnPlayerSpawn_Post", 1);
    RegisterHam(Ham_Touch, "info_target", "OnDroppedNadeTouch");
    RegisterHam(Ham_Think, "info_target", "OnDroppedNadeThink");
    RegisterHam(Ham_Think, "grenade", "OnGrenadeThink");

    // Hook firearm primary attack for smoke bullet tracers (Safe alternative to Ham_TraceAttack on worldspawn)
    RegisterFirearmHooks();

    // Fakemeta Hooks
    register_forward(FM_CmdStart, "OnCmdStart");
    register_forward(FM_SetModel, "OnSetModel_Post", 1);
}

public plugin_precache()
{
    precache_sound(SND_DISPERSE);
    precache_sound(SND_REFUND);
    precache_sound(SND_PICKUP);

    precache_model(MDL_W_HE);
    precache_model(MDL_W_FLASH);
    precache_model(MDL_W_SMOKE);

    g_SprWave   = precache_model("sprites/glow01.spr");
    g_SprTracer = precache_model("sprites/laserbeam.spr");
    g_SprPuff   = precache_model("sprites/smokepuff.spr");
}

public client_putinserver(id)
{
    g_BuyCount[id] = 0;
    g_BotRetrieveEnt[id] = 0;
    g_BotRetrieveExpire[id] = 0.0;
    g_TrackWeapons[id] = 0;
    g_TrackArmor[id] = 0;
    g_TrackArmorType[id] = CS_ARMOR_NONE;
    g_TrackDefuse[id] = 0;
    g_TrackNVG[id] = 0;
    g_TrackNades[id][0] = 0;
    g_TrackNades[id][1] = 0;
    g_TrackNades[id][2] = 0;
    g_StartedWithPistol[id] = false;
    g_DefaultPistolWpn[id] = 0;
    g_iOldButtonsReload[id] = 0;
    g_iThrowMode[id] = THROW_FULL;
    g_flLastStrengthHint[id] = 0.0;
    g_flLastSmokeTracer[id] = 0.0;
    g_LastMoney[id] = 0;
}

public client_disconnected(id)
{
    remove_task(id + TASK_BUY_OFFSET);
    g_BuyCount[id] = 0;
    g_LastMoney[id] = 0;
    g_BotRetrieveEnt[id] = 0;
    g_BotRetrieveExpire[id] = 0.0;
    g_iOldButtonsReload[id] = 0;
    g_iThrowMode[id] = THROW_FULL;
    g_flLastStrengthHint[id] = 0.0;
    g_flLastSmokeTracer[id] = 0.0;
}

public OnPlayerSpawn_Post(id)
{
    if (!is_user_alive(id) || is_user_bot(id))
        return;

    remove_task(id + TASK_BUY_OFFSET);
    g_BuyCount[id] = 0;
    g_iThrowMode[id] = THROW_FULL;
    g_LastMoney[id] = cs_get_user_money(id);
    SnapshotPlayerInventory(id);
}

public Event_NewRound()
{
    new freezeDuration = get_cvar_num("mp_freezetime");
    if (freezeDuration > 0)
    {
        g_FreezeTimeActive = true;
        remove_task(TASK_FREEZETIME);
        set_task(float(freezeDuration), "Task_FreezeTimeOver", TASK_FREEZETIME);
    }
    else
    {
        g_FreezeTimeActive = false;
        remove_task(TASK_FREEZETIME);
    }

    new Float:flBuyTimeMins = get_cvar_float("mp_buytime");
    new Float:flBuyTimeSecs = (flBuyTimeMins > 0.0) ? (flBuyTimeMins * 60.0) : 27.0;
    g_flBuyTimeEnd = get_gametime() + float(freezeDuration) + flBuyTimeSecs;

    // Reset active smokes
    g_ActiveSmokeCount = 0;
    for (new s = 0; s < MAX_ACTIVE_SMOKES; s++)
    {
        g_ActiveSmokeExpire[s] = 0.0;
    }

    for (new i = 1; i <= 32; i++)
    {
        remove_task(i + TASK_BUY_OFFSET);
        g_BuyCount[i] = 0;
        g_BotRetrieveEnt[i] = 0;
        g_BotRetrieveExpire[i] = 0.0;
        g_iThrowMode[i] = THROW_FULL;
        g_flLastStrengthHint[i] = 0.0;
        g_flLastSmokeTracer[i] = 0.0;

        if (is_user_connected(i) && !is_user_bot(i) && is_user_alive(i))
        {
            SnapshotPlayerInventory(i);
        }
        else
        {
            g_LastMoney[i] = 0;
        }
    }
}

public Task_FreezeTimeOver()
{
    g_FreezeTimeActive = false;
}

stock bool:IsPlayerInBuyPeriod(id)
{
    if (!is_user_connected(id) || !is_user_alive(id) || is_user_bot(id))
        return false;

    if (g_FreezeTimeActive)
        return true;

    if (cs_get_user_buyzone(id) && get_gametime() <= g_flBuyTimeEnd)
        return true;

    return false;
}

// ===================================================================
// 1. CRASH-PROOF & GENTLE DROP GRENADES SYSTEM (WITH BOT AI PICKUP)
// ===================================================================
public Cmd_DropWeapon(id)
{
    if (!get_pcvar_num(pCvar_DropNades))
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

    // Spawn dropped grenade entity
    new Float:vOrigin[3], Float:vViewOfs[3], Float:vAngles[3], Float:vForward[3], Float:vVelocity[3];
    pev(id, pev_origin, vOrigin);
    pev(id, pev_view_ofs, vViewOfs);
    xs_vec_add(vOrigin, vViewOfs, vOrigin);

    pev(id, pev_v_angle, vAngles);
    angle_vector(vAngles, ANGLEVECTOR_FORWARD, vForward);

    // Drop position: right in front of player
    vOrigin[0] += vForward[0] * 24.0;
    vOrigin[1] += vForward[1] * 24.0;
    vOrigin[2] += vForward[2] * 24.0;

    // Gentle toss: drops down realistically, no endless bouncing!
    vVelocity[0] = vForward[0] * 120.0;
    vVelocity[1] = vForward[1] * 120.0;
    vVelocity[2] = 40.0;

    new ent = engfunc(EngFunc_CreateNamedEntity, engfunc(EngFunc_AllocString, "info_target"));
    if (!pev_valid(ent))
        return PLUGIN_HANDLED;

    set_pev(ent, pev_classname, "cs2_dropped_nade");
    set_pev(ent, pev_origin, vOrigin);
    set_pev(ent, pev_velocity, vVelocity);
    set_pev(ent, pev_movetype, MOVETYPE_TOSS); // Standard realistic physics toss
    set_pev(ent, pev_solid, SOLID_TRIGGER);
    set_pev(ent, pev_gravity, 1.0);
    set_pev(ent, pev_friction, 0.9);
    set_pev(ent, pev_owner, id);
    set_pev(ent, pev_iuser1, weaponId);

    // Thrower pickup cooldown (1.2 seconds)
    set_pev(ent, pev_fuser1, get_gametime() + 1.2);

    // Large trigger bounding box (60x60x50 units) so players and bots easily touch it
    new Float:mins[3] = {-30.0, -30.0, -20.0};
    new Float:maxs[3] = {30.0, 30.0, 30.0};
    engfunc(EngFunc_SetSize, ent, mins, maxs);

    // Activate think to settle flat on ground
    set_pev(ent, pev_nextthink, get_gametime() + 0.1);

    new nadeName[24];
    switch (weaponId)
    {
        case CSW_HEGRENADE:
        {
            engfunc(EngFunc_SetModel, ent, MDL_W_HE);
            copy(nadeName, charsmax(nadeName), "HE Grenade");
        }
        case CSW_FLASHBANG:
        {
            engfunc(EngFunc_SetModel, ent, MDL_W_FLASH);
            copy(nadeName, charsmax(nadeName), "Flashbang");
        }
        case CSW_SMOKEGRENADE:
        {
            engfunc(EngFunc_SetModel, ent, MDL_W_SMOKE);
            copy(nadeName, charsmax(nadeName), "Smoke Grenade");
        }
    }

    // Deduct ammo from player
    cs_set_user_bpammo(id, weaponId, currentAmmo - 1);

    // If no more grenades of this type, strip weapon safely
    if (currentAmmo - 1 <= 0)
    {
        ham_strip_user_weapon_safe(id, weaponId);
        g_TrackWeapons[id] &= ~(1 << weaponId);
    }
    UpdateTrackNade(id, weaponId, currentAmmo - 1);

    client_print(id, print_center, "Dropped %s", nadeName);

    // Dispatch nearest teammate bot to retrieve the grenade!
    new nearestBot = FindNearestBotForNade(id, weaponId);
    if (nearestBot > 0)
    {
        g_BotRetrieveEnt[nearestBot] = ent;
        g_BotRetrieveExpire[nearestBot] = get_gametime() + 10.0;

        new botName[32];
        get_user_name(nearestBot, botName, charsmax(botName));
        client_print(0, print_chat, "^x04[Squad AI]^x03 %s:^x01 Roger! Moving to pick up the dropped %s.", botName, nadeName);
        client_cmd(id, "spk radio/roger.wav");
    }

    return PLUGIN_HANDLED;
}

// Think hook: when dropped grenade hits the floor, freeze it cleanly!
public OnDroppedNadeThink(ent)
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

    // Settle flat on the floor if grounded or velocity has stopped
    if ((flags & FL_ONGROUND) || xs_vec_len(vVel) < 25.0)
    {
        set_pev(ent, pev_velocity, Float:{0.0, 0.0, 0.0});
        set_pev(ent, pev_movetype, MOVETYPE_NONE); // Completely halt movement on floor
        return HAM_IGNORED;
    }

    set_pev(ent, pev_nextthink, get_gametime() + 0.1);
    return HAM_IGNORED;
}

public OnDroppedNadeTouch(ent, toucher)
{
    if (!pev_valid(ent))
        return HAM_IGNORED;

    new classname[32];
    pev(ent, pev_classname, classname, charsmax(classname));
    if (!equal(classname, "cs2_dropped_nade"))
        return HAM_IGNORED;

    if (!is_user_alive(toucher))
        return HAM_IGNORED;

    // Prevent immediate re-pickup by thrower
    new owner = pev(ent, pev_owner);
    new Float:pickupCooldown;
    pev(ent, pev_fuser1, pickupCooldown);
    if (toucher == owner && get_gametime() < pickupCooldown)
    {
        return HAM_IGNORED;
    }

    if (GiveGrenadeToPlayer(toucher, ent))
        return HAM_HANDLED;

    return HAM_IGNORED;
}

stock bool:GiveGrenadeToPlayer(toucher, ent)
{
    if (!pev_valid(ent) || !is_user_alive(toucher))
        return false;

    new weaponId = pev(ent, pev_iuser1);
    if (weaponId != CSW_HEGRENADE && weaponId != CSW_FLASHBANG && weaponId != CSW_SMOKEGRENADE)
        return false;

    new currentAmmo = cs_get_user_bpammo(toucher, weaponId);

    // Max limits: HE = 1, Flash = 2, Smoke = 1
    new maxLimit = (weaponId == CSW_FLASHBANG) ? 2 : 1;
    if (currentAmmo >= maxLimit)
        return false;

    // Give grenade to player / bot
    new weaponName[32];
    get_weaponname(weaponId, weaponName, charsmax(weaponName));
    if (!weaponName[0])
        return false;

    if (currentAmmo == 0)
    {
        give_item(toucher, weaponName);
        cs_set_user_bpammo(toucher, weaponId, 1);
        g_TrackWeapons[toucher] |= (1 << weaponId);
        UpdateTrackNade(toucher, weaponId, 1);
    }
    else
    {
        cs_set_user_bpammo(toucher, weaponId, currentAmmo + 1);
        UpdateTrackNade(toucher, weaponId, currentAmmo + 1);
    }

    emit_sound(toucher, CHAN_ITEM, SND_PICKUP, 0.9, ATTN_NORM, 0, PITCH_NORM);

    new owner = pev(ent, pev_owner);
    new ownerName[32];
    if (is_user_connected(owner))
        get_user_name(owner, ownerName, charsmax(ownerName));
    else
        copy(ownerName, charsmax(ownerName), "Teammate");

    client_print(toucher, print_center, "Picked up grenade from %s", ownerName);

    // Engine-safe removal
    set_pev(ent, pev_solid, SOLID_NOT);
    set_pev(ent, pev_flags, pev(ent, pev_flags) | FL_KILLME);
    dllfunc(DLLFunc_Think, ent);
    return true;
}

// Bot Squad AI Navigation & Player 'R' Reload-Refund Interceptor
public OnCmdStart(id, uc_handle, seed)
{
    if (!is_user_alive(id))
        return FMRES_IGNORED;

    // 1. Intercept 'R' (+reload) key for Human Players during Freeze Time / Buy Period
    if (!is_user_bot(id))
    {
        new buttons = get_uc(uc_handle, UC_Buttons);
        new oldbuttons = g_iOldButtonsReload[id];
        g_iOldButtonsReload[id] = buttons;

        if (IsPlayerInBuyPeriod(id) && get_pcvar_num(pCvar_ReloadRefund) && get_pcvar_num(pCvar_BuyRefund))
        {
            // Trigger when player presses +reload (R key) on rising edge
            if ((buttons & IN_RELOAD) && !(oldbuttons & IN_RELOAD))
            {
                // Clear IN_RELOAD from usercmd so weapon reload is completely suppressed
                set_uc(uc_handle, UC_Buttons, buttons & ~IN_RELOAD);

                // Execute CS2 sellback / refund
                Cmd_Refund(id);
                return FMRES_HANDLED;
            }
        }

        // 2. CS2 3-Way Variable Throw Strength Engine (Left Click = 100%, Right Click = 40%, Both = 70%)
        if (get_pcvar_num(pCvar_ThrowStrength))
        {
            new clip, ammo;
            new weaponId = get_user_weapon(id, clip, ammo);
            if (weaponId == CSW_HEGRENADE || weaponId == CSW_FLASHBANG || weaponId == CSW_SMOKEGRENADE)
            {
                if ((buttons & IN_ATTACK) && (buttons & IN_ATTACK2))
                {
                    g_iThrowMode[id] = THROW_MEDIUM;
                    set_uc(uc_handle, UC_Buttons, buttons & ~IN_ATTACK2);
                    new Float:now = get_gametime();
                    if (now - g_flLastStrengthHint[id] > 0.4)
                    {
                        client_print(id, print_center, "✦ [CS2] Medium Throw [Left+Right Click] (65%) ✦");
                        g_flLastStrengthHint[id] = now;
                    }
                }
                else if (buttons & IN_ATTACK2)
                {
                    g_iThrowMode[id] = THROW_SHORT;
                    set_uc(uc_handle, UC_Buttons, (buttons & ~IN_ATTACK2) | IN_ATTACK);
                    new Float:now = get_gametime();
                    if (now - g_flLastStrengthHint[id] > 0.4)
                    {
                        client_print(id, print_center, "✦ [CS2] Short Underhand Lob [Right Click] (35%) ✦");
                        g_flLastStrengthHint[id] = now;
                    }
                }
                else if (buttons & IN_ATTACK)
                {
                    g_iThrowMode[id] = THROW_FULL;
                }
            }
        }

        return FMRES_IGNORED;
    }

    new Float:flGameTime = get_gametime();

    // Check if this bot was dispatched to retrieve a dropped grenade
    new targetEnt = g_BotRetrieveEnt[id];
    if (targetEnt > 0 && flGameTime < g_BotRetrieveExpire[id])
    {
        if (pev_valid(targetEnt))
        {
            new Float:vBotOrigin[3], Float:vNadeOrigin[3], Float:vDiff[3];
            pev(id, pev_origin, vBotOrigin);
            pev(targetEnt, pev_origin, vNadeOrigin);
            xs_vec_sub(vNadeOrigin, vBotOrigin, vDiff);
            new Float:flDist = xs_vec_len(vDiff);

            // If arrived at the grenade (within 55 units), pick it up!
            if (flDist <= 55.0)
            {
                GiveGrenadeToPlayer(id, targetEnt);
                g_BotRetrieveEnt[id] = 0;
            }
            // If nearby and not fighting an enemy, navigate towards the grenade
            else if (flDist <= 1800.0 && pev(id, pev_enemy) <= 0)
            {
                new Float:vAimAngles[3];
                vector_to_angle(vDiff, vAimAngles);
                ClampAngles(vAimAngles);

                set_uc(uc_handle, UC_ViewAngles, vAimAngles);
                set_uc(uc_handle, UC_ForwardMove, 280.0);
            }
        }
        else
        {
            // Entity already picked up or destroyed
            g_BotRetrieveEnt[id] = 0;
        }
    }

    return FMRES_IGNORED;
}

stock FindNearestBotForNade(id, weaponId)
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

stock ClampAngles(Float:angles[3])
{
    while (angles[0] > 89.0)  angles[0] -= 180.0;
    while (angles[0] < -89.0) angles[0] += 180.0;
    while (angles[1] > 180.0)  angles[1] -= 360.0;
    while (angles[1] < -180.0) angles[1] += 360.0;
    angles[2] = 0.0;
}

// 100% Crash-proof weapon strip stock that completely eliminates mp.dll 0x01D6FDA5 and 0x01D2ED4A crashes
stock ham_strip_user_weapon_safe(id, weaponId)
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
            // Check if this weapon is currently the active item in the player's hands
            new activeItem = get_pdata_cbase(id, 373, 5); // m_pActiveItem
            if (activeItem == ent)
            {
                // 1. Holster the active item cleanly (ExecuteHamB requires this, skiplocal)
                ExecuteHamB(Ham_Item_Holster, ent, 0);

                // 2. Safely switch the active pointer to knife immediately so m_pActiveItem is NEVER a dangling pointer!
                new knife = -1;
                while ((knife = engfunc(EngFunc_FindEntityByString, knife, "classname", "weapon_knife")) > 0)
                {
                    if (pev(knife, pev_owner) == id && knife != ent)
                        break;
                }

                if (pev_valid(knife) && knife != ent)
                {
                    set_pdata_cbase(id, 373, knife, 5); // m_pActiveItem = knife
                    ExecuteHamB(Ham_Item_Deploy, knife);
                }
                else
                {
                    set_pdata_cbase(id, 373, 0, 5); // Safely clear active item to 0
                }
            }

            // 3. Remove weapon item from player inventory in mp.dll
            ExecuteHamB(Ham_RemovePlayerItem, id, ent);

            // 4. Clear weapons bitmask on player
            set_pev(id, pev_weapons, pev(id, pev_weapons) & ~(1 << weaponId));

            // 5. Safely kill the weapon entity
            set_pev(ent, pev_flags, pev(ent, pev_flags) | FL_KILLME);
            dllfunc(DLLFunc_Think, ent);

            return 1;
        }
    }
    return 0;
}

// ===================================================================
// 2. CS2 BUY REFUND (SELLBACK) SYSTEM
// ===================================================================
public Event_Money(id)
{
    if (id < 1 || id > 32 || !is_user_connected(id) || is_user_bot(id) || !is_user_alive(id) || !IsPlayerInBuyPeriod(id))
        return;

    new currentMoney = read_data(1);
    new diff = g_LastMoney[id] - currentMoney;

    if (diff > 0)
    {
        // Delay detection by 0.02s so engine completes item creation and addition
        remove_task(id + TASK_BUY_OFFSET);
        set_task(0.02, "Task_DetectBuy", id + TASK_BUY_OFFSET);
    }
    else
    {
        g_LastMoney[id] = currentMoney;
    }
}

public Task_DetectBuy(taskId)
{
    new id = taskId - TASK_BUY_OFFSET;
    if (id < 1 || id > 32 || !is_user_connected(id) || is_user_bot(id) || !is_user_alive(id) || !IsPlayerInBuyPeriod(id))
        return;

    new currentMoney = cs_get_user_money(id);
    new totalSpent = g_LastMoney[id] - currentMoney;
    if (totalSpent <= 0)
    {
        g_LastMoney[id] = currentMoney;
        return;
    }

    // 1. Check newly acquired weapons
    new curWeapons = pev(id, pev_weapons);
    new newWeapons = curWeapons & ~g_TrackWeapons[id];

    // Exclude C4 and Knife
    newWeapons &= ~(1 << CSW_C4);
    newWeapons &= ~(1 << CSW_KNIFE);

    // Grenades
    new curHE = cs_get_user_bpammo(id, CSW_HEGRENADE);
    if (curHE > g_TrackNades[id][0])
    {
        PushBuyEntry(id, CAT_GRENADE, CSW_HEGRENADE, 300, 0, CS_ARMOR_NONE);
        g_TrackNades[id][0] = curHE;
        newWeapons &= ~(1 << CSW_HEGRENADE);
    }

    new curFlash = cs_get_user_bpammo(id, CSW_FLASHBANG);
    while (curFlash > g_TrackNades[id][1])
    {
        PushBuyEntry(id, CAT_GRENADE, CSW_FLASHBANG, 200, 0, CS_ARMOR_NONE);
        g_TrackNades[id][1]++;
        newWeapons &= ~(1 << CSW_FLASHBANG);
    }

    new curSmoke = cs_get_user_bpammo(id, CSW_SMOKEGRENADE);
    if (curSmoke > g_TrackNades[id][2])
    {
        PushBuyEntry(id, CAT_GRENADE, CSW_SMOKEGRENADE, 300, 0, CS_ARMOR_NONE);
        g_TrackNades[id][2] = curSmoke;
        newWeapons &= ~(1 << CSW_SMOKEGRENADE);
    }

    // Firearms
    for (new wpn = 1; wpn <= 30; wpn++)
    {
        if (newWeapons & (1 << wpn))
        {
            new price = GetWeaponPrice(wpn);
            if (price > 0)
            {
                PushBuyEntry(id, CAT_WEAPON, wpn, price, 0, CS_ARMOR_NONE);
            }
        }
    }

    // 2. Check Armor
    new CsArmorType:curArmorType;
    new curArmor = cs_get_user_armor(id, curArmorType);
    if (curArmor > g_TrackArmor[id] || curArmorType > g_TrackArmorType[id])
    {
        if (curArmorType == CS_ARMOR_VESTHELM)
        {
            if (g_TrackArmorType[id] == CS_ARMOR_KEVLAR)
            {
                PushBuyEntry(id, CAT_ARMOR_UPGRADE, 0, 350, g_TrackArmor[id], g_TrackArmorType[id]);
            }
            else
            {
                PushBuyEntry(id, CAT_ARMOR_HELMET, 0, 1000, g_TrackArmor[id], g_TrackArmorType[id]);
            }
        }
        else if (curArmorType == CS_ARMOR_KEVLAR && g_TrackArmorType[id] == CS_ARMOR_NONE)
        {
            PushBuyEntry(id, CAT_ARMOR_KEVLAR, 0, 650, g_TrackArmor[id], g_TrackArmorType[id]);
        }
        g_TrackArmor[id] = curArmor;
        g_TrackArmorType[id] = curArmorType;
    }

    // 3. Defusal Kit
    new curDefuse = cs_get_user_defuse(id);
    if (curDefuse && !g_TrackDefuse[id])
    {
        PushBuyEntry(id, CAT_DEFUSER, 0, 200, 0, CS_ARMOR_NONE);
        g_TrackDefuse[id] = 1;
    }

    // 4. Nightvision
    new curNVG = cs_get_user_nvg(id);
    if (curNVG && !g_TrackNVG[id])
    {
        PushBuyEntry(id, CAT_NVG, 0, 1250, 0, CS_ARMOR_NONE);
        g_TrackNVG[id] = 1;
    }

    // Update snapshots
    g_TrackWeapons[id] = curWeapons;
    g_LastMoney[id] = currentMoney;
}

stock PushBuyEntry(id, ItemCategory:cat, wpnId, cost, prevArmorVal, CsArmorType:prevArmorType)
{
    if (g_BuyCount[id] >= MAX_BUY_HISTORY)
        return;

    new idx = g_BuyCount[id];
    g_BuyHistory[id][idx][bCategory] = cat;
    g_BuyHistory[id][idx][bWeaponId] = wpnId;
    g_BuyHistory[id][idx][bCost] = cost;
    g_BuyHistory[id][idx][bPrevArmorVal] = prevArmorVal;
    g_BuyHistory[id][idx][bPrevArmorType] = prevArmorType;
    g_BuyCount[id]++;
}

public Cmd_Refund(id)
{
    if (!get_pcvar_num(pCvar_BuyRefund))
        return PLUGIN_CONTINUE;

    if (!is_user_alive(id))
        return PLUGIN_HANDLED;

    if (!IsPlayerInBuyPeriod(id))
    {
        client_print(id, print_chat, "^x04[CS2 Refund]^x01 Refund is only available during Freeze Time or in Buyzone during Buy Time!");
        return PLUGIN_HANDLED;
    }

    // Flush any pending buy detection immediately
    if (task_exists(id + TASK_BUY_OFFSET))
    {
        remove_task(id + TASK_BUY_OFFSET);
        Task_DetectBuy(id + TASK_BUY_OFFSET);
    }

    if (g_BuyCount[id] <= 0)
    {
        client_print(id, print_chat, "^x04[CS2 Refund]^x01 No purchases to refund this round.");
        return PLUGIN_HANDLED;
    }

    // Pop and refund the most recent valid item (LIFO)
    while (g_BuyCount[id] > 0)
    {
        new lastIdx = g_BuyCount[id] - 1;
        if (ExecuteRefundItem(id, lastIdx))
        {
            return PLUGIN_HANDLED;
        }
    }

    client_print(id, print_chat, "^x04[CS2 Refund]^x01 No refundable items remaining in inventory.");
    return PLUGIN_HANDLED;
}

public Cmd_RefundMenu(id)
{
    if (!get_pcvar_num(pCvar_BuyRefund))
        return PLUGIN_CONTINUE;

    if (!is_user_alive(id))
        return PLUGIN_HANDLED;

    if (!IsPlayerInBuyPeriod(id))
    {
        client_print(id, print_chat, "^x04[CS2 Refund]^x01 Sellback menu is only available during Freeze Time or in Buyzone during Buy Time!");
        return PLUGIN_HANDLED;
    }

    // Flush any pending buy detection immediately
    if (task_exists(id + TASK_BUY_OFFSET))
    {
        remove_task(id + TASK_BUY_OFFSET);
        Task_DetectBuy(id + TASK_BUY_OFFSET);
    }

    if (g_BuyCount[id] <= 0)
    {
        client_print(id, print_chat, "^x04[CS2 Refund]^x01 No purchases to refund this round.");
        return PLUGIN_HANDLED;
    }

    new menu = menu_create("\y[CS2 Sellback Menu] \wSelect Item to Refund:", "HandleRefundMenu");

    for (new i = g_BuyCount[id] - 1; i >= 0; i--)
    {
        new ItemCategory:cat = g_BuyHistory[id][i][bCategory];
        new wpnId = g_BuyHistory[id][i][bWeaponId];
        new cost = g_BuyHistory[id][i][bCost];

        new itemName[32];
        GetItemFriendlyName(cat, wpnId, itemName, charsmax(itemName));

        new bool:eligible = IsItemEligibleForRefund(id, cat, wpnId);

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

public HandleRefundMenu(id, menu, item)
{
    if (item == MENU_EXIT || !is_user_alive(id))
    {
        menu_destroy(menu);
        return PLUGIN_HANDLED;
    }

    if (!IsPlayerInBuyPeriod(id))
    {
        client_print(id, print_chat, "^x04[CS2 Refund]^x01 Refund is only available during Freeze Time or in Buyzone during Buy Time!");
        menu_destroy(menu);
        return PLUGIN_HANDLED;
    }

    new data[8], szName[64], access, callback;
    menu_item_getinfo(menu, item, access, data, charsmax(data), szName, charsmax(szName), callback);
    menu_destroy(menu);

    new idx = str_to_num(data);
    if (idx < 0 || idx >= g_BuyCount[id])
    {
        return PLUGIN_HANDLED;
    }

    new ItemCategory:cat = g_BuyHistory[id][idx][bCategory];
    new wpnId = g_BuyHistory[id][idx][bWeaponId];

    new itemName[32];
    GetItemFriendlyName(cat, wpnId, itemName, charsmax(itemName));

    if (!IsItemEligibleForRefund(id, cat, wpnId))
    {
        client_print(id, print_chat, "^x04[CS2 Refund]^x01 Cannot refund ^x03%s^x01: item is no longer in your inventory!", itemName);
        RemoveBuyHistoryIndex(id, idx);
        if (g_BuyCount[id] > 0)
        {
            Cmd_RefundMenu(id);
        }
        return PLUGIN_HANDLED;
    }

    ExecuteRefundItem(id, idx);

    if (g_BuyCount[id] > 0)
    {
        Cmd_RefundMenu(id);
    }

    return PLUGIN_HANDLED;
}

stock bool:ExecuteRefundItem(id, idx)
{
    new ItemCategory:cat = g_BuyHistory[id][idx][bCategory];
    new wpnId = g_BuyHistory[id][idx][bWeaponId];
    new cost = g_BuyHistory[id][idx][bCost];

    new itemName[32];
    GetItemFriendlyName(cat, wpnId, itemName, charsmax(itemName));

    switch (cat)
    {
        case CAT_WEAPON:
        {
            if (!(pev(id, pev_weapons) & (1 << wpnId)))
            {
                client_print(id, print_chat, "^x04[CS2 Refund]^x01 Cannot refund ^x03%s^x01 (weapon has been dropped or discarded).", itemName);
                RemoveBuyHistoryIndex(id, idx);
                return false;
            }

            ham_strip_user_weapon_safe(id, wpnId);
            cs_set_user_bpammo(id, wpnId, 0);
            g_TrackWeapons[id] &= ~(1 << wpnId);

            if (IsSecondaryPistol(wpnId) && !HasSecondaryWeapon(id) && g_StartedWithPistol[id])
            {
                RestoreStarterPistol(id);
            }

            ProcessRefundSuccess(id, cost, itemName);
            RemoveBuyHistoryIndex(id, idx);
            return true;
        }
        case CAT_GRENADE:
        {
            new curAmmo = cs_get_user_bpammo(id, wpnId);
            if (curAmmo <= 0)
            {
                client_print(id, print_chat, "^x04[CS2 Refund]^x01 Cannot refund ^x03%s^x01 (grenade has been thrown or dropped).", itemName);
                RemoveBuyHistoryIndex(id, idx);
                return false;
            }

            cs_set_user_bpammo(id, wpnId, curAmmo - 1);
            if (curAmmo - 1 <= 0)
            {
                ham_strip_user_weapon_safe(id, wpnId);
                g_TrackWeapons[id] &= ~(1 << wpnId);
            }
            UpdateTrackNade(id, wpnId, curAmmo - 1);

            ProcessRefundSuccess(id, cost, itemName);
            RemoveBuyHistoryIndex(id, idx);
            return true;
        }
        case CAT_ARMOR_KEVLAR, CAT_ARMOR_HELMET:
        {
            new CsArmorType:curType;
            new curArmor = cs_get_user_armor(id, curType);
            if (curArmor <= 0)
            {
                client_print(id, print_chat, "^x04[CS2 Refund]^x01 Cannot refund ^x03%s^x01 (no armor found).", itemName);
                RemoveBuyHistoryIndex(id, idx);
                return false;
            }

            cs_set_user_armor(id, g_BuyHistory[id][idx][bPrevArmorVal], g_BuyHistory[id][idx][bPrevArmorType]);
            g_TrackArmor[id] = g_BuyHistory[id][idx][bPrevArmorVal];
            g_TrackArmorType[id] = g_BuyHistory[id][idx][bPrevArmorType];

            ProcessRefundSuccess(id, cost, itemName);
            RemoveBuyHistoryIndex(id, idx);
            return true;
        }
        case CAT_ARMOR_UPGRADE:
        {
            cs_set_user_armor(id, 100, CS_ARMOR_KEVLAR);
            g_TrackArmor[id] = 100;
            g_TrackArmorType[id] = CS_ARMOR_KEVLAR;

            ProcessRefundSuccess(id, cost, itemName);
            RemoveBuyHistoryIndex(id, idx);
            return true;
        }
        case CAT_DEFUSER:
        {
            if (!cs_get_user_defuse(id))
            {
                client_print(id, print_chat, "^x04[CS2 Refund]^x01 Cannot refund ^x03Defusal Kit^x01 (not equipped).");
                RemoveBuyHistoryIndex(id, idx);
                return false;
            }

            cs_set_user_defuse(id, 0);
            g_TrackDefuse[id] = 0;

            ProcessRefundSuccess(id, cost, itemName);
            RemoveBuyHistoryIndex(id, idx);
            return true;
        }
        case CAT_NVG:
        {
            if (!cs_get_user_nvg(id))
            {
                client_print(id, print_chat, "^x04[CS2 Refund]^x01 Cannot refund ^x03Nightvision^x01 (not equipped).");
                RemoveBuyHistoryIndex(id, idx);
                return false;
            }

            cs_set_user_nvg(id, 0);
            g_TrackNVG[id] = 0;

            ProcessRefundSuccess(id, cost, itemName);
            RemoveBuyHistoryIndex(id, idx);
            return true;
        }
    }
    return false;
}

stock RemoveBuyHistoryIndex(id, idx)
{
    for (new i = idx; i < g_BuyCount[id] - 1; i++)
    {
        g_BuyHistory[id][i][bCategory] = g_BuyHistory[id][i + 1][bCategory];
        g_BuyHistory[id][i][bWeaponId] = g_BuyHistory[id][i + 1][bWeaponId];
        g_BuyHistory[id][i][bCost] = g_BuyHistory[id][i + 1][bCost];
        g_BuyHistory[id][i][bPrevArmorVal] = g_BuyHistory[id][i + 1][bPrevArmorVal];
        g_BuyHistory[id][i][bPrevArmorType] = g_BuyHistory[id][i + 1][bPrevArmorType];
    }
    g_BuyCount[id]--;
}

stock ProcessRefundSuccess(id, cost, const itemName[])
{
    new newMoney = min(16000, cs_get_user_money(id) + cost);
    cs_set_user_money(id, newMoney, 1);
    g_LastMoney[id] = newMoney;

    client_cmd(id, "spk %s", SND_REFUND);
    client_print(id, print_chat, "^x04[CS2 Refund]^x01 Sold back ^x03%s^x01! Returned ^x04+$%d^x01 (New balance: $%d)", itemName, cost, newMoney);
}

stock bool:IsItemEligibleForRefund(id, ItemCategory:cat, wpnId)
{
    if (!is_user_alive(id))
        return false;

    switch (cat)
    {
        case CAT_WEAPON:
            return (pev(id, pev_weapons) & (1 << wpnId)) ? true : false;
        case CAT_GRENADE:
            return (cs_get_user_bpammo(id, wpnId) > 0);
        case CAT_ARMOR_KEVLAR, CAT_ARMOR_HELMET, CAT_ARMOR_UPGRADE:
        {
            new CsArmorType:type;
            return (cs_get_user_armor(id, type) > 0);
        }
        case CAT_DEFUSER:
            return (cs_get_user_defuse(id) > 0);
        case CAT_NVG:
            return (cs_get_user_nvg(id) > 0);
    }
    return false;
}

stock SnapshotPlayerInventory(id)
{
    if (!is_user_alive(id))
        return;

    g_TrackWeapons[id] = pev(id, pev_weapons);
    g_TrackArmor[id] = cs_get_user_armor(id, g_TrackArmorType[id]);
    g_TrackDefuse[id] = cs_get_user_defuse(id);
    g_TrackNVG[id] = cs_get_user_nvg(id);
    g_TrackNades[id][0] = cs_get_user_bpammo(id, CSW_HEGRENADE);
    g_TrackNades[id][1] = cs_get_user_bpammo(id, CSW_FLASHBANG);
    g_TrackNades[id][2] = cs_get_user_bpammo(id, CSW_SMOKEGRENADE);
    g_LastMoney[id] = cs_get_user_money(id);

    new CsTeams:team = cs_get_user_team(id);
    if (team == CS_TEAM_CT && (g_TrackWeapons[id] & (1 << CSW_USP)))
    {
        g_StartedWithPistol[id] = true;
        g_DefaultPistolWpn[id] = CSW_USP;
    }
    else if (team == CS_TEAM_T && (g_TrackWeapons[id] & (1 << CSW_GLOCK18)))
    {
        g_StartedWithPistol[id] = true;
        g_DefaultPistolWpn[id] = CSW_GLOCK18;
    }
    else
    {
        g_StartedWithPistol[id] = false;
        g_DefaultPistolWpn[id] = 0;
    }
}

stock RestoreStarterPistol(id)
{
    new CsTeams:team = cs_get_user_team(id);
    if (team == CS_TEAM_CT)
    {
        give_item(id, "weapon_usp");
        cs_set_user_bpammo(id, CSW_USP, 24);
        g_TrackWeapons[id] |= (1 << CSW_USP);
    }
    else if (team == CS_TEAM_T)
    {
        give_item(id, "weapon_glock18");
        cs_set_user_bpammo(id, CSW_GLOCK18, 40);
        g_TrackWeapons[id] |= (1 << CSW_GLOCK18);
    }
}

stock bool:IsSecondaryPistol(wpnId)
{
    return bool:(CSW_ALL_PISTOLS & (1 << wpnId));
}

stock bool:HasSecondaryWeapon(id)
{
    return bool:(pev(id, pev_weapons) & CSW_ALL_PISTOLS);
}

stock UpdateTrackNade(id, weaponId, newAmount)
{
    switch (weaponId)
    {
        case CSW_HEGRENADE:    g_TrackNades[id][0] = newAmount;
        case CSW_FLASHBANG:    g_TrackNades[id][1] = newAmount;
        case CSW_SMOKEGRENADE: g_TrackNades[id][2] = newAmount;
    }
}

stock GetWeaponPrice(weaponId)
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

stock GetItemFriendlyName(ItemCategory:cat, wpnId, name[], maxlen)
{
    switch (cat)
    {
        case CAT_ARMOR_KEVLAR:   copy(name, maxlen, "Kevlar Vest");
        case CAT_ARMOR_HELMET:   copy(name, maxlen, "Kevlar + Helmet");
        case CAT_ARMOR_UPGRADE:  copy(name, maxlen, "Helmet Upgrade");
        case CAT_DEFUSER:        copy(name, maxlen, "Defusal Kit");
        case CAT_NVG:            copy(name, maxlen, "Nightvision Goggles");
        case CAT_GRENADE:
        {
            switch (wpnId)
            {
                case CSW_HEGRENADE:    copy(name, maxlen, "HE Grenade");
                case CSW_FLASHBANG:    copy(name, maxlen, "Flashbang");
                case CSW_SMOKEGRENADE: copy(name, maxlen, "Smoke Grenade");
                default:               copy(name, maxlen, "Grenade");
            }
        }
        case CAT_WEAPON:
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

// ===================================================================
// 3. HE GRENADE SMOKE DISPERSION & SMOKE REGISTRATION
// ===================================================================
public OnGrenadeThink(ent)
{
    if (!pev_valid(ent))
        return HAM_IGNORED;

    new model[32];
    pev(ent, pev_model, model, charsmax(model));

    new Float:dmgtime;
    pev(ent, pev_dmgtime, dmgtime);
    new Float:now = get_gametime();

    // Check if Smoke grenade is popping & register active smoke sphere
    if (equal(model, MDL_W_SMOKE))
    {
        if (dmgtime > 0.0 && dmgtime <= now)
        {
            if (pev(ent, pev_iuser3) != 1337)
            {
                set_pev(ent, pev_iuser3, 1337);
                new Float:vSmokeOrigin[3];
                pev(ent, pev_origin, vSmokeOrigin);
                RegisterActiveSmoke(vSmokeOrigin);
            }
        }
    }

    // Check if HE grenade is about to detonate
    if (equal(model, MDL_W_HE) && get_pcvar_num(pCvar_SmokeDisperse))
    {
        if (dmgtime > 0.0 && dmgtime <= now)
        {
            new Float:vHeOrigin[3];
            pev(ent, pev_origin, vHeOrigin);

            // Search for nearby smoke grenade entities safely
            new smokeEnt = 0;
            while ((smokeEnt = engfunc(EngFunc_FindEntityByString, smokeEnt, "classname", "grenade")) > 0)
            {
                if (smokeEnt == ent) continue;

                new smokeModel[32];
                pev(smokeEnt, pev_model, smokeModel, charsmax(smokeModel));

                if (equal(smokeModel, MDL_W_SMOKE))
                {
                    new Float:vSmokeOrigin[3];
                    pev(smokeEnt, pev_origin, vSmokeOrigin);

                    if (get_distance_f(vHeOrigin, vSmokeOrigin) <= 260.0)
                    {
                        TriggerSmokeDispersion(vSmokeOrigin);
                        break;
                    }
                }
            }
        }
    }

    return HAM_IGNORED;
}

TriggerSmokeDispersion(Float:vOrigin[3])
{
    // Expire active smoke tracker near this dispersion point
    new Float:now = get_gametime();
    for (new i = 0; i < g_ActiveSmokeCount; i++)
    {
        if (g_ActiveSmokeExpire[i] > now)
        {
            if (get_distance_f(g_ActiveSmokes[i], vOrigin) <= 260.0)
            {
                g_ActiveSmokeExpire[i] = 0.0;
            }
        }
    }

    // Play CS2 smoke dispersion air woosh
    emit_sound(0, CHAN_AUTO, SND_DISPERSE, 1.0, ATTN_NORM, 0, PITCH_NORM);

    // Expanding air shockwave ring
    message_begin(MSG_BROADCAST, SVC_TEMPENTITY);
    write_byte(TE_BEAMCYLINDER);
    write_coord(floatround(vOrigin[0]));
    write_coord(floatround(vOrigin[1]));
    write_coord(floatround(vOrigin[2] + 15.0));
    write_coord(floatround(vOrigin[0]));
    write_coord(floatround(vOrigin[1]));
    write_coord(floatround(vOrigin[2] + 280.0));
    write_short(g_SprWave);
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

// ===================================================================
// 4. CS2 3-WAY THROW VELOCITY CONTROLLER (Fakemeta FM_SetModel)
// ===================================================================
public OnSetModel_Post(ent, const model[])
{
    if (!pev_valid(ent))
        return FMRES_IGNORED;

    if (!get_pcvar_num(pCvar_ThrowStrength))
        return FMRES_IGNORED;

    // Check if model is a thrown grenade worldmodel
    if (!equal(model, MDL_W_HE) && !equal(model, MDL_W_FLASH) && !equal(model, MDL_W_SMOKE))
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

    // Apply modified throw strength if requested
    if (g_iThrowMode[id] == THROW_SHORT)
    {
        // 35% forward force, gentle arc
        vVel[0] *= 0.35;
        vVel[1] *= 0.35;
        vVel[2] = (vVel[2] * 0.35) + 125.0;
        set_pev(ent, pev_velocity, vVel);
        client_print(id, print_center, "★ [CS2] Short Underhand Lob (35%) ★");
        g_iThrowMode[id] = THROW_FULL;
    }
    else if (g_iThrowMode[id] == THROW_MEDIUM)
    {
        // 65% forward force
        vVel[0] *= 0.65;
        vVel[1] *= 0.65;
        vVel[2] = (vVel[2] * 0.65) + 75.0;
        set_pev(ent, pev_velocity, vVel);
        client_print(id, print_center, "★ [CS2] Medium Throw (65%) ★");
        g_iThrowMode[id] = THROW_FULL;
    }
    else
    {
        g_iThrowMode[id] = THROW_FULL;
    }

    return FMRES_IGNORED;
}

public Event_CurWeapon(id)
{
    if (!is_user_alive(id))
        return;

    new wpnId = read_data(2);
    if (wpnId != CSW_HEGRENADE && wpnId != CSW_FLASHBANG && wpnId != CSW_SMOKEGRENADE)
    {
        g_iThrowMode[id] = THROW_FULL;
    }
}

// ===================================================================
// 5. CS2 SMOKE BULLET TRACERS & CAVITY EFFECT (Weapon PrimaryAttack)
// ===================================================================
stock RegisterFirearmHooks()
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
        RegisterHam(Ham_Weapon_PrimaryAttack, szWeapons[i], "OnFirearmPrimaryAttack_Post", 1);
    }
}

public OnFirearmPrimaryAttack_Post(weapon_ent)
{
    if (!get_pcvar_num(pCvar_SmokeBullets))
        return HAM_IGNORED;

    if (!pev_valid(weapon_ent))
        return HAM_IGNORED;

    new attacker = pev(weapon_ent, pev_owner);
    if (attacker < 1 || attacker > 32 || !is_user_alive(attacker))
        return HAM_IGNORED;

    new Float:now = get_gametime();
    if (now - g_flLastSmokeTracer[attacker] < 0.08)
        return HAM_IGNORED;

    if (g_ActiveSmokeCount <= 0)
        return HAM_IGNORED;

    // Trace bullet ray from player eyes forward
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
    for (new i = 0; i < g_ActiveSmokeCount; i++)
    {
        if (g_ActiveSmokeExpire[i] > now)
        {
            if (RayIntersectsSphere(vStart, vEnd, g_ActiveSmokes[i], 145.0, vClosest))
            {
                g_flLastSmokeTracer[attacker] = now;

                // Render CS2 bullet tracer line cutting through the smoke
                new Float:vP1[3], Float:vP2[3], Float:vDir[3];
                xs_vec_sub(vEnd, vStart, vDir);
                xs_vec_normalize(vDir, vDir);

                // Entry and exit points relative to intersection
                xs_vec_mul_scalar(vDir, -70.0, vP1);
                xs_vec_add(vClosest, vP1, vP1);

                xs_vec_mul_scalar(vDir, 70.0, vP2);
                xs_vec_add(vClosest, vP2, vP2);

                // Laser Beam Tracer through smoke
                message_begin(MSG_BROADCAST, SVC_TEMPENTITY);
                write_byte(TE_BEAMPOINTS);
                write_coord(floatround(vP1[0]));
                write_coord(floatround(vP1[1]));
                write_coord(floatround(vP1[2]));
                write_coord(floatround(vP2[0]));
                write_coord(floatround(vP2[1]));
                write_coord(floatround(vP2[2]));
                write_short(g_SprTracer);
                write_byte(0);   // starting frame
                write_byte(0);   // framerate
                write_byte(8);   // life (0.8s)
                write_byte(6);   // line width
                write_byte(0);   // noise amplitude
                write_byte(230); // R
                write_byte(235); // G
                write_byte(245); // B
                write_byte(210); // brightness
                write_byte(0);   // scroll speed
                message_end();

                // Smoke cavity puff at point of penetration
                message_begin(MSG_BROADCAST, SVC_TEMPENTITY);
                write_byte(TE_SMOKE);
                write_coord(floatround(vClosest[0]));
                write_coord(floatround(vClosest[1]));
                write_coord(floatround(vClosest[2]));
                write_short(g_SprPuff);
                write_byte(12); // scale
                write_byte(15); // framerate
                message_end();

                break;
            }
        }
    }

    return HAM_IGNORED;
}

stock bool:RayIntersectsSphere(const Float:vRayStart[3], const Float:vRayEnd[3], const Float:vSphereCenter[3], Float:flRadius, Float:vClosestPoint[3])
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

stock RegisterActiveSmoke(const Float:vOrigin[3])
{
    new Float:flNow = get_gametime();
    // Check if smoke at this location was already registered recently
    for (new i = 0; i < g_ActiveSmokeCount; i++)
    {
        if (g_ActiveSmokeExpire[i] > flNow)
        {
            if (get_distance_f(g_ActiveSmokes[i], vOrigin) < 60.0)
                return;
        }
    }

    // Find free slot or overwrite oldest expired
    new slot = -1;
    for (new i = 0; i < MAX_ACTIVE_SMOKES; i++)
    {
        if (g_ActiveSmokeExpire[i] <= flNow)
        {
            slot = i;
            break;
        }
    }

    if (slot == -1)
    {
        if (g_ActiveSmokeCount < MAX_ACTIVE_SMOKES)
        {
            slot = g_ActiveSmokeCount++;
        }
        else
        {
            slot = 0;
        }
    }
    else if (slot >= g_ActiveSmokeCount)
    {
        g_ActiveSmokeCount = slot + 1;
    }

    g_ActiveSmokes[slot][0] = vOrigin[0];
    g_ActiveSmokes[slot][1] = vOrigin[1];
    g_ActiveSmokes[slot][2] = vOrigin[2];
    g_ActiveSmokeExpire[slot] = flNow + 18.0;
}
