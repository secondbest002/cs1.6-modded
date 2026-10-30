import struct
from pathlib import Path

root = Path(r"D:\Games\Counter-Strike\Counter-Strike 1.6 Original")

def inspect_quick(path):
    print(f"\n==========================================")
    print(f"PATH: {path}")
    if not path.exists():
        print("Not found")
        return
    with open(path, "rb") as f:
        data = f.read()

    numbodyparts, bodypartindex = struct.unpack_from("<II", data, 204)
    print(f"Bodyparts ({numbodyparts}):")
    for bp in range(numbodyparts):
        bp_off = bodypartindex + bp * 76
        bp_name, nummodels, _, modelindex = struct.unpack_from("<64s3i", data, bp_off)
        bp_str = bp_name.split(b"\x00")[0].decode("latin1", errors="ignore")
        m_names = []
        for m in range(nummodels):
            m_off = modelindex + m * 112
            m_name = struct.unpack_from("<64s", data, m_off)[0].split(b"\x00")[0].decode("latin1", errors="ignore")
            m_names.append(m_name)
        print(f"  BP {bp}: {bp_str} -> {', '.join(m_names)}")

    numtextures, textureindex = struct.unpack_from("<II", data, 180)
    print(f"Textures ({numtextures}):")
    for i in range(numtextures):
        tname, flags, w, h, _ = struct.unpack_from("<64sIIII", data, textureindex + i * 80)
        t_str = tname.split(b"\x00")[0].decode("latin1", errors="ignore")
        print(f"  [{i}] {t_str:<22} {w}x{h}")

inspect_quick(root / "cstrike" / "models" / "csgo_skins" / "ct" / "v_m4a4.mdl")
inspect_quick(root / "cstrike" / "models" / "archive_custom_skins" / "ct" / "v_m4a4.mdl")
