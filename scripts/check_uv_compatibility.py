import struct
from pathlib import Path

root = Path(r"D:\Games\Counter-Strike\Counter-Strike 1.6 Original")

def get_mesh_uv_bounds(path, tex_idx):
    with open(path, "rb") as f:
        data = f.read()

    numskinref, numskinfamilies, skinindex = struct.unpack_from("<III", data, 192)
    skin_table = list(struct.unpack_from(f"<{numskinref}h", data, skinindex)) if numskinref > 0 else []

    numbodyparts, bodypartindex = struct.unpack_from("<II", data, 204)
    uv_points = []
    for bp in range(numbodyparts):
        bp_off = bodypartindex + bp * 76
        nummodels, _, modelindex = struct.unpack_from("<3i", data, bp_off + 64)
        for m in range(nummodels):
            m_off = modelindex + m * 112
            nummesh, meshindex = struct.unpack_from("<2I", data, m_off + 72)
            for mi in range(nummesh):
                numtris, triindex, skinref = struct.unpack_from("<3i", data, meshindex + mi * 20)
                actual_idx = skin_table[skinref] if skinref < len(skin_table) else skinref
                if actual_idx == tex_idx:
                    pos = triindex
                    while pos + 2 <= len(data):
                        strip_len = struct.unpack_from("<h", data, pos)[0]
                        pos += 2
                        if strip_len == 0:
                            break
                        count = abs(strip_len)
                        for _ in range(count):
                            v_idx, n_idx, s, t = struct.unpack_from("<4h", data, pos)
                            pos += 8
                            uv_points.append((s, t))

    min_s = min(p[0] for p in uv_points) if uv_points else None
    max_s = max(p[0] for p in uv_points) if uv_points else None
    min_t = min(p[1] for p in uv_points) if uv_points else None
    max_t = max(p[1] for p in uv_points) if uv_points else None
    return len(uv_points), (min_s, max_s, min_t, max_t)

orig_p = root / "cstrike" / "models" / "custom_skins" / "ct" / "v_m4a4.orig.mdl"
tgt_p = root / "cstrike" / "models" / "custom_skins" / "ct" / "v_m4a4.mdl"

print("Orig rif_m4a1 (idx 9):", get_mesh_uv_bounds(orig_p, 9))
print("Target rif_m4a1 (idx 3):", get_mesh_uv_bounds(tgt_p, 3))
