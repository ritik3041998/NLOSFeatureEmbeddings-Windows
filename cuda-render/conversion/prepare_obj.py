"""
prepare_obj.py  -  make ANY .obj loadable by the NLOS renderer.

The renderer's loader (display_4_loaddata.cpp :: readobj) requires each model to:
  * be TRIANGULATED  (every face has exactly 3 vertices)
  * have all vertex coordinates inside [-0.5, 0.5]  (else the model is skipped)
  * reference an .mtl via `mtllib` + `usemtl`
  * live at  <parent>/<name>/model/model_normalized.obj  (+ .mtl)

Arbitrary OBJs from the web usually fail (quads/ngons, wrong scale, no mtl).
This script fixes all of that with NO extra dependencies (pure Python):
  - reads v / f lines (ignores vt/vn, handles negative indices)
  - fan-triangulates quads and n-gons
  - centers the model and rescales so its largest side = --extent (default 0.9),
    guaranteeing it fits inside [-0.5, 0.5]
  - writes model_normalized.obj + model_normalized.mtl in the correct folders

Usage:
    python prepare_obj.py  chair.obj  ../../data/my-models  chair
    python prepare_obj.py  chair.obj  ../../data/my-models  chair --extent 0.9

Result:
    ../../data/my-models/chair/model/model_normalized.obj
    ../../data/my-models/chair/model/model_normalized.mtl

Then point main.cpp's parentFlder at  ../../data/my-models  and render.

(For .ply/.stl/.glb inputs, install trimesh and convert to .obj first, or adapt
this script with trimesh.load(path, force='mesh').)
"""
import argparse
import os


def load_obj(path):
    verts, faces = [], []
    with open(path, "r", errors="ignore") as f:
        for line in f:
            if line.startswith("v "):
                p = line.split()
                verts.append([float(p[1]), float(p[2]), float(p[3])])
            elif line.startswith("f "):
                toks = line.split()[1:]
                # take only the vertex index of each 'v/vt/vn' token
                idx = []
                for t in toks:
                    i = int(t.split("/")[0])
                    idx.append(i - 1 if i > 0 else len(verts) + i)  # neg = relative
                # fan-triangulate any polygon into triangles
                for k in range(1, len(idx) - 1):
                    faces.append((idx[0], idx[k], idx[k + 1]))
    if not verts or not faces:
        raise SystemExit("no vertices/faces parsed from %s" % path)
    return verts, faces


def normalize(verts, extent):
    xs = [v[0] for v in verts]
    ys = [v[1] for v in verts]
    zs = [v[2] for v in verts]
    cx, cy, cz = (min(xs) + max(xs)) / 2, (min(ys) + max(ys)) / 2, (min(zs) + max(zs)) / 2
    scale = max(max(xs) - min(xs), max(ys) - min(ys), max(zs) - min(zs))
    if scale == 0:
        raise SystemExit("degenerate mesh (zero size)")
    s = extent / scale
    return [[(v[0] - cx) * s, (v[1] - cy) * s, (v[2] - cz) * s] for v in verts]


MTL = """newmtl material_0
Ka 0 0 0
Kd 1 1 1
Ks 0.4 0.4 0.4
Ns 10
illum 2
"""


def write_model(verts, faces, out_dir):
    os.makedirs(out_dir, exist_ok=True)
    obj_path = os.path.join(out_dir, "model_normalized.obj")
    mtl_path = os.path.join(out_dir, "model_normalized.mtl")
    with open(mtl_path, "w") as m:
        m.write(MTL)
    with open(obj_path, "w") as o:
        o.write("mtllib model_normalized.mtl\n")
        o.write("usemtl material_0\n")
        for v in verts:
            o.write("v %.6f %.6f %.6f\n" % (v[0], v[1], v[2]))
        for a, b, c in faces:
            o.write("f %d %d %d\n" % (a + 1, b + 1, c + 1))  # OBJ is 1-indexed
    return obj_path


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("input", help="input .obj file")
    ap.add_argument("out_parent", help="parent folder for models (main.cpp parentFlder)")
    ap.add_argument("name", help="model name (becomes the sample folder name)")
    ap.add_argument("--extent", type=float, default=0.9,
                    help="largest side after scaling (must be < 1.0 to stay in [-0.5,0.5])")
    args = ap.parse_args()

    if args.extent >= 1.0:
        raise SystemExit("--extent must be < 1.0 so coords fit in [-0.5, 0.5]")

    verts, faces = load_obj(args.input)
    verts = normalize(verts, args.extent)
    out_dir = os.path.join(args.out_parent, args.name, "model")
    obj = write_model(verts, faces, out_dir)

    mn = [min(v[i] for v in verts) for i in range(3)]
    mx = [max(v[i] for v in verts) for i in range(3)]
    print("wrote %s" % obj)
    print("  vertices=%d  triangles=%d" % (len(verts), len(faces)))
    print("  bounds x[%.3f,%.3f] y[%.3f,%.3f] z[%.3f,%.3f]  (must be within [-0.5,0.5])"
          % (mn[0], mx[0], mn[1], mx[1], mn[2], mx[2]))


if __name__ == "__main__":
    main()
