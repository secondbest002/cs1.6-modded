/*
 * ==============================================================================
 * CS2 WEAPON VARIANTS INTEROPERABILITY API
 * ==============================================================================
 * Shared header providing single-source-of-truth queries for modern CS2
 * weapon variants:
 *   - MAG-7      (XM1014 slot, $1,300, 5-clip box mag, $900 kill reward)
 *   - Negev      (M249 slot, $1,700, 150-clip drum, $300 kill reward)
 *   - Sawed-Off  (M3 slot, $1,100, 8-clip shotgun, $900 kill reward)
 *   - PP-Bizon   (P90 slot, $1,400, 64-clip helical, $600 kill reward)
 *   - CZ75-Auto  (TMP / MAC-10 slot, $500, 12-clip / 12 reserve, $100 kill reward)
 *   - Tec-9      (P228 slot, $500, 18-clip magazine, $300 kill reward)
 *   - MP7        (MP5NAVY slot, $1,500, 30-clip SMG, $600 kill reward)
 * ==============================================================================
 */

#if defined _cs2_weapon_variants_included
    #endinput
#endif
#define _cs2_weapon_variants_included

/**
 * Checks whether the given player is holding/wielding a specific modern weapon variant.
 *
 * @param id            Player index (1 to MaxClients)
 * @param weapon_id     CSW_* weapon constant (or 0 to check current active weapon)
 * @param variant_name  Variant name substring to match (e.g., "mag7", "negev", "sawedoff", "bizon", "cz75", "tec9", "mp7")
 *                      If empty string "", returns true if holding ANY recognized modern variant.
 *
 * @return              true if holding specified variant, false otherwise
 */
native bool:cs2_is_user_holding_variant(id, weapon_id = 0, const variant_name[] = "");

/**
 * Gets the active modern variant name for a player/weapon if applicable.
 *
 * @param id            Player index
 * @param weapon_id     CSW_* weapon constant (or 0 for active weapon)
 * @param buffer        Buffer to store variant name (e.g. "MAG-7", "PP-Bizon", "CZ75-Auto")
 * @param maxlen        Maximum length of buffer
 *
 * @return              true if weapon is a recognized modern variant, false if standard CS 1.6 weapon
 */
native bool:cs2_get_user_weapon_variant(id, weapon_id, buffer[], maxlen);

/**
 * Returns the CS2 meta buy price for a weapon or weapon variant.
 *
 * @param weapon_id     CSW_* weapon constant
 * @param variant_name  Variant name (e.g. "mag7", "negev", "bizon", "cz75", "tec9", "sawedoff")
 *
 * @return              Meta price in dollars
 */
native cs2_get_variant_price(weapon_id, const variant_name[] = "");
