"""Contact sheet of the seven part GLBs. blender -b -P tools/blender/render_parts.py -- out.png"""
import sys, os
import bpy
from mathutils import Vector
ROOT = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
out = sys.argv[sys.argv.index("--") + 1]
bpy.ops.wm.read_factory_settings(use_empty=True)
names = ["motor", "stack", "battery", "camera", "vtx", "antenna", "receiver"]
xs = [0, 0.05, 0.12, 0.19, 0.25, 0.30, 0.34]
for n, x in zip(names, xs):
    bpy.ops.import_scene.gltf(filepath=os.path.join(ROOT, "assets/models/parts", n + ".glb"))
    for o in list(bpy.context.selected_objects):
        if o.parent is None:
            o.location.x += x
            # glTF import turns Y-up back into Blender Z-up; parts face +Y
sc = bpy.context.scene
sc.render.engine = "BLENDER_EEVEE"
sc.render.resolution_x, sc.render.resolution_y = 2000, 800
w = bpy.data.worlds.new("w"); w.use_nodes = True
w.node_tree.nodes["Background"].inputs[0].default_value = (0.35, 0.35, 0.37, 1)
sc.world = w
cam = bpy.data.objects.new("cam", bpy.data.cameras.new("cam"))
sc.collection.objects.link(cam); sc.camera = cam
cam.data.type = "ORTHO"; cam.data.ortho_scale = 0.40
tgt = bpy.data.objects.new("t", None); sc.collection.objects.link(tgt); tgt.location = (0.17, 0, 0.04)
import math
D = 0.5
ANG = float(os.environ.get("ANG", "0")); EL = float(os.environ.get("EL", "0"))
if EL:
    cam.data.ortho_scale = 0.62
    cam.location = Vector((0.17 + D * math.cos(math.radians(EL)) * math.sin(math.radians(ANG)), D * math.cos(math.radians(EL)) * math.cos(math.radians(ANG)), 0.04 + D * math.sin(math.radians(EL))))
else:
    cam.location = Vector((0.17, 0.42, 0.32))
c = cam.constraints.new("TRACK_TO"); c.target = tgt; c.track_axis = "TRACK_NEGATIVE_Z"; c.up_axis = "UP_Y"
for loc, e in (((0.3, -0.3, 0.5), 3.0), ((-0.3, 0.3, 0.3), 1.0)):
    l = bpy.data.objects.new("l", bpy.data.lights.new("l", "SUN")); l.data.energy = e
    l.rotation_euler = (0.9, 0.2, 0.6 if e > 2 else 3.5)
    sc.collection.objects.link(l)
sc.render.filepath = out
bpy.ops.render.render(write_still=True)
