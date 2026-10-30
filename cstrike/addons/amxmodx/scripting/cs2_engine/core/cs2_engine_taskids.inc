#if defined _cs2_engine_taskids_included
    #endinput
#endif
#define _cs2_engine_taskids_included

// ==============================================================================
// CS2 MODERN ENGINE - TASK ID PARTITIONING
// Each module has its own 1000-range dedicated Task ID block to guarantee zero
// collision between timers, tasks, and delayed callbacks.
// ==============================================================================

enum {
    TASK_CORE_BASE          = 1000,
    
    // Module 1: Kill Feedback & Ace (2000 - 2999)
    TASK_KF_BASE            = 2000,
    TASK_KF_C4_10SEC        = 2001,
    TASK_KF_HUD_CLEAR       = 2100, // + player id (1-32)
    
    // Module 3: Modern Utility (3000 - 3999)
    TASK_UTIL_BASE          = 3000,
    TASK_UTIL_FREEZETIME    = 3001,
    TASK_UTIL_BUY_OFFSET    = 3100, // + player id (1-32)
    
    // Module 9: Smart Ping (4000 - 4999)
    TASK_PING_BASE          = 4000,
    TASK_PING_HUD           = 4001,
    TASK_PING_EXPIRE        = 4100, // + player id (1-32)
    
    // Module 5: Arm Switcher (5000 - 5999)
    TASK_ARM_BASE           = 5000,
    
    // Module 6: Ammo Refill (6000 - 6999)
    TASK_AMMO_BASE          = 6000,
    TASK_AMMO_ROUND_REFILL  = 6001,
    TASK_AMMO_BOUGHT_REFILL = 6100, // + player id (1-32)
    TASK_AMMO_SPAWN_REFILL  = 6200, // + player id (1-32)
    
    // Module 4: Weapon Pickup (7000 - 7999)
    TASK_WP_BASE            = 7000,
    
    // Module 7: USPS Silencer (8000 - 8999)
    TASK_USPS_BASE          = 8000,
    TASK_USPS_CHECK_SPAWN   = 8100, // + player id (1-32)
    
    // Module 8: Dynamic Knife Sounds (9000 - 9999)
    TASK_KS_BASE            = 9000,
    TASK_KS_INSPECT_BASE    = 9100, // + player id (1-32)
    TASK_KS_INSPECT_STEP2   = 9200, // + player id (1-32)
    TASK_KS_INSPECT_STEP3   = 9300, // + player id (1-32)
    TASK_KS_DEPLOY_FALLBACK = 9400, // + player id (1-32)
    
    // Module 10: Silent Reload (10000 - 10999)
    TASK_SR_BASE            = 10000
};
