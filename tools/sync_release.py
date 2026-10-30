"""
tools/sync_release.py - Git Multi-Worktree Release Synchronization Tool
Counter-Strike 1.6 Portable & Modular Hub

Automates verification, synchronization, and pushing across the modular worktree architecture:
- tools/studio-mod-hub (.worktrees/studio-mod-hub)
- mod/amxx-mechanics   (.worktrees/amxx-mechanics)
- release/complete     (repository root)

Zero Unicode Emojis - Standard ASCII output only.
"""

import argparse
import os
from pathlib import Path
import shutil
import subprocess
import sys

if hasattr(sys.stdout, 'reconfigure'):
    sys.stdout.reconfigure(encoding='utf-8', errors='replace')
if hasattr(sys.stderr, 'reconfigure'):
    sys.stderr.reconfigure(encoding='utf-8', errors='replace')


def find_git():
    user_git = os.path.expanduser(r'~\AppData\Local\Programs\Git\cmd\git.exe')
    if os.path.exists(user_git):
        return user_git
    which_git = shutil.which('git')
    if which_git:
        return which_git
    return 'git'


GIT_BIN = find_git()


def run_git(args, cwd=None, check=False):
    cmd = [GIT_BIN] + list(args)
    res = subprocess.run(
        cmd,
        cwd=str(cwd) if cwd else None,
        capture_output=True,
        text=True,
        encoding='utf-8',
        errors='replace'
    )
    if check and res.returncode != 0:
        err = res.stderr.strip() or res.stdout.strip()
        raise RuntimeError(f"Command failed ({res.returncode}): {' '.join(cmd)}\n{err}")
    return res


def get_repo_root():
    res = run_git(['rev-parse', '--show-toplevel'], check=True)
    return Path(res.stdout.strip()).resolve()


def get_worktree_info(path):
    if not path.exists():
        return {"exists": False, "branch": "N/A", "sha": "N/A", "dirty": False, "untracked": False}

    branch_res = run_git(['rev-parse', '--abbrev-ref', 'HEAD'], cwd=path)
    branch = branch_res.stdout.strip() if branch_res.returncode == 0 else "UNKNOWN"

    sha_res = run_git(['rev-parse', '--short', 'HEAD'], cwd=path)
    sha = sha_res.stdout.strip() if sha_res.returncode == 0 else "UNKNOWN"

    status_res = run_git(['status', '--porcelain'], cwd=path)
    lines = status_res.stdout.splitlines() if status_res.returncode == 0 else []

    dirty = any(not l.startswith('??') for l in lines)
    untracked = any(l.startswith('??') for l in lines)

    return {
        "exists": True,
        "branch": branch,
        "sha": sha,
        "dirty": dirty,
        "untracked": untracked,
        "file_count": len(lines)
    }


def show_status(root):
    print("=" * 70)
    print("GIT MULTI-WORKTREE ARCHITECTURE STATUS")
    print("=" * 70)

    worktrees = [
        ("Root Integration", root, "release/complete"),
        ("Studio & Mod Hub", root / ".worktrees" / "studio-mod-hub", "tools/studio-mod-hub"),
        ("AMXX Mechanics", root / ".worktrees" / "amxx-mechanics", "mod/amxx-mechanics")
    ]

    for label, path, expected_branch in worktrees:
        info = get_worktree_info(path)
        print(f"\n[{label}]")
        print(f"  Path:            {path}")
        if not info["exists"]:
            print(f"  Status:          [ERROR] Path does not exist!")
            continue

        branch_match = "[OK]" if info["branch"] == expected_branch else f"[WARN] (Expected: {expected_branch})"
        print(f"  Branch:          {info['branch']} {branch_match}")
        print(f"  Head Commit:     {info['sha']}")

        status_flags = []
        if info["dirty"]:
            status_flags.append(f"UNCOMMITTED CHANGES ({info['file_count']} files)")
        if info["untracked"]:
            status_flags.append("UNTRACKED FILES")
        if not info["dirty"] and not info["untracked"]:
            status_flags.append("CLEAN")

        status_str = ", ".join(status_flags)
        flag_tag = "[OK]" if "CLEAN" in status_flags else "[WARN]"
        print(f"  Worktree State:  {flag_tag} {status_str}")

    print("\n" + "=" * 70)


def sync_release(root, push=False):
    print("\n" + "=" * 70)
    print("SYNCHRONIZING RELEASE/COMPLETE")
    print("=" * 70)

    # 1. Verify root is on release/complete
    root_info = get_worktree_info(root)
    if root_info["branch"] != "release/complete":
        print(f"[ERROR] Root repository is on branch '{root_info['branch']}', but must be on 'release/complete'.")
        print("        Switch to release/complete before running sync: git checkout release/complete")
        return False

    # 2. Verify worktrees exist
    studio_wt = root / ".worktrees" / "studio-mod-hub"
    amxx_wt = root / ".worktrees" / "amxx-mechanics"

    if not studio_wt.exists():
        print(f"[ERROR] Studio worktree not found at: {studio_wt}")
        print("        Recreate worktree with: git worktree add .worktrees/studio-mod-hub tools/studio-mod-hub")
        return False

    if not amxx_wt.exists():
        print(f"[ERROR] AMXX Mechanics worktree not found at: {amxx_wt}")
        print("        Recreate worktree with: git worktree add .worktrees/amxx-mechanics mod/amxx-mechanics")
        return False

    # Check for uncommitted tracked changes in worktrees
    studio_info = get_worktree_info(studio_wt)
    if studio_info["dirty"]:
        print(f"[WARN] Worktree 'studio-mod-hub' has uncommitted changes.")
        print("       Commit those changes in .worktrees/studio-mod-hub to include them in release.")

    amxx_info = get_worktree_info(amxx_wt)
    if amxx_info["dirty"]:
        print(f"[WARN] Worktree 'amxx-mechanics' has uncommitted changes.")
        print("       Commit those changes in .worktrees/amxx-mechanics to include them in release.")

    # 3. Merge tools/studio-mod-hub into release/complete
    print("\n[STEP 1/2] Merging 'tools/studio-mod-hub' into 'release/complete'...")
    merge1 = run_git(['merge', 'tools/studio-mod-hub', '-m', 'sync: integrate tools/studio-mod-hub into release'], cwd=root)
    if merge1.returncode != 0:
        print("[ERROR] Merge of 'tools/studio-mod-hub' failed!")
        print(merge1.stdout.strip())
        print(merge1.stderr.strip())
        return False
    print("  " + (merge1.stdout.strip().splitlines()[0] if merge1.stdout.strip() else "[OK] Merged cleanly."))

    # 4. Merge mod/amxx-mechanics into release/complete
    print("\n[STEP 2/2] Merging 'mod/amxx-mechanics' into 'release/complete'...")
    merge2 = run_git(['merge', 'mod/amxx-mechanics', '-m', 'sync: integrate mod/amxx-mechanics into release'], cwd=root)
    if merge2.returncode != 0:
        print("[ERROR] Merge of 'mod/amxx-mechanics' failed!")
        print(merge2.stdout.strip())
        print(merge2.stderr.strip())
        return False
    print("  " + (merge2.stdout.strip().splitlines()[0] if merge2.stdout.strip() else "[OK] Merged cleanly."))

    print("\n[OK] 'release/complete' successfully synchronized with all branches.")

    # 5. Push if requested
    if push:
        return push_all(root, studio_wt, amxx_wt)

    return True


def push_all(root, studio_wt=None, amxx_wt=None):
    if studio_wt is None:
        studio_wt = root / ".worktrees" / "studio-mod-hub"
    if amxx_wt is None:
        amxx_wt = root / ".worktrees" / "amxx-mechanics"

    print("\n" + "=" * 70)
    print("PUSHING ALL BRANCHES TO ORIGIN")
    print("=" * 70)

    # Push tools/studio-mod-hub
    if studio_wt.exists():
        print("\n[*] Pushing 'tools/studio-mod-hub' to origin...")
        p1 = run_git(['push', 'origin', 'tools/studio-mod-hub'], cwd=studio_wt)
        if p1.returncode != 0:
            print(f"[WARN] Failed to push tools/studio-mod-hub: {p1.stderr.strip()}")
        else:
            print("[OK] 'tools/studio-mod-hub' pushed to origin.")

    # Push mod/amxx-mechanics
    if amxx_wt.exists():
        print("\n[*] Pushing 'mod/amxx-mechanics' to origin...")
        p2 = run_git(['push', 'origin', 'mod/amxx-mechanics'], cwd=amxx_wt)
        if p2.returncode != 0:
            print(f"[WARN] Failed to push mod/amxx-mechanics: {p2.stderr.strip()}")
        else:
            print("[OK] 'mod/amxx-mechanics' pushed to origin.")

    # Push release/complete
    print("\n[*] Pushing 'release/complete' to origin...")
    p3 = run_git(['push', 'origin', 'release/complete'], cwd=root)
    if p3.returncode != 0:
        print(f"[WARN] Failed to push release/complete: {p3.stderr.strip()}")
        return False
    else:
        print("[OK] 'release/complete' pushed to origin.")

    print("\n[OK] All branches pushed to origin successfully.")
    return True


def main():
    parser = argparse.ArgumentParser(
        description="Synchronize and manage Git Multi-Worktree architecture for Counter-Strike 1.6."
    )
    parser.add_argument(
        "--status",
        action="store_true",
        help="Check status of all worktrees and branches without modifying."
    )
    parser.add_argument(
        "--sync",
        action="store_true",
        help="Merge updates from studio-mod-hub and amxx-mechanics into release/complete."
    )
    parser.add_argument(
        "--push",
        action="store_true",
        help="Push updated branches to origin."
    )

    args = parser.parse_args()

    try:
        root = get_repo_root()
    except Exception as e:
        print(f"[FATAL] Could not determine repository root: {e}")
        sys.exit(1)

    if args.status:
        show_status(root)
        sys.exit(0)

    if args.push and not args.sync:
        success = push_all(root)
        sys.exit(0 if success else 1)

    # Default action or --sync
    show_status(root)
    success = sync_release(root, push=args.push)
    sys.exit(0 if success else 1)


if __name__ == "__main__":
    main()
