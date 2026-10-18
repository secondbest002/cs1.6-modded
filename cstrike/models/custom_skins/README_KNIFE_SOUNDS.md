# README: Custom Skins Knife Audio (Sistem Penamaan Model Dinamis)

Folder ini berisi viewmodel per tim untuk plugin `team_weapon_skins.amxx`.

### Format Penamaan Model Pisau (Knife Naming Convention):
Mulai versi 1.1, sistem menggunakan penamaan model dinamis (`v_knife_<jenis>.mdl`) agar jenis pisau langsung teridentifikasi secara presisi tanpa asumsi tim:
- Contoh CT: `ct/v_knife_m9.mdl` (Otomatis memainkan profil audio M9 Bayonet)
- Contoh T: `t/v_knife_butterfly.mdl` (Otomatis memainkan profil audio Butterfly Knife)
- Model lainnya yang didukung: `v_knife_karambit.mdl`, `v_knife_bayonet.mdl`, `v_knife_bowie.mdl`, `v_knife_falchion.mdl`, `v_knife_daggers.mdl`, `v_knife_stiletto.mdl`, `v_knife_talon.mdl`, `v_knife_ursus.mdl`, `v_knife_skeleton.mdl`, dll.
- Fallback: `v_knife.mdl` tetap didukung.

### Catatan Model & Audio:
- File model `.mdl` adalah file model murni tanpa modifikasi biner event manual.
- Seluruh penyesuaian suara pisau (Deploy, Inspect, Stab) ditangani secara dinamis oleh:
  [`cstrike/addons/amxmodx/plugins/csgo_knife_sound_manager.amxx`](../../addons/amxmodx/plugins/csgo_knife_sound_manager.amxx).

Untuk dokumentasi lengkap, silakan baca [`.agents/KNIFE_SOUND_SYSTEM.md`](../../.agents/KNIFE_SOUND_SYSTEM.md).
