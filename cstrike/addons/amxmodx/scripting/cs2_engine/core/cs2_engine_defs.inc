#if defined _cs2_engine_defs_included
    #endinput
#endif
#define _cs2_engine_defs_included

#define CS2_ENGINE_VERSION "1.0.0"
#define CS2_ENGINE_AUTHOR  "Antigravity Modular Architecture"

// Primary & Secondary Bitmasks
#if !defined CS2_PRIMARY_WEAPONS_BIT_SUM
const CS2_PRIMARY_WEAPONS_BIT_SUM = (1<<CSW_SCOUT)|(1<<CSW_XM1014)|(1<<CSW_MAC10)|(1<<CSW_AUG)|(1<<CSW_UMP45)|(1<<CSW_SG550)|(1<<CSW_GALIL)|(1<<CSW_FAMAS)|(1<<CSW_AWP)|(1<<CSW_MP5NAVY)|(1<<CSW_M249)|(1<<CSW_M3)|(1<<CSW_M4A1)|(1<<CSW_TMP)|(1<<CSW_G3SG1)|(1<<CSW_SG552)|(1<<CSW_AK47)|(1<<CSW_P90);
#endif

#if !defined CS2_SECONDARY_WEAPONS_BIT_SUM
const CS2_SECONDARY_WEAPONS_BIT_SUM = (1<<CSW_P228)|(1<<CSW_ELITE)|(1<<CSW_FIVESEVEN)|(1<<CSW_USP)|(1<<CSW_GLOCK18)|(1<<CSW_DEAGLE);
#endif

// GoldSrc CBasePlayer / CBasePlayerWeapon Offsets
#if !defined m_pActiveItem
#define m_pActiveItem 373
#endif

#if !defined m_bIsDefusing
#define m_bIsDefusing 99
#endif

#if !defined m_flNextAttack
#define m_flNextAttack 83
#endif

#if !defined extra_offset_player
#define extra_offset_player 5
#endif

#if !defined extra_offset_weapon
#define extra_offset_weapon 4
#endif

#if !defined m_pPlayer
#define m_pPlayer 41
#endif

#if !defined m_flNextPrimaryAttack
#define m_flNextPrimaryAttack 46
#endif

#if !defined m_flNextSecondaryAttack
#define m_flNextSecondaryAttack 47
#endif

#if !defined m_flTimeWeaponIdle
#define m_flTimeWeaponIdle 48
#endif

#if !defined m_fInReload
#define m_fInReload 54
#endif

#if !defined SVC_WEAPONANIM
#define SVC_WEAPONANIM 35
#endif
