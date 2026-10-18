#include <amxmodx>
#include <amxmisc>
#include <cstrike>
#include <fakemeta>
#include <hamsandwich>
#include <fun>

#define PLUGIN  "CS:GO Competitive Match Mod"
#define VERSION "1.1.0"
#define AUTHOR  "Antigravity"

#define TASK_HUD         1001
#define TASK_COUNTDOWN   1002
#define TASK_RESPAWN     1100
#define TASK_TIMEOUT     1200
#define TASK_SIDE_PICK   1300
#define TASK_MATCH_END   1400

enum {
    STATE_WARMUP = 0,
    STATE_COUNTDOWN,
    STATE_KNIFE_ROUND,
    STATE_SIDE_PICK,
    STATE_LIVE_HALF_1,
    STATE_HALFTIME,
    STATE_LIVE_HALF_2,
    STATE_OVERTIME_1,
    STATE_OVERTIME_HALFTIME,
    STATE_OVERTIME_2,
    STATE_FINISHED
};

new g_MatchState = STATE_WARMUP;

// Match Scores & Rounds
new g_ScoreCT = 0;
new g_ScoreT = 0;
new g_RoundNumber = 0;
new g_MaxRoundsHalf = 12; // MR12 default
new g_TargetWinScore = 13; // First to 13 wins

// Overtime
new g_OTRoundNumber = 0;
new g_OTMaxRoundsHalf = 3; // MR3 Overtime
new g_OTTargetWinScore = 16;

// Knife Round
new CsTeams:g_KnifeWinner = CS_TEAM_UNASSIGNED;
new g_KnifeChooserId = 0;
new g_SidePickTimer = 15;

// Player Ready State
new bool:g_PlayerReady[33];
new g_CountdownTimer = 5;

// Tactical Timeout
new g_TimeoutsCT = 0;
new g_TimeoutsT = 0;
new bool:g_TimeoutQueuedCT = false;
new bool:g_TimeoutQueuedT = false;
new bool:g_IsTimeoutActive = false;
new g_TimeoutRemaining = 0;
new CsTeams:g_TimeoutTeam = CS_TEAM_UNASSIGNED;

// Damage Tracking (Current Round)
new g_DamageDealt[33][33];
new g_HitsDealt[33][33];

// MVP Tracking
new g_KillsInRound[33];
new g_BombPlanter = 0;
new g_BombDefuser = 0;

// CS:GO Loss Bonus Ladder (Levels 0..4)
// Level 0 = $1400, Level 1 = $1900, Level 2 = $2400, Level 3 = $2900, Level 4 = $3400
new g_LossStreakCT = 0;
new g_LossStreakT = 0;

// Cvars
new pCvar_Mode;
new pCvar_MaxRounds;
new pCvar_KnifeRound;
new pCvar_Warmup;
new pCvar_Timeouts;
new pCvar_TimeoutDuration;
new pCvar_OTMoney;
new pCvar_BotAutoReady;
new pCvar_LossBonus;
new pCvar_HudStyle;
new pCvar_MvpCard;
new pCvar_C4Timer;
new pCvar_ScreenFade;
new pCvar_DmgCard;

// Multiple HUD Sync Channels
new g_HudSyncHeader;
new g_HudSyncSubHeader;
new g_HudSyncDamage;

// C4 Plant Tracker
new bool:g_BombPlanted = false;
new Float:g_BombPlantedTime = 0.0;
new g_C4TimerCvar = 40;

// ScreenFade Engine Constants
#define FFADE_IN         0x0000
#define FFADE_OUT        0x0001
#define FFADE_MODULATE   0x0002
#define FFADE_STAYOUT    0x0004

// All buy aliases and equipment commands in Counter-Strike 1.6
new const g_BuyCommands[][] = {
    "buy", "buyequip", "cl_autobuy", "cl_rebuy", "cl_setautobuy", "cl_setrebuy",
    "rebuy", "autobuy", "buyammo1", "buyammo2", "primammo", "secammo",
    // Pistols
    "glock", "usp", "p228", "deagle", "elites", "fn57",
    // Shotguns
    "m3", "xm1014",
    // SMGs
    "mac10", "tmp", "mp5", "ump45", "p90",
    // Rifles
    "galil", "famas", "ak47", "m4a1", "sg552", "aug", "scout", "awp", "g3sg1", "sg550",
    // Machine Gun
    "m249",
    // Equipment & Grenades
    "vest", "vesthelm", "flash", "hegren", "sgren", "defuser", "nvgs", "shield"
};

public plugin_init()
{
    register_plugin(PLUGIN, VERSION, AUTHOR);

    // Cvars
    pCvar_Mode            = register_cvar("amx_csgo_mode", "1");
    pCvar_MaxRounds       = register_cvar("amx_csgo_maxrounds", "12"); // MR12 (halftime at 12, win at 13)
    pCvar_KnifeRound      = register_cvar("amx_csgo_kniferound", "1");
    pCvar_Warmup          = register_cvar("amx_csgo_warmup", "1");
    pCvar_Timeouts        = register_cvar("amx_csgo_timeouts", "1"); // 1 timeout per team per half
    pCvar_TimeoutDuration = register_cvar("amx_csgo_timeout_duration", "60"); // 60 seconds
    pCvar_OTMoney         = register_cvar("amx_csgo_ot_money", "10000"); // Start money in OT
    pCvar_BotAutoReady    = register_cvar("amx_csgo_bot_autoready", "1"); // Bots ready automatically with humans
    pCvar_LossBonus       = register_cvar("amx_csgo_lossbonus", "1"); // CS:GO loss bonus decrement rule
    pCvar_HudStyle        = register_cvar("amx_csgo_hud_style", "1"); // 1 = CS:GO Modern Header, 0 = Classic Simple
    pCvar_MvpCard         = register_cvar("amx_csgo_mvp_card", "1"); // 1 = Show Center MVP Card, 0 = Chat only
    pCvar_C4Timer         = register_cvar("amx_csgo_c4_timer", "1"); // 1 = Show C4 Countdown in Top Bar, 0 = Disabled
    pCvar_ScreenFade      = register_cvar("amx_csgo_screenfade", "1"); // 1 = Enable cinematic screenfade transitions
    pCvar_DmgCard         = register_cvar("amx_csgo_dmg_card", "1"); // 1 = Show on-screen damage report card

    // Chat Commands
    register_clcmd("say", "HandleSay");
    register_clcmd("say_team", "HandleSay");

    // Buy & drop blocking during knife round (All aliases + grenades)
    for (new i = 0; i < sizeof(g_BuyCommands); i++)
    {
        register_clcmd(g_BuyCommands[i], "BlockBuyCmd");
    }
    register_clcmd("drop", "BlockDropCmd");

    // Admin Commands
    register_concmd("amx_csgo_start", "AdminCmd_StartMatch", ADMIN_CFG, "- Force start live match");
    register_concmd("amx_csgo_warmup", "AdminCmd_RestartWarmup", ADMIN_CFG, "- Return to warmup");

    // Ham Hooks
    RegisterHam(Ham_Spawn, "player", "OnPlayerSpawnPost", 1);
    RegisterHam(Ham_Killed, "player", "OnPlayerKilledPost", 1);
    RegisterHam(Ham_TakeDamage, "player", "OnTakeDamagePost", 1);
    RegisterHam(Ham_Touch, "weaponbox", "OnWeaponTouchPre");
    RegisterHam(Ham_Touch, "armoury_entity", "OnWeaponTouchPre");
    RegisterHam(Ham_Touch, "weapon_shield", "OnWeaponTouchPre");

    // Game Events
    register_event("CurWeapon", "Event_CurWeapon", "be", "1=1");
    register_event("SendAudio", "Event_TWin", "a", "2=%!MRAD_terwin");
    register_event("SendAudio", "Event_CTWin", "a", "2=%!MRAD_ctwin");
    register_event("SendAudio", "Event_RoundDraw", "a", "2=%!MRAD_rounddraw");
    register_logevent("LogEvent_RoundStart", 2, "1=Round_Start");
    register_logevent("LogEvent_RoundEnd", 2, "1=Round_End");
    register_logevent("LogEvent_Plant", 3, "2=Planted_The_Bomb");
    register_logevent("LogEvent_Defuse", 3, "2=Defused_The_Bomb");
    register_logevent("LogEvent_TargetBombed", 6, "3=Target_Bombed");

    // Multiple HUD Channels
    g_HudSyncHeader    = CreateHudSyncObj();
    g_HudSyncSubHeader = CreateHudSyncObj();
    g_HudSyncDamage    = CreateHudSyncObj();

    // Start HUD Task
    set_task(1.0, "Task_UpdateHUD", TASK_HUD, _, _, "b");

    server_print("[CS:GO Competitive] Plugin v%s initialized successfully.", VERSION);
}

public plugin_cfg()
{
    new config_file[128];
    get_configsdir(config_file, charsmax(config_file));
    format(config_file, charsmax(config_file), "%s/csgo_competitive.cfg", config_file);

    if (file_exists(config_file))
    {
        server_cmd("exec %s", config_file);
        server_exec();
    }

    g_MaxRoundsHalf = get_pcvar_num(pCvar_MaxRounds);
    if (g_MaxRoundsHalf < 1) g_MaxRoundsHalf = 12;
    g_TargetWinScore = g_MaxRoundsHalf + 1;

    ResetToWarmup();
}

public client_putinserver(id)
{
    g_PlayerReady[id] = false;
    ResetPlayerDamage(id);
}

public client_disconnected(id)
{
    g_PlayerReady[id] = false;
    ResetPlayerDamage(id);
    remove_task(id + TASK_RESPAWN);
}

// ========================================================================
// ADMIN COMMANDS
// ========================================================================
public AdminCmd_StartMatch(id, level, cid)
{
    if (!cmd_access(id, level, cid, 1))
        return PLUGIN_HANDLED;

    client_print(0, print_chat, "^x04[CS:GO Match] Admin force-started the match!");
    remove_task(TASK_COUNTDOWN);
    StartLiveMatch();
    return PLUGIN_HANDLED;
}

public AdminCmd_RestartWarmup(id, level, cid)
{
    if (!cmd_access(id, level, cid, 1))
        return PLUGIN_HANDLED;

    client_print(0, print_chat, "^x04[CS:GO Match] Admin reset the match to Warmup!");
    remove_task(TASK_COUNTDOWN);
    remove_task(TASK_SIDE_PICK);
    remove_task(TASK_TIMEOUT);
    ResetToWarmup();
    return PLUGIN_HANDLED;
}

// ========================================================================
// CHAT COMMAND HANDLER
// ========================================================================
public HandleSay(id)
{
    if (get_pcvar_num(pCvar_Mode) == 0)
        return PLUGIN_CONTINUE;

    new text[64];
    read_args(text, charsmax(text));
    remove_quotes(text);
    trim(text);

    if (equali(text, ".ready") || equali(text, "!ready") || equali(text, "ready"))
    {
        Cmd_Ready(id);
        return PLUGIN_HANDLED;
    }
    else if (equali(text, ".unready") || equali(text, "!unready") || equali(text, ".notready") || equali(text, "unready"))
    {
        Cmd_Unready(id);
        return PLUGIN_HANDLED;
    }
    else if (equali(text, ".score") || equali(text, "!score"))
    {
        Cmd_Score(id);
        return PLUGIN_HANDLED;
    }
    else if (equali(text, ".dmg") || equali(text, ".damage") || equali(text, "!dmg") || equali(text, ".hp"))
    {
        Cmd_Damage(id);
        return PLUGIN_HANDLED;
    }
    else if (equali(text, ".timeout") || equali(text, ".pause") || equali(text, "!timeout") || equali(text, "!pause"))
    {
        Cmd_Timeout(id);
        return PLUGIN_HANDLED;
    }
    else if (equali(text, ".stay"))
    {
        Cmd_SideChoice(id, 1);
        return PLUGIN_HANDLED;
    }
    else if (equali(text, ".switch"))
    {
        Cmd_SideChoice(id, 2);
        return PLUGIN_HANDLED;
    }

    return PLUGIN_CONTINUE;
}

public plugin_end()
{
    SetBotKnifeOnly(false);
}

public BlockBuyCmd(id)
{
    if (g_MatchState == STATE_KNIFE_ROUND)
    {
        if (!is_user_bot(id))
        {
            client_print(id, print_center, "Buying is disabled during Knife Round!");
        }
        return PLUGIN_HANDLED;
    }
    return PLUGIN_CONTINUE;
}

public BlockDropCmd(id)
{
    if (g_MatchState == STATE_KNIFE_ROUND)
    {
        return PLUGIN_HANDLED;
    }
    return PLUGIN_CONTINUE;
}

// Low-level engine buy attempt interception (cstrike module)
public CS_OnBuyAttempt(id, item)
{
    if (g_MatchState == STATE_KNIFE_ROUND)
    {
        return PLUGIN_HANDLED;
    }
    return PLUGIN_CONTINUE;
}

// Low-level purchase execution interception
public CS_OnBuy(id, item)
{
    if (g_MatchState == STATE_KNIFE_ROUND)
    {
        return PLUGIN_HANDLED;
    }
    return PLUGIN_CONTINUE;
}

// Block internal buy commands sent to bots or auto-buy
public CS_InternalCommand(id, const cmd[])
{
    if (g_MatchState == STATE_KNIFE_ROUND)
    {
        return PLUGIN_HANDLED;
    }
    return PLUGIN_CONTINUE;
}

// Continuous check: if any player or bot equips anything other than a knife during knife round, strip it instantly!
public Event_CurWeapon(id)
{
    if (g_MatchState == STATE_KNIFE_ROUND && is_user_alive(id))
    {
        new weapon = read_data(2);
        if (weapon != CSW_KNIFE)
        {
            strip_user_weapons(id);
            give_item(id, "weapon_knife");
            cs_set_user_armor(id, 100, CS_ARMOR_VESTHELM);
            cs_set_user_money(id, 0);
        }
    }
}

// Prevent picking up any dropped weapons, grenades, or armoury items during knife round
public OnWeaponTouchPre(entity, id)
{
    if (g_MatchState == STATE_KNIFE_ROUND)
    {
        if (1 <= id <= MaxClients)
        {
            return HAM_SUPERCEDE;
        }
    }
    return HAM_IGNORED;
}

// Helper to configure YaPB & PodBot knife-only behavior dynamically
stock SetBotKnifeOnly(bool:knife_only)
{
    new pcvar_yb_jason = get_cvar_pointer("yb_jasonmode");
    if (pcvar_yb_jason)
    {
        set_pcvar_num(pcvar_yb_jason, knife_only ? 1 : 0);
    }

    new pcvar_yb_botbuy = get_cvar_pointer("yb_botbuy");
    if (pcvar_yb_botbuy)
    {
        set_pcvar_num(pcvar_yb_botbuy, knife_only ? 0 : 1);
    }

    new pcvar_pb_botbuy = get_cvar_pointer("pb_botbuy");
    if (pcvar_pb_botbuy)
    {
        set_pcvar_num(pcvar_pb_botbuy, knife_only ? 0 : 1);
    }
}

// ========================================================================
// SAFE TEAM CHANGER STOCK (Immune to cstrike_amxx sv crash on Build 9947 & bots)
// ========================================================================
#define OFFSET_TEAM 114
#define EXTRAOFFSET_PLAYER 5

stock SafeSetUserTeam(id, CsTeams:team)
{
    if (!is_user_connected(id))
        return;

    // Directly set CBasePlayer m_iTeam offset via fakemeta (prevents cstrike_amxx.dll access violation)
    set_pdata_int(id, OFFSET_TEAM, _:team, EXTRAOFFSET_PLAYER);

    // Dispatch TeamInfo network message so scoreboard, HUD, and radar sync cleanly
    static msgTeamInfo = 0;
    if (!msgTeamInfo)
        msgTeamInfo = get_user_msgid("TeamInfo");

    new team_str[16];
    if (team == CS_TEAM_T)
        copy(team_str, charsmax(team_str), "TERRORIST");
    else if (team == CS_TEAM_CT)
        copy(team_str, charsmax(team_str), "CT");
    else if (team == CS_TEAM_SPECTATOR)
        copy(team_str, charsmax(team_str), "SPECTATOR");
    else
        copy(team_str, charsmax(team_str), "UNASSIGNED");

    message_begin(MSG_ALL, msgTeamInfo);
    write_byte(id);
    write_string(team_str);
    message_end();
}

// ========================================================================
// ENGINE SCREEN FADE STOCK
// ========================================================================

stock Util_ScreenFade(id, Float:duration, Float:holdtime, flags, r, g, b, alpha, bool:reliable = false)
{
    static msgScreenFade = 0;
    if (!msgScreenFade)
    {
        msgScreenFade = get_user_msgid("ScreenFade");
    }

    new dur = floatround(duration * 4096.0);
    new hold = floatround(holdtime * 4096.0);

    if (id)
    {
        if (!is_user_connected(id)) return;
        message_begin(reliable ? MSG_ONE : MSG_ONE_UNRELIABLE, msgScreenFade, _, id);
    }
    else
    {
        message_begin(reliable ? MSG_ALL : MSG_BROADCAST, msgScreenFade);
    }

    write_short(dur);
    write_short(hold);
    write_short(flags);
    write_byte(r);
    write_byte(g);
    write_byte(b);
    write_byte(alpha);
    message_end();
}

// ========================================================================
// READY UP & WARMUP SYSTEM
// ========================================================================
public Cmd_Ready(id)
{
    if (g_MatchState != STATE_WARMUP && g_MatchState != STATE_COUNTDOWN)
    {
        client_print(id, print_chat, "[CS:GO Match] Match is already in progress!");
        return;
    }

    new CsTeams:team = cs_get_user_team(id);
    if (team != CS_TEAM_CT && team != CS_TEAM_T)
    {
        client_print(id, print_chat, "[CS:GO Match] Please join CT or T before typing .ready!");
        return;
    }

    if (g_PlayerReady[id])
    {
        client_print(id, print_chat, "[CS:GO Match] You are already READY!");
        return;
    }

    g_PlayerReady[id] = true;

    new name[32];
    get_user_name(id, name, charsmax(name));
    client_print(0, print_chat, "^x04[CS:GO Match]^x01 %s is now ^x04READY^x01!", name);

    // Auto-ready YaPB bots if enabled
    if (get_pcvar_num(pCvar_BotAutoReady) == 1)
    {
        for (new i = 1; i <= MaxClients; i++)
        {
            if (is_user_connected(i) && is_user_bot(i))
            {
                new CsTeams:bteam = cs_get_user_team(i);
                if (bteam == CS_TEAM_CT || bteam == CS_TEAM_T)
                {
                    g_PlayerReady[i] = true;
                }
            }
        }
    }

    CheckReadyStatus();
}

public Cmd_Unready(id)
{
    if (g_MatchState != STATE_WARMUP && g_MatchState != STATE_COUNTDOWN)
        return;

    if (!g_PlayerReady[id])
    {
        client_print(id, print_chat, "[CS:GO Match] You are not ready!");
        return;
    }

    g_PlayerReady[id] = false;

    if (g_MatchState == STATE_COUNTDOWN)
    {
        g_MatchState = STATE_WARMUP;
        remove_task(TASK_COUNTDOWN);
        client_print(0, print_chat, "^x03[CS:GO Match]^x01 Countdown cancelled because a player unreadied!");
    }

    new name[32];
    get_user_name(id, name, charsmax(name));
    client_print(0, print_chat, "^x03[CS:GO Match]^x01 %s is now ^x03NOT READY^x01.", name);
}

public CheckReadyStatus()
{
    new total_players = 0;
    new ready_players = 0;
    new ct_count = 0;
    new t_count = 0;

    for (new i = 1; i <= MaxClients; i++)
    {
        if (!is_user_connected(i)) continue;

        new CsTeams:team = cs_get_user_team(i);
        if (team == CS_TEAM_CT)
        {
            total_players++;
            ct_count++;
            if (g_PlayerReady[i]) ready_players++;
        }
        else if (team == CS_TEAM_T)
        {
            total_players++;
            t_count++;
            if (g_PlayerReady[i]) ready_players++;
        }
    }

    if (total_players > 0 && ct_count > 0 && t_count > 0 && ready_players == total_players)
    {
        // Cancel any existing countdown task first
        remove_task(TASK_COUNTDOWN);

        g_MatchState = STATE_COUNTDOWN;
        g_CountdownTimer = 5;
        // Run as a repeating loop until cancelled or expired
        set_task(1.0, "Task_MatchCountdown", TASK_COUNTDOWN, _, _, "b");
        client_print(0, print_chat, "^x04[CS:GO Match]^x01 All players READY (%d/%d)! Starting in 5 seconds...", ready_players, total_players);
    }
}

public Task_MatchCountdown()
{
    if (g_MatchState != STATE_COUNTDOWN)
    {
        remove_task(TASK_COUNTDOWN);
        return;
    }

    if (g_CountdownTimer > 0)
    {
        set_dhudmessage(100, 255, 120, -1.0, 0.32, 0, 0.0, 0.95, 0.05, 0.05);
        show_dhudmessage(0, "★ ALL PLAYERS READY ★^nMatch starts in: %d", g_CountdownTimer);

        new sound[32];
        format(sound, charsmax(sound), "buttons/blip%d.wav", (g_CountdownTimer <= 3) ? 2 : 1);
        client_cmd(0, "spk %s", sound);
        g_CountdownTimer--;
    }
    else
    {
        // Countdown finished! Kill loop task and launch match
        remove_task(TASK_COUNTDOWN);
        client_cmd(0, "spk buttons/bell1.wav");

        if (get_pcvar_num(pCvar_KnifeRound) == 1)
        {
            StartKnifeRound();
        }
        else
        {
            StartLiveMatch();
        }
    }
}

// ========================================================================
// KNIFE ROUND
// ========================================================================
public StartKnifeRound()
{
    remove_task(TASK_COUNTDOWN);

    g_MatchState = STATE_KNIFE_ROUND;
    g_KnifeWinner = CS_TEAM_UNASSIGNED;
    g_KnifeChooserId = 0;

    for (new i = 1; i <= MaxClients; i++)
    {
        remove_task(i + TASK_RESPAWN);
        if (is_user_connected(i))
        {
            cs_set_user_money(i, 0);
        }
    }

    // Force bots (YaPB/PodBot) to knife-only & disable buying routines
    SetBotKnifeOnly(true);
    set_cvar_num("mp_startmoney", 0);
    set_cvar_float("mp_buytime", 0.0);
    set_cvar_num("sv_restart", 1);

    // Visual Announcement (DHUD & Screen Flash)
    set_dhudmessage(50, 255, 140, -1.0, 0.28, 2, 0.1, 4.0, 0.1, 1.0);
    show_dhudmessage(0, "⚔ KNIFE ROUND ⚔^nFight for Side Choice! (Knives Only)");

    if (get_pcvar_num(pCvar_ScreenFade) == 1)
    {
        Util_ScreenFade(0, 0.6, 0.2, FFADE_IN, 50, 255, 140, 45);
    }

    client_print(0, print_chat, "^x04==================================================");
    client_print(0, print_chat, "^x04[CS:GO Match] KNIFE ROUND! Fight for side choice!");
    client_print(0, print_chat, "^x04==================================================");
}

// ========================================================================
// LIVE MATCH (MR12 / MR15)
// ========================================================================
public StartLiveMatch()
{
    remove_task(TASK_COUNTDOWN);
    remove_task(TASK_SIDE_PICK);

    g_MatchState = STATE_LIVE_HALF_1;
    g_RoundNumber = 0;
    g_ScoreCT = 0;
    g_ScoreT = 0;
    g_TimeoutsCT = 0;
    g_TimeoutsT = 0;
    g_LossStreakCT = 0;
    g_LossStreakT = 0;

    // Restore bot buying & buytime
    SetBotKnifeOnly(false);
    set_cvar_float("mp_buytime", 0.25);
    set_cvar_num("mp_startmoney", 800);

    for (new i = 1; i <= MaxClients; i++)
    {
        if (is_user_connected(i))
        {
            cs_set_user_money(i, 800);
            remove_task(i + TASK_RESPAWN);
        }
    }

    set_cvar_num("sv_restart", 1);

    // Visual Announcement (DHUD & Screen Flash)
    set_dhudmessage(255, 215, 0, -1.0, 0.28, 2, 0.1, 4.5, 0.1, 1.0);
    show_dhudmessage(0, "★ MATCH IS LIVE ★^nFormat: MR%d  |  First to %d WINS!", g_MaxRoundsHalf, g_TargetWinScore);

    if (get_pcvar_num(pCvar_ScreenFade) == 1)
    {
        Util_ScreenFade(0, 0.6, 0.2, FFADE_IN, 255, 215, 0, 40);
    }

    client_print(0, print_chat, "^x04==================================================");
    client_print(0, print_chat, "^x04[CS:GO Match] MATCH IS LIVE! Format: MR%d", g_MaxRoundsHalf);
    client_print(0, print_chat, "^x04First team to %d points WINS!", g_TargetWinScore);
    client_print(0, print_chat, "^x04==================================================");
}

// ========================================================================
// HALFTIME SWITCH
// ========================================================================
public TriggerHalftime()
{
    g_MatchState = STATE_HALFTIME;

    // Swap scores
    new temp_score = g_ScoreCT;
    g_ScoreCT = g_ScoreT;
    g_ScoreT = temp_score;

    client_print(0, print_chat, "^x04==================================================");
    client_print(0, print_chat, "^x04[CS:GO Match] HALFTIME! Switching Sides (CT <-> T)");
    client_print(0, print_chat, "^x04Score Half 1: CT [%d] - [%d] T", temp_score, g_ScoreCT);
    client_print(0, print_chat, "^x04==================================================");

    // Visual Announcement & ScreenFade
    set_dhudmessage(255, 255, 100, -1.0, 0.30, 2, 0.1, 3.0, 0.1, 0.8);
    show_dhudmessage(0, "★ HALFTIME ★^nSWITCHING SIDES...^nScore: CT [%d] - [%d] T", temp_score, g_ScoreCT);

    if (get_pcvar_num(pCvar_ScreenFade) == 1)
    {
        Util_ScreenFade(0, 1.2, 1.5, FFADE_OUT, 0, 0, 0, 255);
    }

    // Swap players
    for (new i = 1; i <= MaxClients; i++)
    {
        if (!is_user_connected(i)) continue;

        new CsTeams:team = cs_get_user_team(i);
        if (team == CS_TEAM_CT)
        {
            SafeSetUserTeam(i, CS_TEAM_T);
        }
        else if (team == CS_TEAM_T)
        {
            SafeSetUserTeam(i, CS_TEAM_CT);
        }

        cs_set_user_money(i, 800);
    }

    // Reset half timeouts & loss streaks
    g_TimeoutsCT = 0;
    g_TimeoutsT = 0;
    g_LossStreakCT = 0;
    g_LossStreakT = 0;

    // Restart in 3 seconds to apply new team spawns
    set_task(3.0, "Task_RestartSecondHalf");
}

public Task_RestartSecondHalf()
{
    g_MatchState = STATE_LIVE_HALF_2;
    set_cvar_num("sv_restart", 1);

    set_dhudmessage(100, 255, 120, -1.0, 0.28, 2, 0.1, 3.5, 0.1, 1.0);
    show_dhudmessage(0, "★ SECOND HALF IS LIVE ★^nGood luck, have fun!");

    client_print(0, print_chat, "^x04[CS:GO Match] SECOND HALF IS LIVE! Good luck!");
}

// ========================================================================
// OVERTIME (MR3)
// ========================================================================
public TriggerOvertime()
{
    g_MatchState = STATE_OVERTIME_1;
    g_OTRoundNumber = 0;
    g_OTTargetWinScore = g_ScoreCT + 4; // Need 4 wins out of 6 OT rounds to win (e.g. 16 in MR12)

    new ot_money = get_pcvar_num(pCvar_OTMoney);
    set_cvar_num("mp_startmoney", ot_money);

    for (new i = 1; i <= MaxClients; i++)
    {
        if (is_user_connected(i))
        {
            cs_set_user_money(i, ot_money);
        }
    }

    set_dhudmessage(255, 215, 0, -1.0, 0.28, 2, 0.1, 4.5, 0.1, 1.0);
    show_dhudmessage(0, "★ MATCH TIED (%d - %d) ★^nOVERTIME (MR3) STARTED!", g_ScoreCT, g_ScoreT);
    client_cmd(0, "spk buttons/bell1.wav");

    client_print(0, print_chat, "^x04==================================================");
    client_print(0, print_chat, "^x04[CS:GO Match] MATCH TIED (%d - %d)! OVERTIME (MR3)", g_ScoreCT, g_ScoreT);
    client_print(0, print_chat, "^x04Starting OT Half 1. Start Money: $%d", ot_money);
    client_print(0, print_chat, "^x04==================================================");

    set_cvar_num("sv_restart", 1);
}

public TriggerOTHalftime()
{
    g_MatchState = STATE_OVERTIME_HALFTIME;

    // Swap scores
    new temp_score = g_ScoreCT;
    g_ScoreCT = g_ScoreT;
    g_ScoreT = temp_score;

    set_dhudmessage(255, 255, 100, -1.0, 0.30, 2, 0.1, 3.0, 0.1, 0.8);
    show_dhudmessage(0, "★ OVERTIME HALFTIME ★^nSWITCHING SIDES...");

    if (get_pcvar_num(pCvar_ScreenFade) == 1)
    {
        Util_ScreenFade(0, 1.0, 1.5, FFADE_OUT, 0, 0, 0, 255);
    }

    // Swap players
    for (new i = 1; i <= MaxClients; i++)
    {
        if (!is_user_connected(i)) continue;

        new CsTeams:team = cs_get_user_team(i);
        if (team == CS_TEAM_CT)
            SafeSetUserTeam(i, CS_TEAM_T);
        else if (team == CS_TEAM_T)
            SafeSetUserTeam(i, CS_TEAM_CT);

        cs_set_user_money(i, get_pcvar_num(pCvar_OTMoney));
    }

    client_print(0, print_chat, "^x04[CS:GO Match] OVERTIME HALFTIME! Switching Sides...");
    set_task(3.0, "Task_RestartOTSecondHalf");
}

public Task_RestartOTSecondHalf()
{
    g_MatchState = STATE_OVERTIME_2;
    set_cvar_num("sv_restart", 1);
    set_dhudmessage(255, 215, 0, -1.0, 0.28, 2, 0.1, 3.5, 0.1, 1.0);
    show_dhudmessage(0, "★ OVERTIME SECOND HALF IS LIVE ★");
    client_print(0, print_chat, "^x04[CS:GO Match] OVERTIME SECOND HALF IS LIVE!");
}

// ========================================================================
// TACTICAL TIMEOUT
// ========================================================================
public Cmd_Timeout(id)
{
    if (g_MatchState != STATE_LIVE_HALF_1 && g_MatchState != STATE_LIVE_HALF_2 &&
        g_MatchState != STATE_OVERTIME_1 && g_MatchState != STATE_OVERTIME_2)
    {
        client_print(id, print_chat, "[CS:GO Match] Timeouts can only be called during live rounds!");
        return;
    }

    new CsTeams:team = cs_get_user_team(id);
    new max_timeouts = get_pcvar_num(pCvar_Timeouts);

    if (team == CS_TEAM_CT)
    {
        if (g_TimeoutsCT >= max_timeouts)
        {
            client_print(id, print_chat, "[CS:GO Match] Team CT has used all tactical timeouts for this half!");
            return;
        }
        if (g_TimeoutQueuedCT)
        {
            client_print(id, print_chat, "[CS:GO Match] Timeout is already queued for Team CT!");
            return;
        }
        g_TimeoutQueuedCT = true;
        g_TimeoutsCT++;
        client_print(0, print_chat, "^x04[CS:GO Match]^x01 Team ^x04CT^x01 called a Tactical Timeout! It will start next round.");
    }
    else if (team == CS_TEAM_T)
    {
        if (g_TimeoutsT >= max_timeouts)
        {
            client_print(id, print_chat, "[CS:GO Match] Team T has used all tactical timeouts for this half!");
            return;
        }
        if (g_TimeoutQueuedT)
        {
            client_print(id, print_chat, "[CS:GO Match] Timeout is already queued for Team T!");
            return;
        }
        g_TimeoutQueuedT = true;
        g_TimeoutsT++;
        client_print(0, print_chat, "^x03[CS:GO Match]^x01 Team ^x03TERRORIST^x01 called a Tactical Timeout! It will start next round.");
    }
}

public StartTimeout(CsTeams:team)
{
    g_IsTimeoutActive = true;
    g_TimeoutTeam = team;
    g_TimeoutRemaining = get_pcvar_num(pCvar_TimeoutDuration);

    FreezeAllPlayers(true);

    new team_name[16];
    format(team_name, charsmax(team_name), (team == CS_TEAM_CT) ? "Counter-Terrorist" : "Terrorist");
    client_print(0, print_chat, "^x04[CS:GO Match] TACTICAL TIMEOUT (%s) STARTED! (%d seconds)", team_name, g_TimeoutRemaining);

    set_dhudmessage(255, 80, 80, -1.0, 0.28, 2, 0.1, 4.0, 0.1, 1.0);
    show_dhudmessage(0, "⏸ TACTICAL TIMEOUT ⏸^nTeam: %s^nDuration: %d seconds", team_name, g_TimeoutRemaining);

    if (get_pcvar_num(pCvar_ScreenFade) == 1)
    {
        Util_ScreenFade(0, 0.5, 0.5, FFADE_IN, 30, 30, 30, 140);
    }

    set_task(1.0, "Task_TimeoutCountdown", TASK_TIMEOUT, _, _, "b");
}

public Task_TimeoutCountdown()
{
    if (!g_IsTimeoutActive)
    {
        remove_task(TASK_TIMEOUT);
        return;
    }

    if (g_TimeoutRemaining > 0)
    {
        if (g_TimeoutRemaining <= 3)
        {
            client_cmd(0, "spk buttons/blip1.wav");
        }
        g_TimeoutRemaining--;
    }
    else
    {
        // Timeout ended
        g_IsTimeoutActive = false;
        remove_task(TASK_TIMEOUT);
        FreezeAllPlayers(false);

        client_cmd(0, "spk buttons/bell1.wav");
        client_print(0, print_chat, "^x04[CS:GO Match] Tactical Timeout ended! Resuming match.");
    }
}

public FreezeAllPlayers(bool:freeze)
{
    for (new i = 1; i <= MaxClients; i++)
    {
        if (is_user_alive(i))
        {
            new flags = pev(i, pev_flags);
            if (freeze)
            {
                set_pev(i, pev_flags, flags | FL_FROZEN);
            }
            else
            {
                set_pev(i, pev_flags, flags & ~FL_FROZEN);
            }
        }
    }
}

// ========================================================================
// ROUND EVENTS & ECONOMY
// ========================================================================
public LogEvent_RoundStart()
{
    if (get_pcvar_num(pCvar_Mode) == 0)
        return;

    // Reset damage tracking and MVP kills for new round
    for (new i = 1; i <= MaxClients; i++)
    {
        ResetPlayerDamage(i);
        g_KillsInRound[i] = 0;
    }
    g_BombPlanter = 0;
    g_BombDefuser = 0;

    // Check if timeout was queued
    if (g_TimeoutQueuedCT)
    {
        g_TimeoutQueuedCT = false;
        StartTimeout(CS_TEAM_CT);
        return;
    }
    else if (g_TimeoutQueuedT)
    {
        g_TimeoutQueuedT = false;
        StartTimeout(CS_TEAM_T);
        return;
    }

    // Apply CS:GO Loss Bonus notification & adjustment
    if (g_MatchState == STATE_LIVE_HALF_1 || g_MatchState == STATE_LIVE_HALF_2)
    {
        new ct_bonus = 1400 + (g_LossStreakCT * 500);
        new t_bonus = 1400 + (g_LossStreakT * 500);

        client_print(0, print_console, "[Economy] CT Loss Bonus: Level %d ($%d) | T Loss Bonus: Level %d ($%d)",
            g_LossStreakCT, ct_bonus, g_LossStreakT, t_bonus);
    }
}

public LogEvent_RoundEnd()
{
    if (get_pcvar_num(pCvar_Mode) == 0)
        return;

    // Print Damage Summary to all players
    PrintRoundDamageSummary();

    // Announce MVP
    AnnounceMVP();
}

public Event_CTWin()
{
    HandleRoundWin(CS_TEAM_CT);
}

public Event_TWin()
{
    HandleRoundWin(CS_TEAM_T);
}

public Event_RoundDraw()
{
    if (g_MatchState == STATE_KNIFE_ROUND)
    {
        client_print(0, print_chat, "^x04[CS:GO Match] Knife round was a DRAW! Restarting knife round...");
        set_task(2.0, "StartKnifeRound");
    }
}

public HandleRoundWin(CsTeams:winning_team)
{
    if (get_pcvar_num(pCvar_Mode) == 0)
        return;

    if (g_MatchState == STATE_KNIFE_ROUND)
    {
        g_KnifeWinner = winning_team;
        g_MatchState = STATE_SIDE_PICK;
        g_SidePickTimer = 15;

        new team_name[16];
        format(team_name, charsmax(team_name), (winning_team == CS_TEAM_CT) ? "Counter-Terrorist" : "Terrorist");

        client_print(0, print_chat, "^x04==================================================");
        client_print(0, print_chat, "^x04[CS:GO Match] %s WON the Knife Round!", team_name);
        client_print(0, print_chat, "^x04==================================================");

        // Find a representative
        g_KnifeChooserId = FindTeamRepresentative(winning_team);
        if (g_KnifeChooserId > 0 && !is_user_bot(g_KnifeChooserId))
        {
            client_print(0, print_chat, "^x04Type .stay or .switch in chat (15 seconds) to pick side!");
            ShowSidePickMenu(g_KnifeChooserId);
            set_task(1.0, "Task_SidePickCountdown", TASK_SIDE_PICK, _, _, "b");
        }
        else
        {
            // Bot team won! Auto-pick stay after 2 seconds
            client_print(0, print_chat, "^x04[CS:GO Match] %s Bots won Knife Round and chose to STAY!", team_name);
            set_task(2.0, "Task_BotAutoPickStay");
        }
        return;
    }

    if (g_MatchState == STATE_LIVE_HALF_1 || g_MatchState == STATE_LIVE_HALF_2)
    {
        g_RoundNumber++;

        if (winning_team == CS_TEAM_CT)
        {
            g_ScoreCT++;
            // CS:GO Loss ladder: Decrement winner by 1, increment loser by 1
            if (get_pcvar_num(pCvar_LossBonus) == 1)
            {
                if (g_LossStreakCT > 0) g_LossStreakCT--;
                if (g_LossStreakT < 4)  g_LossStreakT++;
            }
        }
        else if (winning_team == CS_TEAM_T)
        {
            g_ScoreT++;
            if (get_pcvar_num(pCvar_LossBonus) == 1)
            {
                if (g_LossStreakT > 0) g_LossStreakT--;
                if (g_LossStreakCT < 4) g_LossStreakCT++;
            }
        }

        // Check Regulation Win Conditions
        if (g_ScoreCT >= g_TargetWinScore)
        {
            EndMatch(CS_TEAM_CT);
            return;
        }
        else if (g_ScoreT >= g_TargetWinScore)
        {
            EndMatch(CS_TEAM_T);
            return;
        }

        // Check Halftime Condition (Half 1 ended)
        if (g_MatchState == STATE_LIVE_HALF_1 && g_RoundNumber == g_MaxRoundsHalf)
        {
            TriggerHalftime();
            return;
        }

        // Check Overtime Condition (Full 24 rounds ended in 12-12 tie)
        if (g_RoundNumber == (g_MaxRoundsHalf * 2) && g_ScoreCT == g_ScoreT)
        {
            TriggerOvertime();
            return;
        }
    }
    else if (g_MatchState == STATE_OVERTIME_1 || g_MatchState == STATE_OVERTIME_2)
    {
        g_OTRoundNumber++;
        if (winning_team == CS_TEAM_CT) g_ScoreCT++;
        else if (winning_team == CS_TEAM_T) g_ScoreT++;

        if (g_ScoreCT >= g_OTTargetWinScore)
        {
            EndMatch(CS_TEAM_CT);
            return;
        }
        else if (g_ScoreT >= g_OTTargetWinScore)
        {
            EndMatch(CS_TEAM_T);
            return;
        }

        if (g_MatchState == STATE_OVERTIME_1 && g_OTRoundNumber == g_OTMaxRoundsHalf)
        {
            TriggerOTHalftime();
            return;
        }

        if (g_OTRoundNumber == (g_OTMaxRoundsHalf * 2))
        {
            // Another tie or match end
            if (g_ScoreCT == g_ScoreT)
            {
                TriggerOvertime(); // Another OT
            }
        }
    }
}

// ========================================================================
// SIDE PICK (KNIFE WINNER)
// ========================================================================
public Task_BotAutoPickStay()
{
    if (g_MatchState == STATE_SIDE_PICK)
    {
        Cmd_SideChoice(0, 1);
    }
}

public ShowSidePickMenu(id)
{
    new menu = menu_create("\y[Knife Round Winner] Choose Your Side:\w", "HandleMenuSidePick");
    menu_additem(menu, "Stay on Current Side (.stay)", "1");
    menu_additem(menu, "Switch Sides (.switch)", "2");
    menu_setprop(menu, MPROP_EXIT, MEXIT_NEVER);
    menu_display(id, menu, 0);
}

public HandleMenuSidePick(id, menu, item)
{
    if (item == MENU_EXIT || g_MatchState != STATE_SIDE_PICK)
    {
        menu_destroy(menu);
        return PLUGIN_HANDLED;
    }

    new access, info[3], name[64], callback;
    menu_item_getinfo(menu, item, access, info, charsmax(info), name, charsmax(name), callback);
    menu_destroy(menu);

    if (info[0] == '1')
    {
        Cmd_SideChoice(id, 1);
    }
    else
    {
        Cmd_SideChoice(id, 2);
    }

    return PLUGIN_HANDLED;
}

public Cmd_SideChoice(id, choice) // 1 = stay, 2 = switch
{
    if (g_MatchState != STATE_SIDE_PICK)
        return;

    new CsTeams:team = (id > 0) ? cs_get_user_team(id) : g_KnifeWinner;
    if (team != g_KnifeWinner && id != 0)
    {
        client_print(id, print_chat, "[CS:GO Match] Only the winning team can choose sides!");
        return;
    }

    remove_task(TASK_SIDE_PICK);

    new chooser_name[32];
    if (id > 0) get_user_name(id, chooser_name, charsmax(chooser_name));
    else format(chooser_name, charsmax(chooser_name), "System");

    if (choice == 2)
    {
        // Switch sides
        client_print(0, print_chat, "^x04[CS:GO Match] %s chose to ^x04SWITCH SIDES^x01!", chooser_name);
        for (new i = 1; i <= MaxClients; i++)
        {
            if (!is_user_connected(i)) continue;
            new CsTeams:t = cs_get_user_team(i);
            if (t == CS_TEAM_CT) SafeSetUserTeam(i, CS_TEAM_T);
            else if (t == CS_TEAM_T) SafeSetUserTeam(i, CS_TEAM_CT);
        }
    }
    else
    {
        client_print(0, print_chat, "^x04[CS:GO Match] %s chose to ^x04STAY^x01 on current side!", chooser_name);
    }

    StartLiveMatch();
}

public Task_SidePickCountdown()
{
    if (g_MatchState != STATE_SIDE_PICK)
    {
        remove_task(TASK_SIDE_PICK);
        return;
    }

    if (g_SidePickTimer > 0)
    {
        client_print(0, print_center, "KNIFE WINNER CHOOSING SIDES^nRemaining: %d s (type .stay or .switch)", g_SidePickTimer);
        g_SidePickTimer--;
    }
    else
    {
        // Timeout -> default to stay
        remove_task(TASK_SIDE_PICK);
        Cmd_SideChoice(0, 1);
    }
}

public FindTeamRepresentative(CsTeams:team)
{
    // Prefer human player
    for (new i = 1; i <= MaxClients; i++)
    {
        if (is_user_connected(i) && !is_user_bot(i) && cs_get_user_team(i) == team)
            return i;
    }
    // Otherwise bot
    for (new i = 1; i <= MaxClients; i++)
    {
        if (is_user_connected(i) && cs_get_user_team(i) == team)
            return i;
    }
    return 0;
}

// ========================================================================
// PLAYER HOOKS (SPAWN, KILL, DAMAGE)
// ========================================================================
public OnPlayerSpawnPost(id)
{
    if (!is_user_alive(id))
        return HAM_IGNORED;

    new CsTeams:team = cs_get_user_team(id);
    if (team != CS_TEAM_CT && team != CS_TEAM_T)
        return HAM_IGNORED;

    if (g_MatchState == STATE_WARMUP)
    {
        cs_set_user_money(id, 16000);
        cs_set_user_armor(id, 100, CS_ARMOR_VESTHELM);
        give_item(id, "weapon_hegrenade");
    }
    else if (g_MatchState == STATE_KNIFE_ROUND)
    {
        cs_set_user_money(id, 0);
        // 0.1s delay ensures engine default Glock/USP is given first and then cleanly stripped
        set_task(0.1, "Task_StripToKnife", id);
    }

    return HAM_IGNORED;
}

public Task_StripToKnife(id)
{
    if (is_user_alive(id) && g_MatchState == STATE_KNIFE_ROUND)
    {
        strip_user_weapons(id);
        give_item(id, "weapon_knife");
        cs_set_user_armor(id, 100, CS_ARMOR_VESTHELM);
        cs_set_user_money(id, 0);
    }
}

public OnPlayerKilledPost(victim, attacker, shouldgib)
{
    if (victim < 1 || victim > MaxClients)
        return HAM_IGNORED;

    if (g_MatchState == STATE_WARMUP)
    {
        // Respawn after 1.5 seconds in warmup
        set_task(1.5, "Task_WarmupRespawn", victim + TASK_RESPAWN);
    }
    else if (g_MatchState == STATE_LIVE_HALF_1 || g_MatchState == STATE_LIVE_HALF_2 ||
             g_MatchState == STATE_OVERTIME_1 || g_MatchState == STATE_OVERTIME_2)
    {
        if (1 <= attacker <= MaxClients && attacker != victim)
        {
            g_KillsInRound[attacker]++;
        }
    }

    return HAM_IGNORED;
}

public Task_WarmupRespawn(taskid)
{
    new id = taskid - TASK_RESPAWN;
    if (is_user_connected(id) && !is_user_alive(id) && g_MatchState == STATE_WARMUP)
    {
        new CsTeams:team = cs_get_user_team(id);
        if (team == CS_TEAM_CT || team == CS_TEAM_T)
        {
            ExecuteHamB(Ham_CS_RoundRespawn, id);
        }
    }
}

public OnTakeDamagePost(victim, inflictor, attacker, Float:damage, damagebits)
{
    if (attacker < 1 || attacker > MaxClients || victim < 1 || victim > MaxClients || attacker == victim)
        return HAM_IGNORED;

    if (!is_user_connected(attacker) || !is_user_connected(victim))
        return HAM_IGNORED;

    if (cs_get_user_team(attacker) != cs_get_user_team(victim))
    {
        g_DamageDealt[attacker][victim] += floatround(damage);
        g_HitsDealt[attacker][victim]++;
    }

    return HAM_IGNORED;
}

public LogEvent_Plant()
{
    new loguser[80], name[32];
    read_logargv(0, loguser, charsmax(loguser));
    parse_loguser(loguser, name, charsmax(name));
    g_BombPlanter = get_user_index(name);

    g_BombPlanted = true;
    g_BombPlantedTime = get_gametime();
    g_C4TimerCvar = get_cvar_num("mp_c4timer");
    if (g_C4TimerCvar <= 0) g_C4TimerCvar = 40;

    if (get_pcvar_num(pCvar_ScreenFade) == 1)
    {
        Util_ScreenFade(0, 0.4, 0.1, FFADE_IN, 255, 80, 40, 35);
    }
}

public LogEvent_Defuse()
{
    new loguser[80], name[32];
    read_logargv(0, loguser, charsmax(loguser));
    parse_loguser(loguser, name, charsmax(name));
    g_BombDefuser = get_user_index(name);

    g_BombPlanted = false;
}

public LogEvent_TargetBombed()
{
    g_BombPlanted = false;
}

// ========================================================================
// DAMAGE REPORT & MVP
// ========================================================================
public PrintRoundDamageSummary()
{
    for (new id = 1; id <= MaxClients; id++)
    {
        if (!is_user_connected(id) || is_user_bot(id))
            continue;

        new bool:has_damage = false;
        client_print(id, print_chat, "^x04----------------- ROUND DAMAGE REPORT -----------------");

        new card_buf[256];
        new card_len = formatex(card_buf, charsmax(card_buf), "── COMBAT REPORT ──^n");

        for (new v = 1; v <= MaxClients; v++)
        {
            if (g_DamageDealt[id][v] > 0)
            {
                has_damage = true;
                new vname[32];
                get_user_name(v, vname, charsmax(vname));
                client_print(id, print_chat, "^x01Damage Given to ^"^x03%s^x01^" -> ^x04%d^x01 in ^x04%d^x01 hit%s%s",
                    vname, g_DamageDealt[id][v], g_HitsDealt[id][v],
                    (g_HitsDealt[id][v] > 1) ? "s" : "",
                    (!is_user_alive(v)) ? " (KILLED)" : "");

                if (card_len < (charsmax(card_buf) - 50))
                {
                    card_len += formatex(card_buf[card_len], charsmax(card_buf) - card_len,
                        "to %s: %d dmg (%d hit%s)%s^n",
                        vname, g_DamageDealt[id][v], g_HitsDealt[id][v],
                        (g_HitsDealt[id][v] > 1) ? "s" : "",
                        (!is_user_alive(v)) ? " [KILLED]" : "");
                }
            }
        }

        if (!has_damage)
        {
            client_print(id, print_chat, "^x01No damage dealt this round.");
            copy(card_buf, charsmax(card_buf), "── COMBAT REPORT ──^nNo damage dealt this round.");
        }
        client_print(id, print_chat, "^x04-------------------------------------------------------");

        if (get_pcvar_num(pCvar_DmgCard) == 1)
        {
            set_hudmessage(200, 220, 255, 0.68, 0.32, 0, 0.0, 6.0, 0.1, 0.5, -1);
            ShowSyncHudMsg(id, g_HudSyncDamage, "%s", card_buf);
        }
    }
}

public Cmd_Damage(id)
{
    new bool:has_damage = false;
    client_print(id, print_chat, "^x04----------------- DAMAGE SUMMARY -----------------");

    new card_buf[256];
    new card_len = formatex(card_buf, charsmax(card_buf), "── COMBAT REPORT ──^n");

    for (new v = 1; v <= MaxClients; v++)
    {
        if (g_DamageDealt[id][v] > 0)
        {
            has_damage = true;
            new vname[32];
            get_user_name(v, vname, charsmax(vname));
            client_print(id, print_chat, "^x01To ^"^x03%s^x01^" -> ^x04%d^x01 dmg (%d hit%s)",
                vname, g_DamageDealt[id][v], g_HitsDealt[id][v],
                (g_HitsDealt[id][v] > 1) ? "s" : "");

            if (card_len < (charsmax(card_buf) - 50))
            {
                card_len += formatex(card_buf[card_len], charsmax(card_buf) - card_len,
                    "to %s: %d dmg (%d hit%s)%s^n",
                    vname, g_DamageDealt[id][v], g_HitsDealt[id][v],
                    (g_HitsDealt[id][v] > 1) ? "s" : "",
                    (!is_user_alive(v)) ? " [KILLED]" : "");
            }
        }
    }

    if (!has_damage)
    {
        client_print(id, print_chat, "^x01No damage recorded yet in this round.");
        copy(card_buf, charsmax(card_buf), "── COMBAT REPORT ──^nNo damage recorded yet.");
    }
    client_print(id, print_chat, "^x04-------------------------------------------------");

    if (get_pcvar_num(pCvar_DmgCard) == 1)
    {
        set_hudmessage(200, 220, 255, 0.68, 0.32, 0, 0.0, 5.0, 0.1, 0.5, -1);
        ShowSyncHudMsg(id, g_HudSyncDamage, "%s", card_buf);
    }
}

public AnnounceMVP()
{
    new best_player = 0;
    new max_kills = 0;

    for (new i = 1; i <= MaxClients; i++)
    {
        if (is_user_connected(i) && g_KillsInRound[i] > max_kills)
        {
            max_kills = g_KillsInRound[i];
            best_player = i;
        }
    }

    new reason[64];
    if (best_player > 0 && max_kills >= 2)
    {
        format(reason, charsmax(reason), "eliminating %d enemies", max_kills);
    }
    else if (g_BombDefuser > 0)
    {
        best_player = g_BombDefuser;
        format(reason, charsmax(reason), "defusing the bomb");
    }
    else if (g_BombPlanter > 0)
    {
        best_player = g_BombPlanter;
        format(reason, charsmax(reason), "planting the bomb");
    }

    if (best_player > 0)
    {
        new mvp_name[32];
        get_user_name(best_player, mvp_name, charsmax(mvp_name));
        client_print(0, print_chat, "^x04★ MVP: %s for %s! ★", mvp_name, reason);

        if (get_pcvar_num(pCvar_MvpCard) == 1)
        {
            set_dhudmessage(255, 215, 0, -1.0, 0.24, 2, 0.1, 4.0, 0.1, 0.8);
            show_dhudmessage(0, "★ ★ ★   ROUND MVP   ★ ★ ★^n%s^n[ %s ]", mvp_name, reason);
            if (get_pcvar_num(pCvar_ScreenFade) == 1)
            {
                Util_ScreenFade(0, 0.4, 0.2, FFADE_IN, 255, 215, 0, 35);
            }
        }
    }
}

public Cmd_Score(id)
{
    client_print(id, print_chat, "^x04[CS:GO Match] Current Score: CT [%d] - [%d] T | Round %d/%d",
        g_ScoreCT, g_ScoreT, g_RoundNumber, g_MaxRoundsHalf * 2);

    new score_str[128];
    formatex(score_str, charsmax(score_str), "SCORE: CT [ %d ] — [ %d ] T^nRound %d of %d",
        g_ScoreCT, g_ScoreT, g_RoundNumber, g_MaxRoundsHalf * 2);
    set_hudmessage(255, 215, 0, -1.0, 0.08, 0, 0.0, 3.0, 0.1, 0.5, -1);
    ShowSyncHudMsg(id, g_HudSyncSubHeader, "%s", score_str);
}

// ========================================================================
// HUD DISPLAY TASK
// ========================================================================
public Task_UpdateHUD()
{
    if (get_pcvar_num(pCvar_Mode) == 0)
        return;

    new hud_msg[128];

    switch (g_MatchState)
    {
        case STATE_WARMUP:
        {
            new total = 0, ready = 0;
            for (new i = 1; i <= MaxClients; i++)
            {
                if (is_user_connected(i))
                {
                    new CsTeams:team = cs_get_user_team(i);
                    if (team == CS_TEAM_CT || team == CS_TEAM_T)
                    {
                        total++;
                        if (g_PlayerReady[i]) ready++;
                    }
                }
            }

            formatex(hud_msg, charsmax(hud_msg), "★ CS:GO WARMUP LOBBY ★^nReady: [ %d / %d ]  —  Type .ready in chat", ready, total);
            set_hudmessage(220, 220, 220, -1.0, 0.02, 0, 0.0, 1.1, 0.1, 0.1, -1);
            ShowSyncHudMsg(0, g_HudSyncHeader, "%s", hud_msg);
        }
        case STATE_COUNTDOWN:
        {
            new display_time = (g_CountdownTimer > 0) ? g_CountdownTimer : 1;
            formatex(hud_msg, charsmax(hud_msg), "★ MATCH STARTING IN %d SECONDS ★^nPrepare for combat!", display_time);
            set_hudmessage(100, 255, 120, -1.0, 0.02, 0, 0.0, 1.1, 0.1, 0.1, -1);
            ShowSyncHudMsg(0, g_HudSyncHeader, "%s", hud_msg);
        }
        case STATE_KNIFE_ROUND:
        {
            formatex(hud_msg, charsmax(hud_msg), "⚔ [ KNIFE ROUND ]   FIGHT FOR SIDE CHOICE ⚔^n(Knives Only)");
            set_hudmessage(50, 255, 140, -1.0, 0.02, 0, 0.0, 1.1, 0.1, 0.1, -1);
            ShowSyncHudMsg(0, g_HudSyncHeader, "%s", hud_msg);
        }
        case STATE_SIDE_PICK:
        {
            new wteam[24];
            format(wteam, charsmax(wteam), (g_KnifeWinner == CS_TEAM_CT) ? "COUNTER-TERRORISTS" : "TERRORISTS");
            formatex(hud_msg, charsmax(hud_msg), "★ %s WON KNIFE ROUND ★^nChoosing Side... [ .stay / .switch ] (%d s)", wteam, g_SidePickTimer);
            set_hudmessage(100, 200, 255, -1.0, 0.02, 0, 0.0, 1.1, 0.1, 0.1, -1);
            ShowSyncHudMsg(0, g_HudSyncHeader, "%s", hud_msg);
        }
        case STATE_LIVE_HALF_1, STATE_LIVE_HALF_2:
        {
            if (g_IsTimeoutActive)
            {
                new tname[16];
                format(tname, charsmax(tname), (g_TimeoutTeam == CS_TEAM_CT) ? "CT" : "T");
                formatex(hud_msg, charsmax(hud_msg), "⏸ [ TACTICAL TIMEOUT: %s ] ⏸^nResuming in: 00:%02d", tname, g_TimeoutRemaining);
                set_hudmessage(255, 80, 80, -1.0, 0.02, 0, 0.0, 1.1, 0.1, 0.1, -1);
                ShowSyncHudMsg(0, g_HudSyncHeader, "%s", hud_msg);
            }
            else
            {
                if (g_BombPlanted && get_pcvar_num(pCvar_C4Timer) == 1)
                {
                    new Float:elapsed = get_gametime() - g_BombPlantedTime;
                    new c4_left = g_C4TimerCvar - floatround(elapsed);
                    if (c4_left < 0) c4_left = 0;

                    if (c4_left <= 10)
                    {
                        static bool:flash_toggle = false;
                        flash_toggle = !flash_toggle;
                        if (flash_toggle)
                        {
                            formatex(hud_msg, charsmax(hud_msg), "[ CT : %02d ]   💣 C4: %02d s [CRITICAL]   [ %02d : T ]",
                                g_ScoreCT, c4_left, g_ScoreT);
                            set_hudmessage(255, 30, 30, -1.0, 0.02, 0, 0.0, 1.1, 0.05, 0.05, -1);
                        }
                        else
                        {
                            formatex(hud_msg, charsmax(hud_msg), "[ CT : %02d ]   💣 [ C4: %02d s ]   [ %02d : T ]",
                                g_ScoreCT, c4_left, g_ScoreT);
                            set_hudmessage(255, 140, 40, -1.0, 0.02, 0, 0.0, 1.1, 0.05, 0.05, -1);
                        }

                        if (c4_left <= 5 && c4_left > 0)
                        {
                            client_cmd(0, "spk buttons/blip1.wav");
                        }
                    }
                    else
                    {
                        formatex(hud_msg, charsmax(hud_msg), "[ CT : %02d ]   💣 C4: %02d s   [ %02d : T ]",
                            g_ScoreCT, c4_left, g_ScoreT);
                        set_hudmessage(255, 180, 50, -1.0, 0.02, 0, 0.0, 1.1, 0.1, 0.1, -1);
                    }
                    ShowSyncHudMsg(0, g_HudSyncHeader, "%s", hud_msg);
                }
                else
                {
                    new match_point[32];
                    match_point[0] = 0;
                    new r = 240, g = 240, b = 240;

                    if (g_ScoreCT == (g_TargetWinScore - 1))
                    {
                        copy(match_point, charsmax(match_point), "^n▲ MATCH POINT (CT) ▲");
                        r = 255; g = 215; b = 0;
                    }
                    else if (g_ScoreT == (g_TargetWinScore - 1))
                    {
                        copy(match_point, charsmax(match_point), "^n▲ MATCH POINT (T) ▲");
                        r = 255; g = 215; b = 0;
                    }

                    if (get_pcvar_num(pCvar_HudStyle) == 1)
                    {
                        formatex(hud_msg, charsmax(hud_msg), "[ CT : %02d ]   —   ROUND %02d/%02d   —   [ %02d : T ]%s",
                            g_ScoreCT, g_RoundNumber, g_MaxRoundsHalf * 2, g_ScoreT, match_point);
                    }
                    else
                    {
                        formatex(hud_msg, charsmax(hud_msg), "CT: %d  |  T: %d  (Round %d/%d)%s",
                            g_ScoreCT, g_ScoreT, g_RoundNumber, g_MaxRoundsHalf * 2, match_point);
                    }

                    set_hudmessage(r, g, b, -1.0, 0.02, 0, 0.0, 1.1, 0.1, 0.1, -1);
                    ShowSyncHudMsg(0, g_HudSyncHeader, "%s", hud_msg);
                }
            }
        }
        case STATE_OVERTIME_1, STATE_OVERTIME_2:
        {
            formatex(hud_msg, charsmax(hud_msg), "[ CT : %02d ]   ★ OVERTIME MR3 ★   [ %02d : T ]",
                g_ScoreCT, g_ScoreT);
            set_hudmessage(255, 215, 0, -1.0, 0.02, 0, 0.0, 1.1, 0.1, 0.1, -1);
            ShowSyncHudMsg(0, g_HudSyncHeader, "%s", hud_msg);
        }
        case STATE_HALFTIME, STATE_OVERTIME_HALFTIME:
        {
            formatex(hud_msg, charsmax(hud_msg), "★ [ HALFTIME — SWITCHING SIDES ] ★");
            set_hudmessage(255, 255, 100, -1.0, 0.02, 0, 0.0, 1.1, 0.1, 0.1, -1);
            ShowSyncHudMsg(0, g_HudSyncHeader, "%s", hud_msg);
        }
        case STATE_FINISHED:
        {
            new winner[24];
            if (g_ScoreCT > g_ScoreT) format(winner, charsmax(winner), "COUNTER-TERRORISTS");
            else if (g_ScoreT > g_ScoreCT) format(winner, charsmax(winner), "TERRORISTS");
            else format(winner, charsmax(winner), "NOBODY (DRAW)");

            formatex(hud_msg, charsmax(hud_msg), "🏆 MATCH FINISHED 🏆^nWINNER: %s (%d - %d)", winner, g_ScoreCT, g_ScoreT);
            set_hudmessage(0, 255, 120, -1.0, 0.02, 0, 0.0, 1.1, 0.1, 0.1, -1);
            ShowSyncHudMsg(0, g_HudSyncHeader, "%s", hud_msg);
        }
    }
}

// ========================================================================
// MATCH END & CLEANUP
// ========================================================================
public EndMatch(CsTeams:winner)
{
    g_MatchState = STATE_FINISHED;

    new team_name[32];
    if (winner == CS_TEAM_CT) format(team_name, charsmax(team_name), "COUNTER-TERRORISTS");
    else if (winner == CS_TEAM_T) format(team_name, charsmax(team_name), "TERRORISTS");
    else format(team_name, charsmax(team_name), "TIE / DRAW");

    set_dhudmessage(0, 255, 120, -1.0, 0.28, 2, 0.1, 6.0, 0.1, 1.5);
    show_dhudmessage(0, "🏆 MATCH FINISHED 🏆^nWINNER: %s^nFinal Score: CT [%d] - [%d] T", team_name, g_ScoreCT, g_ScoreT);

    if (get_pcvar_num(pCvar_ScreenFade) == 1)
    {
        Util_ScreenFade(0, 0.8, 0.4, FFADE_IN, 0, 255, 120, 50);
    }

    set_task(10.0, "ResetToWarmup", TASK_MATCH_END);
}

public ResetToWarmup()
{
    if (get_pcvar_num(pCvar_Warmup) == 0)
    {
        StartLiveMatch();
        return;
    }

    g_MatchState = STATE_WARMUP;
    g_ScoreCT = 0;
    g_ScoreT = 0;
    g_RoundNumber = 0;
    g_TimeoutsCT = 0;
    g_TimeoutsT = 0;
    g_TimeoutQueuedCT = false;
    g_TimeoutQueuedT = false;
    g_IsTimeoutActive = false;
    g_LossStreakCT = 0;
    g_LossStreakT = 0;

    // Restore bot buying & buytime
    SetBotKnifeOnly(false);
    set_cvar_float("mp_buytime", 0.25);

    for (new i = 1; i <= MaxClients; i++)
    {
        g_PlayerReady[i] = false;
        ResetPlayerDamage(i);
        remove_task(i + TASK_RESPAWN);
    }

    set_cvar_num("mp_startmoney", 16000);
    set_cvar_num("sv_restart", 1);

    client_print(0, print_chat, "^x04[CS:GO Match] Warmup Mode Active! Type .ready in chat to play.");
}

public ResetPlayerDamage(id)
{
    for (new v = 1; v <= MaxClients; v++)
    {
        g_DamageDealt[id][v] = 0;
        g_HitsDealt[id][v] = 0;
    }
}
