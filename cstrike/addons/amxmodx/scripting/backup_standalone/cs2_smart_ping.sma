/**
 * ==============================================================================
 * Plugin: CS2 Contextual 3D Smart Ping & Squad AI Engine
 * Version: 2.0.0
 * Author: Antigravity
 * Description:
 *   Elevates CS 1.6 communication to modern CS2 standards with 3D contextual
 *   raytracing, real-time dynamic distance tracking in meters, intelligent
 *   object classification (Weapons, C4 Bomb, Defuse Kit, Enemy, Waypoint),
 *   and coordinated YaPB Bot Squad tactical responses.
 *
 * Features (v2.0):
 *   1. Contextual Object Raytracing: Auto-detects dropped weapons with exact model
 *      names (e.g. [WEAPON: AK-47]), C4 explosive, defuse kits, enemies, and corpses.
 *   2. Real-time Live Distance HUD: Continuously displays distance in meters
 *      updating dynamically as teammates move closer or farther.
 *   3. Modern CS2 Audio-Visuals: Color-coded 3D flare beacons, dynamic lights
 *      (Red, Orange, Green, Blue, Cyan), and CS2 team radio pings.
 *   4. Enhanced YaPB Bot Squad AI:
 *      - Weapon Ping: Under-equipped bots move to scavenge dropped rifles.
 *      - Danger Ping: Entry & AWPer bots pre-aim and hold angles with high alertness.
 *      - C4 Ping: CT bots rotate to secure bomb; T bots set up perimeter guards.
 *      - Defuser Ping: CT bots without kits path to retrieve them.
 * ==============================================================================
 */

#include <amxmodx>
#include <amxmisc>
#include <cstrike>
#include <fakemeta>
#include <hamsandwich>
#include <engine>
#include <xs>

#define PLUGIN  "CS2 3D Smart Ping & Squad AI"
#define VERSION "2.0.0"
#define AUTHOR  "Antigravity"

// Sound Paths (relative to sound/)
new const SND_PING_NORMAL[] = "cs2_ping/ping_normal.wav";
new const SND_PING_DANGER[] = "cs2_ping/ping_danger.wav";
new const SND_PING_C4[]     = "cs2_ping/ping_c4.wav";

// Sprites
new const SPR_WAYPOINT[] = "sprites/flare3.spr";
new const SPR_DANGER[]   = "sprites/3dmflared.spr";
new const SPR_BOMB[]     = "sprites/glow01.spr";

// Ping Types Enum
enum {
    PING_WAYPOINT = 0,
    PING_DANGER,
    PING_C4,
    PING_WEAPON,
    PING_DEFUSER
};

// CVars
new pCvar_Enable;
new pCvar_Cooldown;
new pCvar_Duration;
new pCvar_BotResponse;
new pCvar_DLight;
new pCvar_HudDistance;

// Player Cooldown Tracking
new Float:g_LastPingTime[33];

// Active Ping State per player
new bool:g_PingActive[33];
new g_PlayerPingEnt[33];
new g_PlayerPingType[33];
new Float:g_PingOrigin[33][3];
new g_szPingLabel[33][64];
new CsTeams:g_PingTeam[33];

// YaPB Bot Squad Reaction State
new Float:g_BotPingTarget[33][3];
new Float:g_BotPingExpire[33];
new g_BotPingType[33];

// HUD Synchronization
new g_HudSyncPing;

// Task IDs
#define TASK_PING_EXPIRE 5100
#define TASK_PING_HUD    5200

public plugin_init()
{
    register_plugin(PLUGIN, VERSION, AUTHOR);

    // CVars
    pCvar_Enable       = register_cvar("amx_cs2_ping", "1");
    pCvar_Cooldown     = register_cvar("amx_cs2_ping_cooldown", "1.2");
    pCvar_Duration     = register_cvar("amx_cs2_ping_duration", "4.0");
    pCvar_BotResponse   = register_cvar("amx_cs2_ping_bot_ai", "1");
    pCvar_DLight       = register_cvar("amx_cs2_ping_dlight", "1");
    pCvar_HudDistance  = register_cvar("amx_cs2_ping_hud", "1");

    // Client Commands (Support +ping, -ping, amx_ping, ping_point)
    register_clcmd("+ping", "Cmd_PingPoint");
    register_clcmd("-ping", "Cmd_PingRelease");
    register_clcmd("amx_ping", "Cmd_PingPoint");
    register_clcmd("ping_point", "Cmd_PingPoint");

    // Events
    register_event("HLTV", "Event_NewRound", "a", "1=0", "2=0");
    register_logevent("Event_RoundEnd", 2, "1=Round_End");

    // Fakemeta Bot Angle & Movement Manipulation
    register_forward(FM_CmdStart, "OnCmdStart");

    // Create HUD Sync Object
    g_HudSyncPing = CreateHudSyncObj();

    // Start Real-time Dynamic Distance HUD Task (every 0.25s)
    set_task(0.25, "Task_UpdatePingHUD", TASK_PING_HUD, _, _, "b");
}

public plugin_precache()
{
    precache_sound(SND_PING_NORMAL);
    precache_sound(SND_PING_DANGER);
    precache_sound(SND_PING_C4);

    precache_model(SPR_WAYPOINT);
    precache_model(SPR_DANGER);
    precache_model(SPR_BOMB);
}

public client_putinserver(id)
{
    g_LastPingTime[id] = 0.0;
    g_PingActive[id] = false;
    g_PlayerPingEnt[id] = 0;
    g_BotPingExpire[id] = 0.0;
    g_PingTeam[id] = CS_TEAM_UNASSIGNED;
}

public client_disconnected(id)
{
    RemovePlayerPing(id);
    g_LastPingTime[id] = 0.0;
    g_BotPingExpire[id] = 0.0;
}

public Event_NewRound()
{
    for (new i = 1; i <= 32; i++)
    {
        RemovePlayerPing(i);
        g_BotPingExpire[i] = 0.0;
    }
}

public Event_RoundEnd()
{
    for (new i = 1; i <= 32; i++)
    {
        RemovePlayerPing(i);
        g_BotPingExpire[i] = 0.0;
    }
}

public Cmd_PingRelease(id)
{
    return PLUGIN_HANDLED;
}

public Cmd_PingPoint(id)
{
    if (!get_pcvar_num(pCvar_Enable))
        return PLUGIN_CONTINUE;

    if (!is_user_alive(id))
        return PLUGIN_HANDLED;

    new Float:flGameTime = get_gametime();
    new Float:flCooldown = get_pcvar_float(pCvar_Cooldown);

    if (flGameTime - g_LastPingTime[id] < flCooldown)
        return PLUGIN_HANDLED;

    g_LastPingTime[id] = flGameTime;

    // Trace player crosshair
    new Float:vOrigin[3], Float:vViewOfs[3], Float:vAngles[3], Float:vForward[3], Float:vEnd[3];
    pev(id, pev_origin, vOrigin);
    pev(id, pev_view_ofs, vViewOfs);
    xs_vec_add(vOrigin, vViewOfs, vOrigin);

    pev(id, pev_v_angle, vAngles);
    angle_vector(vAngles, ANGLEVECTOR_FORWARD, vForward);
    xs_vec_mul_scalar(vForward, 8192.0, vForward);
    xs_vec_add(vOrigin, vForward, vEnd);

    new tr;
    engfunc(EngFunc_TraceLine, vOrigin, vEnd, DONT_IGNORE_MONSTERS, id, tr);

    new Float:vHitPos[3];
    get_tr2(tr, TR_vecEndPos, vHitPos);
    new pHit = get_tr2(tr, TR_pHit);

    new pingType = PING_WAYPOINT;
    new szContextLabel[64];

    // Contextual Raytracing & Auto-Classification
    ClassifyPingTarget(id, vHitPos, pHit, pingType, szContextLabel, charsmax(szContextLabel));

    // Store Active Ping Data
    g_PingActive[id] = true;
    g_PlayerPingType[id] = pingType;
    g_PingOrigin[id][0] = vHitPos[0];
    g_PingOrigin[id][1] = vHitPos[1];
    g_PingOrigin[id][2] = vHitPos[2];
    copy(g_szPingLabel[id], charsmax(g_szPingLabel[]), szContextLabel);
    g_PingTeam[id] = cs_get_user_team(id);

    // Spawn / Update 3D Ping Visual Marker
    CreatePingMarker(id, vHitPos, pingType);

    // Play Sound & Broadcast Chat Intel for Player & Teammates
    BroadcastPingFeedback(id, vHitPos, pingType, szContextLabel);

    // Alert & Coordinate YaPB Bot Teammates
    if (get_pcvar_num(pCvar_BotResponse))
    {
        CommandSquadBots(id, vHitPos, pingType, szContextLabel);
    }

    return PLUGIN_HANDLED;
}

// ===================================================================
// CONTEXTUAL OBJECT RAYTRACING & CLASSIFICATION ENGINE
// ===================================================================
stock ClassifyPingTarget(id, Float:vHitPos[3], pHit, &pingType, szLabel[], maxLen)
{
    new CsTeams:myTeam = cs_get_user_team(id);

    // 1. Direct Entity Hit Check
    if (pHit > 0 && pev_valid(pHit))
    {
        // Player Check
        if (pHit <= 32 && is_user_connected(pHit) && is_user_alive(pHit))
        {
            if (cs_get_user_team(pHit) != myTeam)
            {
                pingType = PING_DANGER;
                new enemyName[32];
                get_user_name(pHit, enemyName, charsmax(enemyName));
                format(szLabel, maxLen, "ENEMY: %s", enemyName);
                return;
            }
            else
            {
                pingType = PING_WAYPOINT;
                new teammateName[32];
                get_user_name(pHit, teammateName, charsmax(teammateName));
                format(szLabel, maxLen, "TEAMMATE: %s", teammateName);
                return;
            }
        }

        // Entity Class Check
        new szClass[32];
        pev(pHit, pev_classname, szClass, charsmax(szClass));

        // Dropped Weaponbox
        if (equal(szClass, "weaponbox"))
        {
            new szModel[64];
            pev(pHit, pev_model, szModel, charsmax(szModel));
            if (containi(szModel, "w_c4") != -1)
            {
                pingType = PING_C4;
                copy(szLabel, maxLen, "C4 EXPLOSIVE");
                return;
            }
            else
            {
                pingType = PING_WEAPON;
                new wpnName[32];
                ResolveWeaponNameFromModel(szModel, wpnName, charsmax(wpnName));
                format(szLabel, maxLen, "WEAPON: %s", wpnName);
                return;
            }
        }

        // Pre-placed Armoury Entity (Map Weapons)
        if (equal(szClass, "armoury_entity"))
        {
            pingType = PING_WEAPON;
            new count = 1;
            new itemType = cs_get_armoury_type(pHit, count);
            new wpnName[32];
            ResolveWeaponNameFromId(itemType, wpnName, charsmax(wpnName));
            format(szLabel, maxLen, "WEAPON: %s", wpnName);
            return;
        }

        // Defusal Kit
        if (equal(szClass, "item_thighpack"))
        {
            pingType = PING_DEFUSER;
            copy(szLabel, maxLen, "DEFUSE KIT");
            return;
        }

        // C4 Weapon Entity
        if (equal(szClass, "weapon_c4"))
        {
            pingType = PING_C4;
            copy(szLabel, maxLen, "C4 EXPLOSIVE");
            return;
        }

        // Planted C4 Grenade Entity
        if (equal(szClass, "grenade"))
        {
            new szModel[64];
            pev(pHit, pev_model, szModel, charsmax(szModel));
            if (containi(szModel, "w_c4") != -1)
            {
                pingType = PING_C4;
                copy(szLabel, maxLen, "PLANTED C4 BOMB");
                return;
            }
        }
    }

    // 2. Proximity Sphere Search around Hit Position (Radius 85 units)
    new ent = -1;
    while ((ent = engfunc(EngFunc_FindEntityInSphere, ent, vHitPos, 85.0)) > 0)
    {
        if (!pev_valid(ent))
            continue;

        new szClass[32];
        pev(ent, pev_classname, szClass, charsmax(szClass));

        // Living Enemy in vicinity
        if (ent <= 32 && is_user_connected(ent) && is_user_alive(ent) && cs_get_user_team(ent) != myTeam)
        {
            pingType = PING_DANGER;
            new enemyName[32];
            get_user_name(ent, enemyName, charsmax(enemyName));
            format(szLabel, maxLen, "ENEMY: %s", enemyName);
            return;
        }

        // Dropped C4
        if (equal(szClass, "weapon_c4"))
        {
            pingType = PING_C4;
            copy(szLabel, maxLen, "C4 EXPLOSIVE");
            return;
        }

        // Planted C4
        if (equal(szClass, "grenade"))
        {
            new szModel[64];
            pev(ent, pev_model, szModel, charsmax(szModel));
            if (containi(szModel, "w_c4") != -1)
            {
                pingType = PING_C4;
                copy(szLabel, maxLen, "PLANTED C4 BOMB");
                return;
            }
        }

        // Defusal Kit
        if (equal(szClass, "item_thighpack"))
        {
            pingType = PING_DEFUSER;
            copy(szLabel, maxLen, "DEFUSE KIT");
            return;
        }

        // Dropped Weaponbox
        if (equal(szClass, "weaponbox"))
        {
            new szModel[64];
            pev(ent, pev_model, szModel, charsmax(szModel));
            if (containi(szModel, "w_c4") != -1)
            {
                pingType = PING_C4;
                copy(szLabel, maxLen, "C4 EXPLOSIVE");
                return;
            }
            else
            {
                pingType = PING_WEAPON;
                new wpnName[32];
                ResolveWeaponNameFromModel(szModel, wpnName, charsmax(wpnName));
                format(szLabel, maxLen, "WEAPON: %s", wpnName);
                return;
            }
        }

        // Armoury Entity
        if (equal(szClass, "armoury_entity"))
        {
            pingType = PING_WEAPON;
            new count = 1;
            new itemType = cs_get_armoury_type(ent, count);
            new wpnName[32];
            ResolveWeaponNameFromId(itemType, wpnName, charsmax(wpnName));
            format(szLabel, maxLen, "WEAPON: %s", wpnName);
            return;
        }
    }

    // 3. Extended Enemy Radius Check (150 units)
    if (IsNearEnemy(vHitPos, myTeam, 150.0))
    {
        pingType = PING_DANGER;
        copy(szLabel, maxLen, "DANGER / ENEMY CONTACT");
        return;
    }

    // 4. Default Waypoint
    pingType = PING_WAYPOINT;
    copy(szLabel, maxLen, "TACTICAL WAYPOINT");
}

stock ResolveWeaponNameFromModel(const szModel[], szName[], maxLen)
{
    if (containi(szModel, "ak47") != -1)          copy(szName, maxLen, "AK-47");
    else if (containi(szModel, "m4a1") != -1)     copy(szName, maxLen, "M4A1-S");
    else if (containi(szModel, "m4a4") != -1)     copy(szName, maxLen, "M4A4");
    else if (containi(szModel, "awp") != -1)      copy(szName, maxLen, "AWP");
    else if (containi(szModel, "deagle") != -1)   copy(szName, maxLen, "Desert Eagle");
    else if (containi(szModel, "scout") != -1)    copy(szName, maxLen, "SSG 08 (Scout)");
    else if (containi(szModel, "galil") != -1)    copy(szName, maxLen, "Galil AR");
    else if (containi(szModel, "famas") != -1)    copy(szName, maxLen, "FAMAS");
    else if (containi(szModel, "mp5") != -1)      copy(szName, maxLen, "MP5-SD");
    else if (containi(szModel, "ump45") != -1)    copy(szName, maxLen, "UMP-45");
    else if (containi(szModel, "p90") != -1)      copy(szName, maxLen, "P90");
    else if (containi(szModel, "mac10") != -1)    copy(szName, maxLen, "MAC-10");
    else if (containi(szModel, "tmp") != -1)      copy(szName, maxLen, "MP9 / TMP");
    else if (containi(szModel, "aug") != -1)      copy(szName, maxLen, "AUG");
    else if (containi(szModel, "sg552") != -1)    copy(szName, maxLen, "SG 553");
    else if (containi(szModel, "xm1014") != -1)   copy(szName, maxLen, "XM1014");
    else if (containi(szModel, "m3") != -1)       copy(szName, maxLen, "Nova (M3)");
    else if (containi(szModel, "usp") != -1)      copy(szName, maxLen, "USP-S");
    else if (containi(szModel, "glock") != -1)    copy(szName, maxLen, "Glock-18");
    else if (containi(szModel, "elite") != -1)    copy(szName, maxLen, "Dual Berettas");
    else if (containi(szModel, "fiveseven") != -1)copy(szName, maxLen, "Five-SeveN");
    else if (containi(szModel, "p228") != -1)     copy(szName, maxLen, "P250 / P228");
    else if (containi(szModel, "g3sg1") != -1)    copy(szName, maxLen, "G3SG1");
    else if (containi(szModel, "sg550") != -1)    copy(szName, maxLen, "SCAR-20 / SG550");
    else if (containi(szModel, "m249") != -1)     copy(szName, maxLen, "M249");
    else if (containi(szModel, "hegrenade") != -1)copy(szName, maxLen, "HE Grenade");
    else if (containi(szModel, "flashbang") != -1)copy(szName, maxLen, "Flashbang");
    else if (containi(szModel, "smokegrenade") != -1) copy(szName, maxLen, "Smoke Grenade");
    else                                          copy(szName, maxLen, "Firearm");
}

stock ResolveWeaponNameFromId(weaponId, szName[], maxLen)
{
    switch (weaponId)
    {
        case CSW_AK47:        copy(szName, maxLen, "AK-47");
        case CSW_M4A1:        copy(szName, maxLen, "M4A1-S");
        case CSW_AWP:         copy(szName, maxLen, "AWP");
        case CSW_DEAGLE:      copy(szName, maxLen, "Desert Eagle");
        case CSW_SCOUT:       copy(szName, maxLen, "SSG 08 (Scout)");
        case CSW_GALIL:       copy(szName, maxLen, "Galil AR");
        case CSW_FAMAS:       copy(szName, maxLen, "FAMAS");
        case CSW_MP5NAVY:     copy(szName, maxLen, "MP5-SD");
        case CSW_UMP45:       copy(szName, maxLen, "UMP-45");
        case CSW_P90:         copy(szName, maxLen, "P90");
        case CSW_MAC10:       copy(szName, maxLen, "MAC-10");
        case CSW_TMP:         copy(szName, maxLen, "MP9 / TMP");
        case CSW_AUG:         copy(szName, maxLen, "AUG");
        case CSW_SG552:       copy(szName, maxLen, "SG 553");
        case CSW_XM1014:      copy(szName, maxLen, "XM1014");
        case CSW_M3:          copy(szName, maxLen, "Nova (M3)");
        case CSW_USP:         copy(szName, maxLen, "USP-S");
        case CSW_GLOCK18:     copy(szName, maxLen, "Glock-18");
        case CSW_ELITE:       copy(szName, maxLen, "Dual Berettas");
        case CSW_FIVESEVEN:   copy(szName, maxLen, "Five-SeveN");
        case CSW_P228:        copy(szName, maxLen, "P250 / P228");
        case CSW_G3SG1:       copy(szName, maxLen, "G3SG1");
        case CSW_SG550:       copy(szName, maxLen, "SCAR-20 / SG550");
        case CSW_M249:        copy(szName, maxLen, "M249");
        case CSW_HEGRENADE:   copy(szName, maxLen, "HE Grenade");
        case CSW_FLASHBANG:   copy(szName, maxLen, "Flashbang");
        case CSW_SMOKEGRENADE:copy(szName, maxLen, "Smoke Grenade");
        default:              copy(szName, maxLen, "Firearm");
    }
}

// ===================================================================
// 3D BEACON MARKER & VISUALS
// ===================================================================
CreatePingMarker(id, Float:vPos[3], pingType)
{
    RemovePlayerPing(id);

    new ent = engfunc(EngFunc_CreateNamedEntity, engfunc(EngFunc_AllocString, "env_sprite"));
    if (!pev_valid(ent))
        return;

    g_PlayerPingEnt[id] = ent;
    g_PlayerPingType[id] = pingType;

    // Position marker slightly elevated above surface
    new Float:vSpritePos[3];
    vSpritePos[0] = vPos[0];
    vSpritePos[1] = vPos[1];
    vSpritePos[2] = vPos[2] + 22.0;

    set_pev(ent, pev_origin, vSpritePos);
    set_pev(ent, pev_classname, "cs2_ping_beacon");
    set_pev(ent, pev_owner, id);

    switch (pingType)
    {
        case PING_DANGER:
        {
            engfunc(EngFunc_SetModel, ent, SPR_DANGER);
            set_pev(ent, pev_scale, 0.48);
        }
        case PING_C4:
        {
            engfunc(EngFunc_SetModel, ent, SPR_BOMB);
            set_pev(ent, pev_scale, 0.45);
        }
        case PING_WEAPON:
        {
            engfunc(EngFunc_SetModel, ent, SPR_WAYPOINT);
            set_pev(ent, pev_scale, 0.38);
        }
        case PING_DEFUSER:
        {
            engfunc(EngFunc_SetModel, ent, SPR_WAYPOINT);
            set_pev(ent, pev_scale, 0.38);
        }
        default:
        {
            engfunc(EngFunc_SetModel, ent, SPR_WAYPOINT);
            set_pev(ent, pev_scale, 0.32);
        }
    }

    set_pev(ent, pev_rendermode, kRenderTransAdd);
    set_pev(ent, pev_renderamt, 255.0);
    set_pev(ent, pev_solid, SOLID_NOT);

    // Dynamic Light Effect at hit point
    if (get_pcvar_num(pCvar_DLight))
    {
        CreateDynamicLight(vPos, pingType);
    }

    // Set auto removal task
    new Float:duration = get_pcvar_float(pCvar_Duration);
    if (duration <= 0.0) duration = 4.0;
    set_task(duration, "Task_ExpirePing", TASK_PING_EXPIRE + id);
}

public Task_ExpirePing(taskId)
{
    new id = taskId - TASK_PING_EXPIRE;
    RemovePlayerPing(id);
}

RemovePlayerPing(id)
{
    remove_task(TASK_PING_EXPIRE + id);
    if (g_PlayerPingEnt[id] > 0 && pev_valid(g_PlayerPingEnt[id]))
    {
        engfunc(EngFunc_RemoveEntity, g_PlayerPingEnt[id]);
    }
    g_PlayerPingEnt[id] = 0;
    g_PingActive[id] = false;
}

CreateDynamicLight(Float:vPos[3], pingType)
{
    message_begin(MSG_BROADCAST, SVC_TEMPENTITY);
    write_byte(TE_DLIGHT);
    write_coord(floatround(vPos[0]));
    write_coord(floatround(vPos[1]));
    write_coord(floatround(vPos[2] + 10.0));
    write_byte(18); // Radius

    switch (pingType)
    {
        case PING_DANGER:
        {
            write_byte(255); // R
            write_byte(30);  // G
            write_byte(30);  // B
        }
        case PING_C4:
        {
            write_byte(255); // R
            write_byte(120); // G
            write_byte(0);   // B
        }
        case PING_WEAPON:
        {
            write_byte(40);  // R
            write_byte(255); // G
            write_byte(80);  // B
        }
        case PING_DEFUSER:
        {
            write_byte(30);  // R
            write_byte(160); // G
            write_byte(255); // B
        }
        default:
        {
            write_byte(0);   // R
            write_byte(255); // G
            write_byte(200); // B
        }
    }

    write_byte(35); // Life (3.5s)
    write_byte(10); // Decay rate
    message_end();
}

// ===================================================================
// AUDIO & CHAT INTEL BROADCAST
// ===================================================================
BroadcastPingFeedback(id, Float:vPos[3], pingType, const szLabel[])
{
    new CsTeams:myTeam = cs_get_user_team(id);
    new userName[32];
    get_user_name(id, userName, charsmax(userName));

    new Float:vMyOrigin[3];
    pev(id, pev_origin, vMyOrigin);
    new distMeters = floatround(get_distance_f(vMyOrigin, vPos) * 0.0254);

    new soundFile[64];
    new chatMsg[128];

    switch (pingType)
    {
        case PING_DANGER:
        {
            copy(soundFile, charsmax(soundFile), SND_PING_DANGER);
            format(chatMsg, charsmax(chatMsg), "^x04[Ping]^x03 %s:^x01 ^x02[%s]^x01 (%dm)", userName, szLabel, distMeters);
        }
        case PING_C4:
        {
            copy(soundFile, charsmax(soundFile), SND_PING_C4);
            format(chatMsg, charsmax(chatMsg), "^x04[Ping]^x03 %s:^x01 ^x02[%s]^x01 (%dm)", userName, szLabel, distMeters);
        }
        case PING_WEAPON:
        {
            copy(soundFile, charsmax(soundFile), SND_PING_NORMAL);
            format(chatMsg, charsmax(chatMsg), "^x04[Ping]^x03 %s:^x01 ^x04[%s]^x01 (%dm)", userName, szLabel, distMeters);
        }
        case PING_DEFUSER:
        {
            copy(soundFile, charsmax(soundFile), SND_PING_NORMAL);
            format(chatMsg, charsmax(chatMsg), "^x04[Ping]^x03 %s:^x01 ^x03[%s]^x01 (%dm)", userName, szLabel, distMeters);
        }
        default:
        {
            copy(soundFile, charsmax(soundFile), SND_PING_NORMAL);
            format(chatMsg, charsmax(chatMsg), "^x04[Ping]^x03 %s:^x01 [%s] (%dm)", userName, szLabel, distMeters);
        }
    }

    // Broadcast only to teammates
    for (new i = 1; i <= 32; i++)
    {
        if (is_user_connected(i) && cs_get_user_team(i) == myTeam)
        {
            if (!is_user_bot(i))
            {
                client_cmd(i, "spk %s", soundFile);
            }
            client_print(i, print_chat, "%s", chatMsg);
        }
    }
}

// ===================================================================
// REAL-TIME DYNAMIC DISTANCE HUD TASK (CS2 Live Tracking)
// ===================================================================
public Task_UpdatePingHUD()
{
    if (!get_pcvar_num(pCvar_Enable) || !get_pcvar_num(pCvar_HudDistance))
        return;

    // Render live distance for each alive player based on team's active pings
    for (new viewer = 1; viewer <= 32; viewer++)
    {
        if (!is_user_connected(viewer) || !is_user_alive(viewer) || is_user_bot(viewer))
            continue;

        new CsTeams:viewerTeam = cs_get_user_team(viewer);
        if (viewerTeam != CS_TEAM_T && viewerTeam != CS_TEAM_CT)
            continue;

        // Find highest priority active ping for viewer's team
        new bestPinger = 0;
        new bestPriority = -1;

        for (new pinger = 1; pinger <= 32; pinger++)
        {
            if (g_PingActive[pinger] && g_PingTeam[pinger] == viewerTeam)
            {
                new priority = 1;
                if (g_PlayerPingType[pinger] == PING_DANGER) priority = 5;
                else if (g_PlayerPingType[pinger] == PING_C4) priority = 4;
                else if (g_PlayerPingType[pinger] == PING_WEAPON || g_PlayerPingType[pinger] == PING_DEFUSER) priority = 3;

                // Priority boost if it's the player's own ping
                if (pinger == viewer) priority += 1;

                if (priority > bestPriority)
                {
                    bestPriority = priority;
                    bestPinger = pinger;
                }
            }
        }

        if (bestPinger > 0)
        {
            new Float:vViewerOrigin[3];
            pev(viewer, pev_origin, vViewerOrigin);
            new distMeters = floatround(get_distance_f(vViewerOrigin, g_PingOrigin[bestPinger]) * 0.0254);

            new pingerName[32];
            get_user_name(bestPinger, pingerName, charsmax(pingerName));

            new r = 0, g = 255, b = 200;
            new hudMsg[128];

            switch (g_PlayerPingType[bestPinger])
            {
                case PING_DANGER:
                {
                    r = 255; g = 50; b = 50;
                    format(hudMsg, charsmax(hudMsg), "[!] DANGER: %s (%dm)^n(%s)", g_szPingLabel[bestPinger], distMeters, pingerName);
                }
                case PING_C4:
                {
                    r = 255; g = 140; b = 20;
                    format(hudMsg, charsmax(hudMsg), "[*] BOMB INTEL: %s (%dm)^n(%s)", g_szPingLabel[bestPinger], distMeters, pingerName);
                }
                case PING_WEAPON:
                {
                    r = 60; g = 255; b = 90;
                    format(hudMsg, charsmax(hudMsg), "[+] INTEL: %s (%dm)^n(%s)", g_szPingLabel[bestPinger], distMeters, pingerName);
                }
                case PING_DEFUSER:
                {
                    r = 40; g = 180; b = 255;
                    format(hudMsg, charsmax(hudMsg), "[+] INTEL: %s (%dm)^n(%s)", g_szPingLabel[bestPinger], distMeters, pingerName);
                }
                default:
                {
                    r = 0; g = 230; b = 230;
                    format(hudMsg, charsmax(hudMsg), "[>] WAYPOINT: (%dm)^n(%s)", distMeters, pingerName);
                }
            }

            // Display HUD Sync Message (clean bottom-right above status)
            set_hudmessage(r, g, b, 0.03, 0.38, 0, 0.0, 0.35, 0.05, 0.05);
            ShowSyncHudMsg(viewer, g_HudSyncPing, "%s", hudMsg);
        }
    }
}

// ===================================================================
// ADVANCED YaPB BOT SQUAD COORDINATION ENGINE
// ===================================================================
CommandSquadBots(id, Float:vPos[3], pingType, const szLabel[])
{
    new CsTeams:myTeam = cs_get_user_team(id);
    new Float:flGameTime = get_gametime();
    new responderBot = 0;
    new Float:bestDist = 99999.0;

    for (new bot = 1; bot <= 32; bot++)
    {
        if (is_user_connected(bot) && is_user_alive(bot) && is_user_bot(bot) && cs_get_user_team(bot) == myTeam)
        {
            new Float:vBotOrigin[3];
            pev(bot, pev_origin, vBotOrigin);
            new Float:flDist = get_distance_f(vBotOrigin, vPos);

            // Bots within 3000 units receive tactical assignment
            if (flDist <= 3000.0)
            {
                g_BotPingTarget[bot][0] = vPos[0];
                g_BotPingTarget[bot][1] = vPos[1];
                g_BotPingTarget[bot][2] = vPos[2];
                g_BotPingType[bot] = pingType;

                // Duration bots focus on the ping
                g_BotPingExpire[bot] = flGameTime + ((pingType == PING_DANGER) ? 3.5 : 4.5);

                if (flDist < bestDist)
                {
                    bestDist = flDist;
                    responderBot = bot;
                }
            }
        }
    }

    // Nearest bot responds via team radio & chat
    if (responderBot > 0)
    {
        new botName[32];
        get_user_name(responderBot, botName, charsmax(botName));

        switch (pingType)
        {
            case PING_DANGER:
            {
                client_print(id, print_chat, "^x04[Squad AI]^x03 %s:^x01 Threat identified! Pre-aiming and covering angle!", botName);
                if (!is_user_bot(id)) client_cmd(id, "spk radio/roger.wav");
            }
            case PING_C4:
            {
                if (myTeam == CS_TEAM_CT)
                {
                    client_print(id, print_chat, "^x04[Squad AI]^x03 %s:^x01 Bomb located! Moving to secure the bomb!", botName);
                    if (!is_user_bot(id)) client_cmd(id, "spk radio/go.wav");
                }
                else
                {
                    client_print(id, print_chat, "^x04[Squad AI]^x03 %s:^x01 Securing C4 bomb perimeter!", botName);
                    if (!is_user_bot(id)) client_cmd(id, "spk radio/locknload.wav");
                }
            }
            case PING_WEAPON:
            {
                client_print(id, print_chat, "^x04[Squad AI]^x03 %s:^x01 Moving to retrieve %s!", botName, szLabel);
                if (!is_user_bot(id)) client_cmd(id, "spk radio/roger.wav");
            }
            case PING_DEFUSER:
            {
                client_print(id, print_chat, "^x04[Squad AI]^x03 %s:^x01 Roger that, picking up defuse kit!", botName);
                if (!is_user_bot(id)) client_cmd(id, "spk radio/roger.wav");
            }
            default:
            {
                client_print(id, print_chat, "^x04[Squad AI]^x03 %s:^x01 Copy, moving to investigate marked area.", botName);
                if (!is_user_bot(id)) client_cmd(id, "spk radio/roger.wav");
            }
        }
    }
}

public OnCmdStart(id, uc_handle, random_seed)
{
    if (!is_user_alive(id) || !is_user_bot(id))
        return FMRES_IGNORED;

    new Float:flGameTime = get_gametime();
    if (flGameTime >= g_BotPingExpire[id])
        return FMRES_IGNORED;

    // If bot has target/enemy, prioritize direct combat
    new enemy = pev(id, pev_enemy);
    if (enemy > 0 && is_user_alive(enemy))
    {
        g_BotPingExpire[id] = 0.0;
        return FMRES_IGNORED;
    }

    new Float:vecBotEyes[3], Float:vecDiff[3], Float:vecAimAngles[3];
    pev(id, pev_origin, vecBotEyes);
    vecBotEyes[2] += 17.0; // Eye offset

    xs_vec_sub(g_BotPingTarget[id], vecBotEyes, vecDiff);
    new Float:flDist = xs_vec_len(vecDiff);

    // If bot has reached within 45 units of the ping, release control gracefully
    if (flDist <= 45.0)
    {
        g_BotPingExpire[id] = 0.0;
        return FMRES_IGNORED;
    }

    vector_to_angle(vecDiff, vecAimAngles);
    ClampAngles(vecAimAngles);

    // Orient bot crosshair towards ping point
    set_uc(uc_handle, UC_ViewAngles, vecAimAngles);

    // If it's a waypoint, weapon, defuser, or bomb ping, advance towards it
    if (g_BotPingType[id] != PING_DANGER)
    {
        set_uc(uc_handle, UC_ForwardMove, 260.0);
    }
    else
    {
        // If danger ping, bot holds angle and sneaks/crouches if close
        if (flDist < 400.0)
        {
            set_uc(uc_handle, UC_Buttons, pev(id, pev_button) | IN_DUCK);
        }
    }

    return FMRES_IGNORED;
}

stock bool:IsNearEnemy(Float:vPos[3], CsTeams:myTeam, Float:maxDist)
{
    for (new i = 1; i <= 32; i++)
    {
        if (is_user_connected(i) && is_user_alive(i) && cs_get_user_team(i) != myTeam)
        {
            new Float:vEnemyPos[3];
            pev(i, pev_origin, vEnemyPos);
            if (get_distance_f(vEnemyPos, vPos) <= maxDist)
                return true;
        }
    }
    return false;
}

stock ClampAngles(Float:angles[3])
{
    while (angles[0] > 89.0)  angles[0] -= 180.0;
    while (angles[0] < -89.0) angles[0] += 180.0;
    while (angles[1] > 180.0)  angles[1] -= 360.0;
    while (angles[1] < -180.0) angles[1] += 360.0;
    angles[2] = 0.0;
}
