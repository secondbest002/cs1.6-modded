/*
 * ==============================================================================
 * CS:GO SMART KNIFE SOUND MANAGER (Dynamic Model-Name Driven)
 * ==============================================================================
 * Deskripsi:
 * Plugin ini secara 100% DINAMIS mendeteksi jenis pisau (M9 Bayonet, Butterfly,
 * Karambit, Bayonet, Bowie, Falchion, Shadow Daggers, Stiletto, Talon, Ursus, dll.)
 * murni berdasarkan nama file viewmodel aktif (.mdl) tanpa ada hardcode tim (CT/T).
 *
 * Efek suara yang disesuaikan secara real-time:
 *   1. Deploy (saat pisau ditarik / switch ke pisau)
 *   2. Inspect (saat pemain menekan tombol 'F' / command 'lookatweapon')
 *   3. Stab (saat klik kanan menusuk / backstab)
 *
 * Kompatibel penuh dengan:
 *   - team_weapon_skins.amxx (Sistem penamaan dinamis: v_knife_<jenis>.mdl)
 *   - Sistem custom viewmodel apa pun
 * ==============================================================================
 */

#include <amxmodx>
#include <cstrike>
#include <fakemeta>
#include <hamsandwich>

#define PLUGIN  "CS:GO Smart Knife Sound Manager"
#define VERSION "1.3"
#define AUTHOR  "Antigravity"

// Knife Types
enum _:KnifeType {
    KNIFE_UNKNOWN = 0,
    KNIFE_DEFAULT,
    KNIFE_KARAMBIT,
    KNIFE_BUTTERFLY,
    KNIFE_M9,
    KNIFE_BAYONET,
    KNIFE_BOWIE,
    KNIFE_FALCHION,
    KNIFE_DAGGERS,
    KNIFE_STILETTO,
    KNIFE_TALON,
    KNIFE_URSUS,
    KNIFE_SKELETON,
    KNIFE_FLIP,
    KNIFE_GUT,
    KNIFE_HUNTSMAN,
    KNIFE_NAVAJA,
    KNIFE_NOMAD,
    KNIFE_PARACORD,
    KNIFE_SURVIVAL
};

// Task IDs for scheduled inspect & deploy stages
#define TASK_INSPECT_BASE     3000
#define TASK_INSPECT_STEP2    4000
#define TASK_INSPECT_STEP3    5000
#define TASK_DEPLOY_FALLBACK  6000

new const g_szKnifeTypeNames[][] = {
    "Unknown",
    "Default Knife",
    "Karambit",
    "Butterfly Knife",
    "M9 Bayonet",
    "Bayonet",
    "Bowie Knife",
    "Falchion Knife",
    "Shadow Daggers",
    "Stiletto Knife",
    "Talon Knife",
    "Ursus Knife",
    "Skeleton Knife",
    "Flip Knife",
    "Gut Knife",
    "Huntsman Knife",
    "Navaja Knife",
    "Nomad Knife",
    "Paracord Knife",
    "Survival Knife"
};

new g_iPlayerKnifeType[33];
new Float:g_flLastInspectTime[33];

// Sound files definitions
#define SOUND_DEPLOY_DEFAULT   "weapons/csgo/knife/knife_deploy1.wav"
#define SOUND_DEPLOY_KARAMBIT  "weapons/csgo/knife/knife_deploy1.wav"
#define SOUND_DEPLOY_BUTTERFLY "weapons/csgo/bknife/bknife_draw02.wav"
#define SOUND_DEPLOY_M9        "weapons/csgo/knife/knife_deploy1.wav"
#define SOUND_DEPLOY_BAYONET   "weapons/csgo/knife/knife_deploy1.wav"
#define SOUND_DEPLOY_BOWIE     "weapons/csgo/knife_bowie/knife_bowie_draw.wav"
#define SOUND_DEPLOY_FALCHION  "weapons/csgo/knife_falchion/knife_falchion_draw.wav"
#define SOUND_DEPLOY_DAGGERS   "weapons/csgo/knife_push/knife_push_draw.wav"
#define SOUND_DEPLOY_STILETTO  "weapons/csgo/knife_stilleto/stilletto_draw_01.wav"
#define SOUND_DEPLOY_TALON     "weapons/csgo/knife_widow/widow_deploy_01.wav"
#define SOUND_DEPLOY_NAVAJA    "weapons/csgo/knife_gypsy/gypsy_draw_01.wav"

// Inspect sounds
#define SOUND_SWOOSH_START     "weapons/csgo/movement1.wav"
#define SOUND_SWOOSH_MID       "weapons/csgo/movement2.wav"
#define SOUND_SWOOSH_END       "weapons/csgo/movement3.wav"

#define SOUND_KARAMBIT_SPIN1   "weapons/csgo/movement1.wav"
#define SOUND_KARAMBIT_SPIN2   "weapons/csgo/movement2.wav"
#define SOUND_KARAMBIT_SPIN3   "weapons/csgo/movement3.wav"

#define SOUND_BF_LOOK01_A      "weapons/csgo/bknife/bknife_look01_a.wav"
#define SOUND_BF_LOOK01_B      "weapons/csgo/bknife/bknife_look01_b.wav"
#define SOUND_BF_LOOK02_A      "weapons/csgo/bknife/bknife_look02_a.wav"
#define SOUND_BF_LOOK02_B      "weapons/csgo/bknife/bknife_look02_b.wav"
#define SOUND_BF_LOOK03_A      "weapons/csgo/bknife/bknife_look03_a.wav"
#define SOUND_BF_LOOK03_B      "weapons/csgo/bknife/bknife_look03_b.wav"

#define SOUND_BOWIE_LOOK_START "weapons/csgo/knife_bowie/knife_bowie_inspect_start.wav"
#define SOUND_BOWIE_LOOK_END   "weapons/csgo/knife_bowie/knife_bowie_inspect_end.wav"
#define SOUND_FALCHION_LOOK    "weapons/csgo/knife_falchion/knife_falchion_inspect.wav"
#define SOUND_DAGGERS_LOOK     "weapons/csgo/knife_push/knife_push_lookat_start.wav"
#define SOUND_STILETTO_FLIP    "weapons/csgo/knife_stilleto/stilletto_flip_01.wav"
#define SOUND_TALON_LOOK       "weapons/csgo/knife_widow/widow_lookat2_start.wav"
#define SOUND_URSUS_FLIP       "weapons/csgo/knife_ursus/ursus_flip_01.wav"
#define SOUND_URSUS_CATCH      "weapons/csgo/knife_ursus/ursus_catch_01.wav"

// Attack / Stab sounds
#define SOUND_BF_STAB          "weapons/csgo/bknife/bknife_backstab02.wav"
#define SOUND_DAGGERS_STAB     "weapons/csgo/knife_push/knife_push_attack1_heavy_01.wav"

// List of all sounds to precache safely
new const g_AllSoundsToPrecache[][] = {
    SOUND_DEPLOY_DEFAULT,
    SOUND_DEPLOY_BUTTERFLY,
    SOUND_DEPLOY_BOWIE,
    SOUND_DEPLOY_FALCHION,
    SOUND_DEPLOY_DAGGERS,
    SOUND_DEPLOY_STILETTO,
    SOUND_DEPLOY_TALON,
    SOUND_DEPLOY_NAVAJA,
    SOUND_SWOOSH_START,
    SOUND_SWOOSH_MID,
    SOUND_SWOOSH_END,
    SOUND_BF_LOOK01_A,
    SOUND_BF_LOOK01_B,
    SOUND_BF_LOOK02_A,
    SOUND_BF_LOOK02_B,
    SOUND_BF_LOOK03_A,
    SOUND_BF_LOOK03_B,
    SOUND_BOWIE_LOOK_START,
    SOUND_BOWIE_LOOK_END,
    SOUND_FALCHION_LOOK,
    SOUND_DAGGERS_LOOK,
    SOUND_STILETTO_FLIP,
    SOUND_TALON_LOOK,
    SOUND_URSUS_FLIP,
    SOUND_URSUS_CATCH,
    SOUND_BF_STAB,
    SOUND_DAGGERS_STAB
};

public plugin_precache()
{
    new precached = 0;
    for (new i = 0; i < sizeof(g_AllSoundsToPrecache); i++)
    {
        new fullpath[128];
        formatex(fullpath, charsmax(fullpath), "sound/%s", g_AllSoundsToPrecache[i]);
        if (file_exists(fullpath) || file_exists(fullpath, true))
        {
            precache_sound(g_AllSoundsToPrecache[i]);
            precached++;
        }
    }
    // Ensure fallback slash sound is precached for emission
    precache_sound("weapons/knife_slash1.wav");

    server_print("[Knife Sound Manager] Precached %d / %d knife sounds.", precached, sizeof(g_AllSoundsToPrecache));
}

public plugin_init()
{
    register_plugin(PLUGIN, VERSION, AUTHOR);

    RegisterHam(Ham_Item_Deploy, "weapon_knife", "OnKnifeDeployPost", 1);
    register_event("CurWeapon", "Event_CurWeapon", "be", "1=1");
    register_event("ResetHUD", "Event_ResetHUD", "b");
    register_event("TeamInfo", "Event_TeamInfo", "a");

    register_forward(FM_EmitSound, "fw_EmitSound");
    register_clcmd("lookatweapon", "Cmd_LookAtWeapon");

    server_print("[Knife Sound Manager] Dynamic model-name audio engine loaded.");
}

public client_putinserver(id)
{
    g_iPlayerKnifeType[id] = KNIFE_UNKNOWN;
    g_flLastInspectTime[id] = 0.0;
}

public client_disconnected(id)
{
    g_iPlayerKnifeType[id] = KNIFE_UNKNOWN;
    g_flLastInspectTime[id] = 0.0;
    ClearInspectTasks(id);
}

public Event_ResetHUD(id)
{
    if (id >= 1 && id <= MaxClients)
    {
        g_iPlayerKnifeType[id] = KNIFE_UNKNOWN;
        ClearInspectTasks(id);
    }
}

public Event_TeamInfo()
{
    new id = read_data(1);
    if (id >= 1 && id <= MaxClients)
    {
        g_iPlayerKnifeType[id] = KNIFE_UNKNOWN;
        ClearInspectTasks(id);
    }
}

// ----------------------------------------------------------------------------
// Pure Dynamic Model Name Detection (NO TEAM HARDCODING)
// ----------------------------------------------------------------------------
stock DetectKnifeTypeFromModel(const model[])
{
    if (!model[0])
        return KNIFE_UNKNOWN;

    // Direct check based strictly on the model filename keywords
    if (containi(model, "m9") != -1)
        return KNIFE_M9;

    if (containi(model, "butterfly") != -1 || containi(model, "bknife") != -1)
        return KNIFE_BUTTERFLY;

    if (containi(model, "karambit") != -1)
        return KNIFE_KARAMBIT;

    if (containi(model, "bayonet") != -1)
        return KNIFE_BAYONET;

    if (containi(model, "bowie") != -1)
        return KNIFE_BOWIE;

    if (containi(model, "falchion") != -1)
        return KNIFE_FALCHION;

    if (containi(model, "daggers") != -1 || containi(model, "push") != -1)
        return KNIFE_DAGGERS;

    if (containi(model, "stiletto") != -1 || containi(model, "stilletto") != -1)
        return KNIFE_STILETTO;

    if (containi(model, "talon") != -1 || containi(model, "widow") != -1)
        return KNIFE_TALON;

    if (containi(model, "ursus") != -1)
        return KNIFE_URSUS;

    if (containi(model, "skeleton") != -1)
        return KNIFE_SKELETON;

    if (containi(model, "flip") != -1)
        return KNIFE_FLIP;

    if (containi(model, "gut") != -1)
        return KNIFE_GUT;

    if (containi(model, "huntsman") != -1)
        return KNIFE_HUNTSMAN;

    if (containi(model, "navaja") != -1 || containi(model, "gypsy") != -1)
        return KNIFE_NAVAJA;

    if (containi(model, "nomad") != -1)
        return KNIFE_NOMAD;

    if (containi(model, "paracord") != -1)
        return KNIFE_PARACORD;

    if (containi(model, "survival") != -1)
        return KNIFE_SURVIVAL;

    // Generic knife keyword without specific subtype
    if (containi(model, "knife") != -1)
        return KNIFE_DEFAULT;

    // Non-knife weapon model (e.g. v_ak47.mdl, v_m4a1.mdl)
    return KNIFE_UNKNOWN;
}

stock DetectKnifeType(id)
{
    if (!is_user_alive(id))
        return KNIFE_UNKNOWN;

    new v_model[128];
    pev(id, pev_viewmodel2, v_model, charsmax(v_model));
    return DetectKnifeTypeFromModel(v_model);
}

// ----------------------------------------------------------------------------
// Deploy Events
// ----------------------------------------------------------------------------
public OnKnifeDeployPost(ent)
{
    if (!pev_valid(ent))
        return HAM_IGNORED;

    new id = get_pdata_cbase(ent, 41, 4);
    if (id < 1 || id > MaxClients || !is_user_alive(id))
        return HAM_IGNORED;

    ClearInspectTasks(id);

    // Read viewmodel model directly (team_weapon_skins runs prior to this hook)
    new v_model[128];
    pev(id, pev_viewmodel2, v_model, charsmax(v_model));

    new ktype = DetectKnifeTypeFromModel(v_model);
    if (ktype != KNIFE_UNKNOWN)
    {
        g_iPlayerKnifeType[id] = ktype;
        PlayKnifeDeploySound(id);
    }
    else
    {
        // Viewmodel is not yet a knife model (still previous gun), wait 0.02s for team_weapon_skins
        set_task(0.02, "Task_DeferredDeployCheck", TASK_DEPLOY_FALLBACK + id);
    }

    return HAM_IGNORED;
}

public Task_DeferredDeployCheck(taskid)
{
    new id = taskid - TASK_DEPLOY_FALLBACK;
    if (id < 1 || id > MaxClients || !is_user_alive(id))
        return;

    if (get_user_weapon(id) != CSW_KNIFE)
        return;

    new v_model[128];
    pev(id, pev_viewmodel2, v_model, charsmax(v_model));
    new ktype = DetectKnifeTypeFromModel(v_model);
    if (ktype != KNIFE_UNKNOWN)
    {
        g_iPlayerKnifeType[id] = ktype;
        PlayKnifeDeploySound(id);
    }
}

public Event_CurWeapon(id)
{
    if (id < 1 || id > MaxClients || !is_user_alive(id))
        return;

    new weapon_id = read_data(2);
    if (weapon_id != CSW_KNIFE)
    {
        ClearInspectTasks(id);
        return;
    }

    new v_model[128];
    pev(id, pev_viewmodel2, v_model, charsmax(v_model));
    new ktype = DetectKnifeTypeFromModel(v_model);
    if (ktype != KNIFE_UNKNOWN)
        g_iPlayerKnifeType[id] = ktype;
}

// ----------------------------------------------------------------------------
// Sound Playback Helpers
// ----------------------------------------------------------------------------
stock PlayKnifeDeploySound(id)
{
    if (is_user_bot(id))
        return;

    new v_model[128];
    pev(id, pev_viewmodel2, v_model, charsmax(v_model));

    new ktype = DetectKnifeTypeFromModel(v_model);
    if (ktype == KNIFE_UNKNOWN)
    {
        ktype = g_iPlayerKnifeType[id];
    }
    else
    {
        g_iPlayerKnifeType[id] = ktype;
    }

    server_print("[Knife Sound] Player %d deployed: %s (Type: %s)", id, v_model, g_szKnifeTypeNames[ktype]);

    // M9 and Butterfly models already have embedded Event 5004 deploy sounds in their animations
    if (ktype == KNIFE_M9 || ktype == KNIFE_BUTTERFLY)
    {
        return;
    }

    new sound[128];
    switch (ktype)
    {
        case KNIFE_BOWIE:
            copy(sound, charsmax(sound), SOUND_DEPLOY_BOWIE);
        case KNIFE_FALCHION:
            copy(sound, charsmax(sound), SOUND_DEPLOY_FALCHION);
        case KNIFE_DAGGERS:
            copy(sound, charsmax(sound), SOUND_DEPLOY_DAGGERS);
        case KNIFE_STILETTO:
            copy(sound, charsmax(sound), SOUND_DEPLOY_STILETTO);
        case KNIFE_TALON:
            copy(sound, charsmax(sound), SOUND_DEPLOY_TALON);
        case KNIFE_NAVAJA:
            copy(sound, charsmax(sound), SOUND_DEPLOY_NAVAJA);
        case KNIFE_BAYONET, KNIFE_KARAMBIT, KNIFE_FLIP, KNIFE_GUT, KNIFE_HUNTSMAN, KNIFE_URSUS, KNIFE_SKELETON, KNIFE_NOMAD, KNIFE_PARACORD, KNIFE_SURVIVAL:
            copy(sound, charsmax(sound), SOUND_DEPLOY_M9);
        default:
            copy(sound, charsmax(sound), SOUND_DEPLOY_DEFAULT);
    }

    if (sound[0])
    {
        client_cmd(id, "spk %s", sound);
    }
}

// ----------------------------------------------------------------------------
// Sound Interception (FM_EmitSound)
// ----------------------------------------------------------------------------
public fw_EmitSound(id, channel, const sample[], Float:volume, Float:attn, flags, pitch)
{
    if (id < 1 || id > MaxClients || !is_user_alive(id))
        return FMRES_IGNORED;

    if (get_user_weapon(id) != CSW_KNIFE)
        return FMRES_IGNORED;

    // Intercept default engine deploy sound (knife_deploy1.wav or knife_deploy.wav)
    if (equal(sample, "weapons/knife_deploy1.wav") || equal(sample, "weapons/knife_deploy.wav"))
    {
        return FMRES_SUPERCEDE;
    }

    // Intercept knife_slash2.wav (contains metallic resonant clink) and replace with clean knife_slash1.wav
    if (equal(sample, "weapons/knife_slash2.wav") || containi(sample, "knife_slash2.wav") != -1)
    {
        emit_sound(id, channel, "weapons/knife_slash1.wav", volume, attn, flags, pitch);
        return FMRES_SUPERCEDE;
    }

    // Protection: If ANY butterfly deploy/draw sound is emitted, but player's active knife is NOT butterfly, supercede it!
    if (containi(sample, "butterfly") != -1 || containi(sample, "bknife") != -1)
    {
        if (containi(sample, "draw") != -1 || containi(sample, "deploy") != -1)
        {
            new v_model[128];
            pev(id, pev_viewmodel2, v_model, charsmax(v_model));
            new ktype = DetectKnifeTypeFromModel(v_model);
            if (ktype != KNIFE_BUTTERFLY)
            {
                return FMRES_SUPERCEDE;
            }
        }
    }

    // Intercept stab sound (knife_stab.wav)
    if (equal(sample, "weapons/knife_stab.wav"))
    {
        new v_model[128];
        pev(id, pev_viewmodel2, v_model, charsmax(v_model));
        new ktype = DetectKnifeTypeFromModel(v_model);

        if (ktype == KNIFE_BUTTERFLY)
        {
            emit_sound(id, channel, SOUND_BF_STAB, volume, attn, flags, pitch);
            return FMRES_SUPERCEDE;
        }
        else if (ktype == KNIFE_DAGGERS)
        {
            emit_sound(id, channel, SOUND_DAGGERS_STAB, volume, attn, flags, pitch);
            return FMRES_SUPERCEDE;
        }
    }

    return FMRES_IGNORED;
}

// ----------------------------------------------------------------------------
// Inspect Command (lookatweapon / 'F' key)
// ----------------------------------------------------------------------------
public Cmd_LookAtWeapon(id)
{
    if (!is_user_alive(id))
        return PLUGIN_CONTINUE;

    if (get_user_weapon(id) != CSW_KNIFE)
        return PLUGIN_CONTINUE;

    new Float:flGameTime = get_gametime();
    if (flGameTime - g_flLastInspectTime[id] < 1.5)
        return PLUGIN_CONTINUE;

    g_flLastInspectTime[id] = flGameTime;
    ClearInspectTasks(id);

    new v_model[128];
    pev(id, pev_viewmodel2, v_model, charsmax(v_model));
    new ktype = DetectKnifeTypeFromModel(v_model);
    g_iPlayerKnifeType[id] = ktype;

    switch (ktype)
    {
        case KNIFE_KARAMBIT:
        {
            // Stage 1: initial flick / spin start
            emit_sound(id, CHAN_STATIC, SOUND_KARAMBIT_SPIN1, 1.0, ATTN_NORM, 0, PITCH_NORM);
            // Stage 2: fast spin whoosh
            set_task(0.35, "Task_KarambitSpin2", TASK_INSPECT_BASE + id);
            // Stage 3: closing spin flick
            set_task(1.80, "Task_KarambitSpin3", TASK_INSPECT_STEP2 + id);
        }
        case KNIFE_BUTTERFLY:
        {
            new r = random_num(1, 3);
            if (r == 1)
            {
                emit_sound(id, CHAN_STATIC, SOUND_BF_LOOK01_A, 1.0, ATTN_NORM, 0, PITCH_NORM);
                set_task(1.5, "Task_ButterflyLook1b", TASK_INSPECT_BASE + id);
            }
            else if (r == 2)
            {
                emit_sound(id, CHAN_STATIC, SOUND_BF_LOOK02_A, 1.0, ATTN_NORM, 0, PITCH_NORM);
                set_task(1.8, "Task_ButterflyLook2b", TASK_INSPECT_BASE + id);
            }
            else
            {
                emit_sound(id, CHAN_STATIC, SOUND_BF_LOOK03_A, 1.0, ATTN_NORM, 0, PITCH_NORM);
                set_task(2.0, "Task_ButterflyLook3b", TASK_INSPECT_BASE + id);
            }
        }
        case KNIFE_M9, KNIFE_BAYONET, KNIFE_FLIP, KNIFE_GUT, KNIFE_HUNTSMAN:
        {
            emit_sound(id, CHAN_STATIC, SOUND_SWOOSH_START, 0.8, ATTN_NORM, 0, PITCH_NORM);
            set_task(0.8, "Task_BladeSwooshEnd", TASK_INSPECT_BASE + id);
        }
        case KNIFE_BOWIE:
        {
            emit_sound(id, CHAN_STATIC, SOUND_BOWIE_LOOK_START, 1.0, ATTN_NORM, 0, PITCH_NORM);
            set_task(2.0, "Task_BowieLookEnd", TASK_INSPECT_BASE + id);
        }
        case KNIFE_FALCHION:
        {
            emit_sound(id, CHAN_STATIC, SOUND_FALCHION_LOOK, 1.0, ATTN_NORM, 0, PITCH_NORM);
        }
        case KNIFE_DAGGERS:
        {
            emit_sound(id, CHAN_STATIC, SOUND_DAGGERS_LOOK, 1.0, ATTN_NORM, 0, PITCH_NORM);
        }
        case KNIFE_STILETTO:
        {
            emit_sound(id, CHAN_STATIC, SOUND_STILETTO_FLIP, 1.0, ATTN_NORM, 0, PITCH_NORM);
        }
        case KNIFE_TALON:
        {
            emit_sound(id, CHAN_STATIC, SOUND_TALON_LOOK, 1.0, ATTN_NORM, 0, PITCH_NORM);
        }
        case KNIFE_URSUS, KNIFE_SKELETON, KNIFE_PARACORD:
        {
            emit_sound(id, CHAN_STATIC, SOUND_URSUS_FLIP, 1.0, ATTN_NORM, 0, PITCH_NORM);
            set_task(1.2, "Task_UrsusCatch", TASK_INSPECT_BASE + id);
        }
    }

    return PLUGIN_CONTINUE;
}

// ----------------------------------------------------------------------------
// Scheduled Inspect Stages
// ----------------------------------------------------------------------------
public Task_KarambitSpin2(taskid)
{
    new id = taskid - TASK_INSPECT_BASE;
    if (id >= 1 && id <= MaxClients && is_user_alive(id) && get_user_weapon(id) == CSW_KNIFE)
    {
        emit_sound(id, CHAN_STATIC, SOUND_KARAMBIT_SPIN2, 1.0, ATTN_NORM, 0, PITCH_NORM);
    }
}

public Task_KarambitSpin3(taskid)
{
    new id = taskid - TASK_INSPECT_STEP2;
    if (id >= 1 && id <= MaxClients && is_user_alive(id) && get_user_weapon(id) == CSW_KNIFE)
    {
        emit_sound(id, CHAN_STATIC, SOUND_KARAMBIT_SPIN3, 1.0, ATTN_NORM, 0, PITCH_NORM);
    }
}

public Task_ButterflyLook1b(taskid)
{
    new id = taskid - TASK_INSPECT_BASE;
    if (id >= 1 && id <= MaxClients && is_user_alive(id) && get_user_weapon(id) == CSW_KNIFE)
    {
        emit_sound(id, CHAN_STATIC, SOUND_BF_LOOK01_B, 1.0, ATTN_NORM, 0, PITCH_NORM);
    }
}

public Task_ButterflyLook2b(taskid)
{
    new id = taskid - TASK_INSPECT_BASE;
    if (id >= 1 && id <= MaxClients && is_user_alive(id) && get_user_weapon(id) == CSW_KNIFE)
    {
        emit_sound(id, CHAN_STATIC, SOUND_BF_LOOK02_B, 1.0, ATTN_NORM, 0, PITCH_NORM);
    }
}

public Task_ButterflyLook3b(taskid)
{
    new id = taskid - TASK_INSPECT_BASE;
    if (id >= 1 && id <= MaxClients && is_user_alive(id) && get_user_weapon(id) == CSW_KNIFE)
    {
        emit_sound(id, CHAN_STATIC, SOUND_BF_LOOK03_B, 1.0, ATTN_NORM, 0, PITCH_NORM);
    }
}

public Task_BladeSwooshEnd(taskid)
{
    new id = taskid - TASK_INSPECT_BASE;
    if (id >= 1 && id <= MaxClients && is_user_alive(id) && get_user_weapon(id) == CSW_KNIFE)
    {
        emit_sound(id, CHAN_STATIC, SOUND_SWOOSH_END, 0.7, ATTN_NORM, 0, PITCH_NORM);
    }
}

public Task_BowieLookEnd(taskid)
{
    new id = taskid - TASK_INSPECT_BASE;
    if (id >= 1 && id <= MaxClients && is_user_alive(id) && get_user_weapon(id) == CSW_KNIFE)
    {
        emit_sound(id, CHAN_STATIC, SOUND_BOWIE_LOOK_END, 1.0, ATTN_NORM, 0, PITCH_NORM);
    }
}

public Task_UrsusCatch(taskid)
{
    new id = taskid - TASK_INSPECT_BASE;
    if (id >= 1 && id <= MaxClients && is_user_alive(id) && get_user_weapon(id) == CSW_KNIFE)
    {
        emit_sound(id, CHAN_STATIC, SOUND_URSUS_CATCH, 1.0, ATTN_NORM, 0, PITCH_NORM);
    }
}

stock ClearInspectTasks(id)
{
    remove_task(TASK_INSPECT_BASE + id);
    remove_task(TASK_INSPECT_STEP2 + id);
    remove_task(TASK_INSPECT_STEP3 + id);
    remove_task(TASK_DEPLOY_FALLBACK + id);
}
