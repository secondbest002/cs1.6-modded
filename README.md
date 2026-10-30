# Counter-Strike 1.6 Portable & Modular Hub

Repositori resmi Counter-Strike 1.6 portable dengan arsitektur modular multi-worktree dan jaminan portabilitas lintas perangkat (*zero friction on other devices*).

---

## 1. Arsitektur Repositori (Git Multi-Worktree Model)

Struktur repositori dirancang modular dengan pemisahan peran yang tegas antara engine dasar, modul tooling/GUI, mekanik gameplay/AMXX, dan rilis terpadu:

```
main (Utama: Base Game Clean / Vanilla Portable)
 ├── tools/studio-mod-hub   (Worktree: .worktrees/studio-mod-hub - Python GUI Mod Hub, Asset Studio, Tests)
 ├── mod/amxx-mechanics     (Worktree: .worktrees/amxx-mechanics - AMXX Plugins, Bots, Sounds, Models)
 └── release/complete       (Root Workspace: Rilis Lengkap Siap Main - Integrasi Seluruh Modul)
```

| Branch | Lokasi Direktori | Deskripsi | Status |
| :--- | :--- | :--- | :--- |
| `main` | Base ref | **Game Utama**: Instalasi Counter-Strike 1.6 vanilla bersih dan portable. Tanpa skin berat, tanpa mod pihak ketiga. Selalu siap main di perangkat apa pun. | Bersih / Base |
| `tools/studio-mod-hub` | `.worktrees/studio-mod-hub` | **Modul Tooling & Studio**: Desktop Mod Hub GUI (`tools/cs16_mod_hub/`), CS16 Asset Studio 3D WebGL (`scripts/cs16_studio/`), dan 276 automated test suite. | Modul Tooling |
| `mod/amxx-mechanics` | `.worktrees/amxx-mechanics` | **Modul Mekanik & Konten**: AMXX plugins (`cstrike/addons/amxmodx/`), bot YAPB (`cstrike/addons/yapb/`), sound pack (`cstrike/sound/weapons/csgo/`), POV configs, dan custom models. | Modul Mekanik |
| `release/complete` | Root workspace (`.`) | **Rilis Terpadu**: Penggabungan game utama dengan mod manager dan seluruh modifikasi aktif yang sudah terverifikasi dan siap pakai langsung. | Siap Main |

---

## 2. Jaminan Portabilitas Lintas Perangkat (No More "Work in My Machine")

Agar game dapat diunduh dan langsung dimainkan di PC/laptop lain tanpa kendala (*zero friction*):

1. **Auto-Registry Self-Healing**:
   - CS 1.6 Non-Steam biasanya meminta CD-Key atau error resolusi jika dimainkan di PC baru karena registry `HKCU\Software\Valve\Half-Life\Settings` belum ada.
   - Script `!Start Counter-Strike.bat` secara otomatis mendeteksi dan menginjeksi konfigurasi portabel (`portable_settings.reg`) saat pertama kali dijalankan.
2. **Relative Directory Anchoring**:
   - Seluruh launcher dan tool menggunakan path relatif `%~dp0`, sehingga game dapat diletakkan di drive mana pun (`C:`, `D:`, flashdisk, atau folder download) tanpa path rusak.
3. **Pemisahan Mod Non-Destruktif**:
   - Game mendukung layer modular. Modifikasi visual dan AMXX dapat diuji dan dikembangkan secara terisolasi di worktree tanpa merusak file inti.
4. **1-Click Packaging**:
   - Jalankan `package_portable_release.bat` untuk membuat satu file zip portabel yang siap dikirim via Google Drive/flashdisk dan dimainkan di perangkat mana pun tanpa perlu install Git atau software tambahan.

---

## 3. Cara Menjalankan

### Memulai Game (Tanpa Dependensi Tambahan)
Cukup double-click:
```cmd
!Start Counter-Strike.bat
```

### Membuka Desktop Mod Hub GUI (Customizer & Skin Manager)
Double-click:
```cmd
CS16_Mod_Manager.bat
```
*(Otomatis memeriksa Python dan menginstal dependensi GUI jika diperlukan).*

### Membuka CS16 Asset Studio (3D WebGL Inspector)
Double-click:
```cmd
CS16_Asset_Studio.bat
```

---

## 4. Alur Kerja Git Multi-Worktree & Sinkronisasi

Repositori ini menggunakan Git Multi-Worktree sehingga developer dapat bekerja secara simultan tanpa bolak-balik melakukan `git checkout`:

### Lokasi Worktree
- **Tooling & Studio**: Buka folder `.worktrees/studio-mod-hub` untuk mengedit GUI, script studio, dan tests.
- **AMXX & Gameplay**: Buka folder `.worktrees/amxx-mechanics` untuk mengedit plugin AMXX, konfigurasi bot, sound weapon csgo, atau model.
- **Rilis Terpadu**: Root direktori berada pada cabang `release/complete`.

### Sinkronisasi 1-Klik ke Rilis
Setelah melakukan commit di masing-masing worktree, jalankan script sinkronisasi dari root repositori:
```cmd
tools\sync_release.bat
```
Atau melalui command line Python:
```bash
python tools/sync_release.py --sync --push
```

Untuk melihat status seluruh worktree:
```bash
python tools/sync_release.py --status
```

Panduan teknis mendalam mengenai arsitektur worktree dan penanganan merge dapat dibaca pada [`.agents/GIT_WORKTREE_GUIDE.md`](.agents/GIT_WORKTREE_GUIDE.md).
