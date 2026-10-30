import os
import subprocess

git = os.path.expanduser(r'~\AppData\Local\Programs\Git\cmd\git.exe')

def run(cmd):
    res = subprocess.run([git] + cmd, capture_output=True, text=True)
    print(f"=== git {' '.join(cmd)} ===")
    if res.stdout.strip():
        print("STDOUT:\n" + res.stdout.strip())
    if res.stderr.strip():
        print("STDERR:\n" + res.stderr.strip())

run(['branch', '-a'])
run(['log', '--oneline', '--all', '-n', '10'])
