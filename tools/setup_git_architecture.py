"""
Setup Git Repository and Modular Branching Architecture for Counter-Strike 1.6
Main branch: Base Game Clean / Vanilla Portable
Branch 1: mod/csgo-weapon-pack (CS:GO Weapon Pack & cstrike_addon)
Branch 2: mod/mod-manager-hub (Python GUI Mod Hub, Core Adapters, Tests)
Branch 3: release/complete (Unified Complete Game with all mods active)
"""

import os
import shutil
import subprocess
import sys

if hasattr(sys.stdout, 'reconfigure'):
    sys.stdout.reconfigure(encoding='utf-8', errors='replace')
if hasattr(sys.stderr, 'reconfigure'):
    sys.stderr.reconfigure(encoding='utf-8', errors='replace')

def get_git_exe():
    user_git = os.path.expanduser(r'~\AppData\Local\Programs\Git\cmd\git.exe')
    if os.path.exists(user_git):
        return user_git
    which_git = shutil.which('git')
    if which_git:
        return which_git
    raise RuntimeError('git.exe could not be found.')

GIT = get_git_exe()

def git(*args, check=True):
    cmd = [GIT] + list(args)
    res = subprocess.run(cmd, capture_output=True, text=True, cwd=os.getcwd(), encoding='utf-8', errors='replace')
    if check and res.returncode != 0:
        print(f"FAILED: {' '.join(cmd)}")
        print("STDERR:", res.stderr.strip())
        print("STDOUT:", res.stdout.strip())
        raise RuntimeError(f"Git command failed: {' '.join(args)}")
    return res

def has_staged_changes():
    res = git('diff', '--cached', '--name-only', check=False)
    return bool(res.stdout.strip())

def main():
    print("=" * 70)
    print("COUNTER-STRIKE 1.6 - GIT REPOSITORY & BRANCH ARCHITECTURE SETUP")
    print("=" * 70)
    print(f"Using Git binary: {GIT}")

    # 1. Initialize repo
    if not os.path.exists('.git'):
        print("[*] Initializing git repository with main branch...")
        git('init', '-b', 'main')
    else:
        print("[*] Git repository already exists.")

    git('config', 'user.name', 'CS16 Portable Developer')
    git('config', 'user.email', 'dev@cs16portable.local')
    git('config', 'core.autocrlf', 'false')

    # Ensure on main
    git('checkout', '-B', 'main')

    # 2. Files for main (Game Utama / Base Game)
    print("\n[*] Staging base game files for 'main' branch...")
    base_entries = [
        '.gitignore',
        'README.md',
        'portable_settings.reg',
        '!Start Counter-Strike.bat',
        'package_portable_release.bat',
        'hl.exe',
        'a3dapi.dll',
        'binkw32.dll',
        'Core.dll',
        'DemoPlayer.dll',
        'FileSystem_Stdio.dll',
        'hw.dll',
        'Mss32.dll',
        'SDL2.dll',
        'steam_api.dll',
        'sw.dll',
        'swds.dll',
        'vgui.dll',
        'vgui2.dll',
        'video.dll',
        'vstdlib.dll',
        'vstdlib_d.dll',
        'tier0.dll',
        'tier0_d.dll',
        'proxy.dll',
        'icudt.dll',
        'chromehtml.dll',
        'libcef.dll',
        'libcurl.dll',
        'language.inf',
        'readme.txt',
        'unins000.exe',
        'unins000.dat',
        'valve',
        'cstrike',
        'cstrike_hd',
        'cstrike_russian',
        'platform'
    ]

    for item in base_entries:
        if os.path.exists(item):
            git('add', item)

    if has_staged_changes():
        git('commit', '-m', 'feat(core): initialize Counter-Strike 1.6 portable clean base game')
        print("[OK] 'main' branch committed successfully.")
    else:
        print("[OK] 'main' branch is already up-to-date.")

    # 3. Branch: mod/csgo-weapon-pack
    print("\n[*] Setting up branch 'mod/csgo-weapon-pack'...")
    git('checkout', '-B', 'mod/csgo-weapon-pack', 'main')
    
    weapon_pack_entries = ['CSGO Weapon Pack - Update #4', 'cstrike_addon']
    for item in weapon_pack_entries:
        if os.path.exists(item):
            git('add', item)

    if has_staged_changes():
        git('commit', '-m', 'feat(content): add CS:GO weapon pack assets and cstrike_addon layer')
        print("[OK] 'mod/csgo-weapon-pack' branch committed successfully.")
    else:
        print("[OK] 'mod/csgo-weapon-pack' branch is already up-to-date.")

    # 4. Branch: mod/mod-manager-hub
    print("\n[*] Setting up branch 'mod/mod-manager-hub'...")
    git('checkout', '-B', 'mod/mod-manager-hub', 'main')

    tooling_entries = [
        'tools',
        'CS16_Mod_Manager.bat',
        'tests',
        'TEST_READY.md',
        'TEST_INFRA.md',
        '.agents'
    ]
    for item in tooling_entries:
        if os.path.exists(item):
            git('add', item)

    if has_staged_changes():
        git('commit', '-m', 'feat(tools): add Desktop Mod Hub GUI, core adapters, and automated tests')
        print("[OK] 'mod/mod-manager-hub' branch committed successfully.")
    else:
        print("[OK] 'mod/mod-manager-hub' branch is already up-to-date.")

    # 5. Branch: release/complete (Unified All-in-One ready to play)
    print("\n[*] Setting up branch 'release/complete'...")
    git('checkout', '-B', 'release/complete', 'mod/mod-manager-hub')
    # Merge weapon pack
    git('merge', 'mod/csgo-weapon-pack', '-m', 'release: integrate CS:GO weapon pack with mod manager hub')
    print("[OK] 'release/complete' branch created and merged successfully.")

    # Return to main as default active branch
    git('checkout', 'main')

    # 6. Summary of branches
    print("\n" + "=" * 70)
    print("BRANCH STRUCTURE CREATED:")
    print("=" * 70)
    branches = git('branch', '-v')
    print(branches.stdout)

    print("[OK] Git repository and modular branching setup complete!")

if __name__ == '__main__':
    main()
