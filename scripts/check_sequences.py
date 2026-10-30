import struct
from pathlib import Path

root = Path(r"D:\Games\Counter-Strike\Counter-Strike 1.6 Original")

def get_sequences(path):
    with open(path, "rb") as f:
        data = f.read()
    numseq, seqindex = struct.unpack_from("<II", data, 164)
    seqs = []
    for i in range(numseq):
        s_off = seqindex + i * 176
        s_label = struct.unpack_from("<32s", data, s_off)[0].split(b"\x00")[0].decode("latin1", errors="ignore")
        numframes = struct.unpack_from("<i", data, s_off + 68)[0]
        fps = struct.unpack_from("<f", data, s_off + 64)[0]
        seqs.append(f"{s_label} (frames: {numframes}, fps: {fps:.1f})")
    return seqs

orig_p = root / "cstrike" / "models" / "custom_skins" / "ct" / "v_m4a4.orig.mdl"
tgt_p = root / "cstrike" / "models" / "custom_skins" / "ct" / "v_m4a4.mdl"

print("Orig sequences:")
for s in get_sequences(orig_p):
    print(" ", s)

print("\nTarget sequences:")
for s in get_sequences(tgt_p):
    print(" ", s)
