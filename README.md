# Counter-Strike 1.6 Portable & Modular Hub

Repositori resmi Counter-Strike 1.6 portable dengan arsitektur modular bercabang (branching model) dan jaminan portabilitas lintas perangkat (*zero friction on other devices*).

---

## 1. Arsitektur Repositori (Branching Model)

Struktur cabang dirancang agar game dasar tetap murni (*clean base*), sementara setiap modifikasi dan modul terisolasi pada cabangnya masing-masing:

```
main (Utama: Base Game Clean / Vanilla Portable)
 ├── mod/mod-manager-hub    (Ranting: Python GUI Mod Hub & Automated Test Suite)
 ├── mod/csgo-weapon-pack   (Ranting: CS:GO Weapon Pack & cstrike_addon Models/Maps)
 └── release/complete       (Ranting Integrasi: Game Utama + Seluruh Modifikasi Aktif)
```

| Branch | Deskripsi | Status |
| :--- | :--- | :--- |
| `main` | **Game Utama**: Instalasi Counter-Strike 1.6 vanilla bersih dan portable. Tanpa skin berat, tanpa mod pihak ketiga. Selalu siap main di perangkat apa pun. | Bersih / Base |
| `mod/mod-manager-hub` | **Modul Tooling & Hub**: Aplikasi desktop Modern Dark Slate GUI (`tools/cs16_mod_hub/`), batch launcher (`CS16_Mod_Manager.bat`), dan 115 unit/E2E automated test suite. | Modul Tooling |
| `mod/csgo-weapon-pack` | **Modul Konten**: Aset model senjata, tekstur, suara, dan map tambahan (`CSGO Weapon Pack - Update #4` & `cstrike_addon`). | Modul Konten |
| `release/complete` | **Rilis Terpadu**: Penggabungan game utama dengan mod manager dan seluruh modifikasi yang sudah terverifikasi dan siap pakai langsung. | Siap Main |

---

## 2. Jaminan Portabilitas Lintas Perangkat (No More "Work in My Machine")

Agar game dapat diunduh dan langsung dimainkan di PC/laptop lain tanpa kendala (*zero friction*):

1. **Auto-Registry Self-Healing**:
   - CS 1.6 Non-Steam biasanya meminta CD-Key atau error resolusi jika dimainkan di PC baru karena registry `HKCU\Software\Valve\Half-Life\Settings` belum ada.
   - Script `!Start Counter-Strike.bat` secara otomatis mendeteksi dan menginjeksi konfigurasi portabel (`portable_settings.reg`) saat pertama kali dijalankan.
2. **Relative Directory Anchoring**:
   - Seluruh launcher dan tool menggunakan path relatif `%~dp0`, sehingga game dapat diletakkan di drive mana pun (`C:`, `D:`, flashdisk, atau folder download) tanpa path rusak.
3. **Pemisahan Mod Non-Destruktif**:
   - Game mendukung layer `cstrike_addon/`. Modifikasi visual dapat diaktifkan atau dinonaktifkan tanpa merusak file inti `cstrike/`.
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
*(Otomatis memeriksa Python dan menginstal dependensi GUI `customtkinter` & `pillow` jika diperlukan).*

---

## 4. Perintah Git untuk Beralih Ranting (Branches)

Untuk beralih ke game dasar murni:
```bash
git checkout main
```

Untuk beralih ke cabang Mod Hub Tooling:
```bash
git checkout mod/mod-manager-hub
```

Untuk beralih ke rilis lengkap siap main:
```bash
git checkout release/complete
```
