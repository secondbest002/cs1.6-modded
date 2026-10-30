# Counter-Strike 1.6 Smart Knife Sound Manager & Team Skin Architecture (v1.1)

Dokumen ini menjelaskan arsitektur teknis sistem suara pisau cerdas (**Smart Knife Sound Manager**) dan pembagian skin tim (CT vs T) di workspace Counter-Strike 1.6 ini.

---

## 1. Arsitektur Terpisah: Skin vs Audio Engine

Sistem pisau di workspace ini menggunakan arsitektur non-intrusif di mana file model `.mdl` tetap bersih dan murni (tanpa modifikasi biner event manual), sementara penanganan audio dilakukan sepenuhnya oleh plugin cerdas AMX Mod X:

1. **Model Switcher Plugin**:
   - [`team_weapon_skins.amxx`](file:///d:/Games/Counter-Strike/Counter-Strike%201.6%20Original/cstrike/addons/amxmodx/plugins/team_weapon_skins.amxx) (Source: [`team_weapon_skins.sma`](file:///d:/Games/Counter-Strike/Counter-Strike%201.6%20Original/cstrike/addons/amxmodx/scripting/team_weapon_skins.sma))
   - Secara dinamis mendeteksi dan memuat model pisau custom per tim dengan konvensi penamaan `v_knife_<jenis>.mdl`:
     - **CT Side**: `models/custom_skins/ct/v_knife_m9.mdl` (**M9 Bayonet**)
     - **T Side**: `models/custom_skins/t/v_knife_butterfly.mdl` (**Butterfly Knife**)
     - Mendukung pisau custom apa pun (Karambit, Bowie, Falchion, Bayonet, Flip, Huntsman, dll.) hanya dengan menamai file modelnya sesuai konvensi.

2. **Smart Audio Manager Plugin**:
   - [`csgo_knife_sound_manager.amxx`](file:///d:/Games/Counter-Strike/Counter-Strike%201.6%20Original/cstrike/addons/amxmodx/plugins/csgo_knife_sound_manager.amxx) (Source: [`csgo_knife_sound_manager.sma`](file:///d:/Games/Counter-Strike/Counter-Strike%201.6%20Original/cstrike/addons/amxmodx/scripting/csgo_knife_sound_manager.sma))
   - Membaca viewmodel aktif pemain (`pev_viewmodel2`) dan langsung mencocokkan kata kunci jenis pisau dari nama filenya tanpa asumsi tim (100% deterministik).

---

## 2. Bagaimana Smart Sound Manager Bekerja

### A. Deteksi Pisau Otomatis dari Nama File
Plugin membaca nama viewmodel aktif saat pemain menarik pisau (`Ham_Item_Deploy`), berganti senjata (`CurWeapon`), atau saat melakukan Inspect (`lookatweapon`):
- Jika model mengandung `"m9"` -> Diidentifikasi sebagai **M9 Bayonet**.
- Jika model mengandung `"butterfly"` atau `"bknife"` -> Diidentifikasi sebagai **Butterfly Knife**.
- Jika model mengandung `"karambit"` -> Diidentifikasi sebagai **Karambit**.
- Jika model mengandung `"bayonet"` -> Diidentifikasi sebagai **Bayonet**.
- Jika model mengandung `"bowie"`, `"falchion"`, `"push"` / `"daggers"`, `"stiletto"`, `"talon"`, `"ursus"`, `"skeleton"`, `"flip"`, `"gut"`, `"huntsman"`, `"navaja"` -> Diidentifikasi sesuai profil pisau masing-masing.

### B. Sound Interception & Dispatching
1. **Deploy (Saat Pisau Ditarik)**:
   - Plugin mencegat sinyal bawaan engine `knife_deploy1.wav` pada hook `FM_EmitSound` (`FMRES_SUPERCEDE`).
   - Memainkan suara deploy spesifik:
     - M9 Bayonet: `weapons/csgo/knife/knife_deploy1.wav` (tarikan pisau CS:GO standar yang bersih).
     - Butterfly: `weapons/csgo/bknife/bknife_draw02.wav` (suara buka bilah lipat butterfly).
     - Bowie: `knife_bowie_draw.wav`.
     - Falchion: `knife_falchion_draw.wav`.
     - Stiletto: `stilletto_draw_01.wav`.
     - Talon: `widow_deploy_01.wav`.
     - Daggers: `knife_push_draw.wav`.
2. **Inspect (Tombol `F` / Command `lookatweapon`)**:
   - Memainkan rangkaian audio trik/pergerakan bilah sesuai karakteristik pisau:
     - M9 Bayonet: Pergerakan bilah CS:GO yang halus (`weapons/csgo/movement1.wav` -> `movement3.wav`), bukan derak logam lipat.
     - Butterfly: Rangkaian trik buka-tutup gagang (`weapons/csgo/bknife/bknife_look01` s/d `look03`).
     - Karambit: Rangkaian putaran angin (`weapons/csgo/movement1.wav` -> `movement2.wav` -> `movement3.wav`).
3. **Attack & Stab**:
   - Pada tusukan kanan (`knife_stab.wav`):
     - Butterfly memainkan suara `weapons/csgo/bknife/bknife_backstab02.wav`.
     - M9 Bayonet dan pisau lainnya menggunakan suara tusukan pisau CS:GO yang bersih dan akurat.

---

## 3. Daftar File
- Model CT: `cstrike/models/custom_skins/ct/v_knife_m9.mdl`
- Model T: `cstrike/models/custom_skins/t/v_knife_butterfly.mdl`
- Pendaftaran plugin: `cstrike/addons/amxmodx/configs/plugins.ini`
