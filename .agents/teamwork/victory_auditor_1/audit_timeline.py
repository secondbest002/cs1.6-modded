import os
import time

def check_dir(dir_path):
    results = []
    for root, dirs, files in os.walk(dir_path):
        for f in files:
            p = os.path.join(root, f)
            mtime = os.path.getmtime(p)
            results.append((mtime, p, os.path.getsize(p)))
    return results

print("=== TIMELINE INSPECTION ===")
all_files = []
for d in ['tools/cs16_mod_hub', 'tests']:
    if os.path.exists(d):
        all_files.extend(check_dir(d))
if os.path.exists('CS16_Mod_Manager.bat'):
    all_files.append((os.path.getmtime('CS16_Mod_Manager.bat'), 'CS16_Mod_Manager.bat', os.path.getsize('CS16_Mod_Manager.bat')))

all_files.sort(key=lambda x: x[0])

for mtime, path, size in all_files:
    if '__pycache__' not in path:
        tstr = time.strftime('%Y-%m-%d %H:%M:%S', time.gmtime(mtime))
        print(f"{tstr} UTC | {size:6d} B | {path}")

print("\n=== PRE-POPULATED LOGS / OUTPUT ARTIFACTS DETECTION ===")
suspicious = []
for root, dirs, files in os.walk('.'):
    # Skip .git or .agents metadata
    if '.git' in root or '.agents' in root or '__pycache__' in root:
        continue
    for f in files:
        if f.endswith(('.log', '.out', '.tmp', '.txt')) or 'result' in f.lower() or 'output' in f.lower():
            suspicious.append(os.path.join(root, f))

print(f"Suspicious artifact count in workspace: {len(suspicious)}")
for s in suspicious:
    print(f"  {s}")
