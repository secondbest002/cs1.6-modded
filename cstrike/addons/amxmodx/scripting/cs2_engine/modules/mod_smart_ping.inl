// ==============================================================================
// CS2 MODERN ENGINE - SUB-MODULE: 3D CONTEXTUAL SMART PING & SQUAD AI
// 3D raytracing contextual pings (Weapons, C4, Kits, Enemies) with dynamic distance HUD
// ==============================================================================

#if defined _mod_smart_ping_included
    #endinput
#endif
#define _mod_smart_ping_included

// Sound Paths (relative to sound/)
new const ping_SND_PING_NORMAL[] = "cs2_ping/ping_normal.wav";
new const ping_SND_PING_DANGER[] = "cs2_ping/ping_danger.wav";
new const ping_SND_PING_C4[]     = "cs2_ping/ping_c4.wav";

// Sprites
new const ping_SPR_WAYPOINT[] = "sprites/flare3.spr";
new const ping_SPR_DANGER[]   = "sprites/3dmflared.spr";
new const ping_SPR_BOMB[]     = "sprites/glow01.spr";

// Ping Types Enum
enum {
    PING_WAYPOINT = 0,
    PING_DANGER,
    PING_C4,
    PING_WEAPON,
    PING_DEFUSER
};

// CVars
new ping_pCvar_Enable;
new ping_pCvar_Cooldown;
new ping_pCvar_Duration;
new ping_pCvar_BotResponse;
new ping_pCvar_DLight;
new ping_pCvar_HudDistance;

// Player Cooldown Tracking
new Float:ping_LastPingTime[33];

// Active Ping State per player
new bool:ping_Active[33];
new ping_PlayerPingEnt[33];
new ping_PlayerPingType[33];
new Float:ping_Origin[33][3];
new ping_szLabel[33][64];
new CsTeams:ping_Team[33];

// YaPB Bot Squad Reaction State
new Float:ping_BotTarget[33][3];
new Float:ping_BotExpire[33];
new ping_BotType[33];

// HUD Synchronization
new ping_HudSyncPing;

// -------------------------------------------------------------
// Lifecycle Hooks
// -------------------------------------------------------------
public Mod_SmartPing_Init()
{
    ping_pCvar_Enable       = register_cvar("amx_cs2_ping", "1");
    ping_pCvar_Cooldown     = register_cvar("amx_cs2_ping_cooldown", "1.2");
    ping_pCvar_Duration     = register_cvar("amx_cs2_ping_duration", "4.0");
    ping_pCvar_BotResponse   = register_cvar("amx_cs2_ping_bot_ai", "1");
    ping_pCvar_DLight       = register_cvar("amx_cs2_ping_dlight", "1");
    ping_pCvar_HudDistance  = register_cvar("amx_cs2_ping_hud", "1");

    register_clcmd("+ping", "ping_Cmd_PingPoint");
    register_clcmd("-ping", "ping_Cmd_PingRelease");
    register_clcmd("amx_ping", "ping_Cmd_PingPoint");
    register_clcmd("ping_point", "ping_Cmd_PingPoint");

    register_forward(FM_CmdStart, "ping_OnCmdStart");

    ping_HudSyncPing = CreateHudSyncObj();

    set_task(0.25, "ping_Task_UpdatePingHUD", TASK_PING_HUD, _, _, "b");
}

public Mod_SmartPing_Precache()
{
    precache_sound(ping_SND_PING_NORMAL);
    precache_sound(ping_SND_PING_DANGER);
    precache_sound(ping_SND_PING_C4);

    precache_model(ping_SPR_WAYPOINT);
    precache_model(ping_SPR_DANGER);
    precache_model(ping_SPR_BOMB);
}

public Mod_SmartPing_PutInServer(id)
{
    ping_LastPingTime[id] = 0.0;
    ping_Active[id] = false;
    ping_PlayerPingEnt[id] = 0;
    ping_BotExpire[id] = 0.0;
    ping_Team[id] = CS_TEAM_UNASSIGNED;
}

public Mod_SmartPing_Disconnect(id)
{
    ping_RemovePlayerPing(id);
    ping_LastPingTime[id] = 0.0;
    ping_BotExpire[id] = 0.0;
}

public Mod_SmartPing_NewRound()
{
    for (new i = 1; i <= 32; i++)
    {
        ping_RemovePlayerPing(i);
        ping_BotExpire[i] = 0.0;
    }
}

public Mod_SmartPing_RoundEnd()
{
    for (new i = 1; i <= 32; i++)
    {
        ping_RemovePlayerPing(i);
        ping_BotExpire[i] = 0.0;
    }
}

public ping_Cmd_PingRelease(id)
{
    return PLUGIN_HANDLED;
}

public ping_Cmd_PingPoint(id)
{
    if (!get_pcvar_num(pCvar_MasterEnable) || !get_pcvar_num(ping_pCvar_Enable))
        return PLUGIN_CONTINUE;

    if (!is_user_alive(id))
        return PLUGIN_HANDLED;

    new Float:flGameTime = get_gametime();
    new Float:flCooldown = get_pcvar_float(ping_pCvar_Cooldown);

    if (flGameTime - ping_LastPingTime[id] < flCooldown)
        return PLUGIN_HANDLED;

    ping_LastPingTime[id] = flGameTime;

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

    ping_ClassifyPingTarget(id, vHitPos, pHit, pingType, szContextLabel, charsmax(szContextLabel));

    ping_Active[id] = true;
    ping_PlayerPingType[id] = pingType;
    ping_Origin[id][0] = vHitPos[0];
    ping_Origin[id][1] = vHitPos[1];
    ping_Origin[id][2] = vHitPos[2];
    copy(ping_szLabel[id], charsmax(ping_szLabel[]), szContextLabel);
    ping_Team[id] = cs_get_user_team(id);

    ping_CreatePingMarker(id, vHitPos, pingType);
    ping_BroadcastPingFeedback(id, vHitPos, pingType, szContextLabel);

    if (get_pcvar_num(ping_pCvar_BotResponse))
    {
        ping_CommandSquadBots(id, vHitPos, pingType, szContextLabel);
    }

    return PLUGIN_HANDLED;
}

stock ping_ClassifyPingTarget(id, Float:vHitPos[3], pHit, &pingType, szLabel[], maxLen)
{
    new CsTeams:myTeam = cs_get_user_team(id);

    if (pHit > 0 && pev_valid(pHit))
    {
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

        new szClass[32];
        pev(pHit, pev_classname, szClass, charsmax(szClass));

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
                ping_ResolveWeaponNameFromModel(szModel, wpnName, charsmax(wpnName));
                format(szLabel, maxLen, "WEAPON: %s", wpnName);
                return;
            }
        }

        if (equal(szClass, "armoury_entity"))
        {
            pingType = PING_WEAPON;
            new count = 1;
            new itemType = cs_get_armoury_type(pHit, count);
            new wpnName[32];
            ping_ResolveWeaponNameFromId(itemType, wpnName, charsmax(wpnName));
            format(szLabel, maxLen, "WEAPON: %s", wpnName);
            return;
        }

        if (equal(szClass, "item_thighpack"))
        {
            pingType = PING_DEFUSER;
            copy(szLabel, maxLen, "DEFUSE KIT");
            return;
        }

        if (equal(szClass, "weapon_c4"))
        {
            pingType = PING_C4;
            copy(szLabel, maxLen, "C4 EXPLOSIVE");
            return;
        }

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

    new ent = -1;
    while ((ent = engfunc(EngFunc_FindEntityInSphere, ent, vHitPos, 85.0)) > 0)
    {
        if (!pev_valid(ent))
            continue;

        new szClass[32];
        pev(ent, pev_classname, szClass, charsmax(szClass));

        if (ent <= 32 && is_user_connected(ent) && is_user_alive(ent) && cs_get_user_team(ent) != myTeam)
        {
            pingType = PING_DANGER;
            new enemyName[32];
            get_user_name(ent, enemyName, charsmax(enemyName));
            format(szLabel, maxLen, "ENEMY: %s", enemyName);
            return;
        }

        if (equal(szClass, "weapon_c4"))
        {
            pingType = PING_C4;
            copy(szLabel, maxLen, "C4 EXPLOSIVE");
            return;
        }

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

        if (equal(szClass, "item_thighpack"))
        {
            pingType = PING_DEFUSER;
            copy(szLabel, maxLen, "DEFUSE KIT");
            return;
        }

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
                ping_ResolveWeaponNameFromModel(szModel, wpnName, charsmax(wpnName));
                format(szLabel, maxLen, "WEAPON: %s", wpnName);
                return;
            }
        }

        if (equal(szClass, "armoury_entity"))
        {
            pingType = PING_WEAPON;
            new count = 1;
            new itemType = cs_get_armoury_type(ent, count);
            new wpnName[32];
            ping_ResolveWeaponNameFromId(itemType, wpnName, charsmax(wpnName));
            format(szLabel, maxLen, "WEAPON: %s", wpnName);
            return;
        }
    }

    if (ping_IsNearEnemy(vHitPos, myTeam, 150.0))
    {
        pingType = PING_DANGER;
        copy(szLabel, maxLen, "DANGER / ENEMY CONTACT");
        return;
    }

    pingType = PING_WAYPOINT;
    copy(szLabel, maxLen, "TACTICAL WAYPOINT");
}

stock ping_ResolveWeaponNameFromModel(const szModel[], szName[], maxLen)
{
    if (containi(szModel, "ak47") != -1)          copy(szName, maxLen, "AK-47");
    else if (containi(szModel, "m4a1") != -1)     copy(szName, maxLen, "M4A1-S");
    else if (containi(szModel, "m4a4") != -1)     copy(szName, maxLen, "M4A4");
    else if (containi(szModel, "awp") != -1)      copy(szName, maxLen, "AWP");
    else if (containi(szModel, "deagle") != -1)   copy(szName, maxLen, "Desert Eagle");
    else if (containi(szModel, "scout") != -1)    copy(szName, maxLen, "SSG 08 (Scout)");
    else if (containi(szModel, "galil") != -1)    copy(szName, maxLen, "Galil AR");
    else if (containi(szModel, "famas") != -1)    copy(szName, maxLen, "FAMAS");
    else if (containi(szModel, "mp7") != -1)      copy(szName, maxLen, "MP7");
    else if (containi(szModel, "mp5") != -1)      copy(szName, maxLen, "MP5-SD");
    else if (containi(szModel, "bizon") != -1)    copy(szName, maxLen, "PP-Bizon");
    else if (containi(szModel, "ump45") != -1)    copy(szName, maxLen, "UMP-45");
    else if (containi(szModel, "p90") != -1)      copy(szName, maxLen, "P90");
    else if (containi(szModel, "cz75") != -1)     copy(szName, maxLen, "CZ75-Auto");
    else if (containi(szModel, "mac10") != -1)    copy(szName, maxLen, "MAC-10");
    else if (containi(szModel, "tmp") != -1)      copy(szName, maxLen, "MP9 / TMP");
    else if (containi(szModel, "aug") != -1)      copy(szName, maxLen, "AUG");
    else if (containi(szModel, "sg552") != -1)    copy(szName, maxLen, "SG 553");
    else if (containi(szModel, "mag7") != -1)     copy(szName, maxLen, "MAG-7");
    else if (containi(szModel, "xm1014") != -1)   copy(szName, maxLen, "XM1014");
    else if (containi(szModel, "sawedoff") != -1) copy(szName, maxLen, "Sawed-Off");
    else if (containi(szModel, "m3") != -1)       copy(szName, maxLen, "Nova (M3)");
    else if (containi(szModel, "usp") != -1)      copy(szName, maxLen, "USP-S");
    else if (containi(szModel, "glock") != -1)    copy(szName, maxLen, "Glock-18");
    else if (containi(szModel, "elite") != -1)    copy(szName, maxLen, "Dual Berettas");
    else if (containi(szModel, "fiveseven") != -1)copy(szName, maxLen, "Five-SeveN");
    else if (containi(szModel, "tec9") != -1)     copy(szName, maxLen, "Tec-9");
    else if (containi(szModel, "p228") != -1)     copy(szName, maxLen, "P250 / P228");
    else if (containi(szModel, "g3sg1") != -1)    copy(szName, maxLen, "G3SG1");
    else if (containi(szModel, "sg550") != -1)    copy(szName, maxLen, "SCAR-20 / SG550");
    else if (containi(szModel, "negev") != -1)    copy(szName, maxLen, "Negev");
    else if (containi(szModel, "m249") != -1)     copy(szName, maxLen, "M249");
    else if (containi(szModel, "hegrenade") != -1)copy(szName, maxLen, "HE Grenade");
    else if (containi(szModel, "flashbang") != -1)copy(szName, maxLen, "Flashbang");
    else if (containi(szModel, "smokegrenade") != -1) copy(szName, maxLen, "Smoke Grenade");
    else                                          copy(szName, maxLen, "Firearm");
}

stock ping_ResolveWeaponNameFromId(weaponId, szName[], maxLen)
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

stock ping_CreatePingMarker(id, Float:vPos[3], pingType)
{
    ping_RemovePlayerPing(id);

    new ent = engfunc(EngFunc_CreateNamedEntity, engfunc(EngFunc_AllocString, "env_sprite"));
    if (!pev_valid(ent))
        return;

    ping_PlayerPingEnt[id] = ent;
    ping_PlayerPingType[id] = pingType;

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
            engfunc(EngFunc_SetModel, ent, ping_SPR_DANGER);
            set_pev(ent, pev_scale, 0.48);
        }
        case PING_C4:
        {
            engfunc(EngFunc_SetModel, ent, ping_SPR_BOMB);
            set_pev(ent, pev_scale, 0.45);
        }
        case PING_WEAPON, PING_DEFUSER:
        {
            engfunc(EngFunc_SetModel, ent, ping_SPR_WAYPOINT);
            set_pev(ent, pev_scale, 0.38);
        }
        default:
        {
            engfunc(EngFunc_SetModel, ent, ping_SPR_WAYPOINT);
            set_pev(ent, pev_scale, 0.32);
        }
    }

    set_pev(ent, pev_rendermode, kRenderTransAdd);
    set_pev(ent, pev_renderamt, 255.0);
    set_pev(ent, pev_solid, SOLID_NOT);

    if (get_pcvar_num(ping_pCvar_DLight))
    {
        ping_CreateDynamicLight(vPos, pingType);
    }

    new Float:duration = get_pcvar_float(ping_pCvar_Duration);
    if (duration <= 0.0) duration = 4.0;
    set_task(duration, "ping_Task_ExpirePing", TASK_PING_EXPIRE + id);
}

public ping_Task_ExpirePing(taskId)
{
    new id = taskId - TASK_PING_EXPIRE;
    ping_RemovePlayerPing(id);
}

stock ping_RemovePlayerPing(id)
{
    remove_task(TASK_PING_EXPIRE + id);
    if (ping_PlayerPingEnt[id] > 0 && pev_valid(ping_PlayerPingEnt[id]))
    {
        engfunc(EngFunc_RemoveEntity, ping_PlayerPingEnt[id]);
    }
    ping_PlayerPingEnt[id] = 0;
    ping_Active[id] = false;
}

stock ping_CreateDynamicLight(Float:vPos[3], pingType)
{
    message_begin(MSG_BROADCAST, SVC_TEMPENTITY);
    write_byte(TE_DLIGHT);
    write_coord(floatround(vPos[0]));
    write_coord(floatround(vPos[1]));
    write_coord(floatround(vPos[2] + 10.0));
    write_byte(18);

    switch (pingType)
    {
        case PING_DANGER:
        {
            write_byte(255);
            write_byte(30);
            write_byte(30);
        }
        case PING_C4:
        {
            write_byte(255);
            write_byte(120);
            write_byte(0);
        }
        case PING_WEAPON:
        {
            write_byte(40);
            write_byte(255);
            write_byte(80);
        }
        case PING_DEFUSER:
        {
            write_byte(30);
            write_byte(160);
            write_byte(255);
        }
        default:
        {
            write_byte(0);
            write_byte(255);
            write_byte(200);
        }
    }

    write_byte(35);
    write_byte(10);
    message_end();
}

stock ping_BroadcastPingFeedback(id, Float:vPos[3], pingType, const szLabel[])
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
            copy(soundFile, charsmax(soundFile), ping_SND_PING_DANGER);
            format(chatMsg, charsmax(chatMsg), "^x04[Ping]^x03 %s:^x01 ^x02[%s]^x01 (%dm)", userName, szLabel, distMeters);
        }
        case PING_C4:
        {
            copy(soundFile, charsmax(soundFile), ping_SND_PING_C4);
            format(chatMsg, charsmax(chatMsg), "^x04[Ping]^x03 %s:^x01 ^x02[%s]^x01 (%dm)", userName, szLabel, distMeters);
        }
        case PING_WEAPON:
        {
            copy(soundFile, charsmax(soundFile), ping_SND_PING_NORMAL);
            format(chatMsg, charsmax(chatMsg), "^x04[Ping]^x03 %s:^x01 ^x04[%s]^x01 (%dm)", userName, szLabel, distMeters);
        }
        case PING_DEFUSER:
        {
            copy(soundFile, charsmax(soundFile), ping_SND_PING_NORMAL);
            format(chatMsg, charsmax(chatMsg), "^x04[Ping]^x03 %s:^x01 ^x03[%s]^x01 (%dm)", userName, szLabel, distMeters);
        }
        default:
        {
            copy(soundFile, charsmax(soundFile), ping_SND_PING_NORMAL);
            format(chatMsg, charsmax(chatMsg), "^x04[Ping]^x03 %s:^x01 [%s] (%dm)", userName, szLabel, distMeters);
        }
    }

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

public ping_Task_UpdatePingHUD()
{
    if (!get_pcvar_num(pCvar_MasterEnable) || !get_pcvar_num(ping_pCvar_Enable) || !get_pcvar_num(ping_pCvar_HudDistance))
        return;

    for (new viewer = 1; viewer <= 32; viewer++)
    {
        if (!is_user_connected(viewer) || !is_user_alive(viewer) || is_user_bot(viewer))
            continue;

        new CsTeams:viewerTeam = cs_get_user_team(viewer);
        if (viewerTeam != CS_TEAM_T && viewerTeam != CS_TEAM_CT)
            continue;

        new bestPinger = 0;
        new bestPriority = -1;

        for (new pinger = 1; pinger <= 32; pinger++)
        {
            if (ping_Active[pinger] && ping_Team[pinger] == viewerTeam)
            {
                new priority = 1;
                if (ping_PlayerPingType[pinger] == PING_DANGER) priority = 5;
                else if (ping_PlayerPingType[pinger] == PING_C4) priority = 4;
                else if (ping_PlayerPingType[pinger] == PING_WEAPON || ping_PlayerPingType[pinger] == PING_DEFUSER) priority = 3;

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
            new distMeters = floatround(get_distance_f(vViewerOrigin, ping_Origin[bestPinger]) * 0.0254);

            new pingerName[32];
            get_user_name(bestPinger, pingerName, charsmax(pingerName));

            new r = 0, g = 255, b = 200;
            new hudMsg[128];

            switch (ping_PlayerPingType[bestPinger])
            {
                case PING_DANGER:
                {
                    r = 255; g = 50; b = 50;
                    format(hudMsg, charsmax(hudMsg), "[!] DANGER: %s (%dm)^n(%s)", ping_szLabel[bestPinger], distMeters, pingerName);
                }
                case PING_C4:
                {
                    r = 255; g = 140; b = 20;
                    format(hudMsg, charsmax(hudMsg), "[*] BOMB INTEL: %s (%dm)^n(%s)", ping_szLabel[bestPinger], distMeters, pingerName);
                }
                case PING_WEAPON:
                {
                    r = 60; g = 255; b = 90;
                    format(hudMsg, charsmax(hudMsg), "[+] INTEL: %s (%dm)^n(%s)", ping_szLabel[bestPinger], distMeters, pingerName);
                }
                case PING_DEFUSER:
                {
                    r = 40; g = 180; b = 255;
                    format(hudMsg, charsmax(hudMsg), "[+] INTEL: %s (%dm)^n(%s)", ping_szLabel[bestPinger], distMeters, pingerName);
                }
                default:
                {
                    r = 0; g = 230; b = 230;
                    format(hudMsg, charsmax(hudMsg), "[>] WAYPOINT: (%dm)^n(%s)", distMeters, pingerName);
                }
            }

            set_hudmessage(r, g, b, 0.03, 0.38, 0, 0.0, 0.35, 0.05, 0.05);
            ShowSyncHudMsg(viewer, ping_HudSyncPing, "%s", hudMsg);
        }
    }
}

stock ping_GetBotRole(bot)
{
    if (bot < 1 || bot > 32 || !is_user_connected(bot))
        return 0;

    if (callfunc_begin("savage_get_bot_role", "bot_savage_ai.amxx") == 1)
    {
        callfunc_push_int(bot);
        return callfunc_end();
    }
    return 0;
}

stock ping_GetUserPrimary(id)
{
    if (!is_user_alive(id))
        return 0;

    new weapons[32], numWeapons;
    get_user_weapons(id, weapons, numWeapons);
    for (new i = 0; i < numWeapons; i++)
    {
        new w = weapons[i];
        if (w == CSW_AK47 || w == CSW_M4A1 || w == CSW_AWP || w == CSW_SCOUT ||
            w == CSW_GALIL || w == CSW_FAMAS || w == CSW_AUG || w == CSW_SG552 ||
            w == CSW_MP5NAVY || w == CSW_UMP45 || w == CSW_P90 || w == CSW_MAC10 ||
            w == CSW_TMP || w == CSW_XM1014 || w == CSW_M3 || w == CSW_M249 ||
            w == CSW_G3SG1 || w == CSW_SG550)
        {
            return w;
        }
    }
    return 0;
}

stock ping_CommandSquadBots(id, Float:vPos[3], pingType, const szLabel[])
{
    new CsTeams:myTeam = cs_get_user_team(id);
    new Float:flGameTime = get_gametime();

    // =========================================================
    // CASE 1: PING WEAPON - ROLE TARGETED DISPATCH
    // =========================================================
    if (pingType == PING_WEAPON)
    {
        new bool:bIsSniper = (containi(szLabel, "AWP") != -1 || containi(szLabel, "Scout") != -1 || containi(szLabel, "SSG") != -1);

        // A. Pinged weapon is a SNIPER (AWP / Scout)
        if (bIsSniper)
        {
            new iTargetAwper = 0;
            // First check if team's AWPer is alive and needs an AWP!
            for (new bot = 1; bot <= 32; bot++)
            {
                if (is_user_connected(bot) && is_user_alive(bot) && is_user_bot(bot) && cs_get_user_team(bot) == myTeam)
                {
                    if (ping_GetBotRole(bot) == 2) // 2 = ROLE_AWPER
                    {
                        if (ping_GetUserPrimary(bot) != CSW_AWP)
                        {
                            iTargetAwper = bot;
                            break;
                        }
                    }
                }
            }

            if (iTargetAwper > 0)
            {
                new botName[32];
                get_user_name(iTargetAwper, botName, charsmax(botName));

                ping_BotTarget[iTargetAwper][0] = vPos[0];
                ping_BotTarget[iTargetAwper][1] = vPos[1];
                ping_BotTarget[iTargetAwper][2] = vPos[2];
                ping_BotType[iTargetAwper] = PING_WEAPON;
                ping_BotExpire[iTargetAwper] = flGameTime + 6.0;

                client_print(0, print_chat, "^x04[Squad AI]^x03 %s (AWPer):^x01 Roger! Moving to retrieve the sniper rifle!", botName);
                if (!is_user_bot(id)) client_cmd(id, "spk radio/roger.wav");
                return;
            }

            // AWPer already has an AWP, or no AWPer: Check if any teammate bot has NO primary
            new iUnarmedBot = 0;
            new Float:flBestDist = 99999.0;
            for (new bot = 1; bot <= 32; bot++)
            {
                if (is_user_connected(bot) && is_user_alive(bot) && is_user_bot(bot) && cs_get_user_team(bot) == myTeam)
                {
                    if (ping_GetUserPrimary(bot) == 0)
                    {
                        new Float:vBotOrigin[3];
                        pev(bot, pev_origin, vBotOrigin);
                        new Float:flDist = get_distance_f(vBotOrigin, vPos);
                        if (flDist < flBestDist)
                        {
                            flBestDist = flDist;
                            iUnarmedBot = bot;
                        }
                    }
                }
            }

            if (iUnarmedBot > 0)
            {
                new botName[32];
                get_user_name(iUnarmedBot, botName, charsmax(botName));

                ping_BotTarget[iUnarmedBot][0] = vPos[0];
                ping_BotTarget[iUnarmedBot][1] = vPos[1];
                ping_BotTarget[iUnarmedBot][2] = vPos[2];
                ping_BotType[iUnarmedBot] = PING_WEAPON;
                ping_BotExpire[iUnarmedBot] = flGameTime + 5.0;

                client_print(0, print_chat, "^x04[Squad AI]^x03 %s:^x01 Unarmed! Moving to pick up %s!", botName, szLabel);
                if (!is_user_bot(id)) client_cmd(id, "spk radio/roger.wav");
                return;
            }

            // All teammates already have primary weapons: Do NOT send riflemen to abandon their posts!
            new anyBot = 0;
            for (new bot = 1; bot <= 32; bot++)
            {
                if (is_user_connected(bot) && is_user_alive(bot) && is_user_bot(bot) && cs_get_user_team(bot) == myTeam)
                {
                    anyBot = bot;
                    break;
                }
            }
            if (anyBot > 0)
            {
                new botName[32];
                get_user_name(anyBot, botName, charsmax(botName));
                client_print(0, print_chat, "^x04[Squad AI]^x03 %s:^x01 Squad is fully equipped with weapons. Holding angles.", botName);
                if (!is_user_bot(id)) client_cmd(id, "spk radio/roger.wav");
            }
            return;
        }

        // B. Pinged weapon is a RIFLE or other firearm:
        // Dispatch ONLY the bot who has NO primary or inferior weapon (SMG/shotgun/pistol)
        new iBestCandidate = 0;
        new Float:flBestDist = 99999.0;

        // Priority 1: Unarmed bots
        for (new bot = 1; bot <= 32; bot++)
        {
            if (is_user_connected(bot) && is_user_alive(bot) && is_user_bot(bot) && cs_get_user_team(bot) == myTeam)
            {
                if (ping_GetUserPrimary(bot) == 0)
                {
                    new Float:vBotOrigin[3];
                    pev(bot, pev_origin, vBotOrigin);
                    new Float:flDist = get_distance_f(vBotOrigin, vPos);
                    if (flDist < flBestDist)
                    {
                        flBestDist = flDist;
                        iBestCandidate = bot;
                    }
                }
            }
        }

        // Priority 2: Bots with inferior weapon (SMG / Shotgun)
        if (!iBestCandidate)
        {
            for (new bot = 1; bot <= 32; bot++)
            {
                if (is_user_connected(bot) && is_user_alive(bot) && is_user_bot(bot) && cs_get_user_team(bot) == myTeam)
                {
                    new w = ping_GetUserPrimary(bot);
                    if (w == CSW_MP5NAVY || w == CSW_UMP45 || w == CSW_P90 || w == CSW_MAC10 || w == CSW_TMP || w == CSW_XM1014 || w == CSW_M3)
                    {
                        new Float:vBotOrigin[3];
                        pev(bot, pev_origin, vBotOrigin);
                        new Float:flDist = get_distance_f(vBotOrigin, vPos);
                        if (flDist < flBestDist)
                        {
                            flBestDist = flDist;
                            iBestCandidate = bot;
                        }
                    }
                }
            }
        }

        if (iBestCandidate > 0)
        {
            new botName[32];
            get_user_name(iBestCandidate, botName, charsmax(botName));

            ping_BotTarget[iBestCandidate][0] = vPos[0];
            ping_BotTarget[iBestCandidate][1] = vPos[1];
            ping_BotTarget[iBestCandidate][2] = vPos[2];
            ping_BotType[iBestCandidate] = PING_WEAPON;
            ping_BotExpire[iBestCandidate] = flGameTime + 5.0;

            client_print(0, print_chat, "^x04[Squad AI]^x03 %s:^x01 Moving to retrieve %s!", botName, szLabel);
            if (!is_user_bot(id)) client_cmd(id, "spk radio/roger.wav");
            return;
        }

        // All bots already have high-tier rifles: No bot needs to abandon their angle
        new anyBot = 0;
        for (new bot = 1; bot <= 32; bot++)
        {
            if (is_user_connected(bot) && is_user_alive(bot) && is_user_bot(bot) && cs_get_user_team(bot) == myTeam)
            {
                anyBot = bot;
                break;
            }
        }
        if (anyBot > 0)
        {
            new botName[32];
            get_user_name(anyBot, botName, charsmax(botName));
            client_print(0, print_chat, "^x04[Squad AI]^x03 %s:^x01 Squad has top-tier weapons. Maintaining formation.", botName);
            if (!is_user_bot(id)) client_cmd(id, "spk radio/roger.wav");
        }
        return;
    }

    // =========================================================
    // CASE 2: PING DEFUSER (CT only)
    // =========================================================
    if (pingType == PING_DEFUSER)
    {
        new iNearestWithoutKit = 0;
        new Float:flBestDist = 99999.0;

        for (new bot = 1; bot <= 32; bot++)
        {
            if (is_user_connected(bot) && is_user_alive(bot) && is_user_bot(bot) && cs_get_user_team(bot) == myTeam)
            {
                if (!cs_get_user_defuse(bot))
                {
                    new Float:vBotOrigin[3];
                    pev(bot, pev_origin, vBotOrigin);
                    new Float:flDist = get_distance_f(vBotOrigin, vPos);
                    if (flDist < flBestDist)
                    {
                        flBestDist = flDist;
                        iNearestWithoutKit = bot;
                    }
                }
            }
        }

        if (iNearestWithoutKit > 0)
        {
            new botName[32];
            get_user_name(iNearestWithoutKit, botName, charsmax(botName));

            ping_BotTarget[iNearestWithoutKit][0] = vPos[0];
            ping_BotTarget[iNearestWithoutKit][1] = vPos[1];
            ping_BotTarget[iNearestWithoutKit][2] = vPos[2];
            ping_BotType[iNearestWithoutKit] = PING_DEFUSER;
            ping_BotExpire[iNearestWithoutKit] = flGameTime + 4.5;

            client_print(0, print_chat, "^x04[Squad AI]^x03 %s:^x01 Roger that, picking up defuse kit!", botName);
            if (!is_user_bot(id)) client_cmd(id, "spk radio/roger.wav");
        }
        return;
    }

    // =========================================================
    // CASE 3: DANGER, C4, OR WAYPOINT (Tactical coordination)
    // =========================================================
    new responderBot = 0;
    new Float:bestDist = 99999.0;

    for (new bot = 1; bot <= 32; bot++)
    {
        if (is_user_connected(bot) && is_user_alive(bot) && is_user_bot(bot) && cs_get_user_team(bot) == myTeam)
        {
            new Float:vBotOrigin[3];
            pev(bot, pev_origin, vBotOrigin);
            new Float:flDist = get_distance_f(vBotOrigin, vPos);

            if (flDist <= 3000.0)
            {
                ping_BotTarget[bot][0] = vPos[0];
                ping_BotTarget[bot][1] = vPos[1];
                ping_BotTarget[bot][2] = vPos[2];
                ping_BotType[bot] = pingType;

                ping_BotExpire[bot] = flGameTime + ((pingType == PING_DANGER) ? 3.5 : 4.5);

                if (flDist < bestDist)
                {
                    bestDist = flDist;
                    responderBot = bot;
                }
            }
        }
    }

    if (responderBot > 0)
    {
        new botName[32];
        get_user_name(responderBot, botName, charsmax(botName));

        switch (pingType)
        {
            case PING_DANGER:
            {
                client_print(0, print_chat, "^x04[Squad AI]^x03 %s:^x01 Threat identified! Pre-aiming and covering angle!", botName);
                if (!is_user_bot(id)) client_cmd(id, "spk radio/roger.wav");
            }
            case PING_C4:
            {
                if (myTeam == CS_TEAM_CT)
                {
                    client_print(0, print_chat, "^x04[Squad AI]^x03 %s:^x01 Bomb located! Moving to secure the bomb!", botName);
                    if (!is_user_bot(id)) client_cmd(id, "spk radio/go.wav");
                }
                else
                {
                    client_print(0, print_chat, "^x04[Squad AI]^x03 %s:^x01 Securing C4 bomb perimeter!", botName);
                    if (!is_user_bot(id)) client_cmd(id, "spk radio/locknload.wav");
                }
            }
            default:
            {
                client_print(0, print_chat, "^x04[Squad AI]^x03 %s:^x01 Copy, moving to investigate marked area.", botName);
                if (!is_user_bot(id)) client_cmd(id, "spk radio/roger.wav");
            }
        }
    }
}

public ping_OnCmdStart(id, uc_handle, random_seed)
{
    if (!get_pcvar_num(pCvar_MasterEnable) || !get_pcvar_num(ping_pCvar_Enable))
        return FMRES_IGNORED;

    if (!is_user_alive(id) || !is_user_bot(id))
        return FMRES_IGNORED;

    new Float:flGameTime = get_gametime();
    if (flGameTime >= ping_BotExpire[id])
        return FMRES_IGNORED;

    new enemy = pev(id, pev_enemy);
    if (enemy > 0 && is_user_alive(enemy))
    {
        ping_BotExpire[id] = 0.0;
        return FMRES_IGNORED;
    }

    new Float:vecBotEyes[3], Float:vecDiff[3], Float:vecAimAngles[3];
    pev(id, pev_origin, vecBotEyes);
    vecBotEyes[2] += 17.0;

    xs_vec_sub(ping_BotTarget[id], vecBotEyes, vecDiff);
    new Float:flDist = xs_vec_len(vecDiff);

    if (flDist <= 45.0)
    {
        ping_BotExpire[id] = 0.0;
        return FMRES_IGNORED;
    }

    vector_to_angle(vecDiff, vecAimAngles);
    ping_ClampAngles(vecAimAngles);

    set_uc(uc_handle, UC_ViewAngles, vecAimAngles);

    if (ping_BotType[id] != PING_DANGER)
    {
        set_uc(uc_handle, UC_ForwardMove, 260.0);
    }
    else
    {
        if (flDist < 400.0)
        {
            set_uc(uc_handle, UC_Buttons, pev(id, pev_button) | IN_DUCK);
        }
    }

    return FMRES_IGNORED;
}

stock bool:ping_IsNearEnemy(Float:vPos[3], CsTeams:myTeam, Float:maxDist)
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

stock ping_ClampAngles(Float:angles[3])
{
    while (angles[0] > 89.0)  angles[0] -= 180.0;
    while (angles[0] < -89.0) angles[0] += 180.0;
    while (angles[1] > 180.0)  angles[1] -= 360.0;
    while (angles[1] < -180.0) angles[1] += 360.0;
    angles[2] = 0.0;
}
