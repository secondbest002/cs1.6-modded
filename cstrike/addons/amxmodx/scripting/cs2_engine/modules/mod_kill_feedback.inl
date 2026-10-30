// ==============================================================================
// CS2 MODERN ENGINE - SUB-MODULE: KILL FEEDBACK & ACE SYSTEM
// Chimes 1K-5K ACE, Headshot Dink Sound, Skull Cards HUD, C4 10s Warning Music
// ==============================================================================

#if defined _mod_kill_feedback_included
    #endinput
#endif
#define _mod_kill_feedback_included

// Sound Paths (relative to sound/)
new const kf_SND_KILL1[]     = "cs2_kill/kill1.wav";
new const kf_SND_KILL2[]     = "cs2_kill/kill2.wav";
new const kf_SND_KILL3[]     = "cs2_kill/kill3.wav";
new const kf_SND_KILL4[]     = "cs2_kill/kill4.wav";
new const kf_SND_KILL5_ACE[] = "cs2_kill/kill5_ace.wav";
new const kf_SND_DINK[]      = "cs2_kill/headshot_dink.wav";
new const kf_SND_C4_WARN[]   = "cs2_kill/c4_10sec_warning.wav";

// CVars
new kf_pCvar_KillChimes;
new kf_pCvar_HeadshotDink;
new kf_pCvar_C4Warning;
new kf_pCvar_HudCards;

// Player Tracking (per round)
new kf_RoundKills[33];
new Float:kf_LastDinkTime[33];

// Bomb Tracking
new bool:kf_BombPlanted = false;

// HUD Sync Object
new kf_HudSyncCards;

// -------------------------------------------------------------
// Lifecycle Hooks
// -------------------------------------------------------------
public Mod_KillFeedback_Init()
{
    // CVars
    kf_pCvar_KillChimes  = register_cvar("amx_cs2_kill_chimes", "1");
    kf_pCvar_HeadshotDink = register_cvar("amx_cs2_headshot_dink", "1");
    kf_pCvar_C4Warning   = register_cvar("amx_cs2_c4_warning", "1");
    kf_pCvar_HudCards    = register_cvar("amx_cs2_hud_cards", "1");

    // Events
    register_logevent("kf_Event_BombPlanted", 3, "2=Planted_The_Bomb");
    register_logevent("kf_Event_BombDefused", 3, "2=Defused_The_Bomb");
    register_logevent("kf_Event_BombExploded", 3, "2=Target_Bombed");
    register_logevent("kf_Event_BombExploded", 2, "1=Target_Bombed");

    // Ham Hooks
    RegisterHam(Ham_Killed, "player", "kf_OnPlayerKilledPost", 1);
    RegisterHam(Ham_TraceAttack, "player", "kf_OnPlayerTraceAttack");

    // HUD Sync
    kf_HudSyncCards = CreateHudSyncObj();
}

public Mod_KillFeedback_Precache()
{
    precache_sound(kf_SND_KILL1);
    precache_sound(kf_SND_KILL2);
    precache_sound(kf_SND_KILL3);
    precache_sound(kf_SND_KILL4);
    precache_sound(kf_SND_KILL5_ACE);
    precache_sound(kf_SND_DINK);
    precache_sound(kf_SND_C4_WARN);
}

public Mod_KillFeedback_PutInServer(id)
{
    kf_RoundKills[id] = 0;
    kf_LastDinkTime[id] = 0.0;
}

public Mod_KillFeedback_Disconnect(id)
{
    kf_RoundKills[id] = 0;
    kf_LastDinkTime[id] = 0.0;
    remove_task(TASK_KF_HUD_CLEAR + id);
}

public Mod_KillFeedback_NewRound()
{
    kf_BombPlanted = false;
    remove_task(TASK_KF_C4_10SEC);

    for (new i = 1; i <= 32; i++)
    {
        kf_RoundKills[i] = 0;
        remove_task(TASK_KF_HUD_CLEAR + i);
    }
}

public Mod_KillFeedback_RoundEnd()
{
    kf_BombPlanted = false;
    remove_task(TASK_KF_C4_10SEC);
}

// -------------------------------------------------------------
// Headshot Dink Sound
// -------------------------------------------------------------
public kf_OnPlayerTraceAttack(victim, attacker, Float:damage, Float:direction[3], traceresult, damagebits)
{
    if (!get_pcvar_num(pCvar_MasterEnable) || !get_pcvar_num(kf_pCvar_HeadshotDink))
        return HAM_IGNORED;

    if (!is_user_connected(attacker) || !is_user_alive(attacker))
        return HAM_IGNORED;

    if (attacker == victim)
        return HAM_IGNORED;

    if (cs_get_user_team(attacker) == cs_get_user_team(victim))
        return HAM_IGNORED;

    new hitgroup = get_tr2(traceresult, TR_iHitgroup);
    if (hitgroup == HIT_HEAD)
    {
        new Float:game_time = get_gametime();
        if (game_time - kf_LastDinkTime[attacker] > 0.08)
        {
            kf_LastDinkTime[attacker] = game_time;
            client_cmd(attacker, "spk %s", kf_SND_DINK);
        }
    }

    return HAM_IGNORED;
}

// -------------------------------------------------------------
// Kill Streak & Progressive Chimes + HUD Cards
// -------------------------------------------------------------
public kf_OnPlayerKilledPost(victim, attacker, shouldgib)
{
    if (!get_pcvar_num(pCvar_MasterEnable))
        return HAM_IGNORED;

    if (!is_user_connected(attacker) || !is_user_alive(attacker))
        return HAM_IGNORED;

    if (attacker == victim)
        return HAM_IGNORED;

    if (cs_get_user_team(attacker) == cs_get_user_team(victim))
        return HAM_IGNORED;

    kf_RoundKills[attacker]++;
    new kills = kf_RoundKills[attacker];

    // CS2 Kill Chimes Sound
    if (get_pcvar_num(kf_pCvar_KillChimes))
    {
        switch (kills)
        {
            case 1: client_cmd(attacker, "spk %s", kf_SND_KILL1);
            case 2: client_cmd(attacker, "spk %s", kf_SND_KILL2);
            case 3: client_cmd(attacker, "spk %s", kf_SND_KILL3);
            case 4: client_cmd(attacker, "spk %s", kf_SND_KILL4);
            default:
            {
                client_cmd(attacker, "spk %s", kf_SND_KILL5_ACE);
                new attacker_name[32];
                get_user_name(attacker, attacker_name, charsmax(attacker_name));
                client_print(0, print_chat, "[CS2] ★★★ ACE! %s eliminated the entire enemy squad! ★★★", attacker_name);
            }
        }
    }

    // CS2 HUD Skull Cards
    if (get_pcvar_num(kf_pCvar_HudCards))
    {
        kf_ShowCs2KillCards(attacker, kills);
    }

    return HAM_IGNORED;
}

stock kf_ShowCs2KillCards(id, kills)
{
    if (!is_user_connected(id))
        return;

    new card_text[128];

    switch (kills)
    {
        case 1:
        {
            set_hudmessage(255, 180, 40, -1.0, 0.82, 0, 0.05, 3.5, 0.1, 0.2);
            format(card_text, charsmax(card_text), "[ 1K ]  [ -- ]  [ -- ]  [ -- ]  [ -- ]");
        }
        case 2:
        {
            set_hudmessage(255, 170, 30, -1.0, 0.82, 0, 0.05, 3.5, 0.1, 0.2);
            format(card_text, charsmax(card_text), "[ 1K ]  [ 2K ]  [ -- ]  [ -- ]  [ -- ]");
        }
        case 3:
        {
            set_hudmessage(255, 140, 20, -1.0, 0.82, 0, 0.05, 3.5, 0.1, 0.2);
            format(card_text, charsmax(card_text), "[ 1K ]  [ 2K ]  [ 3K ]  [ -- ]  [ -- ]");
        }
        case 4:
        {
            set_hudmessage(255, 90, 20, -1.0, 0.82, 0, 0.05, 4.0, 0.1, 0.2);
            format(card_text, charsmax(card_text), "[ 1K ]  [ 2K ]  [ 3K ]  [ 4K ]  [ -- ]^n-- ONE ENEMY REMAINING --");
        }
        default:
        {
            set_hudmessage(255, 40, 40, -1.0, 0.80, 1, 0.05, 5.0, 0.1, 0.3);
            format(card_text, charsmax(card_text), "★ ★ ★  A C E  ★ ★ ★^n[ 1K ]  [ 2K ]  [ 3K ]  [ 4K ]  [ 5K ]");
        }
    }

    ShowSyncHudMsg(id, kf_HudSyncCards, "%s", card_text);
}

// -------------------------------------------------------------
// CS:GO / CS2 10-Second Bomb Warning Music
// -------------------------------------------------------------
public kf_Event_BombPlanted()
{
    if (!get_pcvar_num(pCvar_MasterEnable))
        return;

    new pCvarWarmup = get_cvar_pointer("amx_csgo_is_warmup");
    if (pCvarWarmup && get_pcvar_num(pCvarWarmup) == 1)
        return;

    kf_BombPlanted = true;

    if (!get_pcvar_num(kf_pCvar_C4Warning))
        return;

    new c4_time = get_cvar_num("mp_c4timer");
    if (c4_time <= 0) c4_time = 40;

    new Float:delay_to_10s = float(c4_time) - 10.0;
    if (delay_to_10s > 0.0)
    {
        remove_task(TASK_KF_C4_10SEC);
        set_task(delay_to_10s, "kf_Task_Play10SecWarning", TASK_KF_C4_10SEC);
    }
}

public kf_Task_Play10SecWarning()
{
    if (!kf_BombPlanted || !get_pcvar_num(pCvar_MasterEnable))
        return;

    client_cmd(0, "spk %s", kf_SND_C4_WARN);

    for (new i = 1; i <= 32; i++)
    {
        if (is_user_connected(i) && is_user_alive(i))
        {
            new CsTeams:team = cs_get_user_team(i);
            if (team == CS_TEAM_CT)
            {
                new has_kit = cs_get_user_defuse(i);
                if (has_kit)
                {
                    client_print(i, print_center, "[!] 10 SECONDS LEFT - DEFUSE NOW (DEFUSE KIT: 5s) [!]");
                }
                else
                {
                    client_print(i, print_center, "[!] 10 SECONDS LEFT - NO KIT! MUST DEFUSE IMMEDIATELY [!]");
                }
            }
            else if (team == CS_TEAM_T)
            {
                client_print(i, print_center, "[!] 10 SECONDS TO DETONATION - GUARD THE C4! [!]");
            }
        }
    }
}

public kf_Event_BombDefused()
{
    kf_BombPlanted = false;
    remove_task(TASK_KF_C4_10SEC);
    client_cmd(0, "stopsound");
}

public kf_Event_BombExploded()
{
    kf_BombPlanted = false;
    remove_task(TASK_KF_C4_10SEC);
    client_cmd(0, "stopsound");
}
