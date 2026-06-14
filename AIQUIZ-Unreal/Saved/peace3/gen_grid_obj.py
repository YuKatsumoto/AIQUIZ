# Generates a tessellated horizontal grid plane as OBJ, matching the dimensions
# and UVs of /Engine/BasicShapes/Plane (100x100 uu, centred, UV 0..1) so the
# magma material maps identically. High vertex count enables WPO displacement.
# UE's OBJ (Interchange) importer copies OBJ coordinates directly (no axis
# convert), so author a horizontal Z-up plane in the XY plane (z=0, normal +Z).
N = 100          # subdivisions per side -> (N+1)^2 verts, N*N*2 tris
H = 50.0         # half extent (matches BasicShapes/Plane: -50..50)
OUT = r"C:/AIQUIZ/AIQUIZ-Unreal/Saved/peace3/SM_MagmaGrid.obj"

lines = ["# AIQUIZ magma displacement grid", "o MagmaGrid"]
# vertices + UVs
for j in range(N + 1):
    for i in range(N + 1):
        x = -H + (2 * H) * (i / N)
        y = -H + (2 * H) * (j / N)
        lines.append("v %.5f %.5f 0.0" % (x, y))
for j in range(N + 1):
    for i in range(N + 1):
        u = i / N
        v = j / N
        lines.append("vt %.5f %.5f" % (u, v))
lines.append("vn 0.0 0.0 1.0")


def idx(i, j):
    return j * (N + 1) + i + 1   # OBJ is 1-based


for j in range(N):
    for i in range(N):
        a = idx(i, j)
        b = idx(i + 1, j)
        c = idx(i + 1, j + 1)
        d = idx(i, j + 1)
        # two CCW triangles facing +Y (up), with matching vt/vn refs
        lines.append("f %d/%d/1 %d/%d/1 %d/%d/1" % (a, a, b, b, c, c))
        lines.append("f %d/%d/1 %d/%d/1 %d/%d/1" % (a, a, c, c, d, d))

with open(OUT, "w", encoding="utf-8") as f:
    f.write("\n".join(lines))
print("wrote", OUT, "verts", (N + 1) ** 2, "tris", N * N * 2)
