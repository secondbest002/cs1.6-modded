import struct
from pathlib import Path

root = Path(r"D:\Games\Counter-Strike\Counter-Strike 1.6 Original")

def inspect_submodel_textures(path):
    print(f"\nSubmodel Texture Mapping for: {path.name}")
    with open(path, "rb") as f:
        data = f.read()

    numtextures, textureindex = struct.unpack_from("<II", data, 180)
    textures = []
    for i in range(numtextures):
        t_off = textureindex + i * 80
        tname, flags, w, h, _ = struct.unpack_from("<64sIIII", data, t_off)
        textures.append(tname.split(b"\x00")[0].decode("latin1", errors="ignore"))

    numskinref, numskinfamilies, skinindex = struct.unpack_from("<III", data, 192)
    skin_table = []
    if numskinref > 0 and 0 < skinindex < len(data):
        skin_table = list(struct.unpack_from(f"<{numskinref}h", data, skinindex))

    numbodyparts, bodypartindex = struct.unpack_from("<II", data, 204)
    for bp in range(numbodyparts):
        bp_off = bodypartindex + bp * 76
        bp_name, nummodels, base, modelindex = struct.unpack_from("<64s3i", data, bp_off)
        bp_name_str = bp_name.split(b"\x00")[0].decode("latin1", errors="ignore")
        for m in range(nummodels):
            m_off = modelindex + m * 112
            m_name, _, _, nummesh, meshindex = struct.unpack_from("<64sif2I", data, m_off)
            m_name_str = m_name.split(b"\x00")[0].decode("latin1", errors="ignore")
            used_texs = []
            for mi in range(nummesh):
                numtris, triindex, skinref = struct.unpack_from("<3i", data, meshindex + mi * 20)
                actual_idx = skin_table[skinref] if skinref < len(skin_table) else skinref
                tex_name = textures[actual_idx] if actual_idx < len(textures) else f"unknown_{actual_idx}"
                used_texs.append(f"{tex_name} (idx {actual_idx})")
            print(f"  BP {bp:2d} | Submodel: {m_name_str:<22} -> Textures: {', '.join(used_texs)}")

inspect_submodel_textures(root / "cstrike" / "models" / "custom_skins" / "ct" / "v_m4a4.orig.mdl")
inspect_submodel_textures(root / "cstrike" / "models" / "custom_skins" / "ct" / "v_m4a4.mdl")
