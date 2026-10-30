#include <amxmodx>
#include <amxmisc>
#include <cstrike>
#include <fakemeta>
#include <hamsandwich>

#define PLUGIN  "CS2 Kill Audio & Visual Feedback"
#define VERSION "1.0.0"
#define AUTHOR  "Antigravity"

// Sound Paths (relative to sound/)
new const SND_KILL1[]      = "cs2_kill/kill1.wav";
new const SND_KILL2[]      = "cs2_kill/kill2.wav";
new const SND_KILL3[]      = "cs2_kill/kill3.wav";
new const SND_KILL4[]      = "cs2_kill/kill4.wav";
new const SND_KILL5_ACE[]  = "cs2_kill/kill5_ace.wav";
new const SND_DINK[]       = "cs2_kill/headshot_dink.wav";
new const SND_C4_WARN[]    = "cs2_kill/c4_10sec_warning.wav";

// Cvars
new pCvar_KillChimes;
new pCvar_HeadshotDink;
new pCvar_C4Warning;
new pCvar_HudCards;

// Player Tracking (per round)
new g_RoundKills[33];
new Float:g_LastDinkTime[33];

// Bomb Tracking
new bool:g_BombPlanted = false;

// HUD Sync Object
new g_HudSyncCards;

// Task IDs
#define TASK_C4_10SEC 4201
#define TASK_HUD_CLEAR 4300

public plugin_init()
{
    register_plugin(PLUGIN, VERSION, AUTHOR);

    // Cvars
    pCvar_KillChimes   = register_cvar("amx_cs2_kill_chimes", "1");
    pCvar_HeadshotDink  = register_cvar("amx_cs2_headshot_dink", "1");
    pCvar_C4Warning    = register_cvar("amx_cs2_c4_warning", "1");
    pCvar_HudCards     = register_cvar("amx_cs2_hud_cards", "1");

    // Events
    register_event("HLTV", "Event_NewRound", "a", "1=0", "2=0");
    register_logevent("Event_RoundEnd", 2, "1=Round_End");
    register_logevent("Event_BombPlanted", 3, "2=Planted_The_Bomb");
    register_logevent("Event_BombDefused", 3, "2=Defused_The_Bomb");
    register_logevent("Event_BombExploded", 3, "2=Target_Bombed");
    register_logevent("Event_BombExploded", 2, "1=Target_Bombed");

    // Ham Hooks
    RegisterHam(Ham_Killed, "player", "OnPlayerKilledPost", 1);
    RegisterHam(Ham_TraceAttack, "player", "OnPlayerTraceAttack");

    // HUD Sync
    g_HudSyncCards = CreateHudSyncObj();
}

public plugin_precache()
{
    precache_sound(SND_KILL1);
    precache_sound(SND_KILL2);
    precache_sound(SND_KILL3);
    precache_sound(SND_KILL4);
    precache_sound(SND_KILL5_ACE);
    precache_sound(SND_DINK);
    precache_sound(SND_C4_WARN);
}

public client_putinserver(id)
{
    g_RoundKills[id] = 0;
    g_LastDinkTime[id] = 0.0;
}

public client_disconnected(id)
{
    g_RoundKills[id] = 0;
    g_LastDinkTime[id] = 0.0;
    remove_task(TASK_HUD_CLEAR + id);
}

public Event_NewRound()
{
    g_BombPlanted = false;
    remove_task(TASK_C4_10SEC);

    for (new i = 1; i <= 32; i++)
    {
        g_RoundKills[i] = 0;
        remove_task(TASK_HUD_CLEAR + i);
    }
}

public Event_RoundEnd()
{
    g_BombPlanted = false;
    remove_task(TASK_C4_10SEC);
}

// ===================================================================
// HEADSHOT DINK
// ===================================================================
public OnPlayerTraceAttack(victim, attacker, Float:damage, Float:direction[3], traceresult, damagebits)
{
    if (!get_pcvar_num(pCvar_HeadshotDink))
        return HAM_IGNORED;

    if (!is_user_connected(attacker) || !is_user_alive(attacker))
        return HAM_IGNORED;

    if (attacker == victim)
        return HAM_IGNORED;

    if (cs_get_user_team(attacker) == cs_get_user_team(victim))
        return HAM_IGNORED;

    // Hitbox check: HIT_HEAD = 1
    new hitgroup = get_tr2(traceresult, TR_iHitgroup);
    if (hitgroup == HIT_HEAD)
    {
        new Float:game_time = get_gametime();
        // Debounce 0.08s to avoid ear damage on shotgun spreads
        if (game_time - g_LastDinkTime[attacker] > 0.08)
        {
            g_LastDinkTime[attacker] = game_time;
            // Play directly to attacker
            client_cmd(attacker, "spk %s", SND_DINK);
        }
    }

    return HAM_IGNORED;
}

// ===================================================================
// KILL STREAK & PROGRESSIVE CHIMES + HUD CARDS
// ===================================================================
public OnPlayerKilledPost(victim, attacker, shouldgib)
{
    if (!is_user_connected(attacker) || !is_user_alive(attacker))
        return HAM_IGNORED;

    if (attacker == victim)
        return HAM_IGNORED;

    if (cs_get_user_team(attacker) == cs_get_user_team(victim))
        return HAM_IGNORED;

    g_RoundKills[attacker]++;
    new kills = g_RoundKills[attacker];

    // CS2 Kill Chimes Sound
    if (get_pcvar_num(pCvar_KillChimes))
    {
        switch (kills)
        {
            case 1: client_cmd(attacker, "spk %s", SND_KILL1);
            case 2: client_cmd(attacker, "spk %s", SND_KILL2);
            case 3: client_cmd(attacker, "spk %s", SND_KILL3);
            case 4: client_cmd(attacker, "spk %s", SND_KILL4);
            default:
            {
                // 5 or more kills: ACE!
                client_cmd(attacker, "spk %s", SND_KILL5_ACE);
                // Also notify whole server on ACE
                new attacker_name[32];
                get_user_name(attacker, attacker_name, charsmax(attacker_name));
                client_print(0, print_chat, "[CS2] ★★★ ACE! %s eliminated the entire enemy squad! ★★★", attacker_name);
            }
        }
    }

    // CS2 HUD Skull Cards
    if (get_pcvar_num(pCvar_HudCards))
    {
        ShowCs2KillCards(attacker, kills);
    }

    return HAM_IGNORED;
}

ShowCs2KillCards(id, kills)
{
    if (!is_user_connected(id))
        return;

    new card_text[128];

    switch (kills)
    {
        case 1:
        {
            // Orange/Gold Card
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
            // ACE: Bright crimson-gold flashing
            set_hudmessage(255, 40, 40, -1.0, 0.80, 1, 0.05, 5.0, 0.1, 0.3);
            format(card_text, charsmax(card_text), "★ ★ ★  A C E  ★ ★ ★^n[ 1K ]  [ 2K ]  [ 3K ]  [ 4K ]  [ 5K ]");
        }
    }

    ShowSyncHudMsg(id, g_HudSyncCards, "%s", card_text);
}

// ===================================================================
// CS:GO / CS2 10-SECOND BOMB WARNING MUSIC
// ===================================================================
public Event_BombPlanted()
{
    new pCvarWarmup = get_cvar_pointer("amx_csgo_is_warmup");
    if (pCvarWarmup && get_pcvar_num(pCvarWarmup) == 1)
        return;

    g_BombPlanted = true;

    if (!get_pcvar_num(pCvar_C4Warning))
        return;

    new c4_time = get_cvar_num("mp_c4timer");
    if (c4_time <= 0) c4_time = 40;

    // Schedule 10-second warning
    new Float:delay_to_10s = float(c4_time) - 10.0;
    if (delay_to_10s > 0.0)
    {
        remove_task(TASK_C4_10SEC);
        set_task(delay_to_10s, "Task_Play10SecWarning", TASK_C4_10SEC);
    }
}

public Task_Play10SecWarning()
{
    if (!g_BombPlanted)
        return;

    // Broadcast 10-sec warning music to all players
    client_cmd(0, "spk %s", SND_C4_WARN);

    // Show warning HUD message
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

public Event_BombDefused()
{
    g_BombPlanted = false;
    remove_task(TASK_C4_10SEC);
    client_cmd(0, "stopsound");
}

public Event_BombExploded()
{
    g_BombPlanted = false;
    remove_task(TASK_C4_10SEC);
    client_cmd(0, "stopsound");
}
