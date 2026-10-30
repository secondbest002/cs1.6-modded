# Counter-Strike 1.6 - Git Multi-Worktree Architecture Guide

This guide documents the multi-worktree architecture, branch taxonomy, synchronization procedures, and best practices for the Counter-Strike 1.6 Portable & Modular Hub repository.

---

## 1. Architectural Overview

The repository uses a 4-tier modular branching architecture backed by Git Multi-Worktree. This model isolates large binary content, tooling suites, and vanilla engine binaries so that each component can be modified without merge churn or unnecessary disk duplication.

```
                          [main]
               (Clean Vanilla Portable Base)
                     /              \
                    /                \
 [tools/studio-mod-hub]            [mod/amxx-mechanics]
  (.worktrees/studio-mod-hub)       (.worktrees/amxx-mechanics)
  - Asset Studio 3D WebGL           - AMXX Plugins & Configs
  - Desktop Mod Hub GUI             - YAPB Bot System
  - 276 Automated Tests             - Modern POV Adjuster
  - Development Tools               - CS:GO / CS2 Sound Packs
                                    - Custom & PW Models
                    \                /
                     \              /
                   [release/complete]
               (Root Repository Workspace)
               Ready-to-Play Integrated Game
```

### Branch Roles and Worktree Paths

| Branch | Physical Location | Scope and Contents |
| :--- | :--- | :--- |
| `main` | Base ref | Vanilla clean Counter-Strike 1.6 portable installation. Engine binaries (`hl.exe`, DLLs), core game configs, and pristine Half-Life / Valve assets. |
| `tools/studio-mod-hub` | `.worktrees/studio-mod-hub` | Python Web Mod Hub (`tools/cs16_mod_hub/`), CS16 Asset Studio (`scripts/cs16_studio/`), test suite (`tests/`), batch launchers, and automation tools. |
| `mod/amxx-mechanics` | `.worktrees/amxx-mechanics` | AMX Mod X plugins (`cstrike/addons/amxmodx/`), YAPB bots (`cstrike/addons/yapb/`), sound packs (`cstrike/sound/weapons/csgo/`), POV configs, custom models (`cstrike/models/custom_skins/`, `pw_models/`). |
| `release/complete` | Root workspace (`.`) | Production integration branch combining vanilla base, modern tooling, and active mod mechanics into a single turnkey installation. |

---

## 2. Why Multi-Worktree?

Traditional Git branching requires running `git checkout <branch>`, which swaps files back and forth across gigabytes of binaries and triggers IDE reload delays.

Git Multi-Worktree solves this:
1. **Zero Redundancy**: All worktrees share the single `.git` object store. No duplicated `.git` repositories.
2. **Concurrent Development**: You can edit and test Python tooling in `.worktrees/studio-mod-hub` while AMXX plugins are compiled in `.worktrees/amxx-mechanics`, without switching branches.
3. **Ignored by Default**: The `.worktrees/` directory is listed in `.gitignore`, keeping the root workspace clean.
4. **Instant Testing**: The root workspace remains permanently on `release/complete`, so testing the live integrated game requires zero re-checkout.

---

## 3. Daily Developer Workflows

### Scenario A: Developing Tooling & GUI
Navigate to the Studio worktree:
```bash
cd .worktrees/studio-mod-hub
```
Make changes to `scripts/`, `tools/cs16_mod_hub/`, or `tests/`. Run the test suite:
```bash
python -m unittest discover tests
```
Commit your tooling changes:
```bash
git add .
git commit -m "feat(studio): add new feature"
git push origin tools/studio-mod-hub
```

### Scenario B: Developing AMXX Plugins, Models, or Sounds
Navigate to the Mechanics worktree:
```bash
cd .worktrees/amxx-mechanics
```
Edit configs, add sounds, or update AMXX plugins. Commit your changes:
```bash
git add cstrike/addons/amxmodx/ ...
git commit -m "feat(amxx): update weapon sound table"
git push origin mod/amxx-mechanics
```

### Scenario C: Synchronizing Everything into Release
Return to the root workspace:
```bash
cd d:\Games\Counter-Strike\Counter-Strike 1.6 Original
```
Run the automated synchronization tool:
```bash
tools\sync_release.bat
```
Or via Python directly:
```bash
python tools/sync_release.py --sync --push
```

The script performs:
1. Validates that the root is on `release/complete`.
2. Inspects worktrees for uncommitted changes.
3. Merges `tools/studio-mod-hub` into `release/complete`.
4. Merges `mod/amxx-mechanics` into `release/complete`.
5. Pushes all branches to `origin` when `--push` is specified.

---

## 4. Worktree Lifecycle and Rebuilding

If the repository is cloned fresh or `.worktrees/` was cleared, rebuild the worktree links with:

```bash
# From repository root:
git checkout release/complete

# Create studio worktree:
git worktree add .worktrees/studio-mod-hub tools/studio-mod-hub

# Create amxx mechanics worktree:
git worktree add .worktrees/amxx-mechanics mod/amxx-mechanics
```

Verify active worktrees at any time:
```bash
git worktree list
```

Expected output:
```
D:/Games/Counter-Strike/Counter-Strike 1.6 Original                           <sha> [release/complete]
D:/Games/Counter-Strike/Counter-Strike 1.6 Original/.worktrees/amxx-mechanics <sha> [mod/amxx-mechanics]
D:/Games/Counter-Strike/Counter-Strike 1.6 Original/.worktrees/studio-mod-hub <sha> [tools/studio-mod-hub]
```

To remove a worktree cleanly:
```bash
git worktree remove .worktrees/studio-mod-hub
git worktree remove .worktrees/amxx-mechanics
```

---

## 5. Critical Safeguards and Conventions

1. **Active AMXX Sounds Safeguard**:
   Never delete `cstrike/sound/weapons/csgo/`. This directory contains active weapon and knife sound assets referenced by AMXX plugins.
2. **Zero Unicode Emojis**:
   All scripts, documentation, commit messages, and CLI outputs MUST use standard ASCII characters. Use bracketed tags like `[OK]`, `[INFO]`, `[WARN]`, `[ERROR]`. Emojis corrupt Windows batch consoles and break strict encoding validations.
3. **Automated Test Quality Gate**:
   Always run the automated test suite before merging into `release/complete`:
   ```bash
   python -m unittest discover tests
   ```
   All 276 tests must pass without regressions.
