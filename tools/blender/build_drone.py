"""Build hi-fi FPV drones for the ten Lothal classes, export GLB, render a studio shot.

Run one class:  /opt/homebrew/bin/blender -b -P tools/blender/build_drone.py -- --class five_inch
Run all ten:    /opt/homebrew/bin/blender -b -P tools/blender/build_drone.py -- --all
Units are metres. Origin = frame centre. Blender +Y is the front (glTF -Z / Godot forward).
Env LOTHAL_SKIP_RENDER=1 skips the Cycles render; LOTHAL_SAMPLES sets Cycles samples.
"""
import sys, os, subprocess
from math import pi, radians, sin, cos, sqrt, atan2

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))
ORDER = ["tiny_whoop", "toothpick", "cinewhoop_3", "sub250_35", "four_inch",
         "five_inch", "six_inch", "seven_lr", "cinelifter", "x_class"]


def _args():
    a = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    cls, every = "five_inch", False
    if "--all" in a:
        every = True
    if "--class" in a:
        cls = a[a.index("--class") + 1]
    return cls, every


CLASS_ID, RUN_ALL = _args()
if RUN_ALL:
    # one fresh Blender per class: clean scene, and one failure cannot poison the rest
    blender = sys.argv[0] if os.path.basename(sys.argv[0]).lower().startswith("blender") else "/opt/homebrew/bin/blender"
    try:
        import bpy as _b
        blender = _b.app.binary_path or blender
    except Exception:
        pass
    for c in ORDER:
        r = subprocess.run([blender, "-b", "-P", os.path.abspath(__file__), "--", "--class", c])
        if r.returncode != 0:
            print("CLASS FAILED", c)
            sys.exit(1)
    print("ALL CLASSES BUILT")
    sys.exit(0)

import bpy, bmesh
import numpy as np
from mathutils import Vector, Matrix

# --------------------------------------------------------------------------- class table
# wb wheelbase, prop_d prop diameter, motor=(bell diameter, bell-top height), kb = body scale vs the 5" kit,
# Packs are the class's SEED battery in src/design/drone_class.gd: `seed` names the catalogue entry in
# data/parts/batteries.json and L/W/H/label come from it (resolve_pack below; check_pack_vs_catalogue
# fails the build if the modelled pack differs by more than 2 mm). cells/mah are kept literal so the
# picker test can compare them with the seed.
# arm_k / arm_t arm width scale / thickness
CFGS = {
    "tiny_whoop": dict(wb=0.065, prop_d=0.031, blades=3, motor=(0.0085, 0.0090), frame="whoop", kb=0.72, zk=0.72,
                       arm_k=0.4, arm_t=0.0015, duct_above=0.0040, duct_wall=0.0013, cam=0.5,
                       batt=dict(seed="battery_1s_300", w_trim=0.0015, cells="1S", mah="300", col=(0.85, 0.30, 0.05)),
                       zmin=0.0, frame_col="whoop", batt_dy=-0.008),
    "toothpick": dict(wb=0.110, prop_d=0.063, blades=3, motor=(0.0135, 0.0100), frame="open", kb=0.60, zk=0.45,
                      arm_k=0.42, arm_t=0.0025, cam=0.62,
                      batt=dict(seed="battery_2s_450", cells="2S", mah="450", col=(0.10, 0.45, 0.80)),
                      zmin=0.0, batt_dy=-0.007),
    "cinewhoop_3": dict(wb=0.160, prop_d=0.0762, blades=3, motor=(0.0172, 0.0155), frame="open", kb=0.70,
                        arm_k=0.8, arm_t=0.0035, duct_above=0.0130, duct_wall=0.0020, cam=0.8, duct_h=0.0,
                        batt=dict(seed="battery_4s_650", cells="4S", mah="650", col=(0.85, 0.10, 0.10)),
                        zmin=-0.004),
    "sub250_35": dict(wb=0.155, prop_d=0.0889, blades=3, motor=(0.0185, 0.0185), frame="open", kb=0.84,
                      arm_k=0.8, arm_t=0.0040, cam=0.9,
                      batt=dict(seed="battery_4s_650", cells="4S", mah="650", col=(0.95, 0.75, 0.10)),
                      zmin=0.0),
    "four_inch": dict(wb=0.175, prop_d=0.1016, blades=3, motor=(0.0215, 0.0170), frame="open", kb=0.92, zk=0.88,
                      arm_k=0.9, arm_t=0.0040, cam=1.0,
                      batt=dict(seed="battery_4s_1300", cells="4S", mah="1300", col=(0.15, 0.55, 0.30)),
                      zmin=0.0),
    "five_inch": dict(wb=0.220, prop_d=0.127, blades=3, motor=(0.028, 0.0200), frame="open", kb=1.0,
                      arm_k=1.0, arm_t=0.0050, cam=1.0,
                      batt=dict(seed="battery_4s_1500", cells="4S", mah="1500", col=(0.92, 0.38, 0.08)),
                      zmin=0.0),
    "six_inch": dict(wb=0.250, prop_d=0.1524, blades=3, motor=(0.0305, 0.0230), frame="open", kb=1.08,
                     arm_k=1.1, arm_t=0.0060, cam=1.05,
                     batt=dict(seed="battery_6s_1300", cells="6S", mah="1300", col=(0.10, 0.45, 0.80)),
                     zmin=0.0),
    "seven_lr": dict(wb=0.290, prop_d=0.1778, blades=2, motor=(0.0335, 0.0250), frame="open", kb=1.15,
                     arm_k=1.2, arm_t=0.0060, cam=1.05, gps=True,
                     batt=dict(seed="battery_6s_1300", cells="6S", mah="1300", col=(0.12, 0.30, 0.65)),
                     zmin=0.0),
    "cinelifter": dict(wb=0.400, prop_d=0.2286, blades=2, motor=(0.0480, 0.0300), frame="tube", kb=1.25, layout="x8",
                       arm_k=1.0, arm_t=0.0060, tube_r=0.0095, cam=1.4, cine=3.0, gear=True,
                       batt=dict(seed="battery_6s_4000_liion", cells="6S", mah="LI-ION", col=(0.80, 0.10, 0.10), kind="liion"),
                       zmin=-0.15),
    "x_class": dict(wb=0.700, prop_d=0.3302, blades=2, motor=(0.0680, 0.0420), frame="tube", kb=2.0, layout="x8",
                    arm_k=1.0, arm_t=0.0090, tube_r=0.0165, cam=2.0, cine=4.2, gear=True,
                    batt=dict(seed="battery_6s_4000_liion", cells="6S", mah="LI-ION", col=(0.95, 0.75, 0.10), kind="liion"),
                    zmin=-0.23),
}


def resolve_pack(bc):
    """Fill L (front-back, Y), W, H from the catalogue seed battery. A pack lies FLAT on the plate:
    its two cross-section dimensions are laid wide-side-across (W >= H), and a square section is split
    by 1 mm each way (inside the 2 mm check tolerance) so the height is strictly under the width."""
    import json
    parts = json.load(open(os.path.join(ROOT, "data", "parts", "batteries.json")))["parts"]
    part = next(p for p in parts if p["part_id"] == bc["seed"])
    sp = part["specs"]
    L, a, c = sp["length_mm"] / 1000.0, sp["width_mm"] / 1000.0, sp["height_mm"] / 1000.0
    W, H = max(a, c), min(a, c)
    W -= bc.get("w_trim", 0.0)   # whoop only: 1.5 mm narrower (inside the 2 mm check) so it clears the duct walls
    if W - H < 0.0015 and not bc.get("w_trim"):
        W, H = W + 0.001, H - 0.001
    bc.update(L=L, W=W, H=H, cat=sp, name=part["name"], c_label="%dC" % int(sp["c_rating"]))
    return bc


CFG = CFGS[CLASS_ID]
resolve_pack(CFG["batt"])
CFG.setdefault("layout", "x4")
OUT_GLB = os.path.join(ROOT, "assets", "models", "classes", CLASS_ID + ".glb")
OUT_PNG = os.path.join(ROOT, "build", "blender_" + CLASS_ID + ".png")
if os.environ.get("LOTHAL_CLOSE"):
    OUT_PNG = "/tmp/close_" + CLASS_ID + ".png"
os.makedirs(os.path.dirname(OUT_GLB), exist_ok=True)
os.makedirs(os.path.dirname(OUT_PNG), exist_ok=True)

bpy.ops.wm.read_factory_settings(use_empty=True)
scene = bpy.context.scene
scene.unit_settings.system = "METRIC"
scene.unit_settings.scale_length = 1.0

# --------------------------------------------------------------------------- dims
WHEELBASE = CFG["wb"]
MA = WHEELBASE / 2 / sqrt(2)          # motor offset per axis
ARM_R = WHEELBASE / 2                 # motor radius from centre
KB = CFG["kb"]                        # body (plates, stack, camera mount) scale vs the 5" kit
KM = CFG["motor"][0] / 0.028          # motor lateral scale vs the 2306 model
KZ = CFG["motor"][1] / 0.0200         # motor height scale
KP = CFG["prop_d"] / 0.127            # prop scale vs the 5" blade
ARM_T = CFG["arm_t"]
ZK = CFG.get("zk", KB)                # body height scale
U_PLATE, U_TOP0 = 0.002, 0.0215       # kit constants (unscaled)
PLATE_T = U_PLATE * ZK
Z_BOT = -PLATE_T
Z_TOP0 = U_TOP0 * ZK
Z_TOP1 = Z_TOP0 + PLATE_T
PROP_H = (0.0198 + 0.0022) * KZ       # prop plane above motor base
SPAN_STACK = 0.01525                  # stack hole half-pattern (unscaled kit)
TUBE_R = CFG.get("tube_r", 0.0)
if CFG["frame"] == "tube":
    MOTOR_Z = TUBE_R + ARM_T / 2      # top motors sit on the arm plate
    BOT_Z = TUBE_R - ARM_T / 2        # bottom (coaxial) motors hang under it
else:
    MOTOR_Z = ARM_T
    BOT_Z = 0.0

def T(x=0, y=0, z=0):
    return Matrix.Translation((x, y, z))


def R(rx=0, ry=0, rz=0):
    return (Matrix.Rotation(rz, 4, "Z") @ Matrix.Rotation(ry, 4, "Y") @ Matrix.Rotation(rx, 4, "X"))


SWAP_YZ = Matrix(((1, 0, 0, 0), (0, 0, 1, 0), (0, 1, 0, 0), (0, 0, 0, 1)))

# --------------------------------------------------------------------------- materials
def make_mat(name, color, metallic=0.0, rough=0.5, **extra):
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    b = m.node_tree.nodes["Principled BSDF"]
    b.inputs["Base Color"].default_value = (*color, 1.0)
    b.inputs["Metallic"].default_value = metallic
    b.inputs["Roughness"].default_value = rough
    for k, v in extra.items():
        k = k.replace("_", " ")
        try:
            b.inputs[k].default_value = v
        except Exception as e:
            print("mat input fail", name, k, e)
    return m


def new_image(name, arr, srgb):
    h, w = arr.shape[:2]
    img = bpy.data.images.new(name, w, h, alpha=False)
    img.colorspace_settings.name = "sRGB" if srgb else "Non-Color"   # BEFORE the pixels: changing it afterwards re-encodes them
    a = np.ones((h, w, 4), dtype=np.float32)
    a[..., :3] = arr[..., :3]
    img.pixels.foreach_set(a.ravel())
    img.pack()
    return img


def carbon_maps(n=1024, cells=8):
    c = (np.arange(n) + 0.5) / n
    X, Y = np.meshgrid(c, c)
    fu, fv = (X * cells) % 1, (Y * cells) % 1
    ix, iy = np.floor(X * cells).astype(int), np.floor(Y * cells).astype(int)
    warp = ((ix - iy) % 4) < 2          # 2x2 twill
    hw = np.sin(np.pi * fv) ** 0.5 * (0.7 + 0.3 * np.sin(np.pi * fu))
    hf = np.sin(np.pi * fu) ** 0.5 * (0.7 + 0.3 * np.sin(np.pi * fv))
    h = np.where(warp, hw, hf) * 0.65
    fib = np.where(warp, np.sin(2 * np.pi * Y * cells * 14), np.sin(2 * np.pi * X * cells * 14)) * 0.035
    rng = np.random.default_rng(7)
    h = h + fib + rng.normal(0, 0.012, h.shape)
    S = 32.0
    gx = (np.roll(h, -1, 1) - np.roll(h, 1, 1)) * 0.5 * S
    gy = (np.roll(h, -1, 0) - np.roll(h, 1, 0)) * 0.5 * S
    nrm = np.dstack((-gx, -gy, np.ones_like(h)))
    nrm /= np.linalg.norm(nrm, axis=2, keepdims=True)
    nrm = nrm * 0.5 + 0.5
    base = np.where(warp, 0.085, 0.060) + 0.10 * h
    col = np.dstack((base, base, base * 1.02))
    r = 0.30 + 0.30 * (1 - np.clip(h, 0, 1)) + rng.normal(0, 0.02, h.shape)
    rough = np.dstack((r, r, r))
    return col, nrm, rough


def carbon_material():
    col, nrm, rough = carbon_maps()
    m = bpy.data.materials.new("carbon_fibre_twill")
    m.use_nodes = True
    nt = m.node_tree
    b = nt.nodes["Principled BSDF"]
    b.inputs["Metallic"].default_value = 0.0
    b.inputs["Coat Weight"].default_value = 0.6
    b.inputs["Coat Roughness"].default_value = 0.06
    def tex(name, arr, srgb):
        n = nt.nodes.new("ShaderNodeTexImage")
        n.image = new_image(name, arr, srgb)
        n.extension = "REPEAT"
        return n
    tc = tex("carbon_basecolor", col, True)
    tn = tex("carbon_normal", nrm, False)
    tr = tex("carbon_roughness", rough, False)
    nt.links.new(tc.outputs["Color"], b.inputs["Base Color"])
    sep = nt.nodes.new("ShaderNodeSeparateColor")
    nt.links.new(tr.outputs["Color"], sep.inputs["Color"])
    nt.links.new(sep.outputs["Green"], b.inputs["Roughness"])
    nm = nt.nodes.new("ShaderNodeNormalMap")
    nm.inputs["Strength"].default_value = 0.9
    nt.links.new(tn.outputs["Color"], nm.inputs["Color"])
    nt.links.new(nm.outputs["Normal"], b.inputs["Normal"])
    return m


FONT = {
    "0": "01110 10001 10011 10101 11001 10001 01110", "1": "00100 01100 00100 00100 00100 00100 01110",
    "2": "01110 10001 00001 00110 01000 10000 11111", "3": "11110 00001 00001 01110 00001 00001 11110",
    "4": "00010 00110 01010 10010 11111 00010 00010", "5": "11111 10000 11110 00001 00001 10001 01110",
    "6": "00110 01000 10000 11110 10001 10001 01110", "7": "11111 00001 00010 00100 01000 01000 01000",
    "8": "01110 10001 10001 01110 10001 10001 01110", "9": "01110 10001 10001 01111 00001 00010 01100",
    "S": "01111 10000 10000 01110 00001 00001 11110", "P": "11110 10001 10001 11110 10000 10000 10000",
    "M": "10001 11011 10101 10101 10001 10001 10001", "A": "01110 10001 10001 11111 10001 10001 10001",
    "H": "10001 10001 10001 11111 10001 10001 10001", "L": "10000 10000 10000 10000 10000 10000 11111",
    "I": "01110 00100 00100 00100 00100 00100 01110", "O": "01110 10001 10001 10001 10001 10001 01110",
    "N": "10001 11001 10101 10101 10011 10001 10001", "-": "00000 00000 00000 11111 00000 00000 00000",
    "V": "10001 10001 10001 10001 10001 01010 00100",
    "C": "01110 10001 10000 10000 10000 10001 01110",
}


def draw_text(img, text, x, y, px, val):
    """Blit a 5x7 bitmap string; px = pixel size of one font cell. y is top edge in image rows."""
    for ch in text:
        g = FONT.get(ch)
        if g:
            for r, row in enumerate(g.split()):
                for c, bit in enumerate(row):
                    if bit == "1":
                        img[y + (6 - r) * px:y + (7 - r) * px, x + c * px:x + (c + 1) * px] = val
        x += 6 * px


BC_CAT = None


def label_across(bc):
    """Short fat packs carry the label ACROSS the top (text runs left-right as seen from behind); long thin
    ones (whoop, toothpick) carry it lengthwise."""
    return bc["L"] / bc["W"] < 3.5


def lipo_material(bc, cells, mah, kind="lipo", side=False):
    """Printed pack wrap for the TOP face (the only face that carries text; sides get a plain stripe).
    The image has the top face's own aspect, so glyphs are not stretched. across: 1024 wide (pack width)
    x taller (pack length); lengthwise: 1024 wide (pack length) x shorter (pack width)."""
    BCc = BC_CAT
    col = BCc["col"]
    across = label_across(BCc) and not side
    ratio = BCc["L"] / (BCc["H"] if side else BCc["W"])
    if across:
        W, H = 1024, int(1024 * ratio)
    else:
        W, H = 1024, int(1024 / ratio)
    base = np.array(col, dtype=np.float32)
    img = np.zeros((H, W, 3), dtype=np.float32)
    img[:] = base * 0.55
    yy, xx = np.mgrid[0:H, 0:W]
    img[((xx * 0.5 + yy) % 220) < 26] = base * 0.75               # diagonal livery stripes
    sp = BCc["cat"]
    liion = kind == "liion"
    c_txt = BCc["c_label"]
    mah_txt = str(int(sp["mah"]))
    assert cells == "%dS" % int(sp["cells"]) and (liion or mah == mah_txt), "pack label != seed battery"
    white = np.array([0.95, 0.95, 0.93], dtype=np.float32)
    # The strap loop (and its buckle on top) hides the middle fifth of the pack, so the label is split in
    # two blocks that sit either side of it and never under it.
    img[:] = 0.045
    img[:8] = base
    img[-8:] = base
    last = "LI-ION" if liion else "MAH"
    if across:
        line1, line2 = "%s %s" % (cells, c_txt), "%s %s" % (mah_txt, last)
        px = int(W * 0.86 / (6 * max(len(line1), len(line2))))
        gh = 7 * px
        x0 = int(W * 0.07)
        draw_text(img, line1, x0, int(H * 0.25) - gh // 2, px, white)      # rear of the strap
        draw_text(img, line2, x0, int(H * 0.75) - gh // 2, px, white * 0.85)  # front of the strap
    else:
        blocks = [(0.05, [cells, c_txt]), (0.64, [mah_txt, last])]
        blen = int(max(len(t) for _, ts in blocks for t in ts))
        px = int(W * 0.31 / (6 * blen))
        px = min(px, int(H * 0.40 / 7))
        gh = 7 * px
        for fx, lines in blocks:
            for k, t in enumerate(lines):
                yy0 = int(H * (0.72 - 0.44 * k)) - gh // 2
                draw_text(img, t, int(W * fx), yy0, px, white if k == 0 else white * 0.85)
    rng = np.random.default_rng(3)
    img += rng.normal(0, 0.004, img.shape).astype(np.float32)
    lum = img @ np.array([0.2126, 0.7152, 0.0722], dtype=np.float32)   # monochrome product look
    img = np.repeat(lum[:, :, None], 3, axis=2)
    m = bpy.data.materials.new("lipo_wrap_printed_side" if side else "lipo_wrap_printed")
    m.use_nodes = True
    nt = m.node_tree
    b = nt.nodes["Principled BSDF"]
    b.inputs["Roughness"].default_value = 0.42
    b.inputs["Coat Weight"].default_value = 0.2
    b.inputs["Coat Roughness"].default_value = 0.2
    t = nt.nodes.new("ShaderNodeTexImage")
    t.image = new_image("lipo_wrap_side" if side else "lipo_wrap", np.clip(img, 0, 1), True)
    t.extension = "EXTEND"
    nt.links.new(t.outputs["Color"], b.inputs["Base Color"])
    return m


MAT = {}
def build_materials():
    MAT["carbon"] = carbon_material()
    global BC_CAT
    BC = BC_CAT = CFG["batt"]
    MAT["lipo"] = lipo_material(BC["col"], BC["cells"], BC["mah"], BC.get("kind", "lipo"))
    MAT["lipo_side"] = lipo_material(BC["col"], BC["cells"], BC["mah"], BC.get("kind", "lipo"), side=True)
    MAT["standoff"] = make_mat("standoff_anodized_darkgrey", (0.055, 0.057, 0.06), 1.0, 0.32)
    MAT["bell"] = make_mat("motor_bell_anodized", (0.07, 0.072, 0.076), 1.0, 0.28)
    MAT["steel"] = make_mat("steel_screw_black_oxide", (0.12, 0.12, 0.125), 1.0, 0.38)
    MAT["steel_bright"] = make_mat("steel_polished", (0.55, 0.56, 0.57), 1.0, 0.2)
    MAT["lam"] = make_mat("stator_lamination_steel", (0.2, 0.2, 0.21), 1.0, 0.45)
    MAT["copper"] = make_mat("stator_winding_copper", (0.62, 0.30, 0.17), 1.0, 0.34)
    MAT["magnet"] = make_mat("rotor_magnet_nickel", (0.42, 0.42, 0.44), 1.0, 0.25)
    MAT["prop"] = make_mat("prop_translucent_greyplastic", (0.025, 0.026, 0.028), 0.0, 0.25,
                           Transmission_Weight=0.55, IOR=1.46)
    MAT["prop_hub"] = make_mat("prop_hub_plastic", (0.05, 0.05, 0.055), 0.0, 0.35)
    MAT["pcb"] = make_mat("pcb_solder_mask_black", (0.012, 0.013, 0.014), 0.0, 0.4)
    MAT["pad"] = make_mat("pcb_pad_tinned", (0.6, 0.6, 0.62), 1.0, 0.3)
    MAT["chip"] = make_mat("ic_package_black", (0.008, 0.008, 0.009), 0.0, 0.5)
    MAT["pin"] = make_mat("ic_pin_tin", (0.5, 0.5, 0.52), 1.0, 0.35)
    MAT["can"] = make_mat("rf_shield_can", (0.7, 0.7, 0.72), 1.0, 0.35)
    MAT["cap"] = make_mat("capacitor_sleeve", (0.03, 0.03, 0.033), 0.0, 0.4)
    MAT["cap_top"] = make_mat("capacitor_aluminium_end", (0.6, 0.6, 0.62), 1.0, 0.3)
    MAT["conn"] = make_mat("jst_connector_grey", (0.33, 0.33, 0.34), 0.0, 0.5)
    MAT["usb"] = make_mat("usbc_shell", (0.5, 0.5, 0.52), 1.0, 0.3)
    MAT["wire"] = make_mat("wire_silicone_black", (0.012, 0.012, 0.013), 0.0, 0.42)
    MAT["wire2"] = make_mat("wire_silicone_grey", (0.18, 0.18, 0.19), 0.0, 0.42)
    MAT["wire_white"] = make_mat("wire_silicone_lightgrey", (0.5, 0.5, 0.5), 0.0, 0.42)
    MAT["tpu"] = make_mat("tpu_print_grey", (0.07, 0.07, 0.075), 0.0, 0.55, Coat_Weight=0.0)
    MAT["cam"] = make_mat("camera_body_plastic", (0.025, 0.025, 0.028), 0.0, 0.45)
    MAT["lens_ring"] = make_mat("camera_lens_ring_anodized", (0.09, 0.09, 0.095), 1.0, 0.3)
    MAT["glass"] = make_mat("camera_lens_glass", (0.004, 0.004, 0.006), 0.0, 0.03,
                            Coat_Weight=1.0, Coat_Roughness=0.0)
    MAT["shrink"] = make_mat("heatshrink_black", (0.015, 0.015, 0.016), 0.0, 0.55)
    MAT["xt60"] = make_mat("xt60_nylon_housing", (0.2, 0.2, 0.21), 0.0, 0.45)
    MAT["gold"] = make_mat("connector_gold_plated", (0.7, 0.55, 0.25), 1.0, 0.25)
    MAT["endcap"] = make_mat("lipo_end_shrink_black", (0.012, 0.012, 0.013), 0.0, 0.5)
    MAT["strap"] = make_mat("battery_strap_rubber", (0.025, 0.025, 0.027), 0.0, 0.7)
    MAT["pad_rubber"] = make_mat("battery_pad_rubber", (0.018, 0.018, 0.02), 0.0, 0.8)
    MAT["whoop"] = make_mat("whoop_frame_abs_dark", (0.030, 0.032, 0.035), 0.0, 0.7)
    MAT["duct"] = make_mat("duct_print_dark", (0.028, 0.029, 0.032), 0.0, 0.7)
    MAT["cine_body"] = make_mat("cine_camera_body", (0.10, 0.10, 0.11), 0.2, 0.4)
    MAT["gps"] = make_mat("gps_puck_ceramic", (0.70, 0.68, 0.60), 0.0, 0.35)
    MAT["gps_case"] = make_mat("gps_puck_case", (0.03, 0.03, 0.034), 0.0, 0.5)
    MAT["sweep"] = make_mat("studio_sweep_lightgrey", (0.20, 0.20, 0.21), 0.0, 0.8)


# --------------------------------------------------------------------------- geometry builder
def pt_ccw(pts):
    a = sum(pts[i][0] * pts[(i + 1) % len(pts)][1] - pts[(i + 1) % len(pts)][0] * pts[i][1] for i in range(len(pts)))
    return pts if a > 0 else pts[::-1]


def circle(cx, cy, r, n=24):
    return [(cx + r * cos(2 * pi * i / n), cy + r * sin(2 * pi * i / n)) for i in range(n)]


def stadium(cx, cy, length, width, ang=0.0, n=8):
    r = width / 2
    d = max(length - width, 0) / 2
    pts = []
    for i in range(n + 1):
        a = -pi / 2 + pi * i / n
        pts.append((d + r * cos(a), r * sin(a)))
    for i in range(n + 1):
        a = pi / 2 + pi * i / n
        pts.append((-d + r * cos(a), r * sin(a)))
    ca, sa = cos(ang), sin(ang)
    return [(cx + x * ca - y * sa, cy + x * sa + y * ca) for x, y in pts]


def rrect(x0, y0, x1, y1, r, n=5):
    pts = []
    for (cx, cy, a0) in ((x1 - r, y0 + r, -pi / 2), (x1 - r, y1 - r, 0), (x0 + r, y1 - r, pi / 2), (x0 + r, y0 + r, pi)):
        for i in range(n + 1):
            a = a0 + (pi / 2) * i / n
            pts.append((cx + r * cos(a), cy + r * sin(a)))
    return pts


def chamf_rect(hx, hy, c):
    return [(hx - c, -hy), (hx, -hy + c), (hx, hy - c), (hx - c, hy), (-hx + c, hy), (-hx, hy - c), (-hx, -hy + c), (-hx + c, -hy)]


def prism_bm(pts, z0, z1, bm=None, xf=None):
    bm = bm or bmesh.new()
    pts = pt_ccw(list(pts))
    lo = [bm.verts.new((x, y, z0)) for x, y in pts]
    hi = [bm.verts.new((x, y, z1)) for x, y in pts]
    n = len(pts)
    bm.faces.new(lo[::-1])
    bm.faces.new(hi)
    for i in range(n):
        bm.faces.new((lo[i], lo[(i + 1) % n], hi[(i + 1) % n], hi[i]))
    if xf is not None:
        bmesh.ops.transform(bm, matrix=xf, verts=lo + hi)
    return bm


def _tmp_obj(name, bm):
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    ob = bpy.data.objects.new(name, me)
    scene.collection.objects.link(ob)
    return ob


def boolean_mesh(bm, cut_bm=None, bevel=0.0):
    """Return a new Mesh: bm minus cut_bm, optional bevel. Consumes nothing."""
    o = _tmp_obj("tmp_main", bm)
    co = None
    if cut_bm is not None:
        co = _tmp_obj("tmp_cut", cut_bm)
        md = o.modifiers.new("bool", "BOOLEAN")
        md.object = co
        md.operation = "DIFFERENCE"
        md.solver = "EXACT"
        md.use_self = True
    if bevel:
        bv = o.modifiers.new("bev", "BEVEL")
        bv.width = bevel
        bv.segments = 2
        bv.limit_method = "ANGLE"
        bv.angle_limit = radians(35)
    dg = bpy.context.evaluated_depsgraph_get()
    me = bpy.data.meshes.new_from_object(o.evaluated_get(dg))
    for ob in [o] + ([co] if co else []):
        m0 = ob.data
        bpy.data.objects.remove(ob)
        bpy.data.meshes.remove(m0)
    return me


def carve(outline, z0, z1, cuts, bevel=0.00028, xf=None):
    bm = prism_bm(outline, z0, z1)
    cb = None
    if cuts:
        cb = bmesh.new()
        for c in cuts:
            prism_bm(c, z0 - 0.001, z1 + 0.001, cb)
    me = boolean_mesh(bm, cb, bevel)
    bm.free()
    if cb:
        cb.free()
    return me


class Bld:
    def __init__(self, name):
        self.name = name
        self.bm = bmesh.new()
        self.mats = []

    def mi(self, m):
        if m not in self.mats:
            self.mats.append(m)
        return self.mats.index(m)

    def _tag(self, verts, m):
        i = self.mi(m)
        for f in {f for v in verts for f in v.link_faces}:
            f.material_index = i

    def cyl(self, m, r, z0, z1, xf=None, r2=None, seg=24, caps=True):
        M = (xf or Matrix.Identity(4)) @ T(0, 0, (z0 + z1) / 2)
        res = bmesh.ops.create_cone(self.bm, cap_ends=caps, cap_tris=False, segments=seg, radius1=r,
                                    radius2=r if r2 is None else r2, depth=abs(z1 - z0), matrix=M)
        self._tag(res["verts"], m)

    def box(self, m, size, xf=None, bevel=0.0):
        M = (xf or Matrix.Identity(4)) @ Matrix.Diagonal((size[0], size[1], size[2], 1.0))
        before = set(self.bm.faces)
        res = bmesh.ops.create_cube(self.bm, size=1.0, matrix=M)
        if bevel:
            edges = list({e for v in res["verts"] for e in v.link_edges})
            bmesh.ops.bevel(self.bm, geom=edges, offset=bevel, segments=2, profile=0.5, affect="EDGES")
        i = self.mi(m)
        for f in self.bm.faces:
            if f not in before:
                f.material_index = i

    def sphere(self, m, r, xf=None, scale=(1, 1, 1), seg=16):
        M = (xf or Matrix.Identity(4)) @ Matrix.Diagonal((scale[0], scale[1], scale[2], 1.0))
        res = bmesh.ops.create_uvsphere(self.bm, u_segments=seg, v_segments=max(seg // 2, 4), radius=r, matrix=M)
        self._tag(res["verts"], m)

    def lathe(self, m, prof, xf=None, seg=40):
        bm = self.bm
        before = set(bm.verts)
        vs = [bm.verts.new((r, 0, z)) for r, z in prof]
        es = [bm.edges.new((vs[i], vs[(i + 1) % len(vs)])) for i in range(len(vs))]
        bmesh.ops.spin(bm, geom=vs + es, cent=(0, 0, 0), axis=(0, 0, 1), angle=2 * pi, steps=seg,
                       use_merge=True, use_duplicate=False)
        new = [v for v in bm.verts if v not in before]
        bmesh.ops.remove_doubles(bm, verts=new, dist=1e-6)
        new = [v for v in bm.verts if v not in before]
        if xf is not None:
            bmesh.ops.transform(bm, matrix=xf, verts=new)
        self._tag(new, m)

    def prism(self, m, pts, z0, z1, xf=None):
        before = set(self.bm.verts)
        prism_bm(pts, z0, z1, self.bm, xf)
        self._tag([v for v in self.bm.verts if v not in before], m)

    def mesh(self, m, me, xf=None):
        tmp = bmesh.new()
        tmp.from_mesh(me)
        if xf is not None:
            bmesh.ops.transform(tmp, matrix=xf, verts=tmp.verts)
        vm = [self.bm.verts.new(v.co) for v in tmp.verts]
        i = self.mi(m)
        for f in tmp.faces:
            nf = self.bm.faces.new([vm[v.index] for v in f.verts])
            nf.material_index = i
        tmp.free()
        bpy.data.meshes.remove(me)

    def tube(self, m, pts, r, seg=8, samples=8, caps=True):
        P = [Vector(p) for p in pts]
        if len(P) > 2:
            Q = [P[0]] + P + [P[-1]]
            dense = []
            for i in range(1, len(Q) - 2):
                p0, p1, p2, p3 = Q[i - 1], Q[i], Q[i + 1], Q[i + 2]
                for k in range(samples):
                    t = k / samples
                    t2, t3 = t * t, t * t * t
                    dense.append(0.5 * ((2 * p1) + (-p0 + p2) * t + (2 * p0 - 5 * p1 + 4 * p2 - p3) * t2 + (-p0 + 3 * p1 - 3 * p2 + p3) * t3))
            dense.append(P[-1])
            P = dense
        n = len(P)
        tans = []
        for i in range(n):
            a, b = P[max(i - 1, 0)], P[min(i + 1, n - 1)]
            tans.append((b - a).normalized())
        ref = Vector((0, 0, 1)) if abs(tans[0].z) < 0.9 else Vector((1, 0, 0))
        nrm = tans[0].cross(ref).normalized()
        rings = []
        for i in range(n):
            t = tans[i]
            nrm = (nrm - nrm.dot(t) * t).normalized()
            b = t.cross(nrm)
            rr = r(i / (n - 1)) if callable(r) else r
            rings.append([self.bm.verts.new(P[i] + rr * (cos(2 * pi * j / seg) * nrm + sin(2 * pi * j / seg) * b)) for j in range(seg)])
        idx = self.mi(m)
        for i in range(n - 1):
            for j in range(seg):
                f = self.bm.faces.new((rings[i][j], rings[i][(j + 1) % seg], rings[i + 1][(j + 1) % seg], rings[i + 1][j]))
                f.material_index = idx
        if caps:
            for ring in (rings[0], rings[-1]):
                f = self.bm.faces.new(ring)
                f.material_index = idx

    def to_object(self, name, parent, loc=(0, 0, 0), rot=(0, 0, 0), uv=None, sharp=radians(38), scale=None):
        bm = self.bm
        if scale is not None:
            sc3 = (scale, scale, scale) if np.isscalar(scale) else scale
            bmesh.ops.transform(bm, matrix=Matrix.Diagonal((sc3[0], sc3[1], sc3[2], 1.0)), verts=bm.verts)
        bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=1e-7)
        bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
        for f in bm.faces:
            f.smooth = True
        for e in bm.edges:
            if len(e.link_faces) == 2:
                if e.link_faces[0].normal.angle(e.link_faces[1].normal, 0.0) > sharp:
                    e.smooth = False
        if uv:
            layer = bm.loops.layers.uv.verify()
            for f in bm.faces:
                n = f.normal
                ax = max(range(3), key=lambda k: abs(n[k]))
                for l in f.loops:
                    p = l.vert.co
                    a, b = uv(p, ax, f.material_index)
                    l[layer].uv = (a, b)
        me = bpy.data.meshes.new(name)
        bm.to_mesh(me)
        bm.free()
        for m in self.mats:
            me.materials.append(m)
        ob = bpy.data.objects.new(name, me)
        scene.collection.objects.link(ob)
        ob.location = loc
        ob.rotation_euler = rot
        ob.parent = parent
        return ob


def uv_carbon(p, ax, mi, s=1 / 0.016):
    if ax == 2:
        return p.x * s, p.y * s
    if ax == 1:
        return p.x * s, p.z * s
    return p.y * s, p.z * s


def pcb(b, z, half, holes_span, extra_cuts=None):
    cuts = [circle(sx * holes_span, sy * holes_span, 0.0016, 14) for sx in (-1, 1) for sy in (-1, 1)]
    cuts += extra_cuts or []
    b.mesh(MAT["pcb"], carve(chamf_rect(half, half, 0.003), z, z + 0.0016, cuts, bevel=0.00008))
    for sx in (-1, 1):
        for sy in (-1, 1):
            b.cyl(MAT["pad"], 0.0033, z + 0.0016, z + 0.00175, T(sx * holes_span, sy * holes_span, 0), seg=18)


def chip(b, x, y, z, sx, sy, h=0.0008, pins=True, rot=0.0):
    M = T(x, y, z) @ R(rz=rot)
    b.box(MAT["chip"], (sx, sy, h), M @ T(0, 0, h / 2), bevel=0.00006)
    if pins:
        n = max(int(sx / 0.0006), 3)
        for i in range(n):
            px = (i + 0.5) / n * sx - sx / 2
            for s in (-1, 1):
                b.box(MAT["pin"], (0.00022, 0.0004, 0.00012), M @ T(px, s * (sy / 2 + 0.0001), 0.00012))


def build_stack(root):
    b = Bld("stack")
    z_esc, z_fc, z_vtx = 0.0075, 0.0135, 0.0075
    # ESC (4in1)
    pcb(b, z_esc, 0.018, 0.01525)
    for sx in (-1, 1):
        for i in range(6):
            chip(b, sx * 0.0105, -0.0125 + i * 0.0050, z_esc + 0.0016, 0.0042, 0.0042, 0.0009, pins=False)
    chip(b, 0, 0.005, z_esc + 0.0016, 0.007, 0.007, 0.001, pins=True)
    # motor pad groups (3 pads each, 4 corners) and battery pads
    for sy in (-1, 1):
        for sx in (-1, 1):
            for j in range(3):
                b.box(MAT["pad"], (0.0026, 0.0042, 0.00018), T(sx * (0.0040 + 0.0035 * j + 0.0014) * 1.0 + sx * 0.0, sy * 0.0155, z_esc + 0.0017))
    for sx in (-1, 1):
        b.box(MAT["pad"], (0.0034, 0.0042, 0.00018), T(sx * 0.0045, -0.0155, z_esc + 0.0017))
    # capacitor, lying horizontal behind the ESC
    capM = T(0.011, -0.0262, 0.0108) @ R(rx=pi / 2)
    b.cyl(MAT["cap"], 0.0045, -0.0063, 0.0063, capM, seg=32)
    b.cyl(MAT["cap_top"], 0.0044, -0.0066, -0.0062, capM, seg=32)
    b.cyl(MAT["pin"], 0.0004, 0.0063, 0.0090, capM @ T(-0.0016, 0, 0), seg=8)
    b.cyl(MAT["pin"], 0.0004, 0.0063, 0.0090, capM @ T(0.0016, 0, 0), seg=8)
    # FC
    pcb(b, z_fc, 0.018, 0.01525)
    zt = z_fc + 0.0016
    chip(b, 0.002, -0.002, zt, 0.0072, 0.0072, 0.0011, pins=True)                  # MCU
    chip(b, -0.009, 0.006, zt, 0.0030, 0.0030, 0.0008, pins=True)                   # gyro
    chip(b, 0.010, 0.008, zt, 0.0050, 0.0040, 0.0008, pins=True)                    # flash
    chip(b, -0.006, -0.010, zt, 0.0040, 0.0040, 0.0007, pins=True)                  # barometer
    for i in range(7):
        b.box(MAT["chip"], (0.0010, 0.0006, 0.0004), T(-0.012 + i * 0.0035, 0.013, zt + 0.0002))
    for sx in (-1, 1):
        b.box(MAT["conn"], (0.0030, 0.0090, 0.0042), T(sx * 0.0155, 0.000, zt + 0.0021), bevel=0.0002)
    b.box(MAT["usb"], (0.0090, 0.0075, 0.0032), T(0.0, 0.0148, zt + 0.0016), bevel=0.0006)
    b.cyl(MAT["chip"], 0.0007, zt, zt + 0.0012, T(0.010, -0.011, 0), seg=10)
    # VTX
    vy = -0.050
    b.mesh(MAT["pcb"], carve(chamf_rect(0.0125, 0.0125, 0.002), z_vtx, z_vtx + 0.0016, [], bevel=0.00008), T(0, vy, 0))
    zv = z_vtx + 0.0016
    b.mesh(MAT["can"], carve(rrect(-0.0070, -0.0070, 0.0070, 0.0070, 0.001), zv, zv + 0.0030, [], bevel=0.00018), T(0.0, vy, 0))
    chip(b, -0.0085, vy + 0.006, zv, 0.0030, 0.0030, 0.0008, pins=True)
    b.box(MAT["pad"], (0.0034, 0.0034, 0.0030), T(0, vy - 0.0105, zv + 0.0015), bevel=0.0003)
    # receiver under top plate
    RZ = U_TOP0 - 0.0016
    b.mesh(MAT["pcb"], carve(rrect(-0.006, -0.066, 0.006, -0.046, 0.0015), RZ - 0.0012, RZ, [], bevel=0.00006))
    chip(b, 0, -0.0585, RZ - 0.0012, 0.0050, 0.0050, 0.0010, pins=True)
    b.to_object("stack", root, scale=(KB, KB, ZK))


def build_motor(root, key, sx, sy, zloc, flip=False):
    b = Bld("motor_" + key)
    BELL, AL = MAT["bell"], MAT["bell"]
    # base / flange
    b.cyl(MAT["standoff"], 0.0125, 0.0, 0.0030, seg=48)
    b.cyl(MAT["standoff"], 0.0105, 0.0030, 0.0046, seg=48)
    b.cyl(MAT["standoff"], 0.0046, 0.0046, 0.0090, seg=24)
    for k in range(4):
        a = pi / 4 + k * pi / 2
        b.cyl(MAT["steel"], 0.0016, 0.0030, 0.0034, T(0.0098 * cos(a), 0.0098 * sin(a), 0), seg=10)
    # stator stack
    sz0, sz1 = 0.0090, 0.0150
    b.cyl(MAT["lam"], 0.0075, sz0, sz1, seg=36)
    for k in range(12):
        a = 2 * pi * k / 12
        M = R(rz=a)
        b.box(MAT["lam"], (0.0032, 0.0021, sz1 - sz0), M @ T(0.0090, 0, (sz0 + sz1) / 2))
        b.box(MAT["lam"], (0.0014, 0.0040, sz1 - sz0), M @ T(0.0102, 0, (sz0 + sz1) / 2))
        b.box(MAT["copper"], (0.0034, 0.0046, sz1 - sz0 + 0.0022), M @ T(0.0079, 0, (sz0 + sz1) / 2), bevel=0.0009)
    # magnets
    for k in range(14):
        a = 2 * pi * (k + 0.5) / 14
        b.box(MAT["magnet"], (0.0013, 0.0050, 0.0060), R(rz=a) @ T(0.01185, 0, (sz0 + sz1) / 2), bevel=0.00012)
    # bell with vents
    prof = [(0.0140, 0.0070), (0.0140, 0.0185), (0.0130, 0.0195), (0.0062, 0.0195), (0.0062, 0.0200),
            (0.0030, 0.0200), (0.0030, 0.0180), (0.0125, 0.0180), (0.0125, 0.0070)]
    bb = bmesh.new()
    bb2 = Bld("tmp_bell")
    bb2.lathe(MAT["bell"], prof, seg=72)
    cb = bmesh.new()
    for k in range(6):
        a = 2 * pi * k / 6 + pi / 6
        prism_bm(circle(0.0090 * cos(a), 0.0090 * sin(a), 0.0027, 14), 0.0165, 0.0215, cb)
    for k in range(12):
        a = 2 * pi * k / 12 + pi / 12
        prism_bm([(0.0105, -0.0016), (0.0160, -0.0016), (0.0160, 0.0016), (0.0105, 0.0016)], 0.0090, 0.0156, cb, R(rz=a))
    bb2.bm.normal_update()
    bmesh.ops.recalc_face_normals(bb2.bm, faces=bb2.bm.faces)
    me = boolean_mesh(bb2.bm, cb, 0.0)
    bb2.bm.free(); cb.free(); bb.free()
    b.mesh(BELL, me)
    # shaft + locknut
    b.cyl(MAT["steel_bright"], 0.0015, 0.0, 0.0285, seg=16)
    b.cyl(MAT["standoff"], 0.0045, 0.0222, 0.0262, seg=6)
    b.cyl(MAT["standoff"], 0.0036, 0.0262, 0.0268, r2=0.0030, seg=24)
    return b.to_object("motor_" + key, root, loc=(sx * MA, sy * MA, zloc), rot=(pi if flip else 0, 0, 0), scale=(KM, KM, KZ))


def blade_mesh(b, mat, dirn, R0=0.0062, RT=0.0648, nst=26, nx=9, kp=1.0):
    cs = np.array([0, 0.2, 0.4, 0.7, 0.9, 1.0])
    cv = np.array([0.0130, 0.0195, 0.0225, 0.0190, 0.0130, 0.0080])
    xs = (1 - np.cos(np.linspace(0, pi, nx))) / 2
    yt = 5 * 0.10 * (0.2969 * np.sqrt(xs) - 0.1260 * xs - 0.3516 * xs ** 2 + 0.2843 * xs ** 3 - 0.1036 * xs ** 4)
    yc = 0.075 * 4 * xs * (1 - xs)
    up = np.stack([xs, yc + yt], 1)
    lo = np.stack([xs, yc - yt], 1)
    sec = np.concatenate([up, lo[::-1][1:-1]])
    rings = []
    ss = np.concatenate([np.linspace(0, 0.9, 16), np.linspace(0.9, 1.0, nst - 15)[1:]])
    for s in ss:
        r = R0 + (RT - R0) * s
        ch = float(np.interp(s, cs, cv)) * kp
        if s > 0.93:
            ch *= sqrt(max(1 - ((s - 0.93) / 0.07) ** 2, 0.04))
        phi = radians(30 - 20 * s ** 0.75)
        th = 1.0 + 0.5 * (1 - s)
        ring = []
        for xx, zz in sec:
            y = (0.30 - xx) * ch
            z = zz * ch * th
            yr = y * cos(phi) - z * sin(phi)
            zr = y * sin(phi) + z * cos(phi)
            ring.append(b.bm.verts.new((r, yr * dirn, zr)))
        rings.append(ring)
    m = len(sec)
    idx = b.mi(mat)
    for i in range(len(rings) - 1):
        for j in range(m):
            f = b.bm.faces.new((rings[i][j], rings[i][(j + 1) % m], rings[i + 1][(j + 1) % m], rings[i + 1][j]))
            f.material_index = idx
    for ring in (rings[0], rings[-1]):
        f = b.bm.faces.new(ring)
        f.material_index = idx


def build_camera(root, kc, loc, tilt, name='camera'):
    b = Bld("camera")
    # local origin at pivot; body 19 x 21 (deep) x 19
    b.box(MAT["cam"], (0.0190, 0.0210, 0.0190), T(0, 0, 0), bevel=0.0007)
    b.cyl(MAT["lens_ring"], 0.0072, 0.0105, 0.0135, R(rx=-pi / 2), seg=40)      # placeholder replaced below
    b.bm.clear() if False else None
    # barrel (axis +Y)
    ax = R(rx=-pi / 2)
    b.cyl(MAT["lens_ring"], 0.0075, 0.0105, 0.0125, ax, seg=40)
    b.cyl(MAT["cam"], 0.0062, 0.0125, 0.0160, ax, seg=40)
    b.cyl(MAT["lens_ring"], 0.0064, 0.0160, 0.0170, ax, r2=0.0056, seg=40)
    b.cyl(MAT["glass"], 0.0050, 0.0169, 0.0172, ax, seg=40)
    b.sphere(MAT["glass"], 0.0046, T(0, 0.0173, 0), scale=(1, 0.25, 1), seg=24)
    for sx in (-1, 1):
        sh = rrect(-0.0130, -0.0150, 0.0130, 0.0135, 0.0035)
        pts = [(y, z) for (y, z) in sh]
        # TPU side plate, hole for the screw
        me = carve(pts, 0.0, 0.0032, [circle(-0.003, -0.0040, 0.0016, 12), circle(0.0045, 0.006, 0.0016, 12)], bevel=0.0004)
        # plate lies in YZ plane at x = sx*(0.0095+...)
        Mx = T(sx * (0.0095 + (0.0016 if sx > 0 else 0.0016)) , 0, 0) @ Matrix(((0, 0, 1, 0), (1, 0, 0, 0), (0, 1, 0, 0), (0, 0, 0, 1)))
        b.mesh(MAT["tpu"], me, T(sx * 0.0100 + (0.0016 if sx > 0 else -0.0048), 0, 0) @ Matrix(((0, 0, 1, 0), (1, 0, 0, 0), (0, 1, 0, 0), (0, 0, 0, 1))))
        sxh = sx * 0.0128
        for (yy, zz) in ((-0.003, -0.0040), (0.0045, 0.006)):
            b.sphere(MAT["steel"], 0.0020, T(sxh + sx * 0.0015, yy, zz), scale=(0.45, 1, 1), seg=14)
    b.box(MAT["pcb"], (0.0160, 0.0016, 0.0160), T(0, -0.0112, 0))
    return b.to_object(name, root, loc=loc, rot=(tilt, 0, 0), scale=kc)


def build_antennas(root):
    b = Bld("antennas")
    # VTX coax and dipole
    coax = [(0, -0.0605, 0.0105), (0, -0.068, 0.0125), (0, -0.082, 0.0145), (0, -0.092, 0.0145), (0, -0.092, 0.0250)]
    dx = 0.0 if not CFG.get("duct_above") else 0.0000    # ducted: dipole beside the battery lead, not on it
    yd = -0.092 if not CFG.get("duct_above") else -0.110   # ducted: dipole stands behind the battery lead
    if CFG.get("duct_above"):
        coax = [coax[0], (0.0160, -0.068, 0.0125), (0.0160, -0.100, 0.0145), (0.0, yd, 0.0145), (0, yd, 0.0250)]
    b.tube(MAT["wire"], coax, 0.0008, seg=8, samples=8)
    b.tube(MAT["shrink"], [(dx, yd, 0.0215), (dx, yd, 0.0600)], 0.0019, seg=14)
    b.cyl(MAT["pin"], 0.0021, 0.0195, 0.0215, T(dx, yd, 0), seg=14)
    b.sphere(MAT["shrink"], 0.0019, T(dx, yd, 0.0600), seg=14)
    # RX antenna tubes (V out of the TPU mount)
    for sx in (-1, 1):
        pts = [(sx * 0.0065, -0.0765, 0.0170), (sx * 0.0075, -0.088, 0.0165), (sx * 0.020, -0.105, 0.0130), (sx * 0.040, -0.122, 0.0075)]
        if CFG.get("duct_above"):            # ducted: keep the antenna tubes between the rear ducts, above the battery
            pts = [(sx * 0.0065, -0.0765, 0.0170), (sx * 0.0120, -0.082, 0.0340), (sx * 0.0170, -0.092, 0.0340), (sx * 0.0230, -0.100, 0.0260)]
        b.tube(MAT["wire"], pts[:2], 0.0008, seg=8, samples=4)
        b.tube(MAT["shrink"], pts[1:], 0.0016, seg=12, samples=8)
        b.sphere(MAT["shrink"], 0.0016, T(*pts[-1]), seg=12)
    b.to_object("antennas", root, loc=(0, 0, Z_TOP0 - U_TOP0 * KB), scale=KB)


# --------------------------------------------------------------------------- frames
MOTORS = {"FL": (-1, 1, -1), "FR": (1, 1, 1), "BL": (-1, -1, 1), "BR": (1, -1, -1)}   # sx, sy, spin dir
BODY_OUT = [(0.0165, 0.074), (0.025, 0.056), (0.025, -0.056), (0.0165, -0.074),
            (-0.0165, -0.074), (-0.025, -0.056), (-0.025, 0.056), (-0.0165, 0.074)]
STAND_PTS = [(sx * SPAN_STACK, sy * SPAN_STACK) for sx in (-1, 1) for sy in (-1, 1)] + \
            [(sx * 0.016, sy * 0.050) for sx in (-1, 1) for sy in (-1, 1)]
BC = CFG["batt"]
SK = max(0.6, min(2.0, KB))                       # strap / connector scale
STRAP_T = 0.0015 * SK
SX_IN = BC["W"] / 2 + 0.0005                      # strap inner half-width
SX_MID = SX_IN + STRAP_T / 2
BATT_Z0 = Z_TOP1 + 0.0016 * SK                    # pack bottom (rubber pad underneath)
if CFG["frame"] == "whoop":
    BATT_Z0 = 0.0095


def arm_outline():
    ka, rr = CFG["arm_k"], 0.0135 * KM
    u0 = 0.024 * KB
    sl = (ARM_R - u0) / 0.086
    wi, wm1, wm2 = 0.011 * ka, 0.0085 * ka, 0.0095 * ka
    pts = [(u0, -wi), (u0 + 0.036 * sl, -wm1), (u0 + 0.070 * sl, -wm2), (ARM_R, -rr)]
    pts += [(ARM_R + rr * cos(a), rr * sin(a)) for a in np.linspace(-pi / 2, pi / 2, 14)[1:-1]]
    pts += [(ARM_R, rr), (u0 + 0.070 * sl, wm2), (u0 + 0.036 * sl, wm1), (u0, wi)]
    return pts, u0, sl


def motor_mount_cuts(cx):
    cuts = [circle(cx, 0, 0.0045 * KM, 24)]
    for k in range(4):
        a = pi / 4 + k * pi / 2
        cuts.append(circle(cx + 0.0098 * KM * cos(a), 0.0098 * KM * sin(a), max(0.0016 * KM, 0.0007), 14))
    return cuts


def build_body_plates(b, C):
    """Plates + standoffs + tail mount, built at 5in kit size and scaled by (KB,KB,ZK) at export."""
    bx = BC["W"] / 2 + STRAP_T * 0.5 + 0.0005
    slx = SX_MID / KB
    def plate_cuts(top):
        cuts = [circle(x, y, 0.0016, 14) for x, y in STAND_PTS]
        for sgn in (-1, 1):
            cuts.append(stadium(sgn * slx, 0, 0.018, 0.004, pi / 2))
        if top:
            cuts += [stadium(0, 0.058, 0.016, 0.0075, pi / 2),
                     stadium(-0.0105, -0.052, 0.020, 0.0055, pi / 2), stadium(0.0105, -0.052, 0.020, 0.0055, pi / 2),
                     stadium(0, 0.0, 0.034, 0.010, pi / 2)]
        else:
            cuts += [stadium(0, 0.0, 0.040, 0.012, pi / 2), stadium(0, 0.052, 0.020, 0.008, pi / 2),
                     stadium(0, -0.054, 0.016, 0.008, pi / 2)]
            cuts += [circle(sx * 0.0095, sy * 0.0415, 0.002, 12) for sx in (-1, 1) for sy in (-1, 1)]
        return cuts
    b.mesh(C, carve(BODY_OUT, U_TOP0, U_TOP0 + U_PLATE, plate_cuts(True)))
    b.mesh(C, carve(BODY_OUT, -U_PLATE, 0.0, plate_cuts(False)))
    for x, y in STAND_PTS:
        b.cyl(MAT["standoff"], 0.0030, 0.0, U_TOP0, T(x, y, 0), seg=6)
        b.cyl(MAT["standoff"], 0.0018, -0.0002, U_TOP0 + 0.0002, T(x, y, 0), seg=10)
        for zc, flip in ((U_TOP0 + U_PLATE, 1), (-U_PLATE, -1)):
            m = T(x, y, zc) @ (R(rx=pi) if flip < 0 else Matrix.Identity(4))
            b.cyl(MAT["steel"], 0.0027, 0.0, 0.0006, m, r2=0.0027, seg=20)
            b.sphere(MAT["steel"], 0.0027, m @ T(0, 0, 0.0006), scale=(1, 1, 0.45), seg=20)
    tail = rrect(-0.013, -0.080, 0.013, -0.066, 0.003)
    me = carve(tail, 0.0095, U_TOP0 + 0.0005, [circle(-0.0065, -0.080, 0.0017, 12), circle(0.0065, -0.080, 0.0017, 12), circle(0, -0.080, 0.0010, 10)], bevel=0.0007)
    b.mesh(MAT["tpu"], me)


def build_frame_open(root):
    C = MAT["carbon"]
    ka = CFG["arm_k"]
    ba = Bld("frame_arms")
    outline, u0, sl = arm_outline()
    for key, (sx, sy, _) in MOTORS.items():
        ang = atan2(sy, sx)
        cuts = motor_mount_cuts(ARM_R)
        if ka >= 0.75:
            cuts += [stadium(u0 + 0.020 * sl, 0, 0.022 * ka, 0.0075 * ka, 0), stadium(u0 + 0.050 * sl, 0, 0.020 * ka, 0.0065 * ka, 0)]
            for hx in (0.008, 0.016):
                for hy in (-0.0055 * ka, 0.0055 * ka):
                    cuts.append(circle(u0 + hx * KB, hy, 0.0016 * ka, 14))
        if CFG.get("duct_above"):
            # the arm ends AT the duct's outer wall (the duct carries the motor); cut away the rest
            cuts = [circle(ARM_R, 0, CFG["prop_d"] / 2 + DUCT_CLEAR + CFG["duct_wall"] - 0.0001, 48)]
        me = carve(outline, 0, ARM_T, cuts, bevel=max(0.00012, 0.00028 * ka))
        ba.mesh(C, me, R(rz=ang))
    ba.to_object("frame_arms", root, uv=uv_carbon)
    bb = Bld("frame")
    build_body_plates(bb, C)
    bb.to_object("frame", root, uv=uv_carbon, scale=(KB, KB, ZK))


def build_frame_tube(root):
    """Carbon-tube arms with motor plates: the cinelifter / X-class construction."""
    C = MAT["carbon"]
    b = Bld("frame_arms")
    rt = TUBE_R
    pr = 0.0135 * KM
    for key, (sx, sy, _) in MOTORS.items():
        ang = atan2(sy, sx)
        u_a, u_b = 0.030 * KB, ARM_R - pr * 0.8
        M = R(rz=ang) @ R(ry=pi / 2)
        b.cyl(MAT["standoff"], rt, u_a, u_b, T(0, 0, rt) @ M, seg=28)        # the tube
        for (ua, ub, rr_) in ((u_a, u_a + 0.022 * KB, rt * 1.22), (u_b - 0.016 * KB, u_b, rt * 1.22)):
            b.cyl(MAT["steel"], rr_, ua, ub, T(0, 0, rt) @ M, seg=28)        # clamp collars
        zc = rt - ARM_T / 2
        me = carve(circle(0, 0, pr, 40), 0, ARM_T, motor_mount_cuts(0.0), bevel=0.0004)
        b.mesh(C, me, T(sx * MA, sy * MA, zc))
        # saddle block joining tube end to plate
        b.box(MAT["standoff"], (pr * 1.1, rt * 2.2, ARM_T * 1.6), T(sx * MA, sy * MA, rt) @ R(rz=ang) @ T(-pr * 0.9, 0, 0))
    b.to_object("frame_arms", root)
    bb = Bld("frame")
    build_body_plates(bb, C)
    bb.to_object("frame", root, uv=uv_carbon, scale=(KB, KB, ZK))


def duct(b, mat, cx, cy, z0, z1, ri, ro):
    H = z1 - z0
    w = ro - ri
    fl = w * 0.5
    prof = [(ri - w * 0.5, z1 - w * 0.9), (ri - w * 0.1, z1), (ro + w * 0.9, z1), (ro + w * 1.1, z1 - w * 0.9), (ro + w * 0.2, z1 - w * 2.0),
            (ro, z0 + w * 1.5), (ro + w * 0.3, z0), (ri - w * 0.2, z0), (ri, z0 + w * 1.5), (ri, z1 - w * 2.4)]
    b.lathe(mat, prof, xf=T(cx, cy, 0), seg=72)


def build_ducts(root, mat, z0, z1):
    b = Bld("ducts")
    ri = CFG["prop_d"] / 2 + DUCT_CLEAR
    ro = ri + CFG["duct_wall"]
    for key, (sx, sy, _) in MOTORS.items():
        duct(b, mat, sx * MA, sy * MA, z0, z1, ri, ro)
        # printed motor cradle inside the bore: pad + two spokes to the wall, at the foot of the duct
        pad_r = CFG["motor"][0] * 0.62
        b.cyl(mat, pad_r, z0, z0 + 0.0020, T(sx * MA, sy * MA, 0), seg=24)
        for a in (0.0, pi / 2):
            b.box(mat, (2 * (ri + 0.0002), 0.0022, 0.0020), T(sx * MA, sy * MA, z0 + 0.0010) @ R(rz=a + atan2(sy, sx) + pi / 4), bevel=0.0002)
    # outboard tie-bars between neighbouring ducts at the foot of the rings: they run from wall to wall,
    # never through a bore
    tb = 0.0045 * max(KB, 0.7)
    span = 2 * (MA - ro + 0.0001)
    for sy in (-1, 1):
        b.box(mat, (span, tb, 0.0020), T(0, sy * MA, z0 + 0.0010), bevel=0.0003)
    for sx in (-1, 1):
        b.box(mat, (tb, span, 0.0020), T(sx * MA, 0, z0 + 0.0010), bevel=0.0003)
    b.to_object("ducts", root, uv=None)


def build_frame_whoop(root):
    """Moulded whoop: the duct rings with their motor cradles are the `ducts` part; the `frame` part
    (cross bars, arms, FC cradle) joins them at the outer walls and never enters a bore."""
    b = Bld("frame")
    d = b            # a moulded whoop is ONE part: ducts, cradle, bars and struts are a single moulding
    W = MAT["whoop"]
    z1 = MOTOR_Z + PROP_H + CFG["duct_above"]
    ri = CFG["prop_d"] / 2 + DUCT_CLEAR
    ro = ri + CFG["duct_wall"]
    for key, (sx, sy, _) in MOTORS.items():
        duct(d, W, sx * MA, sy * MA, 0.0, z1, ri, ro)
        d.cyl(W, 0.0050, 0.0, ARM_T, T(sx * MA, sy * MA, 0), seg=24)              # motor pad
        for a in (0.0, pi / 2):                                                    # two spokes to the duct wall
            d.box(W, (2 * (ri + 0.0002), 0.0020, ARM_T), T(sx * MA, sy * MA, ARM_T / 2) @ R(rz=a + atan2(sy, sx) + pi / 4), bevel=0.0002)
    span = 2 * (MA - ro + 0.0001)
    for sy in (-1, 1):
        b.box(W, (span, 0.0040, 0.0026), T(0, sy * MA, 0.0013), bevel=0.0004)
    for sx in (-1, 1):
        b.box(W, (0.0040, span, 0.0026), T(sx * MA, 0, 0.0013), bevel=0.0004)
    for key, (sx, sy, _) in MOTORS.items():
        dd = atan2(sy, sx)
        r_in = MA * 1.4142 - (ro - 0.0001)                     # diagonal strut from the cradle to this duct's wall
        b.box(W, (r_in, 0.0050, 0.0026), T(sx * r_in * 0.5 / sqrt(2), sy * r_in * 0.5 / sqrt(2), 0.0013) @ R(rz=dd), bevel=0.0004)
    b.box(W, (0.0285, 0.0330, 0.0030), T(0, 0, 0.0015), bevel=0.0007)                # battery/FC cradle
    b.to_object("frame", root)


def build_aio(root):
    b = Bld("aio")
    pcb(b, 0.0, 0.018, 0.01525)
    zt = 0.0016
    chip(b, 0.002, -0.002, zt, 0.0072, 0.0072, 0.0011, pins=True)
    chip(b, -0.009, 0.006, zt, 0.0030, 0.0030, 0.0008, pins=True)
    chip(b, 0.010, 0.008, zt, 0.0050, 0.0040, 0.0008, pins=True)
    for sx in (-1, 1):
        for sy in (-1, 1):
            for j in range(2):
                b.box(MAT["pad"], (0.0030, 0.0040, 0.00018), T(sx * (0.006 + 0.0045 * j), sy * 0.0155, zt))
    b.box(MAT["usb"], (0.0090, 0.0075, 0.0032), T(0.0, -0.0148, zt + 0.0016), bevel=0.0006)
    b.box(MAT["can"], (0.0100, 0.0100, 0.0028), T(-0.002, 0.0, zt + 0.0020), bevel=0.0003)
    b.to_object("aio", root, loc=(0, 0, 0.0036), scale=(KB, KB, KB))


# --------------------------------------------------------------------------- interpenetration check
# Separate parts may only touch where that is the design. Anything else fails the build (exit 2).
DUCT_CLEAR = 0.0012   # tip clearance, prop tip to duct bore (1-1.5 mm)


def _base(name):
    n = name.split(".")[0]
    for pre in ("prop", "motor"):
        if n.startswith(pre + "_"):
            return pre, n[len(pre) + 1:]
    return {"frame_arms": "frame", "cine_camera": "camera"}.get(n, n), None


# Pairs of part kinds that are bolted, strapped or plugged together by design.
_INTENDED = {frozenset(p) for p in [
    ("frame", "motor"), ("ducts", "motor"), ("prop", "motor"),
    ("frame", "stack"), ("frame", "aio"), ("frame", "battery"), ("frame", "camera"), ("frame", "antennas"),
    ("frame", "wires"), ("frame", "gps"), ("frame", "payload"), ("frame", "gear"),
    ("stack", "battery"), ("stack", "camera"), ("stack", "antennas"), ("stack", "wires"), ("aio", "wires"),
    ("battery", "gps"), ("battery", "payload"), ("battery", "wires"), ("camera", "wires"),
    ("payload", "gear"), ("payload", "camera"), ("motor", "wires"), ("stack", "motor"),
    ("wires", "ducts"),     # motor leads pass through a slot in the duct wall
    ("frame", "ducts"),     # joined at the mount ears; the bore/wall intrusion is tested in _frame_vs_duct
]}


def _bb(o):
    pts = [o.matrix_world @ v.co for v in o.data.vertices]
    return [min(p.x for p in pts), min(p.y for p in pts), min(p.z for p in pts), max(p.x for p in pts), max(p.y for p in pts), max(p.z for p in pts)]


def check_interpenetration(root):
    from mathutils.bvhtree import BVHTree
    dg = bpy.context.evaluated_depsgraph_get()
    objs = [o for o in root.children if o.type == "MESH"]
    def world_tree(o):
        me = o.evaluated_get(dg).to_mesh()
        verts = [o.matrix_world @ v.co for v in me.vertices]
        polys = [tuple(p.vertices) for p in me.polygons]
        world_tree.geo[o.name] = (verts, polys)
        return BVHTree.FromPolygons(verts, polys)
    world_tree.geo = {}
    trees = {o.name: world_tree(o) for o in objs}
    bad = []
    for i, a in enumerate(objs):
        for b in objs[i + 1:]:
            (ka, ia), (kb, ib) = _base(a.name), _base(b.name)
            if {ka, kb} in ({"antennas", "battery"}, {"antennas", "wires"}):
                continue          # antennas are zip-tied to the pack lead / harness (intended contact)
            if ka == kb and ia is None:
                continue                                   # two pieces of the same part
            if frozenset((ka, kb)) in _INTENDED and not (ia and ib and ka == kb) \
                    and not (ka == "prop" and kb == "motor" and ia != ib) \
                    and not (ka == "motor" and kb == "prop" and ia != ib):
                continue
            if trees[a.name].overlap(trees[b.name]):
                ov = trees[a.name].overlap(trees[b.name])
                bad.append((a.name, b.name, len(ov)))
                if os.environ.get("LOTHAL_CHECK_REPORT"):
                    q = trees[a.name].overlap(trees[b.name])[0]
                    va, pa = world_tree.geo[a.name]
                    cen = sum((va[i] for i in pa[q[0]]), Vector()) / len(pa[q[0]])
                    print("  hit at mm", [round(c * 1000, 1) for c in cen])
                    print("  first hit tri idx", q, "bbox a", [round(x * 1000, 1) for x in _bb(a)], "b", [round(x * 1000, 1) for x in _bb(b)])
    bad += _frame_vs_duct(objs)
    for a, b, n in bad:
        print("INTERPENETRATION", CLASS_ID, a, "<->", b, n)
    if bad:
        print("INTERPENETRATION CHECK FAILED", CLASS_ID, len(bad))
        if not os.environ.get("LOTHAL_CHECK_REPORT"):
            sys.exit(2)
    else:
        print("INTERPENETRATION CHECK OK", CLASS_ID, len(objs), "parts")


def pack_aabb_mm(root):
    """AABB (x, y, z extents in mm) of the pack BODY: the faces wearing the printed wrap or the end-cap
    shrink. Leads, connector, strap and pad are excluded: they are not the cell."""
    ob = next(o for o in root.children if o.name.split(".")[0] == "battery")
    me = ob.data
    body = {i for i, m in enumerate(me.materials) if m in (MAT["lipo"], MAT["lipo_side"], MAT["endcap"])}
    pts = [ob.matrix_world @ me.vertices[v].co for poly in me.polygons if poly.material_index in body for v in poly.vertices]
    ext = [(max(p[k] for p in pts) - min(p[k] for p in pts)) * 1000.0 for k in range(3)]
    return ext


def check_pack_vs_catalogue(root, tol_mm=2.0, ext=None):
    """The modelled pack must equal the seed battery in data/parts (length front-back, the two section
    dimensions across/up in either order) within 2 mm, and must lie FLAT: height < width."""
    sp = BC["cat"]
    ext = ext or pack_aabb_mm(root)
    x, y, z = ext
    want_l = sp["length_mm"]
    want_hi, want_lo = max(sp["width_mm"], sp["height_mm"]), min(sp["width_mm"], sp["height_mm"])
    bad = []
    if abs(y - want_l) > tol_mm:
        bad.append("length %.1f vs catalogue %.1f" % (y, want_l))
    if abs(x - want_hi) > tol_mm:
        bad.append("width %.1f vs catalogue %.1f" % (x, want_hi))
    if abs(z - want_lo) > tol_mm:
        bad.append("height %.1f vs catalogue %.1f" % (z, want_lo))
    if z >= x:
        bad.append("not flat: height %.1f >= width %.1f" % (z, x))
    if y < x:
        bad.append("long axis not front-to-back: length %.1f < width %.1f" % (y, x))
    print("PACK", CLASS_ID, BC["seed"], "AABB mm L%.1f W%.1f H%.1f" % (y, x, z), "OK" if not bad else bad)
    if bad:
        print("PACK CHECK FAILED", CLASS_ID, bad)
        sys.exit(3)


def _frame_vs_duct(objs):
    """No frame edge may enter a duct's bore or wall (arms/ears end AT the outer wall). Tested on
    every edge in plan, so a bar that runs clean across a duct is caught even with no vertex inside."""
    if not CFG.get("duct_above") or CFG["frame"] == "whoop":      # a moulded whoop is one part
        return []
    ri = CFG["prop_d"] / 2 + DUCT_CLEAR
    ro = ri + CFG["duct_wall"]
    n = 0
    for o in objs:
        if _base(o.name)[0] != "frame":
            continue
        me = o.data
        co = np.array([tuple(o.matrix_world @ v.co) for v in me.vertices])[:, :2]
        ed = np.array([tuple(e.vertices) for e in me.edges])
        a, b = co[ed[:, 0]], co[ed[:, 1]]
        for sx, sy, _ in MOTORS.values():
            c = np.array([sx * MA, sy * MA])
            ab = b - a
            t = np.clip(((c - a) * ab).sum(1) / np.maximum((ab * ab).sum(1), 1e-18), 0, 1)
            d = np.linalg.norm(a + ab * t[:, None] - c, axis=1)
            n += int((d < ro - 0.0002).sum())
    return [("frame", "ducts (edges inside bore/wall)", n)] if n else []


# --------------------------------------------------------------------------- props
def build_prop(root, key, sx, sy, dirn, phase, z, flip=False):
    b = Bld("prop_" + key)
    PM = MAT["prop"]
    n = CFG["blades"]
    rt = CFG["prop_d"] / 2
    r0 = 0.0062 * KP
    for k in range(n):
        a = phase + 2 * pi * k / n
        before = set(b.bm.verts)
        blade_mesh(b, PM, dirn, R0=r0, RT=rt, kp=KP)
        new = [v for v in b.bm.verts if v not in before]
        bmesh.ops.transform(b.bm, matrix=R(rz=a), verts=new)
    h = KP
    b.lathe(MAT["prop_hub"], [(0.0030 * h, -0.0022 * h), (0.0078 * h, -0.0022 * h), (0.0078 * h, 0.0016 * h), (0.0062 * h, 0.0026 * h),
                              (0.0050 * h, 0.0026 * h), (0.0050 * h, 0.0036 * h), (0.0030 * h, 0.0036 * h)], seg=48)
    return b.to_object("prop_" + key, root, loc=(sx * MA, sy * MA, z), rot=(pi if flip else 0, 0, 0))


# --------------------------------------------------------------------------- wires
def build_wires(root):
    b = Bld("wires")
    cols = [MAT["wire"], MAT["wire2"], MAT["wire"]]
    wr = 0.00082 * max(SK, 0.8)
    zpad = 0.0095 * ZK
    for key, (sx, sy, _) in MOTORS.items():
        d = Vector((sx, sy, 0)).normalized()
        pe = Vector((-sy, sx, 0)).normalized()
        mc = Vector((sx * MA, sy * MA, 0))
        for j in range(3):
            off = (j - 1) * 0.0022 * KM
            lp = pe * (0.0045 * KM * np.sign(pe.dot(Vector((0, sy, 0)))) + off)
            pts = [mc + d * -0.0105 * KM + lp + Vector((0, 0, MOTOR_Z + 0.0083 * KZ)),
                   mc + d * -0.0125 * KM + lp + Vector((0, 0, MOTOR_Z + 0.0012)),
                   mc + d * -0.040 * KM + lp + Vector((0, 0, MOTOR_Z + 0.0011)),
                   Vector((sx * 0.031 * KB, sy * 0.030 * KB, 0.0072 * ZK)),
                   Vector((sx * (0.0040 + 0.0035 * j + 0.0014) * KB, sy * 0.0155 * KB, zpad)),
                   Vector((sx * (0.0040 + 0.0035 * j + 0.0014) * KB, sy * 0.0165 * KB, zpad - 0.0006))]
            b.tube(cols[j], pts, wr, seg=8, samples=6)
    for k, sxx in enumerate((-1, 1)):
        x = sxx * 0.0045 * KB
        pts = [(x, -0.0155 * KB, 0.0097 * ZK), (x, -0.0185 * KB, 0.0098 * ZK), (x * 0.9, -0.050 * KB, 0.0085 * ZK),
               (sxx * 0.0036 * SK, -0.085 * KB, 0.0075 * ZK), (sxx * 0.0036 * SK, -0.0905 * KB, 0.0075 * ZK)]
        b.tube(MAT["wire"] if k == 0 else MAT["wire2"], pts, 0.0016 * SK, seg=10, samples=8)
    pts = [(-0.0078, -0.0041), (0.0078, -0.0041), (0.0078, 0.0016), (0.0053, 0.0041), (-0.0053, 0.0041), (-0.0078, 0.0016)]
    y0, y1 = -0.1065 * KB, -0.0905 * KB
    xtf = Matrix.Translation((0, 0, 0.0075 * ZK)) @ SWAP_YZ
    s = SK
    b.prism(MAT["xt60"], [(x * s, y * s) for x, y in pts], y0, y1, xtf)
    for sxx in (-1, 1):
        b.cyl(MAT["gold"], 0.0016 * s, 0, 0.0030 * s, T(sxx * 0.0036 * s, y0 - 0.0010, 0.0075 * ZK) @ R(rx=pi / 2), seg=16)
    b.to_object("wires", root)


# --------------------------------------------------------------------------- battery, gps
def build_battery(root):
    L, W, H = BC["L"], BC["W"], BC["H"]
    z0 = BATT_Z0
    whoop = CFG["frame"] == "whoop"
    s = 0.5 if whoop else (0.65 if L < 0.06 else (1.0 if L < 0.16 else 1.4))     # XT30 / XT60 / XT90 scale
    b = Bld("battery")
    bev = 0.11 * min(W, H)
    cap = max(0.0015, 0.045 * L)
    b.box(MAT["lipo"], (W, L - 2 * cap + 0.001, H), T(0, 0, z0 + H / 2), bevel=bev)
    for sg in (-1, 1):
        b.box(MAT["endcap"], (W - 0.0008, cap, H - 0.0008), T(0, sg * (L / 2 - cap / 2), z0 + H / 2), bevel=bev * 0.55)
    ry = -L / 2
    zc = z0 + H * 0.46
    for k, sxx in enumerate((-1, 1)):
        pts = [(sxx * 0.0036 * s, ry + 0.001, zc), (sxx * 0.0036 * s, ry - 0.012 * s, zc - 0.002 * s), (sxx * 0.0036 * s, ry - 0.022 * s, zc - 0.006 * s)]
        b.tube(MAT["wire"] if k == 0 else MAT["wire2"], pts, 0.0017 * s * (0.6 if whoop else 1.0), seg=10, samples=8)
    xtf = T(0.0, 0, zc - 0.0105 * s) @ SWAP_YZ
    b.prism(MAT["xt60"], [(x * s, y * s) for x, y in [(-0.0078, -0.0041), (0.0078, -0.0041), (0.0078, 0.0016), (0.0053, 0.0041), (-0.0053, 0.0041), (-0.0078, 0.0016)]],
            ry - 0.040 * s, ry - 0.0235 * s, xtf)
    for sxx in (-1, 1):
        b.cyl(MAT["gold"], 0.0016 * s, 0, 0.0030 * s, T(sxx * 0.0036 * s, ry - 0.0235 * s, zc - 0.0105 * s) @ R(rx=-pi / 2), seg=14)
    if not whoop:
        bl = ry - 0.0085 * s
        ncell = 7 if BC["cells"].startswith("6") else (5 if BC["cells"].startswith("4") else 4)
        for i in range(ncell):
            xx = (-0.0030 * (ncell - 1) / 2 + i * 0.0030) * min(1.0, W / 0.035 + 0.3)
            mt = MAT["wire_white"] if i % 2 == 0 else MAT["wire2"]
            b.tube(mt, [(xx * 0.4, ry + 0.001, z0 + H * 0.2), (xx * 0.8, ry - 0.012 * s, z0 + 0.0045), (xx, bl - 0.012 * s, z0 + 0.0030)], 0.00038 * s, seg=6, samples=6)
        b.box(MAT["wire_white"], (0.0030 * ncell + 0.004, 0.0058 * s, 0.0062 * s), T(0, bl - 0.0155 * s, z0 + 0.0026), bevel=0.0004)
        # strap loop across the pack width, through the plate slots
        sw = 0.016 * KB
        zb = Z_BOT - 0.0005
        r_in = min(0.003 * SK, H * 0.3)
        outer = rrect(-(SX_IN + STRAP_T), zb - STRAP_T, SX_IN + STRAP_T, z0 + H + STRAP_T, r_in + STRAP_T)
        inner = rrect(-SX_IN, zb, SX_IN, z0 + H, r_in)
        b.mesh(MAT["strap"], carve(outer, -sw / 2, sw / 2, [inner], bevel=0.0003), SWAP_YZ)
        b.box(MAT["steel_bright"], (0.0140 * SK, 0.0100 * SK, 0.0030 * SK), T(0, 0, z0 + H + STRAP_T + 0.0015 * SK), bevel=0.0004)
        b.box(MAT["strap"], (0.0090 * SK, 0.0100 * SK, 0.0012 * SK), T(0, 0, z0 + H + STRAP_T + 0.0034 * SK), bevel=0.0003)
        b.box(MAT["pad_rubber"], (min(0.030 * SK, W * 0.86), L * 0.82, 0.0016 * SK), T(0, 0, z0 - 0.0008 * SK), bevel=0.0003)
    else:
        b.box(MAT["pad_rubber"], (W * 0.9, L * 0.8, 0.0014), T(0, 0, z0 - 0.0007), bevel=0.0003)
    lipo_i = b.mats.index(MAT["lipo"])
    side_i = b.mi(MAT["lipo_side"])
    b.bm.normal_update()
    for f in b.bm.faces:                       # the long side faces wear their own label, readable broadside
        if f.material_index == lipo_i and abs(f.normal.x) > 0.7:
            f.material_index = side_i
    def uv(p, ax, mi):
        if mi == side_i:
            u = (p.y + L / 2) / L
            return (1 - u if p.x < 0 else u), (p.z - z0) / H
        if mi == lipo_i:
            if ax == 2:                       # top and bottom faces carry the label (the image has their aspect)
                if label_across(BC):          # text across, upright seen from behind (x right, front up)
                    return (p.x + W / 2) / W, (p.y + L / 2) / L
                return (p.y + L / 2) / L, 1.0 - (p.x + W / 2) / W       # lengthwise, rotated not mirrored
            return 0.02, 0.02                                          # sides and ends: plain livery, no clipped text
        return 0.0, 0.0
    b.to_object("battery", root, loc=(0.0, CFG.get("batt_dy", 0.0), 0.0), uv=uv)


def build_gps(root):
    z = BATT_Z0 + BC["H"]
    b = Bld("gps")
    b.box(MAT["pad_rubber"], (0.030, 0.030, 0.0030), T(0, 0, 0.0015), bevel=0.0006)
    b.cyl(MAT["gps_case"], 0.0128, 0.0030, 0.0078, seg=40)
    b.cyl(MAT["gps"], 0.0100, 0.0078, 0.0086, seg=40)
    b.box(MAT["gps_case"], (0.0040, 0.0060, 0.0030), T(0, -0.0120, 0.0045))
    b.tube(MAT["wire"], [(0, -0.0150, 0.0045), (0, -0.030, 0.0030), (0, -0.045, 0.0)], 0.0007, seg=6, samples=6)
    b.to_object("gps", root, loc=(0, -BC["L"] * 0.30, z))


# --------------------------------------------------------------------------- cinema payload, landing gear
def build_payload(root):
    kc = CFG["cine"]
    C = MAT["carbon"]
    b = Bld("payload")
    pt = 0.003 * KB
    pz = Z_BOT - 0.022 * KB                                   # plate top
    hwp = 0.0245 * KB
    me = carve(rrect(-hwp, -0.070 * KB, hwp, 0.070 * KB, 0.006 * KB), pz - pt, pz,
               [circle(sx * 0.017 * KB, sy * 0.054 * KB, 0.0016 * KB, 12) for sx in (-1, 1) for sy in (-1, 1)], bevel=0.0004)
    b.mesh(C, me)
    for sx in (-1, 1):
        for sy in (-1, 1):
            b.cyl(MAT["standoff"], 0.0030 * KB, pz, Z_BOT, T(sx * 0.017 * KB, sy * 0.054 * KB, 0), seg=10)
            b.sphere(MAT["pad_rubber"], 0.0045 * KB, T(sx * 0.017 * KB, sy * 0.054 * KB, pz - pt - 0.001), seg=12)
    b.to_object("payload", root)
    cz = pz - pt - 0.0015 - 0.0095 * kc
    # cinema camera: body, matte box ring
    bc = Bld("cine_body")
    bc.box(MAT["cine_body"], (0.0190, 0.0210, 0.0190), T(0, 0, 0), bevel=0.0012)
    bc.cyl(MAT["lens_ring"], 0.0085, 0.0105, 0.0150, R(rx=-pi / 2), seg=40)
    bc.cyl(MAT["cam"], 0.0075, 0.0150, 0.0215, R(rx=-pi / 2), seg=40)
    bc.cyl(MAT["lens_ring"], 0.0078, 0.0215, 0.0235, R(rx=-pi / 2), seg=40)
    bc.cyl(MAT["glass"], 0.0062, 0.0234, 0.0238, R(rx=-pi / 2), seg=40)
    bc.box(MAT["cine_body"], (0.0050, 0.0130, 0.0030), T(0, -0.0010, 0.0105), bevel=0.0006)       # top handle
    bc.box(MAT["steel"], (0.0120, 0.0040, 0.0120), T(0, -0.0125, 0.0), bevel=0.0006)            # rear module
    bc.to_object("cine_camera", root, loc=(0, 0.012 * KB, cz), scale=kc)
    return cz - 0.0095 * kc


def build_gear(root, cam_bottom):
    b = Bld("gear")
    S = MAT["carbon"]
    rs = 0.0035 * KB
    zs = cam_bottom - 0.020 * KB
    xs = 0.060 * KB
    ys = 0.060 * KB
    for sx in (-1, 1):
        b.cyl(MAT["standoff"], rs, -ys * 1.6, ys * 1.6, T(sx * xs, 0, zs) @ R(rx=-pi / 2), seg=20)
        for sy in (-1, 1):
            b.tube(MAT["standoff"], [(sx * 0.0230 * KB, sy * ys, Z_BOT), (sx * xs, sy * ys, zs + rs)], rs * 0.8, seg=14)
            b.sphere(MAT["steel"], rs * 1.4, T(sx * xs, sy * ys, zs + rs), seg=14)
    b.to_object("gear", root)
    return zs - rs


# --------------------------------------------------------------------------- scene dressing
def build_studio(f, low, top):
    zf = low - 0.0035 * max(1.0, f * 0.6)
    prof = [(2.5 * f, zf), (-0.45 * f, zf)]
    rad = 0.55 * f
    for a in np.linspace(0, pi / 2, 14)[1:]:
        prof.append((-0.45 * f - rad * sin(a), zf + rad * (1 - cos(a))))
    prof.append((-0.45 * f - rad, zf + 3.0 * f))
    bm = bmesh.new()
    rows = []
    for (y, z) in prof:
        rows.append((bm.verts.new((-3.0 * f, y, z)), bm.verts.new((3.0 * f, y, z))))
    for i in range(len(rows) - 1):
        bm.faces.new((rows[i][0], rows[i][1], rows[i + 1][1], rows[i + 1][0]))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    for fc in bm.faces:
        fc.smooth = True
    me = bpy.data.meshes.new("sweep")
    bm.to_mesh(me)
    me.materials.append(MAT["sweep"])
    ob = bpy.data.objects.new("studio_sweep", me)
    scene.collection.objects.link(ob)
    # soft contact shadow: two gaussian blobs (wide penumbra + tight core) just above the floor
    N = 256
    c = (np.arange(N) + 0.5) / N * 2 - 1
    X, Y = np.meshgrid(c, c)
    rr = X * X + Y * Y
    for nm, sig, amp, size in (("wide", 0.40, 0.70, 1.35), ("core", 0.22, 0.95, 0.85)):
        a = amp * np.exp(-rr / (2 * sig * sig)) * np.clip(1.15 - np.sqrt(rr), 0, 1)
        img = bpy.data.images.new("shadow_" + nm, N, N, alpha=False)
        px = np.ones((N, N, 4), dtype=np.float32)
        px[..., :3] = a[..., None]
        img.colorspace_settings.name = "Non-Color"
        img.pixels.foreach_set(px.ravel())
        img.pack()
        mt = bpy.data.materials.new("shadow_blob_" + nm)
        mt.use_nodes = True
        nt = mt.node_tree
        bs = nt.nodes["Principled BSDF"]
        bs.inputs["Base Color"].default_value = (0.0, 0.0, 0.0, 1.0)
        bs.inputs["Roughness"].default_value = 1.0
        bs.inputs["Specular IOR Level"].default_value = 0.0
        tx = nt.nodes.new("ShaderNodeTexImage")
        tx.image = img
        tx.extension = "EXTEND"
        nt.links.new(tx.outputs["Color"], bs.inputs["Alpha"])
        span = (CFG["wb"] + CFG["prop_d"]) * size
        bmq = bmesh.new()
        h = span / 2
        bmesh.ops.create_grid(bmq, x_segments=1, y_segments=1, size=h)
        mq = bpy.data.meshes.new("shadow_" + nm)
        bmq.to_mesh(mq)
        uvl = mq.uv_layers.new(name="UVMap")
        for lp in mq.loops:
            v = mq.vertices[lp.vertex_index].co
            uvl.data[lp.index].uv = (v.x / span + 0.5, v.y / span + 0.5)
        mq.materials.append(mt)
        qo = bpy.data.objects.new("shadow_" + nm, mq)
        scene.collection.objects.link(qo)
        qo.location = (0, -0.004 * f, zf + 0.0002 * max(f, 1.0) + (0.0001 if nm == "core" else 0))
        qo.visible_shadow = False
    w = bpy.data.worlds.new("studio")
    w.use_nodes = True
    bg = w.node_tree.nodes["Background"]
    bg.inputs["Color"].default_value = (0.55, 0.55, 0.56, 1)
    bg.inputs["Strength"].default_value = 0.07
    scene.world = w

    def area(name, loc, target, size, power):
        ld = bpy.data.lights.new(name, "AREA")
        ld.shape = "RECTANGLE"
        ld.size, ld.size_y = size[0] * f, size[1] * f
        ld.energy = power * f * f
        lo = bpy.data.objects.new(name, ld)
        scene.collection.objects.link(lo)
        lo.location = Vector(loc) * f
        d = Vector(target) - lo.location
        lo.rotation_euler = d.to_track_quat("-Z", "Y").to_euler()
    zc = (low + top) / 2 + 0.006 * f
    tgt = (0, 0, zc)
    area("key", (0.30, 0.30, 0.42 + zc / f), tgt, (0.30, 0.30), 28)
    area("fill", (-0.85, 0.35, 0.30 + zc / f), tgt, (0.9, 0.6), 12)
    area("rim", (-0.15, -0.60, 0.55 + zc / f), tgt, (0.8, 0.25), 40)
    area("top", (0.0, 0.0, 0.95 + zc / f), tgt, (0.8, 0.8), 6)
    cd = bpy.data.cameras.new("cam")
    cd.lens = 70
    cd.sensor_width = 36
    cd.clip_start = 0.01 * f
    cd.clip_end = 50
    co = bpy.data.objects.new("render_cam", cd)
    scene.collection.objects.link(co)
    co.location = Vector((-0.78, 0.55, 0.50)) * 0.80 * f + Vector((0, 0, zc * 0.6))
    ctr = Vector((0.0, -0.004 * f, zc))
    co.rotation_euler = (ctr - co.location).to_track_quat("-Z", "Y").to_euler()
    if os.environ.get('LOTHAL_CLOSE'):
        ctr = Vector((0.0, 0.0, BATT_Z0 + BC['H'] * 0.5))
        co.location = ctr + Vector((-0.07, 0.08, 0.06)) * f
        co.rotation_euler = (ctr - co.location).to_track_quat('-Z', 'Y').to_euler()
    scene.camera = co


def render():
    sc = scene
    sc.render.engine = "CYCLES"
    sc.render.resolution_x, sc.render.resolution_y = 1600, 1000
    sc.render.resolution_percentage = 100
    sc.render.image_settings.file_format = "PNG"
    sc.render.filepath = OUT_PNG
    cy = sc.cycles
    cy.samples = int(os.environ.get("LOTHAL_SAMPLES", "160"))
    cy.use_denoising = True
    try:
        cy.denoiser = "OPENIMAGEDENOISE"
    except Exception:
        pass
    cy.max_bounces = 10
    cy.transmission_bounces = 10
    cy.caustics_reflective = False
    cy.caustics_refractive = False
    cy.device = "CPU"
    try:
        pr = bpy.context.preferences.addons["cycles"].preferences
        pr.compute_device_type = "METAL"
        pr.get_devices()
        for d in pr.devices:
            d.use = True
        cy.device = "GPU"
    except Exception as e:
        print("GPU unavailable:", e)
    try:
        sc.view_settings.view_transform = "AgX"
        sc.view_settings.look = "AgX - Medium High Contrast"
    except Exception as e:
        print("look fail", e)
    sc.view_settings.exposure = float(os.environ.get("LOTHAL_EXPOSURE", "0.0"))
    bpy.ops.render.render(write_still=True)


def main():
    build_materials()
    root = bpy.data.objects.new(CLASS_ID, None)
    scene.collection.objects.link(root)
    kind = CFG["frame"]
    x8 = CFG["layout"] == "x8"
    top_z = BATT_Z0 + BC["H"]
    low = Z_BOT - 0.0005 - STRAP_T
    if kind == "open":
        build_frame_open(root)
        build_stack(root)
    elif kind == "tube":
        build_frame_tube(root)
        build_stack(root)
    else:
        build_frame_whoop(root)
        build_aio(root)
    if CFG.get("duct_above") and kind == "open":                      # cinewhoop: printed ducts on a carbon frame
        zb = Z_BOT
        z1 = MOTOR_Z + PROP_H + CFG["duct_above"]
        build_ducts(root, MAT["duct"], zb, z1)
    phases = {3: (18, 78), 2: (30, 60)}[CFG["blades"]]
    for key, (sx, sy, d) in MOTORS.items():
        build_motor(root, key, sx, sy, MOTOR_Z)
        build_prop(root, key, sx, sy, d, radians(phases[0] if sy > 0 else phases[1]), MOTOR_Z + PROP_H)
        if x8:
            build_motor(root, key + "_lo", sx, sy, BOT_Z, flip=True)
            build_prop(root, key + "_lo", sx, sy, -d, radians(phases[1] if sy > 0 else phases[0]), BOT_Z - PROP_H, flip=True)
            low = min(low, BOT_Z - 0.0285 * KZ)
    if kind != "whoop":
        build_wires(root)
        build_antennas(root)
    cz = max(0.015 * ZK, 0.0105 * CFG["cam"])
    if kind == "whoop":
        build_camera(root, CFG["cam"], (0, 0.0330, 0.0105), radians(18))
    else:
        build_camera(root, CFG["cam"], (0, 0.0600 * KB, cz), radians(25))
    build_battery(root)
    if CFG.get("gps"):
        build_gps(root)
        top_z += 0.012
    if CFG.get("cine"):
        cb = build_payload(root)
        low = min(low, cb)
    if CFG.get("gear"):
        low = min(low, build_gear(root, low if not CFG.get("cine") else cb))
    if kind != "whoop":
        top_z = max(top_z, Z_TOP1 + 0.060 * KB)           # antenna
    drone = [root] + list(root.children)
    tris = 0
    for o in root.children:
        o.data.calc_loop_triangles()
        tris += len(o.data.loop_triangles)
    print("DRONE TRIANGLES", CLASS_ID, tris)
    assert tris < 700000
    check_interpenetration(root)
    check_pack_vs_catalogue(root)
    if os.environ.get("LOTHAL_CHECK_ONLY"):
        return
    bpy.ops.object.select_all(action="DESELECT")
    for o in drone:
        o.select_set(True)
    bpy.context.view_layer.objects.active = root
    bpy.ops.export_scene.gltf(filepath=OUT_GLB, export_format="GLB", use_selection=True, export_apply=True, export_yup=True)
    print("EXPORTED", OUT_GLB, os.path.getsize(OUT_GLB))
    f = (CFG["wb"] + CFG["prop_d"]) / 0.347
    build_studio(f, low, min(top_z, low + (CFG["wb"]) * 0.45))
    if not os.environ.get("LOTHAL_SKIP_RENDER"):
        render()


main()
