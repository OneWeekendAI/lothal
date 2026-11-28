"""Build the seven catalogue PARTS (motor, stack, battery, camera, vtx, antenna, receiver) as glTF.

Run all:  /opt/homebrew/bin/blender -b -P tools/blender/build_parts.py -- --all
Run one:  /opt/homebrew/bin/blender -b -P tools/blender/build_parts.py -- --part motor

Outputs assets/models/parts/<name>.glb, assets/models/parts/src/<name>.blend, assets/models/parts/parts.json.

Conventions (a Godot loader relies on these):
  * metres; Blender +Y is the front (glTF -Z = Godot forward); +Z up (Godot +Y)
  * origin = centre of the part's BOTTOM face (its seat); measured geometry starts at z = 0
  * mesh objects named x_* are UNMEASURED (decorative: shaft, strap, leads, antenna wires). Everything
    else is MEASURED and its bounding box must equal the reference dims below (within 0.05 mm)
  * greyscale materials only, no textures, no text or brand marks
Exit status is non-zero if a budget, a dimension or the greyscale rule fails.
"""
import sys, os, json, struct
from math import pi, sin, cos, radians
import bpy, bmesh
from mathutils import Matrix, Vector, geometry

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))
OUT = os.path.join(ROOT, "assets", "models", "parts")
SRC = os.path.join(OUT, "src")
MM = 0.001

# name -> (x, y(depth, Blender Y), z(height, up)) in mm, and triangle budget
REF = {
    "motor": ((28.0, 28.0, 16.0), 6000),
    "stack": ((36.0, 36.0, 12.0), 8000),
    "battery": ((35.0, 75.0, 37.0), 4000),
    "camera": ((19.0, 19.0, 19.0), 3000),
    "vtx": ((30.0, 30.0, 6.0), 2500),
    "antenna": ((22.0, 22.0, 95.0), 1500),
    "receiver": ((14.0, 11.0, 3.0), 1200),
}
ORDER = list(REF)
TOL_MM = 0.05

# ----------------------------------------------------------------------------- materials
# greyscale base colours (linear). metallic / roughness are the only look levers.
MATS = {
    "matte_board": (0.025, 0.0, 0.55, {}),
    "board_edge": (0.06, 0.0, 0.5, {}),
    "chip": (0.012, 0.0, 0.5, {}),
    "tin": (0.55, 1.0, 0.3, {}),
    "steel": (0.35, 1.0, 0.35, {}),
    "steel_dark": (0.12, 1.0, 0.4, {}),
    "alu": (0.6, 1.0, 0.3, {}),
    "anodized": (0.07, 1.0, 0.28, {}),
    "lamination": (0.22, 1.0, 0.45, {}),
    "winding": (0.42, 1.0, 0.34, {}),
    "magnet": (0.40, 1.0, 0.25, {}),
    "rubber": (0.02, 0.0, 0.8, {}),
    "rubber_light": (0.08, 0.0, 0.75, {}),
    "foam": (0.05, 0.0, 0.9, {}),
    "wrap": (0.10, 0.0, 0.42, {}),
    "wrap_cap": (0.03, 0.0, 0.5, {}),
    "nylon": (0.2, 0.0, 0.45, {}),
    "connector": (0.33, 0.0, 0.5, {}),
    "gold": (0.6, 1.0, 0.25, {}),
    "wire_dark": (0.012, 0.0, 0.42, {}),
    "wire_light": (0.5, 0.0, 0.42, {}),
    "wire_mid": (0.18, 0.0, 0.42, {}),
    "cam_body": (0.03, 0.0, 0.45, {}),
    "lens_ring": (0.1, 1.0, 0.3, {}),
    "lens_glass": (0.02, 0.0, 0.03, {"Transmission Weight": 0.3, "IOR": 1.5, "Coat Weight": 1.0, "Coat Roughness": 0.0}),
    "shrink": (0.02, 0.0, 0.55, {}),
    "can": (0.7, 1.0, 0.35, {}),
}
_matcache = {}


def mat(name):
    if name in _matcache and _matcache[name].name in bpy.data.materials:
        return _matcache[name]
    col, met, rough, extra = MATS[name]
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    b = m.node_tree.nodes["Principled BSDF"]
    b.inputs["Base Color"].default_value = (col, col, col, 1.0)
    b.inputs["Metallic"].default_value = met
    b.inputs["Roughness"].default_value = rough
    for k, v in extra.items():
        b.inputs[k].default_value = v
    m.diffuse_color = (col, col, col, 1.0)
    _matcache[name] = m
    return m


# ----------------------------------------------------------------------------- geometry kit (mm in, metres out)
def T(x=0, y=0, z=0):
    return Matrix.Translation((x, y, z))


def RX(a):
    return Matrix.Rotation(a, 4, "X")


def RZ(a):
    return Matrix.Rotation(a, 4, "Z")


# local z -> world +Y (forward). local y -> world -z. Use for things whose axis points to the front.
ALONG_Y = RX(-pi / 2)


def along_y(x=0, y0=0, z=0):
    """Local z runs along world +Y from y0; (x, z) is the axis position in the cross-section."""
    return T(x, y0, z) @ ALONG_Y


def ccw(pts):
    a = sum(pts[i][0] * pts[(i + 1) % len(pts)][1] - pts[(i + 1) % len(pts)][0] * pts[i][1] for i in range(len(pts)))
    return list(pts) if a > 0 else list(pts)[::-1]


def circle(r, n, cx=0.0, cy=0.0, a0=0.0):
    return [(cx + r * cos(a0 + 2 * pi * i / n), cy + r * sin(a0 + 2 * pi * i / n)) for i in range(n)]


def rrect(hx, hy, r, n=4):
    """Rounded rectangle half-sizes hx, hy, corner radius r. Straight edges sit exactly at +-hx / +-hy."""
    pts = []
    for (cx, cy, a0) in ((hx - r, -hy + r, -pi / 2), (hx - r, hy - r, 0), (-hx + r, hy - r, pi / 2), (-hx + r, -hy + r, pi)):
        for i in range(n + 1):
            a = a0 + (pi / 2) * i / n
            pts.append((cx + r * cos(a), cy + r * sin(a)))
    return pts


def chamf(hx, hy, c):
    return [(hx - c, -hy), (hx, -hy + c), (hx, hy - c), (hx - c, hy), (-hx + c, hy), (-hx, hy - c), (-hx, -hy + c), (-hx + c, -hy)]


class Part:
    """Collects bmesh geometry per object name; faces carry a material slot."""

    def __init__(self, name):
        self.name = name
        self.bms = {}
        self.slots = {}

    def _bm(self, obj):
        if obj not in self.bms:
            self.bms[obj] = bmesh.new()
            self.slots[obj] = []
        return self.bms[obj]

    def _face(self, obj, matname, verts, M):
        bm = self.bms[obj]
        sl = self.slots[obj]
        if matname not in sl:
            sl.append(matname)
        vs = [bm.verts.new((M @ Vector(v)) * MM) for v in verts]
        try:
            f = bm.faces.new(vs)
        except ValueError:
            return
        f.material_index = sl.index(matname)

    def poly_prism(self, obj, matname, outline, z0, z1, M=None, holes=()):
        """Extrude a CCW outline (optionally with hole outlines) between z0 and z1."""
        M = M or Matrix.Identity(4)
        self._bm(obj)
        outline = ccw(outline)
        holes = [ccw(h)[::-1] for h in holes]            # holes run clockwise
        loops = [outline] + holes
        flat = [p for lp in loops for p in lp]
        if holes:
            tris = geometry.tessellate_polygon([[Vector((x, y, 0)) for x, y in lp] for lp in loops])
        else:
            tris = geometry.tessellate_polygon([[Vector((x, y, 0)) for x, y in outline]])
        for a, b, c in tris:
            self._face(obj, matname, [(flat[a][0], flat[a][1], z1), (flat[b][0], flat[b][1], z1), (flat[c][0], flat[c][1], z1)], M)
            self._face(obj, matname, [(flat[c][0], flat[c][1], z0), (flat[b][0], flat[b][1], z0), (flat[a][0], flat[a][1], z0)], M)
        for lp in loops:
            n = len(lp)
            for i in range(n):
                p, q = lp[i], lp[(i + 1) % n]
                self._face(obj, matname, [(p[0], p[1], z0), (q[0], q[1], z0), (q[0], q[1], z1), (p[0], p[1], z1)], M)

    def box(self, obj, matname, sx, sy, sz, M=None, z0=None):
        """Box centred in x/y on the matrix origin; z from z0 (default centred)."""
        z0 = -sz / 2 if z0 is None else z0
        self.poly_prism(obj, matname, [(-sx / 2, -sy / 2), (sx / 2, -sy / 2), (sx / 2, sy / 2), (-sx / 2, sy / 2)], z0, z0 + sz, M)

    def cyl(self, obj, matname, r, z0, z1, seg=24, M=None, r1=None, a0=0.0):
        """Cylinder or frustum (r at z0, r1 at z1), caps closed."""
        M = M or Matrix.Identity(4)
        self._bm(obj)
        r1 = r if r1 is None else r1
        for i in range(seg):
            a, b = a0 + 2 * pi * i / seg, a0 + 2 * pi * (i + 1) / seg
            p0, q0 = (r * cos(a), r * sin(a)), (r * cos(b), r * sin(b))
            p1, q1 = (r1 * cos(a), r1 * sin(a)), (r1 * cos(b), r1 * sin(b))
            self._face(obj, matname, [(p0[0], p0[1], z0), (q0[0], q0[1], z0), (q1[0], q1[1], z1), (p1[0], p1[1], z1)], M)
            if r1 > 0:
                self._face(obj, matname, [(0, 0, z1), (p1[0], p1[1], z1), (q1[0], q1[1], z1)], M)
            self._face(obj, matname, [(q0[0], q0[1], z0), (p0[0], p0[1], z0), (0, 0, z0)], M)

    def sector(self, obj, matname, rin, rout, a0, a1, z0, z1, n=2, M=None):
        """Annular sector (a post of a slotted bell, a magnet arc)."""
        M = M or Matrix.Identity(4)
        self._bm(obj)
        angs = [a0 + (a1 - a0) * i / n for i in range(n + 1)]
        P = lambda r, a, z: (r * cos(a), r * sin(a), z)
        for i in range(n):
            a, b = angs[i], angs[i + 1]
            self._face(obj, matname, [P(rout, a, z0), P(rout, b, z0), P(rout, b, z1), P(rout, a, z1)], M)
            self._face(obj, matname, [P(rin, b, z0), P(rin, a, z0), P(rin, a, z1), P(rin, b, z1)], M)
            self._face(obj, matname, [P(rin, a, z1), P(rin, b, z1), P(rout, b, z1), P(rout, a, z1)], M)
            self._face(obj, matname, [P(rout, a, z0), P(rout, b, z0), P(rin, b, z0), P(rin, a, z0)], M)
        for a in (angs[0], angs[-1]):
            self._face(obj, matname, [P(rin, a, z0), P(rout, a, z0), P(rout, a, z1), P(rin, a, z1)], M)

    def torus(self, obj, matname, R, r, nu=32, nv=8, M=None):
        M = M or Matrix.Identity(4)
        self._bm(obj)
        P = lambda i, j: (((R + r * cos(2 * pi * j / nv)) * cos(2 * pi * i / nu)),
                          ((R + r * cos(2 * pi * j / nv)) * sin(2 * pi * i / nu)), r * sin(2 * pi * j / nv))
        for i in range(nu):
            for j in range(nv):
                self._face(obj, matname, [P(i, j), P(i + 1, j), P(i + 1, j + 1), P(i, j + 1)], M)

    def tube(self, obj, matname, pts, r, sides=6):
        """Wire along a polyline (mm points); each segment a capped prism, joints overlap."""
        for a, b in zip(pts[:-1], pts[1:]):
            a, b = Vector(a), Vector(b)
            d = b - a
            L = d.length
            if L < 1e-6:
                continue
            q = d.normalized().to_track_quat("Z", "Y")
            self.cyl(obj, matname, r, 0, L, sides, T(*a) @ q.to_matrix().to_4x4())

    def finish(self):
        """Create Blender objects: edge-split smooth shading, one slot per material."""
        for obj, bm in self.bms.items():
            bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
            me = bpy.data.meshes.new(obj)
            bm.to_mesh(me)
            bm.free()
            for s in self.slots[obj]:
                me.materials.append(mat(s))
            for p in me.polygons:
                p.use_smooth = True
            ob = bpy.data.objects.new(obj, me)
            bpy.context.scene.collection.objects.link(ob)
            md = ob.modifiers.new("split", "EDGE_SPLIT")
            md.split_angle = radians(32)
            md.use_edge_angle = True
            md.use_edge_sharp = False


# ----------------------------------------------------------------------------- the seven parts
def chip(P, obj, x, y, z, sx, sy, sz, pins=True):
    P.box(obj, "chip", sx, sy, sz, T(x, y, 0), z0=z)
    if pins:
        P.box(obj, "tin", sx + 0.7, sy + 0.7, sz * 0.35, T(x, y, 0), z0=z)


def build_motor(P):
    # base flange with four M2 mount holes on a 12 mm pattern
    holes = [circle(1.1, 10, 8.49 * cos(pi / 4 + k * pi / 2), 8.49 * sin(pi / 4 + k * pi / 2)) for k in range(4)]
    P.poly_prism("motor_base", "anodized", circle(11.0, 48), 0, 2.5, holes=holes)
    P.cyl("motor_base", "anodized", 7.0, 2.5, 3.6, 36)            # hub that carries the stator
    P.cyl("motor_base", "steel_dark", 3.4, 3.6, 5.5, 20)          # bearing seat
    # stator: star of 12 teeth, windings over the teeth
    star = []
    for k in range(12):
        c = 2 * pi * k / 12
        for da, r in ((-0.20, 10.6), (-0.07, 10.6), (-0.065, 6.8), (0.065, 6.8), (0.07, 10.6), (0.20, 10.6)):
            if r == 6.8 and abs(da) > 0.1:
                continue
            star.append((r * cos(c + da), r * sin(c + da)))
    P.poly_prism("motor_stator", "lamination", star, 5.4, 12.6)
    for k in range(12):
        c = 2 * pi * k / 12
        P.box("motor_winding", "winding", 3.4, 2.9, 8.2, T(8.6 * cos(c), 8.6 * sin(c), 0) @ RZ(c), z0=4.9)
    # bell: solid foot ring, 12 posts with cooling slots between them, closed cap
    P.poly_prism("motor_bell", "anodized", circle(14.0, 48), 3.6, 5.0, holes=[circle(12.6, 48)])
    for k in range(12):
        c = radians(15 + 30 * k)
        P.sector("motor_bell", "anodized", 12.6, 14.0, c - radians(8), c + radians(8), 5.0, 14.0, n=3)
    P.cyl("motor_bell", "anodized", 14.0, 14.0, 15.3, 48, r1=14.0)
    P.cyl("motor_bell", "anodized", 14.0, 15.3, 16.0, 48, r1=13.2)
    # magnets stuck inside the bell, seen through the slots
    for k in range(14):
        c = 2 * pi * k / 14
        P.sector("motor_magnet", "magnet", 11.4, 12.6, c - radians(10.5), c + radians(10.5), 5.6, 13.4, n=1)
    # unmeasured: shaft and the prop nut stand above the bell
    P.cyl("x_shaft", "steel", 1.5, 4.0, 22.0, 16)
    P.cyl("x_prop_nut", "steel_dark", 4.4, 16.0, 20.0, 6, a0=0.0)
    P.cyl("x_prop_nut", "steel_dark", 3.4, 20.0, 20.8, 16)


def build_stack(P):
    ZE0, ZE1 = 2.0, 3.6          # ESC
    ZF0, ZF1 = 8.4, 10.0         # FC
    pat = 15.25                  # 30.5 mm pattern
    for z0, z1, obj in ((ZE0, ZE1, "stack_esc"), (ZF0, ZF1, "stack_fc")):
        holes = [circle(1.6, 12, sx * pat, sy * pat) for sx in (-1, 1) for sy in (-1, 1)]
        P.poly_prism(obj, "matte_board", chamf(18.0, 18.0, 2.5), z0, z1, holes=holes)
    # ESC top: MOSFET rows, big capacitor lying between the boards, solder pads, connector
    for s in (-1, 1):
        for i in range(6):
            chip(P, "stack_esc_parts", s * 10.5, -12.5 + i * 5.0, ZE1, 4.2, 4.2, 0.9, pins=False)
    chip(P, "stack_esc_parts", 0, 4.0, ZE1, 7.0, 7.0, 1.0)
    P.cyl("stack_esc_parts", "wire_dark", 2.2, -4.0, 4.0, 20, T(3.5, -12.0, ZE1 + 2.2) @ RX(0) @ Matrix.Rotation(pi / 2, 4, "Y"))
    P.cyl("stack_esc_parts", "alu", 2.1, 4.0, 4.2, 20, T(3.5, -12.0, ZE1 + 2.2) @ Matrix.Rotation(pi / 2, 4, "Y"))
    for s in (-1, 1):
        for j in range(3):
            P.box("stack_esc_parts", "tin", 2.6, 4.2, 0.2, T(s * (14.8 - 3.4 * j), 15.2, 0), z0=ZE1)
    for s in (-1, 1):
        P.box("stack_esc_parts", "tin", 4.0, 3.5, 0.2, T(s * 5.0, -16.0, 0), z0=ZE1)
    # FC top: MCU, gyro, flash, baro, USB-C, JST sockets
    chip(P, "stack_fc_parts", 2.0, -2.0, ZF1, 7.2, 7.2, 1.1)
    chip(P, "stack_fc_parts", -9.0, 6.0, ZF1, 3.0, 3.0, 0.8)
    chip(P, "stack_fc_parts", 10.0, 8.0, ZF1, 5.0, 4.0, 0.8)
    chip(P, "stack_fc_parts", -6.0, -10.0, ZF1, 4.0, 4.0, 0.7)
    for i in range(7):
        P.box("stack_fc_parts", "chip", 1.0, 0.6, 0.4, T(-12.0 + i * 3.5, 13.0, 0), z0=ZF1)
    for s in (-1, 1):
        P.box("stack_fc_parts", "connector", 3.0, 9.0, 1.6, T(s * 15.4, 0.0, 0), z0=ZF1)
    P.box("stack_fc_parts", "alu", 9.0, 7.5, 1.4, T(0.0, 14.1, 0), z0=ZF1)
    # standoffs (hex) and rubber gummies (bottom under the ESC, top over the FC)
    for sx in (-1, 1):
        for sy in (-1, 1):
            c = T(sx * pat, sy * pat, 0)
            P.cyl("stack_standoff", "anodized", 2.75, ZE1, ZF0, 6, c)
            P.cyl("stack_standoff", "anodized", 1.5, ZE0 - 0.2, ZE1, 12, c)
            P.cyl("stack_gummy", "rubber", 2.7, 0.0, ZE0, 16, c)
            P.cyl("stack_gummy", "rubber", 1.2, ZF1, ZF1 + 0.4, 12, c)
            P.cyl("stack_gummy", "rubber", 2.7, ZF1 + 0.4, 12.0, 16, c)


def build_battery(P):
    L, W, H = 75.0, 35.0, 37.0
    # one satin shrink-wrapped box, ~2 mm edge bevel made from stepped layers
    for z0, z1, ins in ((0.0, 0.5, 1.4), (0.5, 1.1, 0.7), (1.1, H - 1.1, 0.0), (H - 1.1, H - 0.5, 0.7), (H - 0.5, H, 1.4)):
        P.poly_prism("battery_wrap", "wrap", rrect(W / 2 - ins, L / 2 - ins, max(3.0 - ins, 0.8)), z0, z1)
    # unmeasured: thin rubber sheet under the seat
    P.poly_prism("x_pad", "foam", rrect(15.5, 34.0, 2.0), -1.8, 0.0)
    # strap: thin band (20 wide, 1 thick) over the top and down both sides, open underneath
    t, zb, ro, ri = 1.0, 4.0, 2.5, 1.5
    a, zt = W / 2 + t, H + t
    outer = [(-a, zb)]
    for cx, cz, a0 in ((-a + ro, zt - ro, pi), (a - ro, zt - ro, pi / 2)):
        for i in range(5):
            ang = a0 - (pi / 2) * i / 4
            outer.append((cx + ro * cos(ang), cz + ro * sin(ang)))
    outer.append((a, zb))
    inner = [(W / 2, zb)]
    for cx, cz, a0 in ((W / 2 - ri, H - ri, 0.0), (-W / 2 + ri, H - ri, pi / 2)):
        for i in range(5):
            ang = a0 + (pi / 2) * i / 4
            inner.append((cx + ri * cos(ang), cz + ri * sin(ang)))
    inner.append((-W / 2, zb))
    # local y -> world z, local z -> world -y (symmetric about y=0)
    P._bm("x_strap")
    pts = outer + inner
    P.poly_prism("x_strap", "rubber", pts, -10.0, 10.0, RX(pi / 2))
    # XT60 at the rear on a short lead that curls up and lies back along the top of the pack
    for sx, m in ((-1, "wire_dark"), (1, "wire_light")):
        x = sx * 3.0
        P.tube("x_xt60_lead", m, [(x, -37.5, 30.0), (x, -43.0, 31.0), (x, -45.0, 36.0), (x, -43.0, 40.5), (x, -38.0, 41.0), (x, -34.0, 41.2)], 1.5, 8)
    P.poly_prism("x_xt60_lead", "nylon", chamf(7.8, 4.0, 1.5), 0.0, 16.0, along_y(0, -34.0, 41.4))
    for sx in (-1, 1):
        P.cyl("x_xt60_lead", "gold", 1.4, 0.0, 16.4, 10, along_y(sx * 3.6, -34.4, 41.4))
    # balance lead: a flat ribbon lying back from the rear corner, small light plug on the end
    P.box("x_balance_lead", "wire_mid", 6.0, 24.0, 0.5, T(12.0, -49.5, 0), z0=8.5)
    P.box("x_balance_lead", "wire_light", 6.0, 0.5, 0.5, T(12.0, -37.7, 0), z0=8.0)
    P.box("x_balance_lead", "wire_light", 12.0, 7.0, 4.0, T(12.0, -65.0, 0), z0=6.6)


def build_camera(P):
    S = 19.0
    ZC = S / 2
    # body: rounded block, depth 12 (y -9.5 .. 2.5)
    P.poly_prism("camera_body", "cam_body", rrect(S / 2, S / 2, 1.8), 0, 12.0, along_y(0, -9.5, ZC))
    # back pcb stub and sensor shroud on the rear
    P.poly_prism("camera_body", "matte_board", rrect(8.5, 8.5, 1.0), 0, 1.0, along_y(0, -9.5, ZC) @ T(0, 0, 0))
    # lens barrel + threaded ring + glass
    P.cyl("camera_lens_barrel", "lens_ring", 6.6, 0, 3.0, 32, along_y(0, 2.5, ZC))
    P.cyl("camera_lens_barrel", "lens_ring", 5.6, 3.0, 7.0, 32, along_y(0, 2.5, ZC))
    P.poly_prism("camera_lens_barrel", "lens_ring", circle(5.6, 32), 6.4, 7.0, along_y(0, 2.5, ZC), holes=[circle(4.5, 32)])
    for k in range(8):
        P.cyl("camera_lens_barrel", "steel_dark", 0.2, 3.0, 6.0, 4, along_y(0, 2.5, ZC) @ T(5.65 * cos(k * pi / 4), 5.65 * sin(k * pi / 4), 0))
    P.cyl("camera_lens_glass", "lens_glass", 4.5, 3.4, 6.7, 32, along_y(0, 2.5, ZC), r1=4.0)


def build_vtx(P):
    holes = [circle(1.6, 12, sx * 12.75, sy * 12.75) for sx in (-1, 1) for sy in (-1, 1)]
    P.poly_prism("vtx_board", "matte_board", chamf(15.0, 15.0, 2.2), 0, 1.2, holes=holes)
    P.poly_prism("vtx_can", "can", rrect(8.0, 7.0, 0.8), 1.2, 4.4, T(-2.0, 0.0, 0))
    P.poly_prism("vtx_can", "can", rrect(7.2, 6.2, 0.6), 4.4, 4.7, T(-2.0, 0.0, 0))
    chip(P, "vtx_parts", 9.0, -8.0, 1.2, 3.0, 3.0, 0.8)
    chip(P, "vtx_parts", 9.5, 5.0, 1.2, 4.0, 4.0, 0.9)
    P.cyl("vtx_parts", "wire_dark", 2.3, 1.2, 4.2, 18, T(-8.0, -10.5, 0))
    P.cyl("vtx_parts", "alu", 2.2, 4.2, 4.4, 18, T(-8.0, -10.5, 0))
    # MMCX socket (tallest, 6 mm) and a u.fl receptacle
    P.cyl("vtx_mmcx", "gold", 2.4, 1.2, 6.0, 20, T(11.0, 11.0, 0))
    P.cyl("vtx_mmcx", "chip", 1.3, 5.9, 6.0, 12, T(11.0, 11.0, 0))
    P.box("vtx_ufl", "connector", 3.0, 3.0, 1.25, T(-11.0, 11.5, 0), z0=1.2)
    P.cyl("vtx_ufl", "gold", 0.9, 2.45, 2.7, 12, T(-11.0, 11.5, 0))
    for i in range(6):
        P.box("vtx_parts", "tin", 1.6, 2.0, 0.2, T(-9.0 + i * 3.6, -14.0, 0), z0=1.2)


def build_antenna(P):
    # SMA hex nut, barrel, heat-shrink sleeve with a flared joint, whip, lollipop head
    P.cyl("antenna_base", "gold", 3.7, 0.0, 4.0, 6)
    P.cyl("antenna_base", "gold", 3.0, 4.0, 8.0, 16)
    P.cyl("antenna_sleeve", "shrink", 2.5, 6.0, 52.0, 18)
    P.cyl("antenna_sleeve", "shrink", 3.1, 52.0, 53.0, 18, r1=0.9)
    P.cyl("antenna_whip", "wire_mid", 0.9, 53.0, 91.0, 10)
    P.cyl("antenna_head", "wire_mid", 2.6, 89.5, 91.5, 12)
    P.torus("antenna_head", "alu", 9.0, 2.0, nu=48, nv=8, M=T(0, 0, 93.0))


def build_receiver(P):
    P.poly_prism("receiver_board", "matte_board", chamf(7.0, 5.5, 1.0), 0, 0.8)
    chip(P, "receiver_parts", -1.0, -0.5, 0.8, 5.0, 5.0, 0.8)
    chip(P, "receiver_parts", 3.5, 2.5, 0.8, 2.5, 2.0, 0.6, pins=False)
    P.box("receiver_parts", "tin", 2.0, 1.4, 0.7, T(-4.5, -3.5, 0), z0=0.8)
    P.box("receiver_parts", "connector", 8.0, 3.4, 2.2, T(0.0, 3.3, 0), z0=0.8)
    for i in range(4):
        P.box("receiver_parts", "tin", 0.5, 0.4, 0.15, T(-2.25 + 1.5 * i, 5.2, 0), z0=0.8)
    # unmeasured: two wire antennas leaving the rear edge
    P.tube("x_wire_antenna", "wire_dark", [(-3.0, -5.5, 0.4), (-3.0, -22.0, 0.4), (-6.0, -34.0, 0.4)], 0.5, 6)
    P.tube("x_wire_antenna", "wire_light", [(-6.0, -34.0, 0.4), (-9.0, -52.0, 0.4)], 0.35, 6)
    P.tube("x_wire_antenna", "wire_dark", [(3.0, -5.5, 0.4), (3.0, -20.0, 0.4), (6.5, -30.0, 3.0)], 0.5, 6)
    P.tube("x_wire_antenna", "wire_light", [(6.5, -30.0, 3.0), (11.0, -48.0, 5.0)], 0.35, 6)


BUILDERS = {"motor": build_motor, "stack": build_stack, "battery": build_battery, "camera": build_camera,
            "vtx": build_vtx, "antenna": build_antenna, "receiver": build_receiver}


# ----------------------------------------------------------------------------- measure / verify / export
def tri_count():
    dg = bpy.context.evaluated_depsgraph_get()
    n = 0
    for ob in bpy.context.scene.objects:
        if ob.type != "MESH":
            continue
        me = ob.evaluated_get(dg).to_mesh()
        me.calc_loop_triangles()
        n += len(me.loop_triangles)
        ob.evaluated_get(dg).to_mesh_clear()
    return n


def measured_bbox_mm():
    lo, hi = Vector((1e9,) * 3), Vector((-1e9,) * 3)
    dg = bpy.context.evaluated_depsgraph_get()
    for ob in bpy.context.scene.objects:
        if ob.type != "MESH" or ob.name.startswith("x_"):
            continue
        me = ob.evaluated_get(dg).to_mesh()
        for v in me.vertices:
            w = ob.matrix_world @ v.co
            for i in range(3):
                lo[i], hi[i] = min(lo[i], w[i]), max(hi[i], w[i])
        ob.evaluated_get(dg).to_mesh_clear()
    return lo / MM, hi / MM


def check_greyscale():
    bad = []
    for m in bpy.data.materials:
        if not m.users:
            continue
        b = m.node_tree.nodes.get("Principled BSDF")
        r, g, bl, _ = b.inputs["Base Color"].default_value
        mx, mn = max(r, g, bl), min(r, g, bl)
        sat = 0.0 if mx == 0 else (mx - mn) / mx
        if not (r == g == bl) and sat >= 0.02:
            bad.append((m.name, (r, g, bl)))
        if any(n.type == "TEX_IMAGE" for n in m.node_tree.nodes):
            bad.append((m.name, "has a texture"))
    return bad


def glb_nodes(path):
    with open(path, "rb") as f:
        f.read(12)
        ln, _ = struct.unpack("<II", f.read(8))
        return json.loads(f.read(ln))


def build_one(name):
    bpy.ops.wm.read_factory_settings(use_empty=True)
    _matcache.clear()
    sc = bpy.context.scene
    sc.unit_settings.system = "METRIC"
    sc.unit_settings.scale_length = 1.0
    P = Part(name)
    BUILDERS[name](P)
    P.finish()
    bpy.context.view_layer.update()
    ref, budget = REF[name]
    tris = tri_count()
    lo, hi = measured_bbox_mm()
    size = hi - lo
    errs = []
    if tris > budget:
        errs.append("%s: %d triangles over budget %d" % (name, tris, budget))
    for i, ax in enumerate("xyz"):
        if abs(size[i] - ref[i]) > TOL_MM:
            errs.append("%s: measured %s = %.3f mm, want %.3f" % (name, ax, size[i], ref[i]))
    if abs(lo.z) > TOL_MM or abs((lo.x + hi.x) / 2) > TOL_MM or abs((lo.y + hi.y) / 2) > TOL_MM:
        errs.append("%s: origin is not the bottom-face centre (lo %s hi %s)" % (name, tuple(lo), tuple(hi)))
    bad = check_greyscale()
    if bad:
        errs.append("%s: non-greyscale materials %s" % (name, bad))
    if not any(o.name.startswith("x_") for o in sc.objects) and name in ("motor", "battery", "receiver"):
        errs.append("%s: expected x_ objects" % name)
    os.makedirs(SRC, exist_ok=True)
    bpy.context.preferences.filepaths.save_version = 0      # no .blend1 backups
    bpy.ops.wm.save_as_mainfile(filepath=os.path.join(SRC, name + ".blend"))
    glb = os.path.join(OUT, name + ".glb")
    bpy.ops.export_scene.gltf(filepath=glb, export_format="GLB", export_yup=True, export_apply=True,
                              export_materials="EXPORT", export_cameras=False, export_lights=False)
    nodes = [n["name"] for n in glb_nodes(glb).get("nodes", [])]
    for o in sc.objects:
        if o.type == "MESH" and not any(n == o.name or n.startswith(o.name) for n in nodes):
            errs.append("%s: object %s missing from the glb nodes" % (name, o.name))
    print("PART %-9s tris %5d  measured %.2f x %.2f x %.2f mm" % (name, tris, size[0], size[1], size[2]))
    return {"file": name + ".glb", "measured_mm": {"x": round(size[0], 3), "y": round(size[2], 3), "z": round(size[1], 3)},
            "triangles": tris, "texture_max_px": 0}, errs


def main():
    a = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    names = ORDER if "--all" in a or "--part" not in a else [a[a.index("--part") + 1]]
    os.makedirs(SRC, exist_ok=True)
    open(os.path.join(SRC, ".gdignore"), "w").close()      # the .blend sources are not Godot assets
    jpath = os.path.join(OUT, "parts.json")
    doc = {"units": "metres in the file; measured_mm is in Godot axes (x right, y up, z back)",
           "parts": {}}
    if os.path.exists(jpath):
        try:
            doc["parts"] = json.load(open(jpath))["parts"]
        except Exception:
            pass
    allerr = []
    for n in names:
        entry, errs = build_one(n)
        doc["parts"][n] = entry
        allerr += errs
    doc["parts"] = {k: doc["parts"][k] for k in ORDER if k in doc["parts"]}
    with open(jpath, "w") as f:
        json.dump(doc, f, indent=2)
        f.write("\n")
    if allerr:
        for e in allerr:
            print("BUILD FAIL:", e)
        sys.exit(1)
    print("BUILD OK", names)


main()
