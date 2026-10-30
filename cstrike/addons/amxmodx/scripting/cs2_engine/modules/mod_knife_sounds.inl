// ==============================================================================
// CS2 MODERN ENGINE - SUB-MODULE: DYNAMIC KNIFE SOUND ENGINE
// Model-name driven CS:GO / CS2 knife sound manager (Deploy, Inspect, Stab)
// ==============================================================================

#if defined _mod_knife_sounds_included
    #endinput
#endif
#define _mod_knife_sounds_included

// CVars
new ks_pCvar_Enable;

// Knife Types
enum _:KsKnifeType {
    KS_KNIFE_UNKNOWN = 0,
    KS_KNIFE_DEFAULT,
    KS_KNIFE_KARAMBIT,
    KS_KNIFE_BUTTERFLY,
    KS_KNIFE_M9,
    KS_KNIFE_BAYONET,
    KS_KNIFE_BOWIE,
    KS_KNIFE_FALCHION,
    KS_KNIFE_DAGGERS,
    KS_KNIFE_STILETTO,
    KS_KNIFE_TALON,
    KS_KNIFE_URSUS,
    KS_KNIFE_SKELETON,
    KS_KNIFE_FLIP,
    KS_KNIFE_GUT,
    KS_KNIFE_HUNTSMAN,
    KS_KNIFE_NAVAJA,
    KS_KNIFE_NOMAD,
    KS_KNIFE_PARACORD,
    KS_KNIFE_SURVIVAL
};



new ks_PlayerKnifeType[33];
new Float:ks_flLastInspectTime[33];

// Sound files definitions
#define KS_SOUND_DEPLOY_DEFAULT   "weapons/csgo/knife/knife_deploy1.wav"
#define KS_SOUND_DEPLOY_KARAMBIT  "weapons/csgo/knife/knife_deploy1.wav"
#define KS_SOUND_DEPLOY_BUTTERFLY "weapons/csgo/bknife/bknife_draw02.wav"
#define KS_SOUND_DEPLOY_M9        "weapons/csgo/knife/knife_deploy1.wav"
#define KS_SOUND_DEPLOY_BAYONET   "weapons/csgo/knife/knife_deploy1.wav"
#define KS_SOUND_DEPLOY_BOWIE     "weapons/csgo/knife_bowie/knife_bowie_draw.wav"
#define KS_SOUND_DEPLOY_FALCHION  "weapons/csgo/knife_falchion/knife_falchion_draw.wav"
#define KS_SOUND_DEPLOY_DAGGERS   "weapons/csgo/knife_push/knife_push_draw.wav"
#define KS_SOUND_DEPLOY_STILETTO  "weapons/csgo/knife_stilleto/stilletto_draw_01.wav"
#define KS_SOUND_DEPLOY_TALON     "weapons/csgo/knife_widow/widow_deploy_01.wav"
#define KS_SOUND_DEPLOY_NAVAJA    "weapons/csgo/knife_gypsy/gypsy_draw_01.wav"

// Inspect sounds
#define KS_SOUND_SWOOSH_START     "weapons/csgo/movement1.wav"
#define KS_SOUND_SWOOSH_MID       "weapons/csgo/movement2.wav"
#define KS_SOUND_SWOOSH_END       "weapons/csgo/movement3.wav"

#define KS_SOUND_KARAMBIT_SPIN1   "weapons/csgo/movement1.wav"
#define KS_SOUND_KARAMBIT_SPIN2   "weapons/csgo/movement2.wav"
#define KS_SOUND_KARAMBIT_SPIN3   "weapons/csgo/movement3.wav"

#define KS_SOUND_BF_LOOK01_A      "weapons/csgo/bknife/bknife_look01_a.wav"
#define KS_SOUND_BF_LOOK01_B      "weapons/csgo/bknife/bknife_look01_b.wav"
#define KS_SOUND_BF_LOOK02_A      "weapons/csgo/bknife/bknife_look02_a.wav"
#define KS_SOUND_BF_LOOK02_B      "weapons/csgo/bknife/bknife_look02_b.wav"
#define KS_SOUND_BF_LOOK03_A      "weapons/csgo/bknife/bknife_look03_a.wav"
#define KS_SOUND_BF_LOOK03_B      "weapons/csgo/bknife/bknife_look03_b.wav"

#define KS_SOUND_BOWIE_LOOK_START "weapons/csgo/knife_bowie/knife_bowie_inspect_start.wav"
#define KS_SOUND_BOWIE_LOOK_END   "weapons/csgo/knife_bowie/knife_bowie_inspect_end.wav"
#define KS_SOUND_FALCHION_LOOK    "weapons/csgo/knife_falchion/knife_falchion_inspect.wav"
#define KS_SOUND_DAGGERS_LOOK     "weapons/csgo/knife_push/knife_push_lookat_start.wav"
#define KS_SOUND_STILETTO_FLIP    "weapons/csgo/knife_stilleto/stilletto_flip_01.wav"
#define KS_SOUND_TALON_LOOK       "weapons/csgo/knife_widow/widow_lookat2_start.wav"
#define KS_SOUND_URSUS_FLIP       "weapons/csgo/knife_ursus/ursus_flip_01.wav"
#define KS_SOUND_URSUS_CATCH      "weapons/csgo/knife_ursus/ursus_catch_01.wav"

// Attack / Stab sounds
#define KS_SOUND_BF_STAB          "weapons/csgo/bknife/bknife_backstab02.wav"
#define KS_SOUND_DAGGERS_STAB     "weapons/csgo/knife_push/knife_push_attack1_heavy_01.wav"

// List of all sounds to precache safely
new const ks_AllSoundsToPrecache[][] = {
    KS_SOUND_DEPLOY_DEFAULT,
    KS_SOUND_DEPLOY_BUTTERFLY,
    KS_SOUND_DEPLOY_BOWIE,
    KS_SOUND_DEPLOY_FALCHION,
    KS_SOUND_DEPLOY_DAGGERS,
    KS_SOUND_DEPLOY_STILETTO,
    KS_SOUND_DEPLOY_TALON,
    KS_SOUND_DEPLOY_NAVAJA,
    KS_SOUND_SWOOSH_START,
    KS_SOUND_SWOOSH_MID,
    KS_SOUND_SWOOSH_END,
    KS_SOUND_BF_LOOK01_A,
    KS_SOUND_BF_LOOK01_B,
    KS_SOUND_BF_LOOK02_A,
    KS_SOUND_BF_LOOK02_B,
    KS_SOUND_BF_LOOK03_A,
    KS_SOUND_BF_LOOK03_B,
    KS_SOUND_BOWIE_LOOK_START,
    KS_SOUND_BOWIE_LOOK_END,
    KS_SOUND_FALCHION_LOOK,
    KS_SOUND_DAGGERS_LOOK,
    KS_SOUND_STILETTO_FLIP,
    KS_SOUND_TALON_LOOK,
    KS_SOUND_URSUS_FLIP,
    KS_SOUND_URSUS_CATCH,
    KS_SOUND_BF_STAB,
    KS_SOUND_DAGGERS_STAB
};

// -------------------------------------------------------------
// Lifecycle Hooks
// -------------------------------------------------------------
public Mod_KnifeSounds_Init()
{
    ks_pCvar_Enable = register_cvar("amx_cs2_knife_sounds", "1");

    RegisterHam(Ham_Item_Deploy, "weapon_knife", "ks_OnKnifeDeployPost", 1);
    register_event("CurWeapon", "ks_Event_CurWeapon", "be", "1=1");
    register_event("ResetHUD", "ks_Event_ResetHUD", "b");
    register_event("TeamInfo", "ks_Event_TeamInfo", "a");

    register_forward(FM_EmitSound, "ks_fw_EmitSound");
    register_clcmd("lookatweapon", "ks_Cmd_LookAtWeapon");
}

public Mod_KnifeSounds_Precache()
{
    for (new i = 0; i < sizeof(ks_AllSoundsToPrecache); i++)
    {
        new fullpath[128];
        formatex(fullpath, charsmax(fullpath), "sound/%s", ks_AllSoundsToPrecache[i]);
        if (file_exists(fullpath) || file_exists(fullpath, true))
        {
            precache_sound(ks_AllSoundsToPrecache[i]);
        }
    }
    precache_sound("weapons/knife_slash1.wav");
}

public Mod_KnifeSounds_PutInServer(id)
{
    ks_PlayerKnifeType[id] = KS_KNIFE_UNKNOWN;
    ks_flLastInspectTime[id] = 0.0;
}

public Mod_KnifeSounds_Disconnect(id)
{
    ks_PlayerKnifeType[id] = KS_KNIFE_UNKNOWN;
    ks_flLastInspectTime[id] = 0.0;
    ks_ClearInspectTasks(id);
}

public Mod_KnifeSounds_NewRound()
{
    for (new i = 1; i <= 32; i++)
    {
        ks_flLastInspectTime[i] = 0.0;
        ks_ClearInspectTasks(i);
    }
}

public Mod_KnifeSounds_RoundEnd()
{
    for (new i = 1; i <= 32; i++)
    {
        ks_ClearInspectTasks(i);
    }
}

public ks_Event_ResetHUD(id)
{
    if (id >= 1 && id <= MaxClients)
    {
        ks_PlayerKnifeType[id] = KS_KNIFE_UNKNOWN;
        ks_ClearInspectTasks(id);
    }
}

public ks_Event_TeamInfo()
{
    new id = read_data(1);
    if (id >= 1 && id <= MaxClients)
    {
        ks_PlayerKnifeType[id] = KS_KNIFE_UNKNOWN;
        ks_ClearInspectTasks(id);
    }
}

// -------------------------------------------------------------
// Pure Dynamic Model Name Detection
// -------------------------------------------------------------
stock ks_DetectKnifeTypeFromModel(const model[])
{
    if (!model[0])
        return KS_KNIFE_UNKNOWN;

    if (containi(model, "m9") != -1)
        return KS_KNIFE_M9;

    if (containi(model, "butterfly") != -1 || containi(model, "bknife") != -1)
        return KS_KNIFE_BUTTERFLY;

    if (containi(model, "karambit") != -1)
        return KS_KNIFE_KARAMBIT;

    if (containi(model, "bayonet") != -1)
        return KS_KNIFE_BAYONET;

    if (containi(model, "bowie") != -1)
        return KS_KNIFE_BOWIE;

    if (containi(model, "falchion") != -1)
        return KS_KNIFE_FALCHION;

    if (containi(model, "daggers") != -1 || containi(model, "push") != -1)
        return KS_KNIFE_DAGGERS;

    if (containi(model, "stiletto") != -1 || containi(model, "stilletto") != -1)
        return KS_KNIFE_STILETTO;

    if (containi(model, "talon") != -1 || containi(model, "widow") != -1)
        return KS_KNIFE_TALON;

    if (containi(model, "ursus") != -1)
        return KS_KNIFE_URSUS;

    if (containi(model, "skeleton") != -1)
        return KS_KNIFE_SKELETON;

    if (containi(model, "flip") != -1)
        return KS_KNIFE_FLIP;

    if (containi(model, "gut") != -1)
        return KS_KNIFE_GUT;

    if (containi(model, "huntsman") != -1)
        return KS_KNIFE_HUNTSMAN;

    if (containi(model, "navaja") != -1 || containi(model, "gypsy") != -1)
        return KS_KNIFE_NAVAJA;

    if (containi(model, "nomad") != -1)
        return KS_KNIFE_NOMAD;

    if (containi(model, "paracord") != -1)
        return KS_KNIFE_PARACORD;

    if (containi(model, "survival") != -1)
        return KS_KNIFE_SURVIVAL;

    if (containi(model, "knife") != -1)
        return KS_KNIFE_DEFAULT;

    return KS_KNIFE_UNKNOWN;
}

stock ks_DetectKnifeType(id)
{
    if (!is_user_alive(id))
        return KS_KNIFE_UNKNOWN;

    new v_model[128];
    pev(id, pev_viewmodel2, v_model, charsmax(v_model));
    return ks_DetectKnifeTypeFromModel(v_model);
}

// -------------------------------------------------------------
// Deploy Events
// -------------------------------------------------------------
public ks_OnKnifeDeployPost(ent)
{
    if (!get_pcvar_num(pCvar_MasterEnable) || !get_pcvar_num(ks_pCvar_Enable))
        return HAM_IGNORED;

    if (!pev_valid(ent))
        return HAM_IGNORED;

    new id = get_pdata_cbase(ent, 41, 4);
    if (id < 1 || id > MaxClients || !is_user_alive(id))
        return HAM_IGNORED;

    ks_ClearInspectTasks(id);

    new v_model[128];
    pev(id, pev_viewmodel2, v_model, charsmax(v_model));

    new ktype = ks_DetectKnifeTypeFromModel(v_model);
    if (ktype != KS_KNIFE_UNKNOWN)
    {
        ks_PlayerKnifeType[id] = ktype;
        ks_PlayKnifeDeploySound(id);
    }
    else
    {
        remove_task(TASK_KS_DEPLOY_FALLBACK + id);
        set_task(0.02, "ks_Task_DeferredDeployCheck", TASK_KS_DEPLOY_FALLBACK + id);
    }

    return HAM_IGNORED;
}

public ks_Task_DeferredDeployCheck(taskid)
{
    new id = taskid - TASK_KS_DEPLOY_FALLBACK;
    if (id < 1 || id > MaxClients || !is_user_alive(id))
        return;

    if (get_user_weapon(id) != CSW_KNIFE)
        return;

    new v_model[128];
    pev(id, pev_viewmodel2, v_model, charsmax(v_model));
    new ktype = ks_DetectKnifeTypeFromModel(v_model);
    if (ktype != KS_KNIFE_UNKNOWN)
    {
        ks_PlayerKnifeType[id] = ktype;
        ks_PlayKnifeDeploySound(id);
    }
}

public ks_Event_CurWeapon(id)
{
    if (id < 1 || id > MaxClients || !is_user_alive(id))
        return;

    new weapon_id = read_data(2);
    if (weapon_id != CSW_KNIFE)
    {
        ks_ClearInspectTasks(id);
        return;
    }

    new v_model[128];
    pev(id, pev_viewmodel2, v_model, charsmax(v_model));
    new ktype = ks_DetectKnifeTypeFromModel(v_model);
    if (ktype != KS_KNIFE_UNKNOWN)
        ks_PlayerKnifeType[id] = ktype;
}

// -------------------------------------------------------------
// Sound Playback Helpers
// -------------------------------------------------------------
stock ks_PlayKnifeDeploySound(id)
{
    if (is_user_bot(id))
        return;

    new v_model[128];
    pev(id, pev_viewmodel2, v_model, charsmax(v_model));

    new ktype = ks_DetectKnifeTypeFromModel(v_model);
    if (ktype == KS_KNIFE_UNKNOWN)
    {
        ktype = ks_PlayerKnifeType[id];
    }
    else
    {
        ks_PlayerKnifeType[id] = ktype;
    }

    if (ktype == KS_KNIFE_M9)
    {
        return;
    }

    new sound[128];
    switch (ktype)
    {
        case KS_KNIFE_BUTTERFLY:
            copy(sound, charsmax(sound), KS_SOUND_DEPLOY_BUTTERFLY);
        case KS_KNIFE_BOWIE:
            copy(sound, charsmax(sound), KS_SOUND_DEPLOY_BOWIE);
        case KS_KNIFE_FALCHION:
            copy(sound, charsmax(sound), KS_SOUND_DEPLOY_FALCHION);
        case KS_KNIFE_DAGGERS:
            copy(sound, charsmax(sound), KS_SOUND_DEPLOY_DAGGERS);
        case KS_KNIFE_STILETTO:
            copy(sound, charsmax(sound), KS_SOUND_DEPLOY_STILETTO);
        case KS_KNIFE_TALON:
            copy(sound, charsmax(sound), KS_SOUND_DEPLOY_TALON);
        case KS_KNIFE_NAVAJA:
            copy(sound, charsmax(sound), KS_SOUND_DEPLOY_NAVAJA);
        case KS_KNIFE_BAYONET, KS_KNIFE_KARAMBIT, KS_KNIFE_FLIP, KS_KNIFE_GUT, KS_KNIFE_HUNTSMAN, KS_KNIFE_URSUS, KS_KNIFE_SKELETON, KS_KNIFE_NOMAD, KS_KNIFE_PARACORD, KS_KNIFE_SURVIVAL:
            copy(sound, charsmax(sound), KS_SOUND_DEPLOY_M9);
        default:
            copy(sound, charsmax(sound), KS_SOUND_DEPLOY_DEFAULT);
    }

    if (sound[0])
    {
        client_cmd(id, "spk %s", sound);
    }
}

// -------------------------------------------------------------
// Sound Interception (FM_EmitSound)
// -------------------------------------------------------------
public ks_fw_EmitSound(id, channel, const sample[], Float:volume, Float:attn, flags, pitch)
{
    if (!get_pcvar_num(pCvar_MasterEnable) || !get_pcvar_num(ks_pCvar_Enable))
        return FMRES_IGNORED;

    if (id < 1 || id > MaxClients || !is_user_alive(id))
        return FMRES_IGNORED;

    if (get_user_weapon(id) != CSW_KNIFE)
        return FMRES_IGNORED;

    if (equal(sample, "weapons/knife_deploy1.wav") || equal(sample, "weapons/knife_deploy.wav"))
    {
        return FMRES_SUPERCEDE;
    }

    if (equal(sample, "weapons/knife_slash2.wav") || containi(sample, "knife_slash2.wav") != -1)
    {
        emit_sound(id, channel, "weapons/knife_slash1.wav", volume, attn, flags, pitch);
        return FMRES_SUPERCEDE;
    }

    if (containi(sample, "butterfly") != -1 || containi(sample, "bknife") != -1)
    {
        if (containi(sample, "draw") != -1 || containi(sample, "deploy") != -1)
        {
            return FMRES_SUPERCEDE;
        }
    }

    if (equal(sample, "weapons/knife_stab.wav"))
    {
        new v_model[128];
        pev(id, pev_viewmodel2, v_model, charsmax(v_model));
        new ktype = ks_DetectKnifeTypeFromModel(v_model);

        if (ktype == KS_KNIFE_BUTTERFLY)
        {
            emit_sound(id, channel, KS_SOUND_BF_STAB, volume, attn, flags, pitch);
            return FMRES_SUPERCEDE;
        }
        else if (ktype == KS_KNIFE_DAGGERS)
        {
            emit_sound(id, channel, KS_SOUND_DAGGERS_STAB, volume, attn, flags, pitch);
            return FMRES_SUPERCEDE;
        }
    }

    return FMRES_IGNORED;
}

// -------------------------------------------------------------
// Inspect Command (lookatweapon / 'F' key)
// -------------------------------------------------------------
public ks_Cmd_LookAtWeapon(id)
{
    if (!get_pcvar_num(pCvar_MasterEnable) || !get_pcvar_num(ks_pCvar_Enable))
        return PLUGIN_CONTINUE;

    if (!is_user_alive(id))
        return PLUGIN_CONTINUE;

    if (get_user_weapon(id) != CSW_KNIFE)
        return PLUGIN_CONTINUE;

    new Float:flGameTime = get_gametime();
    if (flGameTime - ks_flLastInspectTime[id] < 1.5)
        return PLUGIN_CONTINUE;

    ks_flLastInspectTime[id] = flGameTime;
    ks_ClearInspectTasks(id);

    new v_model[128];
    pev(id, pev_viewmodel2, v_model, charsmax(v_model));
    new ktype = ks_DetectKnifeTypeFromModel(v_model);
    ks_PlayerKnifeType[id] = ktype;

    switch (ktype)
    {
        case KS_KNIFE_KARAMBIT:
        {
            emit_sound(id, CHAN_STATIC, KS_SOUND_KARAMBIT_SPIN1, 1.0, ATTN_NORM, 0, PITCH_NORM);
            set_task(0.35, "ks_Task_KarambitSpin2", TASK_KS_INSPECT_BASE + id);
            set_task(1.80, "ks_Task_KarambitSpin3", TASK_KS_INSPECT_STEP2 + id);
        }
        case KS_KNIFE_BUTTERFLY:
        {
            new r = random_num(1, 3);
            if (r == 1)
            {
                emit_sound(id, CHAN_STATIC, KS_SOUND_BF_LOOK01_A, 1.0, ATTN_NORM, 0, PITCH_NORM);
                set_task(1.5, "ks_Task_ButterflyLook1b", TASK_KS_INSPECT_BASE + id);
            }
            else if (r == 2)
            {
                emit_sound(id, CHAN_STATIC, KS_SOUND_BF_LOOK02_A, 1.0, ATTN_NORM, 0, PITCH_NORM);
                set_task(1.8, "ks_Task_ButterflyLook2b", TASK_KS_INSPECT_BASE + id);
            }
            else
            {
                emit_sound(id, CHAN_STATIC, KS_SOUND_BF_LOOK03_A, 1.0, ATTN_NORM, 0, PITCH_NORM);
                set_task(2.0, "ks_Task_ButterflyLook3b", TASK_KS_INSPECT_BASE + id);
            }
        }
        case KS_KNIFE_M9, KS_KNIFE_BAYONET, KS_KNIFE_FLIP, KS_KNIFE_GUT, KS_KNIFE_HUNTSMAN:
        {
            emit_sound(id, CHAN_STATIC, KS_SOUND_SWOOSH_START, 0.8, ATTN_NORM, 0, PITCH_NORM);
            set_task(0.8, "ks_Task_BladeSwooshEnd", TASK_KS_INSPECT_BASE + id);
        }
        case KS_KNIFE_BOWIE:
        {
            emit_sound(id, CHAN_STATIC, KS_SOUND_BOWIE_LOOK_START, 1.0, ATTN_NORM, 0, PITCH_NORM);
            set_task(2.0, "ks_Task_BowieLookEnd", TASK_KS_INSPECT_BASE + id);
        }
        case KS_KNIFE_FALCHION:
        {
            emit_sound(id, CHAN_STATIC, KS_SOUND_FALCHION_LOOK, 1.0, ATTN_NORM, 0, PITCH_NORM);
        }
        case KS_KNIFE_DAGGERS:
        {
            emit_sound(id, CHAN_STATIC, KS_SOUND_DAGGERS_LOOK, 1.0, ATTN_NORM, 0, PITCH_NORM);
        }
        case KS_KNIFE_STILETTO:
        {
            emit_sound(id, CHAN_STATIC, KS_SOUND_STILETTO_FLIP, 1.0, ATTN_NORM, 0, PITCH_NORM);
        }
        case KS_KNIFE_TALON:
        {
            emit_sound(id, CHAN_STATIC, KS_SOUND_TALON_LOOK, 1.0, ATTN_NORM, 0, PITCH_NORM);
        }
        case KS_KNIFE_URSUS, KS_KNIFE_SKELETON, KS_KNIFE_PARACORD:
        {
            emit_sound(id, CHAN_STATIC, KS_SOUND_URSUS_FLIP, 1.0, ATTN_NORM, 0, PITCH_NORM);
            set_task(1.2, "ks_Task_UrsusCatch", TASK_KS_INSPECT_BASE + id);
        }
    }

    return PLUGIN_CONTINUE;
}

// -------------------------------------------------------------
// Scheduled Inspect Stages
// -------------------------------------------------------------
public ks_Task_KarambitSpin2(taskid)
{
    new id = taskid - TASK_KS_INSPECT_BASE;
    if (id >= 1 && id <= MaxClients && is_user_alive(id) && get_user_weapon(id) == CSW_KNIFE)
    {
        emit_sound(id, CHAN_STATIC, KS_SOUND_KARAMBIT_SPIN2, 1.0, ATTN_NORM, 0, PITCH_NORM);
    }
}

public ks_Task_KarambitSpin3(taskid)
{
    new id = taskid - TASK_KS_INSPECT_STEP2;
    if (id >= 1 && id <= MaxClients && is_user_alive(id) && get_user_weapon(id) == CSW_KNIFE)
    {
        emit_sound(id, CHAN_STATIC, KS_SOUND_KARAMBIT_SPIN3, 1.0, ATTN_NORM, 0, PITCH_NORM);
    }
}

public ks_Task_ButterflyLook1b(taskid)
{
    new id = taskid - TASK_KS_INSPECT_BASE;
    if (id >= 1 && id <= MaxClients && is_user_alive(id) && get_user_weapon(id) == CSW_KNIFE)
    {
        emit_sound(id, CHAN_STATIC, KS_SOUND_BF_LOOK01_B, 1.0, ATTN_NORM, 0, PITCH_NORM);
    }
}

public ks_Task_ButterflyLook2b(taskid)
{
    new id = taskid - TASK_KS_INSPECT_BASE;
    if (id >= 1 && id <= MaxClients && is_user_alive(id) && get_user_weapon(id) == CSW_KNIFE)
    {
        emit_sound(id, CHAN_STATIC, KS_SOUND_BF_LOOK02_B, 1.0, ATTN_NORM, 0, PITCH_NORM);
    }
}

public ks_Task_ButterflyLook3b(taskid)
{
    new id = taskid - TASK_KS_INSPECT_BASE;
    if (id >= 1 && id <= MaxClients && is_user_alive(id) && get_user_weapon(id) == CSW_KNIFE)
    {
        emit_sound(id, CHAN_STATIC, KS_SOUND_BF_LOOK03_B, 1.0, ATTN_NORM, 0, PITCH_NORM);
    }
}

public ks_Task_BladeSwooshEnd(taskid)
{
    new id = taskid - TASK_KS_INSPECT_BASE;
    if (id >= 1 && id <= MaxClients && is_user_alive(id) && get_user_weapon(id) == CSW_KNIFE)
    {
        emit_sound(id, CHAN_STATIC, KS_SOUND_SWOOSH_END, 0.7, ATTN_NORM, 0, PITCH_NORM);
    }
}

public ks_Task_BowieLookEnd(taskid)
{
    new id = taskid - TASK_KS_INSPECT_BASE;
    if (id >= 1 && id <= MaxClients && is_user_alive(id) && get_user_weapon(id) == CSW_KNIFE)
    {
        emit_sound(id, CHAN_STATIC, KS_SOUND_BOWIE_LOOK_END, 1.0, ATTN_NORM, 0, PITCH_NORM);
    }
}

public ks_Task_UrsusCatch(taskid)
{
    new id = taskid - TASK_KS_INSPECT_BASE;
    if (id >= 1 && id <= MaxClients && is_user_alive(id) && get_user_weapon(id) == CSW_KNIFE)
    {
        emit_sound(id, CHAN_STATIC, KS_SOUND_URSUS_CATCH, 1.0, ATTN_NORM, 0, PITCH_NORM);
    }
}

stock ks_ClearInspectTasks(id)
{
    remove_task(TASK_KS_INSPECT_BASE + id);
    remove_task(TASK_KS_INSPECT_STEP2 + id);
    remove_task(TASK_KS_INSPECT_STEP3 + id);
    remove_task(TASK_KS_DEPLOY_FALLBACK + id);
}
