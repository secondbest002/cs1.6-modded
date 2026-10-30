import os
import sys
import struct
from pathlib import Path

root = Path(r"D:\Games\Counter-Strike\Counter-Strike 1.6 Original")
sys.path.insert(0, str(root / "scripts"))

from cs16_studio.mdl_core import MdlModel

def inspect_model_structure(path):
    print(f"\n=======================================================")
    print(f"PATH: {path}")
    if not path.exists():
        print("Does not exist!")
        return
    with open(path, "rb") as f:
        data = f.read()

    magic, ver, name, length = struct.unpack_from("<4sI64sI", data, 0)
    name_str = name.split(b"\x00")[0].decode("latin1", errors="ignore")
    print(f"Name: {name_str}, Length: {length:,} bytes")

    numbodyparts, bodypartindex = struct.unpack_from("<II", data, 204)
    print(f"Bodyparts: {numbodyparts}")
    for bp in range(numbodyparts):
        bp_off = bodypartindex + bp * 76
        bp_name, nummodels, base, modelindex = struct.unpack_from("<64s3i", data, bp_off)
        bp_name_str = bp_name.split(b"\x00")[0].decode("latin1", errors="ignore")
        print(f"  Bodypart {bp}: '{bp_name_str}' (models: {nummodels})")
        for m in range(nummodels):
            m_off = modelindex + m * 112
            m_name, m_type, m_radius, nummesh, meshindex, numverts, _, vertindex = struct.unpack_from("<64sif5I", data, m_off)
            m_name_str = m_name.split(b"\x00")[0].decode("latin1", errors="ignore")
            print(f"    Submodel {m}: '{m_name_str}' (verts: {numverts}, meshes: {nummesh})")

    numtextures, textureindex = struct.unpack_from("<II", data, 180)
    print(f"Textures: {numtextures}")
    for i in range(numtextures):
        t_off = textureindex + i * 80
        tname, flags, w, h, _ = struct.unpack_from("<64sIIII", data, t_off)
        tname_str = tname.split(b"\x00")[0].decode("latin1", errors="ignore")
        print(f"    [{i}] {tname_str:<24} {w}x{h}")

inspect_model_structure(root / "cstrike" / "models" / "custom_skins" / "ct" / "v_m4a4.orig.mdl")
inspect_model_structure(root / "cstrike" / "models" / "custom_skins" / "ct" / "v_m4a4.mdl")
inspect_model_structure(root / "cstrike" / "models" / "custom_skins" / "ct" / "v_ak47_usethis_sleeve.mdl")
