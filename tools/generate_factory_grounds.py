"""Abandoned Halvorsen Ironworks: original, fully procedural Blender scene kit.

The factory is an additive, standalone location.  It does not edit rules.json,
the playable street, the main scene or any existing gameplay script.

Run (from the repository root):
    D:/Blender/blender.exe --background --factory-startup \
        --python tools/generate_factory_grounds.py

Outputs:
    art/source/factory_grounds.blend
    godot/assets/factory_grounds.glb
    godot/data/factory_layout.json
"""
from pathlib import Path
import json
import math
import random
import runpy
import time
import bpy
import bmesh
from mathutils import Vector, Quaternion

START_TIME = time.time()
PUT_COUNT = 0


def stage(name):
    print("STAGE", name, "%.1fs" % (time.time() - START_TIME), flush=True)

ROOT = Path(__file__).resolve().parents[1]
if not bpy.app.background:
    raise RuntimeError("Background mode required; the generator clears the scene")

kit = runpy.run_path(str(ROOT / "tools/generate_assets.py"))
kit["reset"]()
MATS = kit["MATS"]
MATERIAL_LIBRARY = kit["MATERIAL_LIBRARY"]
SURFACES = kit["SURFACES"]
BASE = ROOT
OUT = BASE / "godot" / "assets"
DATA = BASE / "godot" / "data"
SOURCE = BASE / "art" / "source"
OUT.mkdir(parents=True, exist_ok=True)
DATA.mkdir(parents=True, exist_ok=True)
SOURCE.mkdir(parents=True, exist_ok=True)

GROUPS = {}
CURRENT = "DD_Factory_Ground"
COLLIDERS = []


def srgb(value):
    h = value.lstrip("#")
    channels = [int(h[i:i + 2], 16) / 255.0 for i in (0, 2, 4)]
    return tuple(c / 12.92 if c <= .04045 else ((c + .055) / 1.055) ** 2.4 for c in channels) + (1.0,)


def make_material(name, color, roughness=.9, metallic=0.0, alias=None):
    """Factor material.  A library alias is applied when supplied."""
    recipe = MATERIAL_LIBRARY["materials"].get(alias) if alias else None
    if recipe:
        color = "#" + recipe["color"]
        roughness = recipe["roughness"]
        metallic = recipe["metallic"]
    material = bpy.data.materials.new("DD_" + name)
    material.use_nodes = True
    shader = material.node_tree.nodes.get("Principled BSDF")
    linear = srgb(color)
    material.diffuse_color = linear
    shader.inputs["Base Color"].default_value = linear
    shader.inputs["Roughness"].default_value = roughness
    shader.inputs["Metallic"].default_value = metallic
    if alias:
        SURFACES["apply"](material, dict(recipe, id=alias), ROOT)
    MATS[name] = material
    return material


# Existing shared recipes only.  No edits to material_library_v1.json.
make_material("paving", "#77756b", alias="concrete")
make_material("asphalt", "#414547", alias="road_patch")
make_material("brick", "#736153", .93)
make_material("crack", "#161816", .99)
make_material("oil", "#141716", .78)
make_material("water", "#27383b", .24)
make_material("rubber", "#151716", .95)
make_material("signal_red", "#7b2f25", .82)
make_material("lamp_glow", "#ffd6a0", .45)
make_material("soil", "#635c45", .97, alias="soil")
make_material("grass_dry", "#77704d", .96)
make_material("concrete_dark", "#595a51", .94)
make_material("painted_metal", "#50625e", .64, .15, alias="painted_metal")
make_material("galvanized", "#87918e", .58, .22)
make_material("steel_factory", "#505b5d", .50, .34)
make_material("iron_rust", "#5d3d2d", .90, .05)
make_material("stack_brick", "#6d5f53", .93)
# Readable aliases used by the factory authoring vocabulary.  They point at
# the existing recipe materials and therefore share their PBR maps.  Bulk
# structural steel deliberately uses a non-metallic-dominated recipe: under
# the fixed late-afternoon sun, near-pure metals without an environment probe
# read as black silhouettes.
MATS["old_wood"] = MATS["wood"]
MATS["light_wood"] = MATS["wood_light"]
MATS["steel"] = MATS["steel_factory"]
MATS["metal"] = MATS["galvanized"]
MATS["rust"] = MATS["iron_rust"]
MATS["ceramic"] = MATS["white"]


def set_group(name):
    global CURRENT
    CURRENT = name


def put(obj):
    global PUT_COUNT
    if obj is None:
        return obj
    GROUPS.setdefault(CURRENT, []).append(obj)
    obj["dd_group"] = CURRENT
    PUT_COUNT += 1
    if PUT_COUNT % 100 == 0:
        stage("parts:%d" % PUT_COUNT)
    return obj


def apply_transform(obj, location=False):
    bpy.context.view_layer.objects.active = obj
    obj.select_set(True)
    bpy.ops.object.transform_apply(location=location, rotation=True, scale=True)
    obj.select_set(False)


def solid(name, verts, faces, material, smooth=False):
    mesh = bpy.data.meshes.new(name)
    mesh.from_pydata(verts, [], faces)
    mesh.validate()
    if faces:
        bm = bmesh.new()
        bm.from_mesh(mesh)
        bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
        bm.to_mesh(mesh)
        bm.free()
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.collection.objects.link(obj)
    mesh.materials.append(MATS[material])
    if smooth:
        for polygon in mesh.polygons:
            polygon.use_smooth = True
    return put(obj)


def _link_mesh(name, mesh, material, at=(0, 0, 0)):
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.collection.objects.link(obj)
    obj.location = at
    mesh.materials.append(MATS[material])
    return obj


def _box_mesh(name, size, bevel):
    # Direct bmesh generation avoids thousands of operator/depsgraph updates.
    bm = bmesh.new()
    bmesh.ops.create_cube(bm, size=1.0)
    bmesh.ops.scale(bm, vec=Vector(size), verts=bm.verts)
    if bevel > 0:
        width = min(bevel, min(size) * .45)
        bmesh.ops.bevel(bm, geom=list(bm.edges), offset=width, segments=1,
                        affect="EDGES", clamp_overlap=True)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    mesh = bpy.data.meshes.new(name)
    bm.to_mesh(mesh)
    bm.free()
    return mesh


def box(name, at, size, material, bevel=0.0, group=None):
    previous = CURRENT
    if group:
        set_group(group)
    obj = _link_mesh(name, _box_mesh(name, size, bevel), material, at)
    put(obj)
    set_group(previous)
    return obj


def _cylinder_mesh(name, radius, depth, vertices, bevel):
    rings = []
    half = depth * .5
    if bevel > 0:
        chamfer = min(bevel, depth * .30, radius * .30)
        rings = [(-half, radius - chamfer), (-half + chamfer, radius),
                 (half - chamfer, radius), (half, radius - chamfer)]
    else:
        rings = [(-half, radius), (half, radius)]
    verts = []
    for z, r in rings:
        for i in range(vertices):
            angle = math.tau * i / vertices
            verts.append((math.cos(angle) * r, math.sin(angle) * r, z))
    faces = []
    for j in range(len(rings) - 1):
        for i in range(vertices):
            a = j * vertices + i
            b = j * vertices + (i + 1) % vertices
            faces.append((a, b, b + vertices, a + vertices))
    faces.append(tuple(reversed(range(vertices))))
    top = (len(rings) - 1) * vertices
    faces.append(tuple(top + i for i in range(vertices)))
    mesh = bpy.data.meshes.new(name)
    mesh.from_pydata(verts, [], faces)
    mesh.validate()
    bm = bmesh.new()
    bm.from_mesh(mesh)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bm.to_mesh(mesh)
    bm.free()
    for polygon in mesh.polygons:
        if len(polygon.vertices) == 4:
            polygon.use_smooth = True
    return mesh


def cylinder(name, at, radius, depth, material, axis="Z", vertices=16,
             bevel=0.0, smooth=True, group=None):
    previous = CURRENT
    if group:
        set_group(group)
    mesh = _cylinder_mesh(name, radius, depth, vertices, bevel)
    obj = _link_mesh(name, mesh, material, at)
    if axis == "X":
        obj.rotation_euler.y = math.pi * .5
    elif axis == "Y":
        obj.rotation_euler.x = math.pi * .5
    if not smooth:
        for polygon in mesh.polygons:
            polygon.use_smooth = False
    put(obj)
    set_group(previous)
    return obj


def cylinder_between(name, start, end, radius, material, vertices=12,
                     smooth=True, group=None):
    p1, p2 = Vector(start), Vector(end)
    delta = p2 - p1
    length = delta.length
    if length < 1e-5:
        return None
    previous = CURRENT
    if group:
        set_group(group)
    mesh = _cylinder_mesh(name, radius, length, vertices, 0.0)
    obj = _link_mesh(name, mesh, material, (p1 + p2) * .5)
    obj.rotation_mode = "QUATERNION"
    obj.rotation_quaternion = delta.to_track_quat("Z", "Y")
    if not smooth:
        for polygon in mesh.polygons:
            polygon.use_smooth = False
    put(obj)
    set_group(previous)
    return obj


def beam(name, start, end, width, height, material, bevel=.008, group=None):
    p1, p2 = Vector(start), Vector(end)
    delta = p2 - p1
    length = delta.length
    if length < 1e-5:
        return None
    previous = CURRENT
    if group:
        set_group(group)
    obj = _link_mesh(name, _box_mesh(name, (width, height, length), bevel),
                     material, (p1 + p2) * .5)
    obj.rotation_mode = "QUATERNION"
    obj.rotation_quaternion = delta.to_track_quat("Z", "Y")
    put(obj)
    set_group(previous)
    return obj


def ibeam_profile(width, height, flange=.045, web=.032):
    hw, hh = width * .5, height * .5
    return [(-hw, -hh), (hw, -hh), (hw, -hh + flange), (web * .5, -hh + flange),
            (web * .5, hh - flange), (hw, hh - flange), (hw, hh), (-hw, hh),
            (-hw, hh - flange), (-web * .5, hh - flange), (-web * .5, -hh + flange),
            (-hw, -hh + flange)]


def profile_between(name, profile, start, end, material, group=None):
    p1, p2 = Vector(start), Vector(end)
    delta = p2 - p1
    length = delta.length
    if length < 1e-5:
        return None
    quat = delta.to_track_quat("Z", "Y")
    matrix = quat.to_matrix()
    count = len(profile)
    verts = []
    for depth in (0.0, length):
        for x, y in profile:
            verts.append(tuple(p1 + matrix @ Vector((x, y, depth))))
    faces = [tuple(reversed(range(count))), tuple(range(count, count * 2))]
    for i in range(count):
        j = (i + 1) % count
        faces.append((i, j, count + j, count + i))
    previous = CURRENT
    if group:
        set_group(group)
    obj = solid(name, verts, faces, material)
    set_group(previous)
    return obj


def ibeam(name, start, end, width=.26, height=.34, material="steel", group=None):
    return profile_between(name, ibeam_profile(width, height), start, end, material, group)


def flat_prism(name, polygon, z, thickness, material, group=None):
    count = len(polygon)
    top = [(x, y, z) for x, y in polygon]
    bottom = [(x, y, z - thickness) for x, y in polygon]
    faces = [tuple(range(count)), tuple(reversed(range(count, count * 2)))]
    for i in range(count):
        j = (i + 1) % count
        faces.append((i, j, count + j, count + i))
    previous = CURRENT
    if group:
        set_group(group)
    obj = solid(name, top + bottom, faces, material)
    set_group(previous)
    return obj


def strip_on_ground(name, points, width, z, thickness, material, group=None):
    left, right = [], []
    for i, point in enumerate(points):
        a = Vector(points[max(0, i - 1)])
        b = Vector(points[min(len(points) - 1, i + 1)])
        tangent = (b - a).normalized()
        normal = Vector((-tangent.y, tangent.x))
        left.append((point[0] + normal.x * width * .5,
                     point[1] + normal.y * width * .5))
        right.append((point[0] - normal.x * width * .5,
                      point[1] - normal.y * width * .5))
    return flat_prism(name, left + list(reversed(right)), z, thickness, material, group)


def ellipse(cx, cy, rx, ry, count=18, phase=.3, wobble=.18):
    points = []
    for i in range(count):
        angle = phase + math.tau * i / count
        radius = 1.0 + math.sin(angle * 3.0 + phase * 2.0) * wobble
        points.append((cx + math.cos(angle) * rx * radius,
                       cy + math.sin(angle) * ry * radius))
    return points


def corrugated_sheet(name, origin, u_dir, v_dir, u_length, v_length, material,
                     period=.24, amplitude=.032, thickness=.022, group=None,
                     u_segments=None, phase=0.0):
    origin = Vector(origin)
    u = Vector(u_dir).normalized()
    v = Vector(v_dir).normalized()
    n = u.cross(v).normalized()
    if u_segments is None:
        u_segments = max(12, min(280, int(round(u_length / period * 2.0))))
    v_segments = 3
    front, back = [], []
    for j in range(v_segments + 1):
        vv = v_length * j / v_segments
        for i in range(u_segments + 1):
            uu = u_length * i / u_segments
            wave = math.sin(math.tau * uu / period + phase) * amplitude
            point = origin + u * uu + v * vv
            front.append(tuple(point + n * wave))
            back.append(tuple(point + n * (wave - thickness)))
    stride = u_segments + 1
    faces = []
    for j in range(v_segments):
        for i in range(u_segments):
            a = j * stride + i
            b = a + 1
            c = a + stride + 1
            d = a + stride
            faces.append((a, b, c, d))
            faces.append((a + len(front), d + len(front), c + len(front), b + len(front)))
    for i in range(u_segments):
        a = i
        b = i + 1
        faces.append((a, a + len(front), b + len(front), b))
        top = v_segments * stride + i
        faces.append((top, top + 1, top + 1 + len(front), top + len(front)))
    for j in range(v_segments):
        a = j * stride
        d = (j + 1) * stride
        faces.append((a, d, d + len(front), a + len(front)))
        b = j * stride + u_segments
        e = (j + 1) * stride + u_segments
        faces.append((b, b + len(front), e + len(front), e))
    previous = CURRENT
    if group:
        set_group(group)
    obj = solid(name, front + back, faces, material)
    set_group(previous)
    return obj


def torus(name, at, major, minor, material, axis="Z", major_segments=20,
          minor_segments=6, group=None):
    previous = CURRENT
    if group:
        set_group(group)
    verts = []
    for i in range(major_segments):
        u = math.tau * i / major_segments
        for j in range(minor_segments):
            v = math.tau * j / minor_segments
            verts.append(((major + minor * math.cos(v)) * math.cos(u),
                          (major + minor * math.cos(v)) * math.sin(u),
                          minor * math.sin(v)))
    faces = []
    for i in range(major_segments):
        for j in range(minor_segments):
            a = i * minor_segments + j
            b = i * minor_segments + (j + 1) % minor_segments
            c = ((i + 1) % major_segments) * minor_segments + (j + 1) % minor_segments
            d = ((i + 1) % major_segments) * minor_segments + j
            faces.append((a, b, c, d))
    obj = solid(name, verts, faces, material, smooth=True)
    obj.location = at
    if axis == "X":
        obj.rotation_euler.y = math.pi * .5
    elif axis == "Y":
        obj.rotation_euler.x = math.pi * .5
    set_group(previous)
    return obj


def ico(name, at, radius, material, scale=(1, 1, 1), group=None):
    previous = CURRENT
    if group:
        set_group(group)
    bm = bmesh.new()
    bmesh.ops.create_icosphere(bm, subdivisions=1, radius=radius)
    mesh = bpy.data.meshes.new(name)
    bm.to_mesh(mesh)
    bm.free()
    obj = _link_mesh(name, mesh, material, at)
    obj.scale = scale
    put(obj)
    set_group(previous)
    return obj


def bolt(name, at, direction, radius=.018, depth=.018, material="steel"):
    return cylinder_between(name, at, Vector(at) + Vector(direction).normalized() * depth,
                            radius, material, vertices=6, smooth=False)


def text_sign(name, text, at, size, material, rotation=(math.pi * .5, 0, 0),
              extrude=.008, align="CENTER"):
    bpy.ops.object.text_add(location=at, rotation=rotation)
    obj = bpy.context.object
    obj.name = name
    obj.data.body = text
    obj.data.size = size
    obj.data.extrude = extrude
    obj.data.align_x = align
    obj.data.align_y = "CENTER"
    obj.data.materials.append(MATS[material])
    bpy.context.view_layer.objects.active = obj
    obj.select_set(True)
    bpy.ops.object.convert(target="MESH")
    obj = bpy.context.object
    obj.name = name
    apply_transform(obj)
    put(obj)
    return obj


def reassign(prefixes, target):
    moved = []
    for source, objects in GROUPS.items():
        if source == target:
            continue
        keep = []
        for obj in objects:
            if any(str(obj.name).startswith(prefix) for prefix in prefixes):
                obj["dd_group"] = target
                moved.append(obj)
            else:
                keep.append(obj)
        GROUPS[source] = keep
    GROUPS.setdefault(target, []).extend(moved)


def add_collider(name, center, size):
    """Register a Godot-space AABB collider from a Blender-space box."""
    cx, cy, cz = center
    sx, sy, sz = size
    COLLIDERS.append({
        "id": name,
        "position": [round(cx, 3), round(cz, 3), round(-cy, 3)],
        "size": [round(sx, 3), round(sz, 3), round(sy, 3)],
    })


def point_blocked(x, y):
    # Main hall, annexes, dock, and fenced equipment footprints.
    if -13.6 <= x <= 13.6 and -8.6 <= y <= 7.6:
        return True
    if -20.4 <= x <= -13.0 and -8.6 <= y <= -.4:
        return True
    if -21.5 <= x <= -16.5 and -2.4 <= y <= 8.0:
        return True
    if -13.0 <= x <= -2.0 and -11.0 <= y <= -8.0:
        return True
    if 16.0 <= x <= 21.0 and -2.0 <= y <= 5.0:
        return True
    if 17.0 <= x <= 22.0 and -15.0 <= y <= -9.0:
        return True
    if -12.5 <= x <= -5.0 and -16.0 <= y <= -12.0:
        return True
    if -4.0 <= x <= 1.0 and 14.0 <= y <= 18.0:
        return True
    return False


# ---------------------------------------------------------------------------
# Yard, hardstanding, rail spur and accumulated wear
stage("yard")
# ---------------------------------------------------------------------------
set_group("DD_Factory_Ground")
box("DD_Yard_SoilBase", (0, 0, -.10), (50, 40, .20), "soil")
box("DD_Yard_ConcreteApron", (-1, -.5, -.035), (43, 30, .11), "paving")

# Large concrete pours with separate expansion joints, not one flat colour.
random.seed(19)
for row in range(7):
    for column in range(11):
        x = -20.5 + column * 4.05
        y = -14.0 + row * 3.55
        if x > 20 or y > 10.5:
            continue
        if point_blocked(x, y):
            continue
        shade = "paving" if (row + column) % 3 else "foundation"
        slab = flat_prism("DD_ConcreteSlab", ellipse(x, y, 2.02, 1.76, 12,
                                                   (row * .7 + column) * .31, .035),
                          .038 + (row % 2) * .002, .028, shade)
        slab.data.materials.clear()
        slab.data.materials.append(MATS[shade])

# Entry road and its failed patchwork.  The road is deliberately interrupted by
# weeds and settlement cracks, not a perfect rectangle.
box("DD_EntryRoad", (3.7, 14.7, -.012), (13.5, 8.8, .055), "asphalt")
box("DD_EntryRoadWorn", (-.1, 11.2, .016), (4.7, 3.8, .028), "asphalt")
box("DD_LoadingApron", (-7.0, -4.9, .012), (15.2, 10.9, .042), "asphalt")

# Weathered lane markings.
for y in (10.8, 12.9, 15.0, 17.1):
    for x in (1.8, 5.7):
        box("DD_LanePaint", (x, y, .043), (.10, 1.35, .008), "cream")
for x in (-10.2, -9.7, -9.2):
    box("DD_DockHatch", (x, -9.6, .042), (.11, 2.35, .009), "hard_hat")
box("DD_KeepClear", (6.6, -7.3, .046), (3.8, .12, .010), "hard_hat")

# Connected settlement fractures and local repairs.
for network in range(9):
    x0 = random.uniform(-21, 20)
    y0 = random.uniform(-16, 17)
    if point_blocked(x0, y0):
        continue
    points = [(x0, y0)]
    heading = random.uniform(-math.pi, math.pi)
    for step in range(random.randint(5, 9)):
        heading += random.uniform(-.38, .38)
        length = random.uniform(.45, 1.15)
        nx = points[-1][0] + math.cos(heading) * length
        ny = points[-1][1] + math.sin(heading) * length
        if abs(nx) > 22.8 or abs(ny) > 18.8:
            break
        points.append((nx, ny))
    if len(points) > 2:
        strip_on_ground("DD_SettlementCrack", points, .022, .050, .009, "crack")
        if network % 3 == 0:
            branch_at = points[len(points) // 2]
            strip_on_ground("DD_CrackBranch", [branch_at,
                (branch_at[0] + .55, branch_at[1] + .42),
                (branch_at[0] + .92, branch_at[1] + .63)], .016, .051, .008, "crack")

# Standing water in the low corners and beneath the failed gutter.
for i, (x, y, rx, ry) in enumerate([(-14.0, 9.8, 1.8, .65), (-11.8, 10.4, .85, .4),
                                    (17.6, 6.8, 1.45, .75), (7.0, -15.8, 1.75, .55),
                                    (-20.2, -7.0, 1.2, .52)]):
    flat_prism("DD_Puddle", ellipse(x, y, rx, ry, 16, i * .7, .22),
               .058, .008, "water")
    if i % 2 == 0:
        flat_prism("DD_PuddleSheen", ellipse(x + .28, y - .05, rx * .42, ry * .25, 12,
                                             i, .12), .060, .005, "glass")

# Oil stains are irregular, directional and concentrated under machines /
# vehicles rather than scattered uniformly.
for i, (x, y, rx, ry, angle) in enumerate([(-8.7, .3, 1.1, .55, .3),
                                            (2.9, 12.4, .85, .38, -.4),
                                            (12.2, -5.6, .75, .46, .9),
                                            (-5.6, -14.3, 2.0, .7, .1)]):
    flat_prism("DD_OilStain", ellipse(x, y, rx, ry, 14, angle, .28),
               .056, .006, "oil")

# Embedded rail spur to the loading bay, with real chairs, spikes and a stop.
box("DD_RailBallast", (-8.0, -12.9, .035), (31.0, 2.65, .055), "crack")
for side in (-1, 1):
    rail_y = -12.9 + side * .7175
    ibeam("DD_Rail", (-23.2, rail_y, .12), (7.2, rail_y, .12),
          .075, .13, "rust")
for i in range(45):
    x = -23.0 + i * .68
    box("DD_RailSleeper", (x, -12.9, .08), (.24, 2.45, .13), "old_wood", .006)
    for side in (-1, 1):
        for foot in (-.32, .32):
            box("DD_RailPlate", (x + foot, -12.9 + side * .7175, .152),
                (.18, .11, .026), "steel", .004)
buffer_y = -12.9
for side in (-1, 1):
    box("DD_BufferPost", (7.3, buffer_y + side * .82, .64), (.22, .24, 1.28), "rust", .012)
box("DD_BufferBeam", (7.3, buffer_y, .98), (.42, 2.55, .34), "signal_red", .02)
text_sign("DD_BufferMark", "STOP", (7.12, buffer_y, .98), .22, "cream",
          rotation=(math.pi * .5, 0, math.pi * .5))

add_collider("rail_buffer", (7.3, buffer_y, .65), (.5, 2.6, 1.3))


# ---------------------------------------------------------------------------
# Chain-link perimeter, gate gantry and gatehouse
stage("fence")
# ---------------------------------------------------------------------------
def add_wire_prism(vertices, faces, a, b, normal, width=.012, thickness=.0035):
    a, b = Vector(a), Vector(b)
    direction = b - a
    if direction.length < .03:
        return
    side = direction.normalized().cross(normal).normalized() * width * .5
    offset = normal * thickness * .5
    base = len(vertices)
    for sign in (-1, 1):
        for point in (a, b):
            vertices.extend([tuple(point + side * sign + offset),
                             tuple(point + side * sign - offset)])
    # 8 verts: near/far x a/b.  Build a closed box.
    faces.extend([
        (base, base + 2, base + 3, base + 1),
        (base + 4, base + 5, base + 7, base + 6),
        (base, base + 1, base + 5, base + 4),
        (base + 2, base + 6, base + 7, base + 3),
        (base, base + 4, base + 6, base + 2),
        (base + 1, base + 3, base + 7, base + 5),
    ])


def chainlink_run(start, end, height=2.2, spacing=.14, name="DD_ChainLink",
                  add_wire=True, barbed=False):
    p0 = Vector((start[0], start[1], start[2] if len(start) > 2 else 0))
    p1 = Vector((end[0], end[1], end[2] if len(end) > 2 else 0))
    direction = p1 - p0
    length = Vector((direction.x, direction.y, 0)).length
    if length < .1:
        return
    u = Vector((direction.x, direction.y, 0)).normalized()
    normal = u.cross(Vector((0, 0, 1)))
    if add_wire:
        vertices, faces = [], []
        max_c = int(round((length + height) / spacing)) + 1
        for slope in (1, -1):
            for c in [i * spacing for i in range(-max_c, max_c + 1)]:
                if slope == 1:
                    s0, s1 = max(0.0, -c), min(length, height - c)
                else:
                    s0, s1 = max(0.0, c - height), min(length, c)
                if s1 - s0 < .055:
                    continue
                a = p0 + u * s0 + Vector((0, 0, slope * s0 + c))
                b = p0 + u * s1 + Vector((0, 0, slope * s1 + c))
                add_wire_prism(vertices, faces, a, b, normal)
        if vertices:
            solid(name + "_Mesh", vertices, faces, "steel")
    # Tension rails / posts.
    cylinder_between(name + "_Post0", p0, p0 + Vector((0, 0, height + .16)),
                     .045, "rust", vertices=10)
    cylinder_between(name + "_Post1", p1, p1 + Vector((0, 0, height + .16)),
                     .045, "rust", vertices=10)
    cylinder_between(name + "_TopRail", p0 + Vector((0, 0, height - .06)),
                     p1 + Vector((0, 0, height - .06)), .025, "rust", vertices=8)
    cylinder_between(name + "_BottomRail", p0 + Vector((0, 0, .12)),
                     p1 + Vector((0, 0, .12)), .018, "rust", vertices=8)
    if barbed:
        for offset in (.05, .20, .35):
            cylinder_between(name + "_BarbWire", p0 + Vector((0, 0, height + offset)),
                             p1 + Vector((0, 0, height + offset)), .006, "steel",
                             vertices=5)
        count = max(2, int(length / .42))
        for i in range(count):
            at = p0.lerp(p1, (i + .5) / count)
            for offset in (.05, .20, .35):
                center = at + Vector((0, 0, height + offset))
                box(name + "_Barb", tuple(center), (.11, .011, .011), "steel")


fence_height = 2.25
for x0, x1, y in [(-23.5, 1.15, 19.0), (7.85, 15.2, 19.0),
                  (19.4, 23.5, 19.0)]:
    length = x1 - x0
    count = max(1, int(round(length / 3.0)))
    for i in range(count):
        a = x0 + i * length / count
        b = x0 + (i + 1) * length / count
        chainlink_run((a, y, .04), (b, y, .04), fence_height,
                      name="DD_FenceSouth_%02d" % i, barbed=True)
for x in (-23.5, 23.5):
    for i in range(13):
        y0 = -19.0 + i * 38.0 / 13
        y1 = -19.0 + (i + 1) * 38.0 / 13
        chainlink_run((x, y0, .04), (x, y1, .04), fence_height,
                      name="DD_FenceSide_%02d_%02d" % (int(x), i), barbed=False)
for x0, x1 in [(-23.5, -7.5), (-4.0, 23.5)]:
    chainlink_run((x0, -19.0, .04), (x1, -19.0, .04), fence_height,
                  name="DD_FenceNorth", barbed=False)

# Front fence colliders leave the gate and the collapsed section passable.
add_collider("fence_south_west", (-11.2, 19.0, 1.15), (24.6, .18, 2.3))
add_collider("fence_south_mid", (11.5, 19.0, 1.15), (7.35, .18, 2.3))
add_collider("fence_south_east", (21.45, 19.0, 1.15), (4.1, .18, 2.3))
add_collider("fence_west", (-23.5, 0, 1.15), (.18, 38.2, 2.3))
add_collider("fence_east", (23.5, 0, 1.15), (.18, 38.2, 2.3))
add_collider("fence_north_west", (-15.5, -19.0, 1.15), (16.2, .18, 2.3))
add_collider("fence_north_east", (9.75, -19.0, 1.15), (27.7, .18, 2.3))

# Collapsed fence: bent posts, wire lying in the dirt and a warning barrier.
box("DD_FenceFall_Post", (16.2, 18.95, .42), (.12, .12, 2.7), "rust", .016)
for i in range(5):
    x = 15.7 + i * .72
    box("DD_FenceFall_Wire", (x, 18.25 + (i % 2) * .20, .12),
        (.36, .05, .018), "steel")
for x in (15.2, 19.4):
    cylinder("DD_FenceBrokenPost", (x, 19.0, 1.35), .055, 2.7, "rust",
             axis="Z", vertices=10)
box("DD_FenceWarningBar", (17.3, 18.55, .74), (4.25, .10, .18), "hard_hat", .01)
box("DD_FenceWarningStripe", (17.3, 18.50, .74), (4.0, .02, .05), "crack")
text_sign("DD_FenceWarning", "BROKEN FENCE / KEEP OUT", (17.3, 18.46, .96),
          .20, "crack")

# Main gate: one leaf swung inward, one hanging from a single hinge.
gate_y = 19.0
for x in (1.25, 7.75):
    box("DD_GateFooting", (x, gate_y, .20), (.72, .72, .40), "foundation", .02)
    box("DD_GatePost", (x, gate_y, 1.85), (.26, .26, 3.3), "rust", .02)
    box("DD_GatePostCap", (x, gate_y, 3.53), (.34, .34, .10), "steel", .012)
    for side in (-1, 1):
        bolt("DD_GatePostBolt", (x + side * .14, gate_y - .02, 3.0),
             (1, 0, 0), .015, .03)
chainlink_run((1.25, 17.9, .05), (1.25, 14.8, .05), 2.1,
              name="DD_GateLeafA", barbed=False)
# Hanging leaf, rotated ~20 degrees off the fence line.
chainlink_run((7.75, gate_y, .05), (6.0, 16.9, .05), 2.1,
              name="DD_GateLeafB", barbed=False)
for leaf_start, leaf_end in [((1.25, 14.8, .0), (1.25, 17.9, .0)),
                             ((6.0, 16.9, .0), (7.75, 19.0, .0))]:
    for z in (.18, 2.16):
        beam("DD_GateLeafRail", (leaf_start[0], leaf_start[1], z),
             (leaf_end[0], leaf_end[1], z), .07, .07, "rust", .006)
beam("DD_GateLeafBrace", (6.0, 16.9, .2), (7.75, 19.0, 2.15),
     .05, .05, "rust", .005)
for hinge in ((1.25, 17.5, 2.05), (1.25, 15.0, 2.05)):
    cylinder_between("DD_GateHinge", (hinge[0] - .18, hinge[1], hinge[2]),
                     (hinge[0] + .18, hinge[1], hinge[2]), .055, "steel", vertices=8)
# A loose gate chain and padlock at the open leaf.
for i in range(9):
    angle = i * .65
    torus("DD_GateChain", (1.25, 14.55 - i * .07, .75 + .05 * math.sin(angle)),
          .045, .008, "rust", axis="Y", major_segments=8, minor_segments=4)
box("DD_GatePadlock", (1.25, 14.0, .77), (.09, .07, .12), "steel", .01)

# Gate gantry sign.
for x in (1.05, 7.95):
    box("DD_GateSignPost", (x, 18.75, 2.1), (.18, .18, 4.2), "steel", .012)
box("DD_GateSignBeam", (4.5, 18.75, 4.05), (7.3, .16, .18), "steel", .012)
box("DD_GateSignBack", (4.5, 18.70, 3.45), (6.7, .10, 1.25), "crack", .015)
box("DD_GateSignBorder", (4.5, 18.66, 3.45), (6.5, .03, 1.05), "rust", .008)
text_sign("DD_GateSignText", "HALVORSEN WORKS", (4.5, 18.62, 3.55),
          .62, "hard_hat")
text_sign("DD_GateSignSub", "IRON  /  STEEL  /  NO TRESPASSING", (4.5, 18.60, 3.05),
          .22, "cream")

# Gatehouse.
gx, gy = -2.25, 15.6
box("DD_GatehouseBase", (gx, gy, .09), (3.1, 2.8, .18), "foundation", .02)
box("DD_GatehouseBody", (gx, gy, 1.42), (2.9, 2.55, 2.55), "cream", .04)
box("DD_GatehouseRoof", (gx, gy, 2.82), (3.3, 2.95, .18), "roof", .02)
beam("DD_GatehouseRoofSlope", (gx - 1.62, gy, 2.82), (gx, gy, 3.25),
     2.95, .10, "roof", .012)
for side in (-1, 1):
    beam("DD_GatehouseRoofEdge", (gx, gy + side * 1.53, 3.22),
         (gx, gy - side * 1.53, 3.22), .12, .10, "rust", .008)
# Window and door.
box("DD_GatehouseWindowDark", (gx + 1.47, gy + .15, 1.65), (.05, 1.0, .85), "glass")
for z in (1.18, 1.65, 2.12):
    box("DD_GatehouseWindowMullion", (gx + 1.50, gy + .15, z),
        (.04, 1.08, .055), "steel", .004)
for y in (gy - .39, gy + .15, gy + .69):
    box("DD_GatehouseWindowMullionV", (gx + 1.50, y, 1.65),
        (.04, .045, .92), "steel", .004)
box("DD_GatehouseDoor", (gx - .35, gy - 1.30, 1.04), (.92, .08, 1.9), "old_wood", .015)
box("DD_GatehouseDoorFrame", (gx - .35, gy - 1.34, 2.04), (1.12, .10, .10), "steel")
box("DD_GatehouseStep", (gx - .35, gy - 1.55, .14), (1.3, .45, .18), "foundation", .015)
for i in range(4):
    box("DD_Sandbag", (gx + 1.15 + (i % 2) * .35, gy - 1.62, .17 + i * .17),
        (.56, .34, .20), "canvas", .035)
add_collider("gatehouse", (gx, gy, 1.4), (3.2, 2.9, 2.8))
add_collider("gate_post_a", (1.25, gate_y, 1.7), (.4, .4, 3.4))
add_collider("gate_post_b", (7.75, gate_y, 1.7), (.4, .4, 3.4))


# ---------------------------------------------------------------------------
# Main hall shell: brick plinth, corrugated cladding, broken openings, roof
stage("hall-shell")
# ---------------------------------------------------------------------------
set_group("DD_Factory_Shell")
HX0, HX1 = -13.0, 13.0
HY0, HY1 = -8.0, 7.0
EAVE, RIDGE = 5.5, 7.3

box("DD_HallFoundation", (0, -.5, -.055), (27.0, 15.8, .19), "foundation", .02)
box("DD_HallFloor", (0, -.5, .035), (26.2, 15.0, .050), "paving")
# Floor plates, drains and the long painted walkway.
for x in (-9.0, -3.0, 3.0, 9.0):
    box("DD_FloorJoint", (x, -.5, .064), (.035, 14.7, .008), "crack")
for y in (-4.8, -.6, 3.6):
    box("DD_FloorJoint", (0, y, .064), (26.0, .035, .008), "crack")
for i in range(7):
    box("DD_FloorDrain", (-11.0 + i * 3.6, -6.8, .068), (.36, .26, .018), "steel")
box("DD_Walkway", (1.8, -.2, .070), (2.7, 14.0, .008), "hard_hat")
for y in (-5.0, -1.5, 2.0, 5.5):
    box("DD_WalkwayStripe", (1.8, y, .079), (2.35, .10, .004), "crack")
# Machine plinths.
for cx, cy, sx, sy in [(-9.4, 1.4, 4.1, 3.0), (-5.4, -4.5, 4.0, 2.2),
                       (8.6, -4.8, 3.0, 2.5)]:
    box("DD_MachinePlinth", (cx, cy, .11), (sx, sy, .14), "foundation", .025)
    box("DD_MachinePlinthEdge", (cx, cy, .185), (sx - .12, sy - .12, .018), "concrete_dark")

# Brick plinth bands and structural columns.
for x0, x1 in [(-13.0, -2.2), (5.2, 7.4), (7.4, 7.75), (11.65, 13.0)]:
    box("DD_SouthBrickPlinth", ((x0 + x1) * .5, -8.18, 1.20),
        (x1 - x0, .38, 2.30), "brick", .025)
    box("DD_SouthPlinthCap", ((x0 + x1) * .5, -8.18, 2.36),
        (x1 - x0 + .12, .50, .13), "foundation", .025)
for x0, x1 in [(-13.2, -13.0), (13.0, 13.2)]:
    box("DD_CornerPier", (x0, -.5, 2.9), (.40, 15.2, 5.8), "brick", .03)

for x in (-13.0, -6.5, -.35, 5.5, 13.0):
    ibeam("DD_HallColumn_S", (x, -8.25, .05), (x, -8.25, 5.65),
          .30, .38, "steel")
    box("DD_ColumnFoot", (x, -8.25, .10), (.62, .62, .20), "foundation", .02)
    for dx, dy in [(-.23, -.23), (.23, -.23), (-.23, .23), (.23, .23)]:
        bolt("DD_ColumnBolt", (x + dx, -8.25 + dy, .21), (0, 0, 1), .020, .025)
    # Knee brace into the truss / eave.
    beam("DD_KneeBrace", (x, -8.25, 4.6), (x, -6.9, 5.35), .13, .13, "steel")
for x in (-13.0, -6.5, -.35, 5.5, 13.0):
    ibeam("DD_HallColumn_N", (x, 7.15, .05), (x, 7.15, 5.65), .26, .34, "steel")

# Upper cladding, with real corrugation and separate expansion bays.
set_group("DD_Factory_Wall_South")
corrugated_sheet("DD_SouthClad_A", (-13.0, -8.34, 2.30), (1, 0, 0), (0, 0, 1),
                 10.8, 3.20, "roof", .22, .030)
corrugated_sheet("DD_SouthClad_B", (5.2, -8.34, 2.30), (1, 0, 0), (0, 0, 1),
                 7.8, 3.20, "roof", .22, .030)
for x in (-13.0, -8.7, -4.1, 5.2, 9.2, 13.0):
    box("DD_SouthGirt", (x, -8.30, 3.88), (.13, .18, 3.28), "steel", .008)
for z in (2.34, 5.47):
    box("DD_SouthCladTrim", (0, -8.26, z), (26.0, .20, .12), "rust", .008)
# Torn header above the collapsed centre bay.
box("DD_BreachHeader", (2.35, -8.20, 4.84), (7.7, .40, .70), "brick", .025)
beam("DD_BreachHeaderBeam", (-.55, -8.20, 4.35), (5.25, -8.20, 4.35),
     .20, .28, "rust", .012)
for i in range(12):
    x = -.45 + i * .48
    box("DD_BrokenBrickEdge", (x, -8.20, 4.35 + (i % 3) * .16),
        (.32, .40, .18 + (i % 4) * .07), "brick", .008)
for i in range(7):
    x = -.35 + i * .82
    box("DD_BrokenHeaderBrick", (x, -8.20, 5.18 + (i % 2) * .11),
        (.48, .40, .30), "brick", .008)
    if i % 2:
        cylinder_between("DD_ExposedRebar", (x, -8.02, 5.15),
                         (x + .18, -8.02, 5.52), .012, "rust", vertices=5)
# The east wall is a separate cutaway group.
set_group("DD_Factory_Wall_East")
for y0, y1 in [(-8.0, -4.0), (0.0, 7.0)]:
    box("DD_EastBrickPlinth", (13.18, (y0 + y1) * .5, 1.20),
        (.38, y1 - y0, 2.30), "brick", .025)
    corrugated_sheet("DD_EastClad", (13.34, y0, 2.30), (0, 1, 0), (0, 0, 1),
                     y1 - y0, 3.20, "roof", .22, .030)
    box("DD_EastTrim", (13.26, (y0 + y1) * .5, 5.45),
        (.22, y1 - y0, .12), "rust", .008)
# Jagged east breach edge.
for i in range(8):
    y = -4.0 + i * .48
    box("DD_EastBrokenBrick", (13.10, y, 2.72 + (i % 2) * .20),
        (.40, .32, .55 + (i % 3) * .10), "brick", .006)
# Back and west walls are complete and stay in the cutaway.
set_group("DD_Factory_Shell")
box("DD_NorthBrickPlinth", (0, 7.18, 1.20), (26.0, .38, 2.30), "brick", .025)
corrugated_sheet("DD_NorthClad", (-13.0, 7.34, 2.30), (1, 0, 0), (0, 0, 1),
                 26.0, 3.20, "roof", .22, .030)
box("DD_NorthTrim", (0, 7.26, 5.45), (26.0, .22, .12), "rust", .008)
box("DD_WestBrickPlinth", (-13.18, -.5, 1.20), (.38, 15.0, 2.30), "brick", .025)
corrugated_sheet("DD_WestClad", (-13.34, -8.0, 2.30), (0, 1, 0), (0, 0, 1),
                 15.0, 3.20, "roof", .22, .030)
box("DD_WestTrim", (-13.26, -.5, 5.45), (.22, 15.0, .12), "rust", .008)
for y in (-6.5, -2.5, 1.5, 5.5):
    box("DD_InteriorWallGirt", (-12.92, y, 3.9), (.13, .18, 3.3), "steel", .008)

# Roofline gutter, downpipes and fascia.
for x in (-13.15, 13.15):
    box("DD_RoofFascia", (x, -.5, 5.53), (.22, 15.2, .18), "rust", .008)
box("DD_GutterSouth", (0, -8.28, 5.44), (26.0, .24, .20), "rust", .01)
for x in (-12.5, 8.0):
    cylinder("DD_Downpipe", (x, -8.40, 2.72), .09, 5.35, "rust",
             axis="Z", vertices=10)
    for z in (1.0, 2.7, 4.4):
        cylinder("DD_DownpipeClamp", (x, -8.40, z), .12, .06, "steel",
                 axis="Z", vertices=10)
    cylinder("DD_DownpipeElbow", (x - .15, -8.40, .18), .10, .36, "rust",
             axis="X", vertices=10)

# Windows: four on the south, two on the east, four on the north.
def glass_shard(name, corners, y):
    verts = []
    for point in corners:
        verts.extend([(point[0], y, point[1]), (point[0], y - .012, point[1])])
    solid(name, verts, [(0, 1, 3, 2), (4, 6, 7, 5), (0, 2, 6, 4),
                        (1, 5, 7, 3), (0, 4, 5, 1), (2, 3, 7, 6)], "glass")


def window_south(name, x, z, w=1.35, h=1.05, broken=False):
    y = -8.46
    box(name + "_Dark", (x, y + .08, z), (w - .08, .10, h - .08), "crack")
    box(name + "_Glass", (x, y, z), (w - .16, .028, h - .16),
        "glass" if not broken else "crack")
    for side in (-1, 1):
        box(name + "_Jamb", (x + side * w * .5, y - .02, z),
            (.09, .16, h + .12), "steel", .004)
    for side in (-1, 1):
        box(name + "_Rail", (x, y - .02, z + side * h * .5),
            (w + .12, .16, .09), "steel", .004)
    box(name + "_Transom", (x, y - .025, z), (.065, .12, h), "steel", .003)
    box(name + "_Sill", (x, y - .10, z - h * .5 - .05),
        (w + .30, .34, .10), "foundation", .015)
    if broken:
        glass_shard(name + "_ShardA",
                    [(x - w * .45, z - h * .44), (x - w * .18, z - h * .10),
                     (x - w * .37, z + h * .15)], y - .03)
        glass_shard(name + "_ShardB",
                    [(x + w * .13, z + h * .46), (x + w * .43, z + h * .42),
                     (x + w * .36, z + h * .12)], y - .03)
        glass_shard(name + "_ShardC",
                    [(x + w * .05, z - h * .45), (x + w * .28, z - h * .38),
                     (x + w * .20, z - h * .18)], y - .03)


def window_east(name, y, z, w=1.30, h=1.02, broken=False):
    x = 13.46
    box(name + "_Dark", (x - .08, y, z), (.10, w - .08, h - .08), "crack")
    box(name + "_Glass", (x, y, z), (.028, w - .16, h - .16),
        "glass" if not broken else "crack")
    for side in (-1, 1):
        box(name + "_Jamb", (x - .02, y + side * w * .5, z),
            (.16, .09, h + .12), "steel", .004)
    for side in (-1, 1):
        box(name + "_Rail", (x - .02, y, z + side * h * .5),
            (.16, w + .12, .09), "steel", .004)
    box(name + "_Transom", (x - .025, y, z), (.12, .065, h), "steel", .003)
    box(name + "_Sill", (x - .10, y, z - h * .5 - .05),
        (.34, w + .30, .10), "foundation", .015)


set_group("DD_Factory_Wall_South")
window_south("DD_Win_S1", -9.6, 3.85, 1.55, 1.10, True)
window_south("DD_Win_S2", -6.2, 3.85, 1.55, 1.10, False)
window_south("DD_Win_S3", 6.3, 3.95, 1.25, .95, True)
window_south("DD_Win_S4", 12.0, 3.95, 1.25, .95, False)
set_group("DD_Factory_Wall_East")
window_east("DD_Win_E1", -6.4, 3.70, 1.70, 1.10, False)
window_east("DD_Win_E2", -2.9, 3.70, 1.70, 1.10, True)
window_east("DD_Win_E3", 2.2, 3.70, 1.70, 1.10, True)
window_east("DD_Win_E4", 5.5, 3.70, 1.70, 1.10, False)
set_group("DD_Factory_Shell")
for x in (-9.5, -4.0, 2.0, 8.4):
    box("DD_NorthWindow", (x, 7.43, 3.9), (1.8, .06, 1.0), "glass")
    box("DD_NorthWindowFrame", (x, 7.39, 3.9), (1.95, .10, 1.15), "steel", .008)
    box("DD_NorthWindowHole", (x, 7.34, 3.9), (1.7, .10, .90), "crack")

# Dock doors and the half-open bay 03.
def rollup_door(name, cx, y, z0, width, height, open_bottom=None, label="01"):
    frame_mat = "rust"
    box(name + "_FrameL", (cx - width * .5 - .08, y - .03, z0 + height * .5),
        (.16, .18, height + .22), frame_mat, .01)
    box(name + "_FrameR", (cx + width * .5 + .08, y - .03, z0 + height * .5),
        (.16, .18, height + .22), frame_mat, .01)
    box(name + "_Header", (cx, y - .03, z0 + height + .09),
        (width + .32, .18, .18), frame_mat, .01)
    if open_bottom is None:
        bottom = z0
        slats = int(height / .18)
        for i in range(slats):
            z = bottom + i * .18 + .09
            box(name + "_Slat", (cx, y, z), (width, .07, .16), "roof", .006)
        box(name + "_Lock", (cx + width * .30, y - .07, z0 + .55),
            (.28, .12, .22), "steel", .008)
        for i in range(4):
            box(name + "_DoorStripe", (cx - width * .44 + i * .11, y - .05, z0 + .28),
                (.07, .04, .34), "hard_hat")
    else:
        bottom = open_bottom
        slats = max(1, int((z0 + height - bottom) / .18))
        for i in range(slats):
            z = bottom + i * .18 + .09
            box(name + "_Slat", (cx, y, z), (width, .07, .16), "roof", .006)
        box(name + "_HeaderCurtain", (cx, y + .02, z0 + height - .10),
            (width, .10, .20), "rust", .01)

    for side in (-1, 1):
        box(name + "_Guide", (cx + side * (width * .5 + .02), y - .10,
                              z0 + height * .5), (.10, .12, height), "steel", .004)
    box(name + "_NumberPlate", (cx, y - .14, z0 + height - .42),
        (1.05, .06, .48), "hard_hat", .01)
    text_sign(name + "_Number", "BAY " + label, (cx, y - .18, z0 + height - .42),
              .27, "crack")


rollup_door("DD_DockDoor", -8.5, -8.44, 1.05, 4.3, 4.1, label="01")
rollup_door("DD_Bay03", 9.7, -8.44, .05, 3.9, 4.15, open_bottom=2.65, label="03")
# Personnel door beside bay 03.
box("DD_PersonDoor", (6.25, -8.47, 1.15), (1.12, .10, 2.2), "old_wood", .012)
box("DD_PersonDoorFrame", (6.25, -8.41, 2.28), (1.34, .14, .13), "steel", .008)
box("DD_PersonDoorFrameL", (5.61, -8.41, 1.17), (.13, .14, 2.3), "steel", .008)
box("DD_PersonDoorFrameR", (6.89, -8.41, 1.17), (.13, .14, 2.3), "steel", .008)
for z in (.55, 1.55):
    box("DD_PersonDoorBrace", (6.25, -8.52, z), (1.0, .035, .09), "rust")
box("DD_PersonDoorHandle", (6.73, -8.56, 1.07), (.08, .08, .18), "steel", .01)

# Loading dock, steps, canopy and bumpers.
box("DD_DockPlatform", (-7.35, -9.35, .53), (10.3, 2.7, 1.06), "foundation", .04)
box("DD_DockTop", (-7.35, -9.35, 1.075), (10.2, 2.6, .06), "concrete_dark", .02)
for i in range(4):
    x = -2.2 + i * .34
    box("DD_DockStep", (x, -9.35, .18 + i * .22), (.36, 2.4, .20 + i * .22),
        "foundation", .012)
for i in range(5):
    box("DD_DockEdgeStripe", (-12.0 + i * 2.05, -10.72, 1.095),
        (.62, .16, .02), "hard_hat")
for x in (-10.5, -7.2, -3.9):
    box("DD_DockBumper", (x, -10.76, .62), (.55, .20, .46), "rubber", .03)
    box("DD_DockBumperBolt", (x - .18, -10.88, .62), (.05, .04, .05), "steel")
box("DD_DockStairRail", (-1.82, -10.38, 1.3), (.08, .08, 1.0), "steel")
beam("DD_DockStairRailSlope", (-1.82, -10.38, 1.3), (-1.82, -8.15, 2.15),
     .06, .06, "steel", .004)
# Canopy over the dock.
for x in (-12.0, -2.7):
    box("DD_CanopyPost", (x, -10.45, 2.15), (.20, .20, 4.2), "steel", .012)
    beam("DD_CanopyBrace", (x, -10.45, 2.2), (x, -8.3, 3.7), .10, .10, "steel")
box("DD_DockCanopy", (-7.35, -9.45, 4.28), (10.1, 2.65, .18), "roof", .02)
for i in range(9):
    box("DD_CanopyRib", (-11.9 + i * 1.2, -9.45, 4.16),
        (.09, 2.62, .10), "steel", .004)
for i in range(6):
    box("DD_CanopyRust", (-11.2 + i * 1.6, -8.16, 4.28), (.45, .10, .12), "rust")
cylinder("DD_DockLampHousing", (-7.35, -9.65, 4.13), .22, .12, "rust",
         axis="Z", vertices=16)
cylinder("DD_DockLampLens", (-7.35, -9.65, 4.05), .17, .025, "lamp_glow",
         axis="Z", vertices=16)

# Colliders: walls leave the breach, bay 03 and personnel door passable.
add_collider("hall_south_west", (-7.5, -8.18, 2.7), (11.0, .42, 5.4))
add_collider("hall_south_mid", (6.3, -8.18, 2.7), (2.2, .42, 5.4))
add_collider("hall_south_east", (12.325, -8.18, 2.7), (1.35, .42, 5.4))
add_collider("hall_breach_header", (2.35, -8.18, 4.85), (7.7, .42, 1.0))
add_collider("hall_bay03_header", (9.7, -8.18, 4.2), (3.9, .42, 2.6))
add_collider("hall_north", (0, 7.18, 2.7), (26.0, .42, 5.4))
add_collider("hall_west", (-13.18, -.5, 2.7), (.42, 15.0, 5.4))
add_collider("hall_east_south", (13.18, -6.0, 2.7), (.42, 4.0, 5.4))
add_collider("hall_east_north", (13.18, 3.5, 2.7), (.42, 7.0, 5.4))
add_collider("dock_platform", (-7.35, -9.35, .53), (10.3, 2.7, 1.06))
add_collider("canopy_post_w", (-12.0, -10.45, 2.15), (.25, .25, 4.2))
add_collider("canopy_post_e", (-2.7, -10.45, 2.15), (.25, .25, 4.2))
add_collider("gatehouse_canopy", (-7.35, -9.45, 4.3), (10.2, 2.7, .2))

# ---------------------------------------------------------------------------
# Sawtooth roof, north-light glazing and collapsed east bay
stage("roof")
# ---------------------------------------------------------------------------
set_group("DD_Factory_Roof")
roof_bays = [(-8.0, -4.25), (-4.25, -.5), (-.5, 3.25), (3.25, 7.0)]
roof_x_end = [13.0, 13.0, 7.4, 10.2]
for i, (y0, y1) in enumerate(roof_bays):
    x_end = roof_x_end[i]
    length = x_end - HX0
    corrugated_sheet("DD_RoofSlope_%d" % i, (HX0, y0, EAVE),
                     (1, 0, 0), (0, y1 - y0, RIDGE - EAVE),
                     length, 1.0, "roof", .24, .032, u_segments=132)
    # Vertical north-light glazing at the high edge of each bay.
    glazing_x0 = HX0
    glazing_x1 = x_end
    box("DD_NorthLightHeader", ((glazing_x0 + glazing_x1) * .5, y1, 7.28),
        (glazing_x1 - glazing_x0, .08, .12), "rust", .004)
    box("DD_NorthLightFrame", ((glazing_x0 + glazing_x1) * .5, y1, 6.35),
        (glazing_x1 - glazing_x0, .10, .05), "steel", .003)
    if i < 3:
        box("DD_NorthLightGlass", ((glazing_x0 + glazing_x1) * .5, y1, 6.38),
            (glazing_x1 - glazing_x0, .035, 1.65), "glass")
    else:
        # Last strip is mostly gone; only shards remain clipped to the frame.
        for panel in range(5):
            x = glazing_x0 + 2.2 + panel * 2.25
            glass_shard("DD_RoofGlassShard",
                        [(x, 5.60), (x + 1.25, 5.62), (x + .45, 6.45)],
                        y1 + .03)
    for panel in range(int((glazing_x1 - glazing_x0) / 2.1) + 1):
        x = glazing_x0 + panel * 2.1
        box("DD_NorthLightMullion", (x, y1 + .01, 6.38),
            (.08, .12, 1.72), "steel", .003)
    if i < 3:
        for panel in range(int((glazing_x1 - glazing_x0) / 4.2) + 1):
            x = glazing_x0 + panel * 4.2 + 2.1
            box("DD_NorthLightTransom", (x, y1 - .02, 6.38),
                (.08, .15, .06), "steel", .003)
    if i > 0:
        # Gutter at the bottom of each sawtooth.
        box("DD_SawGutter", ((HX0 + x_end) * .5, y0, EAVE - .02),
            (x_end - HX0, .22, .16), "rust", .008)
    # Purlins under the roof, visible from the floor when the roof is cut.
    for t in (.36, .68):
        px = (HX0 + x_end) * .5
        py = y0 + (y1 - y0) * t
        pz = EAVE + (RIDGE - EAVE) * t - .06
        box("DD_RoofPurlin", (px, py, pz), (x_end - HX0, .10, .12),
            "steel", .004).rotation_euler.x = math.atan2(RIDGE - EAVE, y1 - y0)
for y in (-8.0, -4.25, -.5, 3.25, 7.0):
    box("DD_RoofRidge", (0, y, EAVE if y == -8.0 else RIDGE),
        (26.0 if y != 7.0 else 26.0, .16, .12), "rust", .006)
# Collapsed roof debris, bent sheets and torn purlins.
for i in range(5):
    box("DD_RoofTear", (8.2 + i * .9, -2.0 + i * .3, 5.1 + i * .15),
        (1.4, .06, .28 + i * .12), "rust", .006)
    box("DD_RoofTearRib", (8.0 + i * .95, -2.1 + i * .3, 5.0 + i * .14),
        (1.5, .04, .05), "steel")
# Dangling strip near the collapsed eave.
for i in range(7):
    beam("DD_RoofFlap", (10.8 + i * .22, -8.0 + i * .65, 5.4),
         (10.4 + i * .30, -7.7 + i * .65, 3.4 - i * .15),
         .5, .035, "roof", .003)
# Roof edge trims.
for x in (HX0, roof_x_end[0]):
    box("DD_RoofEdgeTrim", (x, -.5, 5.72), (.16, 15.0, .28), "rust", .008)
for y in (-8.0, 7.0):
    box("DD_RoofEndCap", (0, y, 5.53), (26.0, .22, .18), "rust", .008)
# Ductwork and a cyclone on the surviving west roof.
for cx, cy, cz in [(-9.5, -5.8, 5.6), (-8.9, -4.8, 6.9)]:
    cylinder("DD_RoofDuct", (cx, cy, cz), .34, 2.8, "metal",
             axis="X", vertices=16)
    for i in range(3):
        torus("DD_RoofDuctFlange", (cx - 1.2 + i * 1.1, cy, cz), .39, .04,
              "rust", axis="X", major_segments=16, minor_segments=4)
cylinder("DD_RoofCyclone", (-8.9, 1.2, 7.55), .85, 1.1, "rust", axis="Z", vertices=20)
cylinder("DD_RoofCycloneCone", (-8.9, 1.2, 6.65), .85, 1.0, "rust", axis="Z", vertices=20)
cylinder("DD_RoofCycloneStack", (-8.9, 1.2, 8.35), .30, 1.2, "metal", axis="Z", vertices=16)
text_sign("DD_RoofNumber", "07", (-8.9, 1.2, 8.9), .35, "hard_hat",
          rotation=(math.pi * .5, 0, 0))

# Roof warning stripe at the loading side.
for i in range(16):
    box("DD_RoofHazard", (-12.2 + i * 1.7, -8.34, 5.56),
        (.55, .08, .16), "hard_hat")


# ---------------------------------------------------------------------------
# Structural trusses, crane runway and bridge crane
stage("trusses")
# ---------------------------------------------------------------------------
set_group("DD_Factory_Trusses")
for frame, x in enumerate((-11.6, -6.1, -.55, 5.0, 10.55)):
    ibeam("DD_TrussBottom", (x, -8.0, 4.55), (x, 7.0, 4.55),
          .19, .26, "steel")
    top_points = [(-8.0, 5.32), (-4.25, 7.10), (-4.25, 5.52),
                  (-.5, 7.10), (-.5, 5.52), (3.25, 7.10),
                  (3.25, 5.52), (7.0, 7.10)]
    for j in range(len(top_points) - 1):
        beam("DD_TrussTop", (x, top_points[j][0], top_points[j][1]),
             (x, top_points[j + 1][0], top_points[j + 1][1]),
             .13, .15, "steel", .004)
    for y, z in [(-8.0, 5.32), (-4.25, 7.10), (-.5, 7.10),
                 (3.25, 7.10), (7.0, 7.10)]:
        beam("DD_TrussPost", (x, y, 4.55), (x, y, z), .11, .13, "steel", .004)
    # Alternate diagonals, plus secondary struts at third points.
    for y0, y1 in [(-7.2, -4.25), (-3.5, -.5), (.5, 3.25), (4.1, 7.0)]:
        beam("DD_TrussDiag", (x, y0, 4.55), (x, y1, 7.08),
             .075, .085, "steel", .003)
        beam("DD_TrussDiagB", (x, y1, 4.55), (x, y0, 7.08),
             .065, .075, "steel", .003)
    for y, z in [(-4.25, 7.10), (-.5, 7.10), (3.25, 7.10)]:
        cylinder("DD_TrussGusset", (x - .12, y, z), .23, .035, "rust",
                 axis="X", vertices=10)
        for offset in (-.11, .11):
            bolt("DD_TrussBolt", (x - .145, y + offset, z), (-1, 0, 0), .016, .03)

# Crane runway beams along both sides of the hall.
for y in (-6.55, 5.55):
    ibeam("DD_CraneRailBeam", (-12.8, y, 4.23), (12.8, y, 4.23),
          .36, .44, "steel")
    box("DD_CraneRail", (0, y, 4.48), (25.6, .10, .10), "metal", .006)
    for x in (-12.4, -7.0, -1.5, 4.0, 9.5, 12.4):
        beam("DD_CraneBracket", (x, y, 4.08), (x, y + (0.7 if y < 0 else -0.7), 4.95),
             .12, .16, "steel", .004)
    for x in (-12.5, 12.5):
        box("DD_CraneEndStop", (x, y, 4.56), (.26, .18, .34), "hard_hat", .01)

# Bridge crane parked near the centre bay.
crane_x = 1.15
for y in (-6.55, 5.55):
    box("DD_CraneEndTruck", (crane_x, y, 4.43), (1.15, .75, .46), "rust", .02)
    for side in (-1, 1):
        for dx in (-.35, .35):
            cylinder("DD_CraneWheel", (crane_x + dx, y + side * .87, 4.40),
                     .22, .14, "steel", axis="X", vertices=14)
    box("DD_CraneWheelGuard", (crane_x, y, 4.65), (1.25, .18, .12), "hard_hat")
for y in (-7.0, 6.0):
    box("DD_CraneGirderWeb", (crane_x, y, 4.72), (.33, .18, .56), "steel", .01)
ibeam("DD_CraneBridge", (crane_x, -6.4, 4.72), (crane_x, 5.6, 4.72),
      .38, .52, "rust")
box("DD_CraneBridgeWalk", (crane_x - .62, 4.55, 4.95), (.55, 10.6, .07), "metal", .006)
for i in range(13):
    box("DD_CraneWalkRib", (crane_x - .62, -6.2 + i * .84, 4.90),
        (.55, .05, .07), "rust")
for y in (-6.4, -2.2, 2.0, 5.6):
    beam("DD_CraneWalkRailPost", (crane_x - .85, y, 4.95),
         (crane_x - .85, y, 5.95), .045, .045, "steel")
beam("DD_CraneWalkRail", (crane_x - .85, -6.4, 5.92),
     (crane_x - .85, 5.6, 5.92), .05, .05, "steel")
beam("DD_CraneWalkToe", (crane_x - .84, -6.4, 5.00),
     (crane_x - .84, 5.6, 5.00), .04, .12, "steel")

# Trolley, hook and control pendant.
trolley_y = -.55
box("DD_CraneTrolley", (crane_x, trolley_y, 4.98), (.84, .95, .34), "rust", .018)
cylinder("DD_CraneDrum", (crane_x, trolley_y, 5.18), .19, 1.0, "steel",
         axis="Y", vertices=16)
cylinder_between("DD_CraneCable", (crane_x + .25, trolley_y, 5.02),
                 (crane_x + .25, trolley_y, 2.36), .022, "steel", vertices=6)
box("DD_CraneHookBlock", (crane_x + .25, trolley_y, 2.25), (.24, .30, .42),
    "rust", .025)
torus("DD_CraneHook", (crane_x + .25, trolley_y, 1.98), .15, .045, "metal",
      axis="X", major_segments=12, minor_segments=5)
box("DD_CraneControlBox", (crane_x + .65, trolley_y, 4.24), (.19, .28, .40),
    "hard_hat", .012)
cylinder_between("DD_CranePendantCable", (crane_x + .65, trolley_y, 5.05),
                 (crane_x + .65, trolley_y, 4.48), .015, "crack", vertices=5)
for i in range(6):
    cylinder("DD_CraneButton", (crane_x + .65, trolley_y - .17, 4.15 + i * .035),
             .015, .03, "crack", axis="Z", vertices=6)

# Overhead service pipes, brackets and valves.
for z, radius, material in [(4.72, .10, "rust"), (4.50, .075, "metal"),
                            (4.28, .12, "roof")]:
    cylinder_between("DD_OverheadPipe", (-12.65, -7.8, z),
                     (-12.65, 6.8, z), radius, material, vertices=10)
    for y in (-7.0, -3.8, -.6, 2.6, 5.8):
        cylinder_between("DD_PipeFlange", (-12.65, y, z - .04),
                         (-12.65, y, z + .04), radius * 1.65, "steel",
                         vertices=12)
        beam("DD_PipeBracket", (-12.95, y, z), (-12.65, y, z),
             .18, .05, "steel")
for z in (4.4, 4.85):
    cylinder_between("DD_CrossPipe", (-12.6, -7.3, z), (12.5, -7.3, z),
                     .085, "rust", vertices=10)
    for x in (-8.0, -1.5, 5.0, 11.0):
        cylinder_between("DD_CrossPipeFlange", (x, -7.3, z - .03),
                         (x, -7.3, z + .03), .14, "steel", vertices=12)
for x in (-10.5, 6.5):
    cylinder_between("DD_PipeDrop", (x, -7.3, 4.4), (x, -7.3, 1.1),
                     .085, "rust", vertices=10)
    torus("DD_PipeValveWheel", (x, -7.05, 2.15), .27, .035, "signal_red",
          axis="Y", major_segments=14, minor_segments=5)
    cylinder_between("DD_ValveStem", (x, -7.3, 2.15), (x, -7.02, 2.15),
                     .04, "steel", vertices=8)

# Hanging industrial lights with cages.
for i, x in enumerate((-10.0, -6.0, -2.0, 2.0, 6.0, 10.0)):
    y = -.3
    cylinder_between("DD_LightDrop", (x, y, 5.35), (x, y, 4.55),
                     .015, "steel", vertices=5)
    bpy.ops.mesh.primitive_cone_add(vertices=16, radius1=.42, radius2=.12,
                                    depth=.28, location=(x, y, 4.43))
    shade = bpy.context.object
    shade.name = "DD_LightShade"
    shade.data.materials.append(MATS["roof"])
    for polygon in shade.data.polygons:
        polygon.use_smooth = True
    put(shade)
    cylinder("DD_LightLens", (x, y, 4.28), .30, .035, "lamp_glow",
             axis="Z", vertices=16)
    torus("DD_LightCage", (x, y, 4.24), .32, .014, "steel", axis="Z",
          major_segments=16, minor_segments=4)
    for side in (-1, 1):
        cylinder_between("DD_LightCageBar", (x + side * .30, y, 4.24),
                         (x + side * .12, y, 4.56), .010, "steel", vertices=5)
text_sign("DD_WallPipeLabel", "STEAM  /  RETURN", (-12.50, 2.3, 4.98),
          .17, "cream", rotation=(math.pi * .5, 0, math.pi * .5))


# ---------------------------------------------------------------------------
# Mezzanine control deck and stair
stage("mezzanine")
# ---------------------------------------------------------------------------
set_group("DD_Factory_Interior")
DECK_Z = 3.15
for x in (6.3, 12.65):
    for y in (2.35, 6.75):
        ibeam("DD_MezzPost", (x, y, .06), (x, y, DECK_Z), .22, .26, "steel")
        box("DD_MezzFoot", (x, y, .11), (.45, .45, .16), "foundation", .018)
beam("DD_MezzBeamFront", (6.3, 2.35, DECK_Z - .12), (12.65, 2.35, DECK_Z - .12),
     .22, .34, "steel", .006)
beam("DD_MezzBeamBack", (6.3, 6.75, DECK_Z - .12), (12.65, 6.75, DECK_Z - .12),
     .22, .34, "steel", .006)
for x in (7.4, 8.6, 9.8, 11.0, 12.2):
    beam("DD_MezzJoist", (x, 2.35, DECK_Z - .15), (x, 6.75, DECK_Z - .15),
         .12, .20, "steel", .004)
box("DD_MezzDeck", (9.48, 4.55, DECK_Z + .02), (6.35, 4.45, .10),
    "metal", .012)
for i in range(18):
    box("DD_MezzGrate", (7.0 + i * .34, 4.55, DECK_Z + .08),
        (.14, 4.35, .018), "rust")
box("DD_MezzToeBoard", (9.48, 2.32, DECK_Z + .24), (6.4, .08, .24), "hard_hat", .008)
# Guard rail around the open edges.
for y in (2.35, 4.6, 6.75):
    beam("DD_MezzRailPost", (6.3, y, DECK_Z), (6.3, y, DECK_Z + 1.10),
         .055, .055, "steel", .004)
for x in (6.3, 8.2, 10.1, 12.0, 12.65):
    beam("DD_MezzRailPost", (x, 2.35, DECK_Z), (x, 2.35, DECK_Z + 1.10),
         .055, .055, "steel", .004)
for z in (DECK_Z + .57, DECK_Z + 1.08):
    beam("DD_MezzRail", (6.3, 2.35, z), (12.65, 2.35, z),
         .055, .055, "steel", .004)
    beam("DD_MezzRail", (6.3, 2.35, z), (6.3, 6.75, z),
         .055, .055, "steel", .004)
# Stair from the floor to the deck.
stair_x = 5.25
stair_bottom_y = .9
stair_top_y = 4.55
stair_width = 1.05
for i in range(16):
    t0 = i / 16.0
    t1 = (i + 1) / 16.0
    y0 = stair_bottom_y + (stair_top_y - stair_bottom_y) * t0
    y1 = stair_bottom_y + (stair_top_y - stair_bottom_y) * t1
    z = DECK_Z * t1
    box("DD_StairTread", (stair_x, (y0 + y1) * .5, z - .035),
        (stair_width, y1 - y0 + .04, .07), "metal", .006)
    if i % 3 == 0:
        box("DD_StairRiser", (stair_x, y0 + .02, z - .16),
            (stair_width, .04, .24), "rust")
for side in (-1, 1):
    x = stair_x + side * (stair_width * .5 + .05)
    beam("DD_StairStringer", (x, stair_bottom_y, .1), (x, stair_top_y, DECK_Z),
         .08, .16, "steel", .004)
    for i in range(6):
        y = stair_bottom_y + (stair_top_y - stair_bottom_y) * i / 5
        z = DECK_Z * (i / 5) + .08
        beam("DD_StairRailPost", (x, y, z), (x, y, z + .9), .045, .045,
             "steel", .003)
    beam("DD_StairHandRail", (x, stair_bottom_y, .98),
         (x, stair_top_y, DECK_Z + .96), .055, .055, "steel", .004)
    beam("DD_StairMidRail", (x, stair_bottom_y, .58),
         (x, stair_top_y, DECK_Z + .56), .045, .045, "steel", .003)
add_collider("mezz_stairs", (stair_x, 2.75, 1.55), (1.32, 3.8, 3.1))
add_collider("mezz_posts_w", (6.3, 4.55, 1.6), (.3, 4.7, 3.2))
# A compact control room, built as a glazed enclosure rather than a solid box.
for x in (10.45, 12.55):
    for y in (5.15, 6.65):
        beam("DD_ControlPost", (x, y, DECK_Z), (x, y, DECK_Z + 2.25),
             .10, .10, "steel", .005)
for y in (5.15, 6.65):
    beam("DD_ControlTop", (10.45, y, DECK_Z + 2.25),
         (12.55, y, DECK_Z + 2.25), .10, .10, "steel", .005)
for xa, xb in ((10.45, 11.15), (11.15, 11.85), (11.85, 12.55)):
    box("DD_ControlGlass", ((xa + xb) * .5, 5.15, DECK_Z + 1.12),
        (xb - xa - .06, .035, 2.1), "glass")
box("DD_ControlDoor", (11.5, 6.65, DECK_Z + 1.05), (.82, .06, 2.05),
    "glass", .01)
box("DD_ControlDoorFrame", (11.5, 6.63, DECK_Z + 2.06), (.94, .10, .08), "steel")
# Desk, chair, console, files and fan inside the control room.
box("DD_ControlDeskTop", (11.5, 5.8, DECK_Z + .77), (1.85, .75, .07),
    "old_wood", .012)
for x in (10.75, 12.25):
    box("DD_ControlDeskLeg", (x, 5.8, DECK_Z + .38), (.08, .62, .74),
        "steel", .005)
box("DD_ControlMonitor", (11.25, 5.55, DECK_Z + 1.15), (.62, .42, .48),
    "roof", .018)
box("DD_ControlScreen", (11.25, 5.32, DECK_Z + 1.15), (.48, .03, .34), "glass")
box("DD_ControlKeyboard", (11.75, 5.55, DECK_Z + .84), (.62, .24, .04),
    "rust", .006)
box("DD_ControlPaper", (10.9, 5.9, DECK_Z + .83), (.34, .26, .008), "cream")
cylinder("DD_ControlMug", (12.05, 5.95, DECK_Z + .92), .07, .13, "ceramic",
         axis="Z", vertices=12)
torus("DD_ControlMugHandle", (12.15, 5.95, DECK_Z + .94), .055, .014,
      "ceramic", axis="Y", major_segments=10, minor_segments=4)
box("DD_ControlCabinet", (10.85, 6.42, DECK_Z + .55), (.65, .44, 1.1),
    "painted_metal", .018)
for z in (DECK_Z + .25, DECK_Z + .52, DECK_Z + .79):
    box("DD_ControlDrawer", (10.85, 6.18, z), (.55, .035, .20), "steel")
    box("DD_ControlDrawerHandle", (10.85, 6.15, z), (.22, .02, .025), "metal")
# Console along the railing.
box("DD_ControlConsole", (8.5, 2.62, DECK_Z + .55), (2.7, .62, .90),
    "painted_metal", .025)
box("DD_ControlConsoleTop", (8.5, 2.62, DECK_Z + 1.03), (2.9, .7, .12),
    "roof", .02)
for i in range(7):
    cylinder("DD_ConsoleButton", (7.55 + i * .28, 2.32, DECK_Z + 1.11),
             .035, .025, "signal_red" if i % 3 == 0 else "hard_hat",
             axis="Y", vertices=10)
for i in range(2):
    box("DD_ConsoleGauge", (8.0 + i * .95, 2.31, DECK_Z + 1.16),
        (.22, .03, .13), "cream")
text_sign("DD_ControlLabel", "LINE 03 / PRESS", (8.5, 2.55, DECK_Z + .68),
          .12, "cream")
# Wall-mounted electrical cabinets and cable tray at floor level.
for x in (3.8, 5.1):
    box("DD_ElectricalCabinet", (x, -7.65, 1.55), (.82, .30, 1.75),
        "painted_metal", .018)
    box("DD_ElectricalDoor", (x - .05, -7.83, 1.55), (.65, .035, 1.58),
        "roof", .008)
    box("DD_ElectricalLabel", (x - .05, -7.86, 2.18), (.42, .015, .16),
        "hard_hat")
    for j in range(3):
        cylinder("DD_ElectricalDial", (x - .18 + j * .24, -7.86, 1.72),
                 .035, .012, "crack", axis="Y", vertices=10)
cylinder_between("DD_Conduit", (3.8, -7.60, 2.45), (5.1, -7.60, 2.45),
                 .035, "metal", vertices=8)
for x in (3.8, 5.1):
    cylinder_between("DD_ConduitDrop", (x, -7.60, 2.45), (x, -7.60, .08),
                     .035, "metal", vertices=8)


# ---------------------------------------------------------------------------
# 400-ton stamping press
stage("press")
# ---------------------------------------------------------------------------
press_x, press_y = -9.35, 1.35
box("DD_PressBase", (press_x, press_y, .38), (3.65, 2.75, .52), "roof", .035)
box("DD_PressBed", (press_x, press_y + .15, .80), (2.55, 1.80, .38), "steel", .025)
for side in (-1, 1):
    box("DD_PressUpright", (press_x + side * 1.32, press_y + .55, 1.92),
        (.45, .95, 2.35), "roof", .025)
    for z in (.82, 1.85, 2.82):
        for y in (press_y + .16, press_y + .92):
            bolt("DD_PressUprightBolt", (press_x + side * 1.53, y, z),
                 (side, 0, 0), .022, .035)
box("DD_PressCrown", (press_x, press_y + .55, 3.14), (3.5, 1.15, .66),
    "roof", .03)
for side in (-1, 1):
    box("DD_PressCrownCap", (press_x + side * 1.55, press_y + .55, 3.14),
        (.12, 1.28, .76), "rust", .01)
for side in (-1, 1):
    cylinder_between("DD_PressGuide", (press_x + side * .68, press_y + .12, 1.0),
                     (press_x + side * .68, press_y + .12, 3.0),
                     .075, "metal", vertices=12)
box("DD_PressRam", (press_x, press_y + .16, 1.92), (1.45, 1.0, 1.10),
    "steel", .022)
box("DD_PressRamStripe", (press_x, press_y - .37, 1.92), (1.25, .03, .20),
    "hard_hat")
box("DD_PressUpperDie", (press_x, press_y + .10, 1.34), (1.15, .82, .28),
    "rust", .015)
box("DD_PressLowerDie", (press_x, press_y + .10, 1.00), (1.28, .92, .22),
    "steel", .012)
for i in range(5):
    box("DD_PressDieRib", (press_x - .48 + i * .24, press_y - .28, 1.06),
        (.07, .05, .16), "rust")
# Flywheel, spokes and belt guard at the rear.
flywheel_y = press_y + 1.62
cylinder("DD_PressFlywheel", (press_x, flywheel_y, 2.38), .82, .20, "rust",
         axis="Y", vertices=24)
cylinder("DD_PressFlywheelHub", (press_x, flywheel_y - .13, 2.38), .20, .30,
         "steel", axis="Y", vertices=14)
for i in range(8):
    angle = math.tau * i / 8
    a = (press_x + math.cos(angle) * .22, flywheel_y - .03,
         2.38 + math.sin(angle) * .22)
    b = (press_x + math.cos(angle) * .68, flywheel_y - .03,
         2.38 + math.sin(angle) * .68)
    beam("DD_PressFlywheelSpoke", a, b, .09, .07, "rust", .004)
for i in range(16):
    angle = math.tau * i / 16
    cylinder("DD_FlywheelRivet", (press_x + math.cos(angle) * .72,
             flywheel_y - .12, 2.38 + math.sin(angle) * .72), .030, .035,
             "steel", axis="Y", vertices=6)
cylinder_between("DD_PressMotor", (press_x + 1.92, flywheel_y, 1.72),
                 (press_x + 2.82, flywheel_y, 1.72), .38, "roof", vertices=16)
for i in range(3):
    box("DD_MotorFin", (press_x + 2.08 + i * .18, flywheel_y - .37, 1.72),
        (.06, .04, .60), "rust")
cylinder_between("DD_PressBeltGuard", (press_x + 1.75, flywheel_y - .05, 1.92),
                 (press_x + 1.75, flywheel_y - .05, 2.35), .30, "roof", vertices=12)
for i in range(4):
    box("DD_BeltGuardRib", (press_x + 1.61, flywheel_y - .05, 1.96 + i * .11),
        (.04, .18, .035), "steel")
# Control pedestal, gauges, foot pedal and safety gate.
box("DD_PressControl", (press_x + 1.90, press_y - .78, 1.18), (.46, .42, 1.45),
    "painted_metal", .02)
box("DD_PressControlFace", (press_x + 1.90, press_y - 1.00, 1.45),
    (.38, .04, .50), "roof", .01)
for i in range(3):
    cylinder("DD_PressButton", (press_x + 1.78 + i * .12, press_y - 1.03, 1.58),
             .032, .035, "signal_red" if i == 0 else "hard_hat",
             axis="Y", vertices=10)
cylinder("DD_PressGauge", (press_x + 1.90, press_y - 1.03, 1.30), .10, .025,
         "cream", axis="Y", vertices=16)
box("DD_PressPedal", (press_x - .35, press_y - 1.00, .20), (.45, .28, .12),
    "hard_hat", .02)
for side in (-1, 1):
    cylinder_between("DD_PressGatePost", (press_x + side * .95, press_y - .85, .08),
                     (press_x + side * .95, press_y - .85, 2.15),
                     .045, "hard_hat", vertices=8)
for i in range(4):
    cylinder_between("DD_PressGateBar", (press_x - .95, press_y - .85, .55 + i * .42),
                     (press_x + .95, press_y - .85, .55 + i * .42),
                     .025, "hard_hat", vertices=6)
# Machine plate and a crush-hazard placard on a stand.
box("DD_PressPlate", (press_x, press_y - 1.04, .70), (.92, .035, .28), "cream")
text_sign("DD_PressPlateText", "PRESS 03  /  400 T", (press_x, press_y - 1.07, .72),
          .10, "crack")
for side in (-1, 1):
    cylinder_between("DD_PressSignPost", (press_x + 2.6 + side * .42, press_y - 1.15, .06),
                     (press_x + 2.6 + side * .42, press_y - 1.15, 1.42),
                     .035, "steel", vertices=6)
box("DD_PressSignBoard", (press_x + 2.6, press_y - 1.15, 1.32), (1.0, .05, .52),
    "hard_hat", .012)
text_sign("DD_PressSignText", "CRUSH\nHAZARD", (press_x + 2.6, press_y - 1.20, 1.33),
          .16, "crack")
# Small oil can and a stack of blanks.
cylinder("DD_OilCan", (press_x - 1.95, press_y - 1.05, .16), .10, .28, "signal_red",
         axis="Z", vertices=12)
for i in range(8):
    box("DD_PressBlank", (press_x - 1.75, press_y + 1.10, .12 + i * .035),
        (.65, .45, .032), "metal")
add_collider("press", (press_x, press_y, 1.6), (4.2, 2.9, 3.2))

# ---------------------------------------------------------------------------
# Engine lathe and workbench
stage("lathe")
# ---------------------------------------------------------------------------
lathe_x, lathe_y = -5.35, -4.45
box("DD_LatheBed", (lathe_x, lathe_y, .82), (3.25, .52, .22), "roof", .018)
box("DD_LatheChipTray", (lathe_x, lathe_y - .55, .62), (3.45, .55, .12), "rust", .012)
for x in (lathe_x - 1.23, lathe_x + 1.23):
    box("DD_LatheLeg", (x, lathe_y, .38), (.26, .70, .66), "roof", .015)
    box("DD_LatheFoot", (x, lathe_y, .10), (.42, .85, .16), "foundation", .012)
box("DD_LatheHeadstock", (lathe_x - 1.08, lathe_y, 1.13), (.85, .62, .65),
    "painted_metal", .025)
cylinder("DD_LatheChuck", (lathe_x - 1.53, lathe_y, 1.14), .34, .18, "steel",
         axis="X", vertices=20)
for i in range(3):
    angle = i * math.tau / 3
    box("DD_LatheJaw", (lathe_x - 1.64, lathe_y + math.cos(angle) * .22,
                        1.14 + math.sin(angle) * .22), (.10, .13, .13),
        "metal", .006).rotation_euler.x = angle
cylinder("DD_LatheSpindle", (lathe_x - 1.72, lathe_y, 1.14), .10, .16, "steel",
         axis="X", vertices=14)
box("DD_LatheTailstock", (lathe_x + 1.06, lathe_y, 1.10), (.48, .48, .48),
    "painted_metal", .02)
cylinder("DD_LatheQuill", (lathe_x + .78, lathe_y, 1.12), .055, .38, "metal",
         axis="X", vertices=10)
torus("DD_LatheHandwheelTail", (lathe_x + 1.37, lathe_y, 1.10), .17, .028,
      "steel", axis="X", major_segments=14, minor_segments=4)
box("DD_LatheCarriage", (lathe_x + .20, lathe_y - .24, 1.08), (.64, .50, .26),
    "rust", .015)
box("DD_LatheToolPost", (lathe_x + .20, lathe_y - .36, 1.27), (.28, .22, .16),
    "steel", .01)
box("DD_LatheTool", (lathe_x + .20, lathe_y - .51, 1.31), (.10, .18, .035),
    "metal")
cylinder_between("DD_LatheLeadScrew", (lathe_x - 1.45, lathe_y - .36, .88),
                 (lathe_x + 1.40, lathe_y - .36, .88), .030, "steel", vertices=8)
cylinder_between("DD_LatheFeedRod", (lathe_x - 1.45, lathe_y - .44, .96),
                 (lathe_x + 1.40, lathe_y - .44, .96), .018, "metal", vertices=6)
torus("DD_LatheHandwheel", (lathe_x - 1.80, lathe_y - .36, .88), .16, .026,
      "steel", axis="X", major_segments=14, minor_segments=4)
for i in range(3):
    box("DD_LatheLever", (lathe_x - .68 + i * .18, lathe_y - .36, 1.23),
        (.035, .18, .26), "hard_hat", .004)
box("DD_LatheControlPlate", (lathe_x - .64, lathe_y - .54, 1.20),
    (.55, .04, .22), "cream", .006)
for i in range(3):
    cylinder("DD_LatheButton", (lathe_x - .84 + i * .16, lathe_y - .57, 1.22),
             .025, .025, "signal_red" if i == 0 else "hard_hat",
             axis="Y", vertices=8)
box("DD_LatheTray", (lathe_x + 1.15, lathe_y - .55, .86), (.55, .35, .06), "steel")
for i in range(4):
    cylinder("DD_LatheChip", (lathe_x + .90 + i * .12, lathe_y - .52, .91),
             .035, .012, "metal", axis="Z", vertices=5)
add_collider("lathe", (lathe_x, lathe_y, .75), (3.6, 1.35, 1.5))

# Workbench, vise, tools and pegboard on the south wall.
bench_x, bench_y = -3.55, -7.15
box("DD_BenchTop", (bench_x, bench_y, .79), (3.35, .72, .09), "old_wood", .012)
for x in (-4.95, -2.15):
    box("DD_BenchLeg", (x, bench_y, .39), (.12, .56, .78), "steel", .008)
box("DD_BenchShelf", (bench_x, bench_y, .23), (3.15, .60, .06), "old_wood", .008)
box("DD_BenchVise", (-2.55, bench_y - .18, .94), (.36, .30, .24), "rust", .02)
cylinder_between("DD_BenchViseJaw", (-2.72, bench_y - .30, 1.02),
                 (-2.38, bench_y - .30, 1.02), .045, "metal", vertices=8)
cylinder_between("DD_BenchViseHandle", (-2.55, bench_y - .35, 1.02),
                 (-2.55, bench_y - .35, 1.22), .025, "steel", vertices=8)
for i in range(3):
    box("DD_BenchDrawer", (-3.65 + i * .55, bench_y - .38, .55),
        (.45, .04, .18), "rust", .004)
    box("DD_BenchHandle", (-3.65 + i * .55, bench_y - .41, .55),
        (.18, .02, .025), "steel")
# Pegboard, wrench silhouettes, Hammer and a clamp.
box("DD_Pegboard", (bench_x, -7.57, 1.72), (3.4, .06, 1.10), "old_wood", .008)
for i in range(5):
    x = bench_x - 1.2 + i * .58
    box("DD_Wrench", (x, -7.63, 1.72 + (i % 2) * .18), (.07, .02, .42),
        "metal", .006)
    box("DD_WrenchJaw", (x, -7.63, 1.72 + (i % 2) * .18 + .24), (.18, .02, .08),
        "metal", .012)
for i in range(3):
    cylinder("DD_BenchCan", (bench_x - .9 + i * .55, bench_y + .08, .97),
             .075, .22, "rust", axis="Z", vertices=10)
    cylinder("DD_BenchCanLid", (bench_x - .9 + i * .55, bench_y + .08, 1.09),
             .08, .03, "steel", axis="Z", vertices=10)
box("DD_BenchRadio", (bench_x + 1.30, bench_y, 1.02), (.34, .23, .28),
    "roof", .012)
for i in range(3):
    box("DD_BenchRadioSlot", (bench_x + 1.30, bench_y - .12, .96 + i * .05),
        (.20, .02, .018), "crack")
box("DD_BenchPaper", (bench_x + .55, bench_y - .05, .845), (.38, .28, .01), "cream")
text_sign("DD_BenchNote", "NIGHT SHIFT\nM. VOSS", (bench_x + .55, bench_y - .20, .842),
          .045, "crack", rotation=(0, 0, 0))
# Safety board over the bench.
box("DD_BenchBoard", (bench_x + 1.62, -7.58, 2.28), (1.0, .05, .68),
    "hard_hat", .012)
text_sign("DD_BenchBoardText", "LOCK OUT\nBEFORE REPAIR", (bench_x + 1.62, -7.62, 2.29),
          .10, "crack")

# ---------------------------------------------------------------------------
# Roller conveyor and material handling
stage("conveyor")
# ---------------------------------------------------------------------------
conv_y = -1.85
box("DD_ConveyorBelt", (.75, conv_y, .93), (9.4, .66, .11), "rubber", .03)
for side in (-1, 1):
    beam("DD_ConveyorSide", (-3.95, conv_y + side * .38, 1.02),
         (5.45, conv_y + side * .38, 1.02), .10, .16, "steel", .004)
    beam("DD_ConveyorSideLower", (-3.95, conv_y + side * .38, .42),
         (5.45, conv_y + side * .38, .42), .09, .12, "rust", .004)
for i in range(24):
    x = -3.75 + i * .39
    cylinder("DD_ConveyorRoller", (x, conv_y, .97), .095, .58, "metal",
             axis="Y", vertices=10)
for i in range(5):
    x = -3.55 + i * 2.25
    for side in (-1, 1):
        beam("DD_ConveyorLeg", (x, conv_y + side * .34, .08),
             (x, conv_y + side * .34, .90), .09, .09, "steel", .004)
    beam("DD_ConveyorCross", (x, conv_y - .34, .30), (x, conv_y + .34, .30),
         .07, .07, "steel", .003)
    beam("DD_ConveyorBrace", (x, conv_y - .34, .16), (x, conv_y + .34, .68),
         .045, .045, "steel", .002)
cylinder_between("DD_ConveyorDrive", (5.55, conv_y, .82), (6.15, conv_y, .82),
                 .24, "roof", vertices=14)
box("DD_ConveyorMotor", (6.35, conv_y, .75), (.55, .50, .55), "roof", .02)
for i in range(4):
    box("DD_ConveyorMotorFin", (6.50 + i * .07, conv_y, .75), (.03, .60, .40),
        "rust")
for i in range(3):
    box("DD_ConveyorCrate", (-2.55 + i * 2.35, conv_y, 1.28), (.72, .58, .48),
        "old_wood", .012)
    box("DD_ConveyorCrateBand", (-2.55 + i * 2.35, conv_y, 1.28), (.75, .61, .05),
        "rust")
add_collider("conveyor", (.75, conv_y, .72), (9.8, 1.0, 1.4))


# ---------------------------------------------------------------------------
# Forklift, compressor, lockers and loose industrial clutter
stage("clutter")
# ---------------------------------------------------------------------------
def pallet(name, at, yaw=0.0, load=None):
    x, y, z = at
    box(name + "_Deck", (x, y, z + .125), (1.15, 1.05, .045), "old_wood", .006)
    for side in (-1, 1):
        for offset in (-.38, 0, .38):
            box(name + "_Block", (x + offset, y + side * .36, z + .06),
                (.18, .18, .12), "old_wood", .006)
    for i in range(5):
        box(name + "_Slat", (x - .46 + i * .23, y, z + .155),
            (.19, 1.04, .025), "light_wood", .004)
    if load:
        for i in range(load):
            box(name + "_Crate", (x, y, z + .40 + i * .55), (.86, .76, .50),
                "old_wood", .015)
            box(name + "_CrateBand", (x, y, z + .40 + i * .55), (.89, .79, .045),
                "rust")


def crate(name, at, size=(.82, .70, .55), material="old_wood"):
    x, y, z = at
    sx, sy, sz = size
    box(name + "_Body", (x, y, z + sz * .5), (sx, sy, sz), material, .012)
    for side in (-1, 1):
        box(name + "_TopBand", (x, y + side * sy * .5, z + sz * .86),
            (sx + .02, .035, .07), "rust")
        box(name + "_BottomBand", (x, y + side * sy * .5, z + .07),
            (sx + .02, .035, .07), "rust")
    for side in (-1, 1):
        box(name + "_Corner", (x + side * sx * .5, y, z + sz * .5),
            (.05, sy + .02, sz + .02), "rust")
    text_sign(name + "_Mark", "H-7", (x, y - sy * .5 - .015, z + sz * .58),
              .16, "crack")


def barrel(name, at, material="rust", tipped=False):
    x, y, z = at
    if tipped:
        cylinder(name + "_Body", (x, y, z + .28), .28, .86, material,
                 axis="X", vertices=16)
        for offset in (-.28, .28):
            torus(name + "_Ring", (x + offset, y, z + .28), .29, .025,
                  "steel", axis="X", major_segments=14, minor_segments=4)
    else:
        cylinder(name + "_Body", (x, y, z + .44), .28, .88, material,
                 axis="Z", vertices=16)
        for h in (.12, .44, .76):
            torus(name + "_Ring", (x, y, z + h), .29, .025, "steel",
                  axis="Z", major_segments=14, minor_segments=4)
        cylinder(name + "_Lid", (x, y, z + .89), .285, .035, "steel",
                 axis="Z", vertices=16)
        cylinder(name + "_Bung", (x + .13, y, z + .91), .045, .02, "rust",
                 axis="Z", vertices=8)
        box(name + "_Label", (x, y - .29, z + .55), (.30, .02, .22),
            "cream")


def cable_spool(name, at, radius=.65, width=.62, yaw=0.0):
    x, y, z = at
    for side in (-1, 1):
        cylinder(name + "_Flange", (x, y + side * width * .5, z + radius),
                 radius, .08, "old_wood", axis="Y", vertices=24)
        for i in range(6):
            angle = math.tau * i / 6
            box(name + "_FlangeRib",
                (x + math.cos(angle) * radius * .52,
                 y + side * (width * .5 + .045),
                 z + radius + math.sin(angle) * radius * .52),
                (.08, .03, radius * .72), "old_wood", .004)
    cylinder(name + "_Core", (x, y, z + radius), .30, width, "metal",
             axis="Y", vertices=16)
    for i in range(3):
        torus(name + "_Cable", (x, y, z + radius + .3),
              .48 - i * .025, .055, "rubber", axis="Y",
              major_segments=20, minor_segments=5)


fork_x, fork_y = 4.55, 3.4
box("DD_ForkliftCounterweight", (fork_x, fork_y + .60, .63), (1.22, .80, .72),
    "rust", .035)
box("DD_ForkliftBody", (fork_x, fork_y - .10, .66), (1.18, 1.30, .66),
    "roof", .03)
box("DD_ForkliftHood", (fork_x, fork_y + .34, .96), (1.03, .72, .42),
    "roof", .025)
for side in (-1, 1):
    cylinder("DD_ForkliftWheel", (fork_x + side * .66, fork_y - .44, .38),
             .32, .22, "rubber", axis="X", vertices=16)
    cylinder("DD_ForkliftHub", (fork_x + side * .78, fork_y - .44, .38),
             .13, .035, "metal", axis="X", vertices=12)
    cylinder("DD_ForkliftWheel", (fork_x + side * .66, fork_y + .52, .40),
             .34, .24, "rubber", axis="X", vertices=16)
    cylinder("DD_ForkliftHub", (fork_x + side * .79, fork_y + .52, .40),
             .14, .035, "metal", axis="X", vertices=12)
    beam("DD_ForkliftMast", (fork_x + side * .34, fork_y - .92, .15),
         (fork_x + side * .34, fork_y - .92, 2.72), .12, .16, "rust", .006)
    beam("DD_ForkliftGuardPost", (fork_x + side * .52, fork_y + .42, 1.04),
         (fork_x + side * .52, fork_y + .42, 2.18), .07, .07, "steel", .004)
    beam("DD_ForkliftGuardPost", (fork_x + side * .52, fork_y - .52, 1.04),
         (fork_x + side * .52, fork_y - .52, 2.18), .07, .07, "steel", .004)
    box("DD_ForkliftFork", (fork_x + side * .32, fork_y - 1.65, .13),
        (.18, 1.45, .055), "steel", .01)
    beam("DD_ForkliftForks", (fork_x + side * .32, fork_y - .90, .18),
         (fork_x + side * .32, fork_y - .90, .74), .18, .10, "steel", .006)
for z in (1.95, 2.28):
    beam("DD_ForkliftGuardRail", (fork_x - .56, fork_y - .54, z),
         (fork_x - .56, fork_y + .44, z), .055, .055, "steel")
    beam("DD_ForkliftGuardRail", (fork_x + .56, fork_y - .54, z),
         (fork_x + .56, fork_y + .44, z), .055, .055, "steel")
    beam("DD_ForkliftGuardRail", (fork_x - .56, fork_y + .44, z),
         (fork_x + .56, fork_y + .44, z), .055, .055, "steel")
    beam("DD_ForkliftGuardRail", (fork_x - .56, fork_y - .54, z),
         (fork_x + .56, fork_y - .54, z), .055, .055, "steel")
box("DD_ForkliftSeat", (fork_x, fork_y + .25, 1.18), (.58, .50, .16),
    "rubber", .03)
box("DD_ForkliftSeatBack", (fork_x, fork_y + .47, 1.45), (.58, .12, .55),
    "rubber", .025)
cylinder_between("DD_ForkliftSteering", (fork_x, fork_y - .30, 1.30),
                 (fork_x, fork_y - .18, 1.57), .035, "steel", vertices=8)
torus("DD_ForkliftWheelSteer", (fork_x, fork_y - .30, 1.32), .15, .022,
      "rubber", axis="Y", major_segments=12, minor_segments=4)
cylinder("DD_ForkliftTank", (fork_x, fork_y + .83, 1.30), .22, .82,
         "metal", axis="Y", vertices=14)
for i in range(4):
    box("DD_ForkliftMastCross", (fork_x - .34 + i * .23, fork_y - .95, 1.16),
        (.05, .10, .80), "rust")
add_collider("forklift", (fork_x, fork_y, 1.0), (1.6, 2.8, 2.0))

# Compressor: horizontal receiver, motor, belt guard, valves and gauges.
comp_x, comp_y = 8.6, -5.15
cylinder("DD_CompressorTank", (comp_x, comp_y, 1.02), .48, 2.15, "roof",
         axis="X", vertices=20)
for x in (comp_x - .82, comp_x + .82):
    cylinder("DD_CompressorTankBand", (x, comp_y, 1.02), .52, .06, "rust",
             axis="X", vertices=20)
    box("DD_CompressorLeg", (x, comp_y, .35), (.18, .72, .70), "steel", .012)
box("DD_CompressorMotor", (comp_x, comp_y + .60, .88), (.82, .55, .58),
    "roof", .02)
for i in range(5):
    box("DD_CompressorFin", (comp_x - .30 + i * .15, comp_y + .90, .88),
        (.04, .05, .46), "rust")
cylinder_between("DD_CompressorBeltA", (comp_x - .35, comp_y + .60, .95),
                 (comp_x - .35, comp_y + .02, 1.15), .045, "rubber", vertices=8)
cylinder_between("DD_CompressorBeltB", (comp_x + .18, comp_y + .60, .95),
                 (comp_x + .18, comp_y + .02, 1.16), .045, "rubber", vertices=8)
box("DD_CompressorGuard", (comp_x - .05, comp_y + .30, .96),
    (1.05, .12, .58), "rust", .02)
for i in range(3):
    box("DD_CompressorGuardRib", (comp_x - .35 + i * .32, comp_y + .22, .96),
        (.04, .04, .48), "steel")
cylinder("DD_CompressorGauge", (comp_x + 1.02, comp_y, 1.34), .13, .05,
         "cream", axis="X", vertices=16)
cylinder_between("DD_CompressorPipe", (comp_x + 1.08, comp_y, 1.02),
                 (comp_x + 1.08, comp_y, 2.25), .055, "rust", vertices=8)
cylinder_between("DD_CompressorPipe", (comp_x + 1.08, comp_y, 2.25),
                 (comp_x + 1.08, comp_y + .60, 2.25), .055, "rust", vertices=8)
torus("DD_CompressorValve", (comp_x + 1.08, comp_y + .60, 2.28), .16, .026,
      "signal_red", axis="Z", major_segments=12, minor_segments=4)
box("DD_CompressorTag", (comp_x - .45, comp_y - .50, 1.02), (.52, .02, .28),
    "hard_hat")
add_collider("compressor", (comp_x, comp_y, 1.0), (2.8, 1.6, 2.0))

# Lockers.
for i in range(3):
    x = .35 + i * .82
    box("DD_Locker", (x, -7.53, 1.00), (.77, .52, 1.92), "painted_metal", .018)
    box("DD_LockerDoor", (x, -7.81, 1.01), (.67, .035, 1.78), "roof", .008)
    for slot in range(4):
        box("DD_LockerVent", (x, -7.84, 1.58 + slot * .055),
            (.35, .015, .022), "crack")
    box("DD_LockerHandle", (x + .24, -7.86, 1.00), (.035, .02, .16), "steel")
    box("DD_LockerLabel", (x, -7.85, 1.82), (.22, .015, .08), "cream")

# Storage rack with steel stock and pipe.
rack_x = -11.75
for y in (3.0, 5.0, 6.9):
    ibeam("DD_RackPost", (rack_x, y, .05), (rack_x, y, 3.0), .16, .20, "rust")
for z in (.45, 1.55, 2.65):
    beam("DD_RackBeam", (rack_x, 2.95, z), (rack_x, 6.95, z),
         .14, .20, "rust", .006)
for side in (-1, 1):
    beam("DD_RackBrace", (rack_x + side * .25, 3.0, .2),
         (rack_x + side * .25, 5.0, 2.9), .05, .05, "steel", .003)
for i in range(5):
    cylinder_between("DD_StockPipe", (rack_x, 3.1 + i * .17, 1.74),
                     (rack_x, 6.8 - i * .05, 1.74), .085, "metal", vertices=10)
for i in range(4):
    box("DD_StockSheet", (rack_x, 4.4 + i * .03, 2.78),
        (.18, 3.0, .06), "rust", .008)
add_collider("stock_rack", (rack_x + .1, 4.8, 1.5), (.8, 4.1, 3.0))

# Pallets, crates, drums, spools and scrap.
pallet("DD_PalletA", (-11.7, -6.7, .06), load=2)
crate("DD_CrateA", (-10.15, -6.9, .06), (.95, .8, .62))
crate("DD_CrateB", (-10.15, -6.9, .68), (.80, .7, .48))
pallet("DD_PalletB", (.05, 5.6, .06))
for i in range(3):
    crate("DD_CrateC", (1.4 + i * .05, 5.6, .18 + i * .47),
          (.80, .72, .44))
for x, y in [(-7.3, 6.1), (-6.6, 6.25), (-7.0, 5.5), (8.4, 6.2), (9.0, 5.8)]:
    barrel("DD_Barrel", (x, y, .06), "rust" if int(x * 10) % 2 else "signal_red")
barrel("DD_BarrelTipped", (10.9, 6.0, .28), "rust", tipped=True)
cable_spool("DD_CableSpool", (-10.9, 1.0, .06))
cable_spool("DD_CableSpoolSmall", (9.6, 3.65, .06), .45, .42)
# Scrap pile near the press: bent plate, rods, chain and concrete rubble.
for i in range(13):
    angle = i * 1.73
    x = -6.8 + math.cos(angle) * (1.2 + (i % 3) * .25)
    y = 5.35 + math.sin(angle) * (.6 + (i % 4) * .15)
    box("DD_ScrapPlate", (x, y, .10 + (i % 3) * .07),
        (.55 + (i % 3) * .2, .35, .035), "rust", .006).rotation_euler.z = angle
for i in range(8):
    cylinder_between("DD_ScrapRod", (-7.8 + i * .24, 4.9, .18),
                     (-7.2 + i * .31, 5.35 + i * .05, .22), .025, "metal", vertices=6)
for i in range(9):
    ico("DD_Rubble", (random.uniform(-12.8, 12.8), random.uniform(-7.8, 6.8), .12),
        random.uniform(.08, .22), "foundation", (1, 1, .65))
# Fire point, extinguisher and spill kit.
box("DD_ExtinguisherCabinet", (5.45, -7.62, 1.18), (.55, .28, .92),
    "signal_red", .018)
box("DD_ExtinguisherDoor", (5.45, -7.78, 1.18), (.44, .03, .78), "cream", .006)
text_sign("DD_ExtinguisherLabel", "FIRE", (5.45, -7.81, 1.42), .12, "signal_red")
for i in range(3):
    box("DD_SandBucket", (6.1 + i * .34, -7.62, .18), (.24, .24, .30),
        "signal_red", .015)
    cylinder("DD_BucketHandle", (6.1 + i * .34, -7.45, .34), .12, .015,
             "steel", axis="X", vertices=8)
# Loose hoses and an extension lead.
for i in range(16):
    x = -1.9 + i * .46
    y = 5.9 + math.sin(i * .8) * .16
    box("DD_AirHose", (x, y, .085), (.45, .055, .035), "rubber", .008)
for i in range(12):
    x = -9.3 + i * .53
    y = -.35 + math.sin(i * .65) * .24
    box("DD_ExtensionLead", (x, y, .083), (.52, .035, .022), "rubber", .006)
# A mobile tool chest.
box("DD_ToolChest", (-1.85, 3.9, .58), (.82, .52, 1.08), "signal_red", .025)
for i in range(4):
    box("DD_ToolDrawer", (-1.85, 3.64, .30 + i * .22), (.72, .03, .17),
        "rust", .004)
    box("DD_ToolHandle", (-1.85, 3.61, .30 + i * .22), (.25, .02, .025), "steel")
for side in (-1, 1):
    cylinder("DD_ToolChestWheel", (-1.85 + side * .29, 4.2, .10), .08, .05,
             "rubber", axis="X", vertices=10)
add_collider("tool_chest", (-1.85, 3.9, .55), (.9, .6, 1.1))
add_collider("pallet_a", (-11.7, -6.7, .75), (1.3, 1.2, 1.5))
add_collider("crate_a", (-10.15, -6.9, .8), (1.0, .85, 1.6))
add_collider("storage_crates", (.7, 5.6, .8), (2.7, 1.0, 1.7))
add_collider("barrels", (-7.0, 6.0, .45), (2.2, 1.2, .95))
add_collider("barrels_east", (8.7, 6.0, .45), (1.8, 1.2, .95))
add_collider("cable_spool", (-10.9, 1.0, .62), (1.4, .85, 1.35))

# Facade sign over the loading side.
set_group("DD_Factory_Wall_South")
for x in (-5.1, 6.3):
    beam("DD_FacadeSignBracket", (x, -8.52, 5.05), (x, -9.25, 5.05),
         .10, .12, "steel", .006)
box("DD_FacadeSignBoard", (.6, -9.34, 5.55), (11.6, .12, 1.52), "crack", .02)
box("DD_FacadeSignBorder", (.6, -9.42, 5.55), (11.2, .035, 1.18), "rust", .008)
text_sign("DD_FacadeSign", "HALVORSEN", (.3, -9.50, 5.72), 1.0, "hard_hat")
text_sign("DD_FacadeSignSub", "IRONWORKS  /  BAY 03", (.3, -9.49, 5.08),
          .32, "cream")
box("DD_FacadeLampArm", (-5.1, -9.0, 4.98), (.10, 1.0, .08), "steel")
cylinder("DD_FacadeLampHousing", (-5.1, -9.48, 4.90), .18, .12, "rust",
         axis="Z", vertices=12)
cylinder("DD_FacadeLampLens", (-5.1, -9.48, 4.82), .14, .03, "lamp_glow",
         axis="Z", vertices=12)

# Graffiti / stencil on the surviving east pier.
box("DD_StencilBoard", (11.95, -8.55, 2.92), (1.35, .03, .54), "rust", .005)
text_sign("DD_StencilText", "SECTOR 7", (11.95, -8.58, 2.94), .22, "cream")

# ---------------------------------------------------------------------------
# Boiler annex and its chimney
stage("boiler")
# ---------------------------------------------------------------------------
set_group("DD_Factory_Boiler")
box("DD_BoilerPad", (-16.85, -4.5, -.02), (7.0, 7.4, .16), "foundation", .025)
box("DD_BoilerBody", (-16.85, -4.5, 2.05), (6.45, 6.8, 4.0), "brick", .04)
for x in (-20.0, -13.7):
    for y in (-7.75, -1.25):
        box("DD_BoilerPilaster", (x, y, 2.1), (.45, .45, 4.2), "brick", .02)
# Low pitched roof, ridge along Y.
for side in (-1, 1):
    box("DD_BoilerRoofSlope", (-16.85 + side * 1.70, -4.5, 4.52),
        (3.55, 7.2, .18), "roof", .025).rotation_euler.y = side * .34
box("DD_BoilerRidge", (-16.85, -4.5, 5.08), (.16, 7.25, .18), "rust", .006)
box("DD_BoilerDoor", (-16.85, -7.93, 1.12), (1.65, .10, 2.10), "roof", .02)
box("DD_BoilerDoorFrame", (-16.85, -7.88, 2.20), (1.90, .15, .14), "steel", .008)
for z in (.55, 1.10, 1.65):
    box("DD_BoilerDoorBrace", (-16.85, -8.01, z), (1.50, .035, .08), "rust")
box("DD_BoilerDoorBeam", (-16.85, -8.01, 1.10), (.10, .035, 2.0), "rust")
for x in (-19.15, -14.55):
    box("DD_BoilerWindow", (x, -7.94, 2.80), (1.15, .04, .90), "glass")
    for z in (2.35, 2.80, 3.25):
        box("DD_BoilerWindowBar", (x, -7.97, z), (1.22, .05, .045), "steel")
    for dx in (-.55, 0, .55):
        box("DD_BoilerWindowBarV", (x + dx, -7.97, 2.80), (.045, .05, .95), "steel")
# Roof vents and steam pipes into the hall.
for x in (-19.1, -14.7):
    cylinder("DD_BoilerVent", (x, -3.0, 5.15), .22, 1.0, "rust", axis="Z",
             vertices=12)
    cylinder("DD_BoilerVentCap", (x, -3.0, 5.72), .34, .12, "metal", axis="Z",
             vertices=12)
for z in (1.2, 1.9):
    cylinder_between("DD_BoilerPipe", (-13.6, -4.5, z), (-12.7, -4.5, z),
                     .15, "rust", vertices=12)
    cylinder_between("DD_BoilerPipeFlange", (-12.95, -4.5, z - .04),
                     (-12.95, -4.5, z + .04), .22, "steel", vertices=12)
# Lean-to fuel shelter.
box("DD_FuelShelter", (-18.3, -.6, 1.55), (3.3, 1.5, .12), "rust", .015)
for x in (-19.8, -16.8):
    beam("DD_FuelShelterPost", (x, -.05, .06), (x, -.05, 2.65),
         .10, .10, "steel", .004)
for i in range(4):
    barrel("DD_FuelDrum", (-19.3 + i * .45, -.6, .06), "signal_red")
# Boiler chimney.
cylinder("DD_BoilerChimney", (-19.7, -2.1, 7.2), .56, 8.2, "stack_brick",
         axis="Z", vertices=20)
for z in (3.2, 5.2, 7.2, 9.2, 11.0):
    torus("DD_BoilerChimneyBand", (-19.7, -2.1, z), .60, .055, "rust",
          axis="Z", major_segments=20, minor_segments=4)
cylinder("DD_BoilerChimneyCap", (-19.7, -2.1, 11.36), .72, .18, "steel",
         axis="Z", vertices=20)
for i in range(4):
    box("DD_BoilerChimneyBrace", (-19.7 + math.cos(i * math.pi * .5) * .76,
                                 -2.1 + math.sin(i * math.pi * .5) * .76, 9.35),
        (.10, .10, 2.4), "steel")
add_collider("boiler_house", (-16.85, -4.5, 2.1), (6.6, 7.0, 4.4))
add_collider("boiler_chimney", (-19.7, -2.1, 6.0), (1.3, 1.3, 11.5))
add_collider("fuel_shelter", (-18.3, -.6, .7), (3.4, 1.8, 1.5))


# ---------------------------------------------------------------------------
# Twin material silos and the elevated pipe bridge
stage("silos")
# ---------------------------------------------------------------------------
set_group("DD_Factory_Silo")


def silo(name, cx, cy, height=9.8):
    # Support skirt.
    for side_x in (-1, 1):
        for side_y in (-1, 1):
            ibeam(name + "_Leg", (cx + side_x * 1.35, cy + side_y * 1.35, .05),
                  (cx + side_x * 1.35, cy + side_y * 1.35, 1.55),
                  .20, .24, "steel")
            box(name + "_Foot", (cx + side_x * 1.35, cy + side_y * 1.35, .10),
                (.48, .48, .18), "foundation", .015)
    for side in (-1, 1):
        beam(name + "_LegBraceX", (cx - 1.35, cy + side * 1.35, .25),
             (cx + 1.35, cy + side * 1.35, 1.35), .10, .10, "steel", .004)
        beam(name + "_LegBraceY", (cx + side * 1.35, cy - 1.35, .25),
             (cx + side * 1.35, cy + 1.35, 1.35), .10, .10, "steel", .004)
    # Inverted discharge cone and barrel.
    bpy.ops.mesh.primitive_cone_add(vertices=28, radius1=.42, radius2=2.10,
                                    depth=1.15, location=(cx, cy, 2.02))
    cone = bpy.context.object
    cone.name = name + "_Hopper"
    cone.data.materials.append(MATS["rust"])
    for polygon in cone.data.polygons:
        if len(polygon.vertices) == 4:
            polygon.use_smooth = True
    put(cone)
    cylinder(name + "_Body", (cx, cy, 2.55 + height * .5), 2.10, height,
             "galvanized", axis="Z", vertices=32)
    for t in (.06, .22, .40, .58, .76, .92):
        z = 2.55 + height * t
        torus(name + "_Band", (cx, cy, z), 2.13, .055, "rust",
              axis="Z", major_segments=28, minor_segments=4)
        for i in range(12):
            angle = math.tau * i / 12 + t * .4
            bolt(name + "_BandBolt",
                 (cx + math.cos(angle) * 2.15, cy + math.sin(angle) * 2.15, z),
                 (math.cos(angle), math.sin(angle), 0), .018, .028)
    # Roof cone, vent and explosion relief.
    bpy.ops.mesh.primitive_cone_add(vertices=32, radius1=2.10, radius2=.28,
                                    depth=1.05,
                                    location=(cx, cy, 2.55 + height + .525))
    roof = bpy.context.object
    roof.name = name + "_Roof"
    roof.data.materials.append(MATS["roof"])
    for polygon in roof.data.polygons:
        if len(polygon.vertices) == 4:
            polygon.use_smooth = True
    put(roof)
    cylinder(name + "_Vent", (cx, cy, 2.55 + height + 1.26), .30, .62,
             "metal", axis="Z", vertices=16)
    cylinder(name + "_VentCap", (cx, cy, 2.55 + height + 1.62), .48, .12,
             "rust", axis="Z", vertices=16)
    # Top service railing.
    for i in range(12):
        angle = math.tau * i / 12
        x = cx + math.cos(angle) * 1.92
        y = cy + math.sin(angle) * 1.92
        z = 2.55 + height + .18
        cylinder_between(name + "_RailPost", (x, y, z), (x, y, z + .95),
                         .035, "steel", vertices=6)
    for z in (2.55 + height + .65, 2.55 + height + 1.08):
        torus(name + "_TopRail", (cx, cy, z), 1.92, .033, "steel",
              axis="Z", major_segments=28, minor_segments=4)
    # Side ladder and cage on the south face.
    ladder_y = cy - 2.22
    for side in (-1, 1):
        cylinder_between(name + "_LadderRail", (cx + side * .28, ladder_y, .55),
                         (cx + side * .28, ladder_y, 2.55 + height + .55),
                         .040, "steel", vertices=8)
    rung_count = int((height + 2.5) / .32)
    for i in range(rung_count):
        z = .72 + i * .32
        cylinder_between(name + "_LadderRung", (cx - .28, ladder_y, z),
                         (cx + .28, ladder_y, z), .022, "steel", vertices=6)
    for i in range(9):
        z = 1.9 + i * (height / 8.8)
        torus(name + "_LadderCage", (cx, cy - 1.92, z), .55, .022,
              "steel", axis="Z", major_segments=16, minor_segments=4)
        for angle in (0.15, 1.05, 2.10, 3.14):
            cylinder_between(name + "_CageBar",
                             (cx + math.cos(angle) * .55, cy - 1.92 + math.sin(angle) * .55, z),
                             (cx + math.cos(angle) * .55, cy - 1.92 + math.sin(angle) * .55, z + 1.3),
                             .018, "steel", vertices=5)
    # Inspection hatch, discharge valve and rust runs.
    box(name + "_Hatch", (cx, cy - 2.16, 4.35), (.78, .08, 1.05), "rust", .015)
    box(name + "_HatchHinge", (cx - .44, cy - 2.21, 4.35), (.08, .07, .30), "steel")
    box(name + "_HatchClamp", (cx + .42, cy - 2.21, 4.35), (.10, .08, .16), "steel")
    cylinder_between(name + "_Discharge", (cx, cy, .20), (cx, cy, 1.55),
                     .16, "rust", vertices=12)
    torus(name + "_DischargeValve", (cx, cy - .01, .88), .23, .04, "signal_red",
          axis="Y", major_segments=14, minor_segments=4)
    for i in range(7):
        angle = -.9 + i * .38
        x = cx + math.cos(angle) * 2.11
        y = cy + math.sin(angle) * 2.11
        h = .8 + (i % 4) * 1.25
        box(name + "_RustStreak", (x, y, 3.0 + h * .5),
            (.8, .035, h), "rust", .003).rotation_euler.z = angle + math.pi * .5
    box(name + "_IDPlate", (cx, cy - 2.17, 3.05), (.64, .03, .26), "cream")
    text_sign(name + "_IDText", "SILO 0" + ("1" if name.endswith("A") else "2"),
              (cx, cy - 2.20, 3.07), .13, "crack")
    add_collider("silo_" + name[-1].lower(), (cx, cy, (height + 5.2) * .5),
                 (4.5, 4.5, height + 5.2))


silo("DD_SiloA", -19.3, 1.15, 9.4)
silo("DD_SiloB", -19.3, 6.05, 8.3)

# Pipe bridge between the silos and the hall.
bridge_y = 3.55
for x in (-17.3, -14.1, -12.9):
    for side in (-1, 1):
        ibeam("DD_BridgeColumn", (x, bridge_y + side * .58, .05),
              (x, bridge_y + side * .58, 5.25), .16, .20, "steel")
        box("DD_BridgeFoot", (x, bridge_y + side * .58, .10), (.38, .38, .16),
            "foundation", .015)
    beam("DD_BridgeCross", (x, bridge_y - .58, .35),
         (x, bridge_y + .58, .35), .08, .08, "steel")
    beam("DD_BridgeBrace", (x, bridge_y - .58, .45),
         (x, bridge_y + .58, 2.2), .05, .05, "steel")
beam("DD_BridgeChordS", (-18.2, bridge_y - .62, 5.26),
     (-12.8, bridge_y - .62, 5.26), .18, .20, "rust", .006)
beam("DD_BridgeChordN", (-18.2, bridge_y + .62, 5.26),
     (-12.8, bridge_y + .62, 5.26), .18, .20, "rust", .006)
box("DD_BridgeDeck", (-15.5, bridge_y, 5.36), (5.45, 1.30, .08), "metal", .008)
for i in range(14):
    x = -18.1 + i * .39
    box("DD_BridgeGrate", (x, bridge_y, 5.41), (.14, 1.22, .025), "rust")
for y in (bridge_y - .63, bridge_y + .63):
    beam("DD_BridgeRail", (-18.15, y, 6.33), (-12.85, y, 6.33),
         .055, .055, "steel", .004)
    for x in (-18.15, -16.5, -14.8, -13.0):
        beam("DD_BridgeRailPost", (x, y, 5.40), (x, y, 6.34), .05, .05,
             "steel", .003)
    beam("DD_BridgeToe", (-18.15, y, 5.48), (-12.85, y, 5.48),
         .04, .14, "steel", .003)
# X bracing beneath the walkway.
for i in range(3):
    x0 = -18.1 + i * 1.75
    x1 = x0 + 1.75
    beam("DD_BridgeX", (x0, bridge_y - .55, 5.18), (x1, bridge_y + .55, 4.45),
         .065, .065, "steel", .003)
    beam("DD_BridgeX", (x0, bridge_y + .55, 5.18), (x1, bridge_y - .55, 4.45),
         .065, .065, "steel", .003)
# Three product lines with flanges, insulation and an expansion loop.
for index, (z, radius, material) in enumerate([(5.72, .17, "rust"),
                                               (5.72, .11, "metal"),
                                               (5.95, .13, "painted_metal")]):
    offset = -.38 + index * .38
    cylinder_between("DD_BridgePipe", (-18.35, bridge_y + offset, z),
                     (-12.55, bridge_y + offset, z), radius, material, vertices=14)
    for x in (-17.9, -16.5, -15.1, -13.7):
        cylinder_between("DD_BridgeFlange", (x, bridge_y + offset, z - .05),
                         (x, bridge_y + offset, z + .05), radius * 1.72,
                         "steel", vertices=14)
        for side in (-1, 1):
            bolt("DD_BridgeFlangeBolt",
                 (x, bridge_y + offset + side * radius * 1.2, z),
                 (0, 0, 1), .014, .025)
    if index == 0:
        # A rectangular expansion loop above the walkway.
        cylinder_between("DD_ExpansionLoop", (-15.5, bridge_y + offset, z),
                         (-15.5, bridge_y + offset, z + 1.0), radius,
                         material, vertices=14)
        cylinder_between("DD_ExpansionLoop", (-15.5, bridge_y + offset, z + 1.0),
                         (-14.6, bridge_y + offset, z + 1.0), radius,
                         material, vertices=14)
        cylinder_between("DD_ExpansionLoop", (-14.6, bridge_y + offset, z + 1.0),
                         (-14.6, bridge_y + offset, z), radius,
                         material, vertices=14)
# Penetration boots where the pipes enter the hall.
for index in range(3):
    offset = -.38 + index * .38
    box("DD_BridgeWallBoot", (-12.6, bridge_y + offset, 5.82),
        (.55, .55, .55), "steel", .015)
    box("DD_BridgeWallPlate", (-12.3, bridge_y + offset, 5.82),
        (.05, .78, .78), "rust", .008)
# Ladder to the bridge.
for side in (-1, 1):
    cylinder_between("DD_BridgeLadderRail", (-14.85 + side * .26, bridge_y - .75, .3),
                     (-14.85 + side * .26, bridge_y - .75, 5.35), .035,
                     "steel", vertices=8)
for i in range(18):
    z = .48 + i * .28
    cylinder_between("DD_BridgeLadderRung", (-15.11, bridge_y - .75, z),
                     (-14.59, bridge_y - .75, z), .020, "steel", vertices=6)
add_collider("bridge_column_a", (-17.3, bridge_y, 2.6), (.5, 1.5, 5.2))
add_collider("bridge_column_b", (-14.1, bridge_y, 2.6), (.5, 1.5, 5.2))


# ---------------------------------------------------------------------------
# Smokestack, water tower and electrical substation
stage("stack")
# ---------------------------------------------------------------------------
set_group("DD_Factory_Stack")
stack_x, stack_y = 19.3, 3.1
box("DD_StackPad", (stack_x, stack_y, .20), (4.5, 4.5, .40), "foundation", .03)
bpy.ops.mesh.primitive_cone_add(vertices=32, radius1=2.05, radius2=1.42,
                                depth=19.0, location=(stack_x, stack_y, 9.7))
stack = bpy.context.object
stack.name = "DD_StackBarrel"
stack.data.materials.append(MATS["stack_brick"])
for polygon in stack.data.polygons:
    if len(polygon.vertices) == 4:
        polygon.use_smooth = True
put(stack)
for z in (1.0, 3.2, 5.4, 7.6, 9.8, 12.0, 14.2, 16.4, 18.3):
    t = z / 19.0
    radius = 2.05 - .63 * t + .05
    torus("DD_StackBand", (stack_x, stack_y, z), radius, .06, "rust",
          axis="Z", major_segments=28, minor_segments=4)
    for i in range(10):
        angle = math.tau * i / 10
        bolt("DD_StackBandBolt",
             (stack_x + math.cos(angle) * (radius + .02),
              stack_y + math.sin(angle) * (radius + .02), z),
             (math.cos(angle), math.sin(angle), 0), .019, .03)
# Corbel and cap.
cylinder("DD_StackCorbel", (stack_x, stack_y, 18.62), 1.63, .28, "brick",
         axis="Z", vertices=32)
cylinder("DD_StackCap", (stack_x, stack_y, 19.35), 1.78, .48, "rust",
         axis="Z", vertices=32)
cylinder("DD_StackMouth", (stack_x, stack_y, 19.62), 1.40, .06, "crack",
         axis="Z", vertices=32)
cylinder_between("DD_StackRod", (stack_x, stack_y, 19.62),
                 (stack_x, stack_y, 21.1), .022, "metal", vertices=6)
cylinder("DD_StackBeacon", (stack_x, stack_y, 20.35), .13, .24, "signal_red",
         axis="Z", vertices=10)
# Ladder, safety cage and an inspection platform.
ladder_y = stack_y - 2.18
for side in (-1, 1):
    cylinder_between("DD_StackLadder", (stack_x + side * .30, ladder_y, .9),
                     (stack_x + side * .30, ladder_y, 18.7), .038,
                     "steel", vertices=8)
for i in range(56):
    z = 1.05 + i * .318
    cylinder_between("DD_StackRung", (stack_x - .30, ladder_y, z),
                     (stack_x + .30, ladder_y, z), .021, "steel", vertices=6)
for i in range(9):
    z = 2.5 + i * 1.85
    torus("DD_StackCage", (stack_x, stack_y - 1.92, z), .58, .023,
          "steel", axis="Z", major_segments=16, minor_segments=4)
    for angle in (.2, 1.1, 2.15, 3.0):
        cylinder_between("DD_StackCageBar",
                         (stack_x + math.cos(angle) * .58, stack_y - 1.92 + math.sin(angle) * .58, z),
                         (stack_x + math.cos(angle) * .58, stack_y - 1.92 + math.sin(angle) * .58, z + 1.85),
                         .018, "steel", vertices=5)
box("DD_StackPlatform", (stack_x, stack_y - 2.55, 16.75), (2.5, 1.2, .10),
    "metal", .01)
for x in (-1.2, 1.2):
    beam("DD_StackPlatformRail", (stack_x + x, stack_y - 3.10, 16.80),
         (stack_x + x, stack_y - 3.10, 17.75), .05, .05, "steel")
beam("DD_StackPlatformRail", (stack_x - 1.2, stack_y - 3.10, 17.72),
     (stack_x + 1.2, stack_y - 3.10, 17.72), .05, .05, "steel")
# Warning band and identification at the base.
torus("DD_StackWarning", (stack_x, stack_y, 15.5), 1.67, .16, "hard_hat",
      axis="Z", major_segments=32, minor_segments=6)
box("DD_StackPlaque", (stack_x, stack_y - 2.18, 3.1), (1.05, .04, .48),
    "cream", .008)
text_sign("DD_StackPlaqueText", "H-1", (stack_x, stack_y - 2.21, 3.12),
          .28, "crack")
# Soot and lime runs.
for i in range(8):
    angle = 2.5 + i * .28
    x = stack_x + math.cos(angle) * (1.55 + i * .02)
    y = stack_y + math.sin(angle) * (1.55 + i * .02)
    h = .7 + (i % 3) * 1.1
    box("DD_StackSoot", (x, y, 17.4 - h * .5), (.55, .03, h), "crack",
        .002).rotation_euler.z = angle + math.pi * .5
add_collider("smokestack", (stack_x, stack_y, 10.0), (4.4, 4.4, 20.0))

set_group("DD_Factory_WaterTower")
wt_x, wt_y = 19.25, -12.15
for side_x in (-1, 1):
    for side_y in (-1, 1):
        ibeam("DD_WaterLeg", (wt_x + side_x * 1.45, wt_y + side_y * 1.45, .06),
              (wt_x + side_x * 1.10, wt_y + side_y * 1.10, 7.65),
              .26, .30, "steel")
        box("DD_WaterFoot", (wt_x + side_x * 1.45, wt_y + side_y * 1.45, .12),
            (.65, .65, .22), "foundation", .02)
for side in (-1, 1):
    for x0, x1 in [(-1.45, 0.0), (0.0, 1.45)]:
        beam("DD_WaterBraceX", (wt_x + x0, wt_y + side * 1.45, .4),
             (wt_x + x1, wt_y + side * 1.10, 3.8), .09, .09, "steel", .004)
        beam("DD_WaterBraceX", (wt_x + x0, wt_y + side * 1.10, 3.8),
             (wt_x + x1, wt_y + side * 1.10, 7.4), .08, .08, "steel", .004)
    for y0, y1 in [(-1.45, 0.0), (0.0, 1.45)]:
        beam("DD_WaterBraceY", (wt_x + side * 1.45, wt_y + y0, .4),
             (wt_x + side * 1.10, wt_y + y1, 3.8), .09, .09, "steel", .004)
        beam("DD_WaterBraceY", (wt_x + side * 1.10, wt_y + y0, 3.8),
             (wt_x + side * 1.10, wt_y + y1, 7.4), .08, .08, "steel", .004)
# Tank: riveted courses and conical cap.
cylinder("DD_WaterTank", (wt_x, wt_y, 9.35), 2.45, 3.40, "galvanized",
         axis="Z", vertices=32)
for z in (7.88, 8.78, 9.68, 10.58):
    torus("DD_WaterTankBand", (wt_x, wt_y, z), 2.48, .045, "rust",
          axis="Z", major_segments=32, minor_segments=4)
    for i in range(20):
        angle = math.tau * i / 20
        bolt("DD_WaterRivet",
             (wt_x + math.cos(angle) * 2.46, wt_y + math.sin(angle) * 2.46, z),
             (math.cos(angle), math.sin(angle), 0), .018, .025)
bpy.ops.mesh.primitive_cone_add(vertices=32, radius1=2.45, radius2=.22,
                                depth=1.2, location=(wt_x, wt_y, 11.65))
wt_roof = bpy.context.object
wt_roof.name = "DD_WaterRoof"
wt_roof.data.materials.append(MATS["rust"])
for polygon in wt_roof.data.polygons:
    if len(polygon.vertices) == 4:
        polygon.use_smooth = True
put(wt_roof)
cylinder("DD_WaterVent", (wt_x, wt_y, 12.34), .18, .42, "metal",
         axis="Z", vertices=12)
for i in range(12):
    angle = math.tau * i / 12
    x = wt_x + math.cos(angle) * 2.22
    y = wt_y + math.sin(angle) * 2.22
    cylinder_between("DD_WaterRailPost", (x, y, 11.02), (x, y, 11.85),
                     .028, "steel", vertices=5)
torus("DD_WaterTopRail", (wt_x, wt_y, 11.82), 2.22, .026, "steel",
      axis="Z", major_segments=28, minor_segments=4)
# Ladder and down pipe.
ladder_y = wt_y - 2.55
for side in (-1, 1):
    cylinder_between("DD_WaterLadder", (wt_x + side * .30, ladder_y, .45),
                     (wt_x + side * .30, ladder_y, 11.0), .035, "steel",
                     vertices=8)
for i in range(36):
    z = .60 + i * .295
    cylinder_between("DD_WaterRung", (wt_x - .30, ladder_y, z),
                     (wt_x + .30, ladder_y, z), .020, "steel", vertices=5)
for i in range(6):
    z = 1.2 + i * 1.8
    torus("DD_WaterCage", (wt_x, wt_y - 2.25, z), .55, .022, "steel",
          axis="Z", major_segments=14, minor_segments=3)
cylinder_between("DD_WaterDownpipe", (wt_x - 2.04, wt_y, 7.9),
                 (wt_x - 2.04, wt_y, .18), .12, "rust", vertices=10)
for z in (.7, 3.2, 5.7):
    cylinder("DD_WaterPipeClamp", (wt_x - 2.04, wt_y, z), .16, .07, "steel",
             axis="Z", vertices=10)
torus("DD_WaterValve", (wt_x - 2.04, wt_y + .02, 2.15), .24, .04, "signal_red",
      axis="Y", major_segments=14, minor_segments=4)
box("DD_WaterSign", (wt_x, wt_y - 2.47, 9.55), (2.2, .04, .62), "cream", .008)
text_sign("DD_WaterSignText", "WATER  /  40,000 L", (wt_x, wt_y - 2.50, 9.56),
          .25, "crack")
for x, y in [(-1.45, -1.45), (1.45, -1.45), (-1.45, 1.45), (1.45, 1.45)]:
    add_collider("water_leg", (wt_x + x, wt_y + y, 3.8), (.6, .6, 7.6))

# Substation cage.
set_group("DD_Factory_Yard")
sub_x, sub_y = -15.8, -13.4
box("DD_SubPad", (sub_x, sub_y, .12), (6.4, 5.1, .24), "foundation", .025)
chainlink_run((sub_x - 3.0, sub_y - 2.35, .10), (sub_x + 3.0, sub_y - 2.35, .10),
              2.45, name="DD_SubFenceS", barbed=True)
chainlink_run((sub_x - 3.0, sub_y + 2.35, .10), (sub_x + 3.0, sub_y + 2.35, .10),
              2.45, name="DD_SubFenceN")
chainlink_run((sub_x - 3.0, sub_y - 2.35, .10), (sub_x - 3.0, sub_y + 2.35, .10),
              2.45, name="DD_SubFenceW")
chainlink_run((sub_x + 3.0, sub_y - 2.35, .10), (sub_x + 3.0, sub_y + 2.35, .10),
              2.45, name="DD_SubFenceE")
for side in (-1, 1):
    for y in (-1.96, 1.96):
        box("DD_SubGatePost", (sub_x + side * 1.2, sub_y - 2.38, 1.25),
            (.16, .16, 2.3), "rust", .01)
box("DD_SubGate", (sub_x, sub_y - 2.38, 1.20), (2.2, .06, 2.0), "steel", .01)
box("DD_SubGateBrace", (sub_x, sub_y - 2.42, 1.20), (2.0, .03, .07), "rust")
box("DD_SubSign", (sub_x, sub_y - 2.45, 2.05), (1.25, .04, .28), "hard_hat")
text_sign("DD_SubSignText", "HIGH VOLTAGE", (sub_x, sub_y - 2.49, 2.06),
          .16, "crack")
box("DD_TransformerTank", (sub_x, sub_y + .35, 1.10), (2.10, 1.25, 1.70),
    "roof", .025)
for side in (-1, 1):
    for i in range(6):
        box("DD_TransformerFin", (sub_x - .84 + i * .33, sub_y + side * .74,
                                  1.10), (.08, .20, 1.35), "rust")
for i in range(3):
    x = sub_x - .65 + i * .65
    cylinder("DD_BushingBase", (x, sub_y + .35, 2.05), .12, .25, "ceramic",
             axis="Z", vertices=12)
    for j in range(4):
        cylinder("DD_BushingDisc", (x, sub_y + .35, 2.20 + j * .08),
                 .20 - j * .015, .035, "ceramic", axis="Z", vertices=12)
    cylinder_between("DD_BushingRod", (x, sub_y + .35, 2.20),
                     (x, sub_y + .35, 2.78), .025, "steel", vertices=6)
box("DD_TransformerPlate", (sub_x, sub_y - .30, 1.30), (.80, .03, .32),
    "cream")
text_sign("DD_TransformerText", "T-2  /  11kV", (sub_x, sub_y - .34, 1.31),
          .12, "crack")
for i in range(4):
    cylinder("DD_Insulator", (sub_x - 2.2 + i * 1.45, sub_y + 1.8, .45),
             .11, .55, "ceramic", axis="Z", vertices=10)
add_collider("substation", (sub_x, sub_y, 1.25), (6.3, 5.0, 2.5))


# ---------------------------------------------------------------------------
# Abandoned flatbed truck and the gate approach
stage("truck")
# ---------------------------------------------------------------------------
set_group("DD_Factory_Yard")
truck_x, truck_y = -8.2, -15.1
for side in (-1, 1):
    box("DD_TruckChassis", (truck_x, truck_y + side * .55, .72),
        (7.0, .16, .24), "rust", .01)
    box("DD_TruckFlatbedFrame", (truck_x - 1.0, truck_y + side * 1.0, 1.00),
        (4.6, .12, .18), "steel", .006)
box("DD_TruckFlatbed", (truck_x - 1.0, truck_y, 1.12), (4.75, 2.30, .14),
    "old_wood", .014)
for i in range(12):
    box("DD_TruckDeckPlank", (truck_x - 3.3 + i * .37, truck_y, 1.20),
        (.34, 2.22, .035), "light_wood", .004)
for side in (-1, 1):
    for i in range(7):
        box("DD_TruckStake", (truck_x - 3.25 + i * .72,
                              truck_y + side * 1.16, 1.55), (.10, .09, .90),
            "rust", .006)
    for z in (1.32, 1.76):
        box("DD_TruckSideRail", (truck_x - 1.0, truck_y + side * 1.18, z),
            (4.6, .07, .10), "rust", .004)
box("DD_TruckCabBase", (truck_x + 2.05, truck_y, 1.18), (1.80, 2.15, .56),
    "roof", .03)
box("DD_TruckCab", (truck_x + 2.10, truck_y, 1.98), (1.68, 2.0, 1.15),
    "roof", .035)
box("DD_TruckCabRoof", (truck_x + 2.10, truck_y, 2.58), (1.80, 2.12, .14),
    "rust", .02)
for side in (-1, 1):
    box("DD_TruckDoorSeam", (truck_x + 2.10, truck_y + side * 1.01, 1.80),
        (1.25, .03, .95), "rust", .004)
    box("DD_TruckDoorHandle", (truck_x + 1.70, truck_y + side * 1.045, 1.78),
        (.16, .03, .05), "steel", .005)
    box("DD_TruckSideGlass", (truck_x + 2.34, truck_y + side * 1.015, 2.17),
        (.95, .035, .50), "glass" if side > 0 else "crack")
    box("DD_TruckMirrorArm", (truck_x + 2.90, truck_y + side * 1.18, 2.16),
        (.06, .32, .05), "steel")
    box("DD_TruckMirror", (truck_x + 2.90, truck_y + side * 1.35, 2.10),
        (.10, .20, .26), "glass")
box("DD_TruckWindshield", (truck_x + 2.96, truck_y, 2.16), (.06, 1.60, .62),
    "crack", .01)
for i in range(3):
    beam("DD_TruckWindshieldBar", (truck_x + 2.92, truck_y - .75 + i * .75, 1.88),
         (truck_x + 2.92, truck_y - .75 + i * .75, 2.45), .05, .045, "rust")
box("DD_TruckHood", (truck_x + 3.30, truck_y, 1.50), (1.10, 1.85, .62),
    "roof", .035)
box("DD_TruckHoodTop", (truck_x + 3.30, truck_y, 1.83), (.95, 1.60, .08),
    "rust", .015)
box("DD_TruckGrille", (truck_x + 3.86, truck_y, 1.28), (.08, 1.55, .55),
    "rust", .012)
for i in range(6):
    box("DD_TruckGrilleBar", (truck_x + 3.91, truck_y, 1.08 + i * .09),
        (.03, 1.42, .025), "steel")
box("DD_TruckBumper", (truck_x + 3.95, truck_y, .88), (.18, 2.3, .20),
    "steel", .015)
for side in (-1, 1):
    cylinder("DD_TruckHeadlight", (truck_x + 3.94, truck_y + side * .70, 1.48),
             .15, .05, "cream", axis="X", vertices=12)
    box("DD_TruckFender", (truck_x + 3.0, truck_y + side * 1.05, .88),
        (1.1, .24, .20), "rust", .03)
# Six wheels, tread blocks and hubs.
for x in (-5.35, -9.55, -10.45):
    for side in (-1, 1):
        y = truck_y + side * 1.12
        cylinder("DD_TruckTyre", (x, y, .48), .47, .30, "rubber",
                 axis="Y", vertices=20)
        cylinder("DD_TruckHub", (x, y + side * .17, .48), .19, .05, "steel",
                 axis="Y", vertices=12)
        for i in range(10):
            angle = math.tau * i / 10
            box("DD_TruckTread",
                (x + math.cos(angle) * .48, y, .48 + math.sin(angle) * .48),
                (.12, .32, .04), "crack", .004).rotation_euler.y = -angle
        for i in range(6):
            angle = math.tau * i / 6
            bolt("DD_TruckLug",
                 (x + math.cos(angle) * .23, y + side * .205,
                  .48 + math.sin(angle) * .23), (0, side, 0), .017, .02)
# Cargo: wrapped pallet load and pipe bundle.
box("DD_TruckCargo", (truck_x - 1.7, truck_y, 1.62), (2.6, 1.55, .82),
    "canvas", .025)
for i in range(4):
    box("DD_TruckCargoStrap", (truck_x - 2.9 + i * .78, truck_y, 1.62),
        (.06, 1.62, .88), "rust")
for i in range(4):
    cylinder("DD_TruckPipe", (truck_x - .2 + i * .15, truck_y + .55, 1.40),
             .085, 3.2, "metal", axis="X", vertices=10)
# Exhaust stack and small details.
cylinder_between("DD_TruckExhaust", (truck_x + 1.30, truck_y + 1.10, 1.0),
                 (truck_x + 1.30, truck_y + 1.10, 3.10), .055, "rust",
                 vertices=8)
cylinder("DD_TruckExhaustCap", (truck_x + 1.30, truck_y + 1.10, 3.14),
         .09, .10, "steel", axis="Z", vertices=8)
box("DD_TruckPlate", (truck_x + 3.98, truck_y, .76), (.03, .56, .16),
    "cream")
text_sign("DD_TruckPlateText", "HD-4021", (truck_x + 4.00, truck_y, .76),
          .07, "crack", rotation=(math.pi * .5, math.pi * .5, 0))
for i in range(5):
    box("DD_TruckRustPatch", (truck_x + 1.55 + i * .35, truck_y - 1.04,
                              1.25 + (i % 2) * .55), (.32, .025, .22),
        "rust", .004)
add_collider("truck", (truck_x, truck_y, 1.2), (8.2, 2.7, 2.4))

# A few barricades and cones around the yard.
for x, y, yaw in [(-4.6, 12.0, .12), (10.8, 9.8, -.2), (-14.8, 9.2, .05)]:
    for side in (-1, 1):
        box("DD_BarricadeLeg", (x + side * .65, y, .55), (.10, .55, 1.10),
            "old_wood", .008)
    for z in (.45, .88):
        box("DD_BarricadeRail", (x, y, z), (1.65, .12, .22), "hard_hat", .012)
        for i in range(3):
            box("DD_BarricadeStripe", (x - .5 + i * .5, y - .075, z),
                (.18, .02, .22), "crack")
for x, y in [(1.1, 12.6), (3.3, 12.0), (12.0, 10.4)]:
    bpy.ops.mesh.primitive_cone_add(vertices=12, radius1=.24, radius2=.04,
                                    depth=.62, location=(x, y, .37))
    cone = bpy.context.object
    cone.name = "DD_TrafficCone"
    cone.data.materials.append(MATS["signal_red"])
    put(cone)
    torus("DD_TrafficConeBase", (x, y, .08), .27, .035, "rubber",
          axis="Z", major_segments=12, minor_segments=4)
    cylinder("DD_TrafficConeBand", (x, y, .40), .16, .08, "cream",
             axis="Z", vertices=12)
# Fallen concrete and bent sheet at the dock.
for i in range(12):
    ico("DD_BreachRubble", (random.uniform(-.4, 5.0), random.uniform(-7.9, -6.7),
        .12 + (i % 3) * .06), random.uniform(.10, .28), "foundation", (1, 1, .55))
for i in range(4):
    box("DD_BreachBrick", (random.uniform(-.2, 4.9), random.uniform(-7.8, -7.0), .08),
        (.24, .12, .07), "brick", .004).rotation_euler.z = random.uniform(0, 3.1)
for i in range(3):
    beam("DD_BreachRebar", (-.2 + i * 1.8, -7.6, .1), (.3 + i * 1.8, -6.9, .75),
         .016, .016, "rust", .002)

# ---------------------------------------------------------------------------
# Dead trees and dry shrubs beyond the fence
stage("trees")
# ---------------------------------------------------------------------------
set_group("DD_Factory_Vegetation")


def dead_tree(name, x, y, scale=1.0, seed=1):
    local = random.Random(seed)
    base = Vector((x, y, .06))
    trunk_height = 2.2 * scale
    cylinder_between(name + "_Trunk0", base, base + Vector((0, 0, trunk_height)),
                     .20 * scale, "old_wood", vertices=9)
    tips = []
    for level in range(3):
        count = 3 if level == 0 else 2
        for i in range(count):
            angle = local.uniform(0, math.tau)
            start_z = trunk_height * (.55 + level * .16)
            length = (1.3 - level * .25) * scale
            direction = Vector((math.cos(angle), math.sin(angle),
                                local.uniform(.3, .75))).normalized()
            start = base + Vector((0, 0, start_z))
            mid = start + direction * length * .55
            end = mid + direction * length * .45 + Vector((0, 0, .16))
            cylinder_between(name + "_Branch", start, mid, .10 * scale - level * .015,
                             "old_wood", vertices=7)
            cylinder_between(name + "_Branch", mid, end, .055 * scale, "old_wood",
                             vertices=6)
            tips.append(end)
    for i, tip in enumerate(tips):
        direction = Vector((local.uniform(-.7, .7), local.uniform(-.7, .7),
                            local.uniform(.4, .8))).normalized()
        cylinder_between(name + "_Twig", tip, tip + direction * .55 * scale,
                         .020 * scale, "old_wood", vertices=5)


dead_tree("DD_DeadTreeA", -23.4, 15.2, 1.30, 5)
dead_tree("DD_DeadTreeB", 22.8, 16.7, 1.05, 9)
dead_tree("DD_DeadTreeC", -23.9, -16.4, .95, 13)
# Dry weed fans in the foreground and against the fence.
for i in range(34):
    x = random.uniform(-23, 23)
    y = random.uniform(-18.2, 18.4)
    if point_blocked(x, y):
        continue
    for j in range(5):
        angle = j * 1.256 + i * .37
        height = random.uniform(.20, .52)
        cylinder_between("DD_WeedStem", (x, y, .04),
                         (x + math.cos(angle) * .13, y + math.sin(angle) * .13,
                          .04 + height), .008, "grass_dry", vertices=4)
        box("DD_WeedSeed", (x + math.cos(angle) * .14, y + math.sin(angle) * .14,
                            .04 + height), (.10, .025, .045), "grass_dry", .002).rotation_euler.z = angle


# ---------------------------------------------------------------------------
# Cutaway ownership, export and scene metadata
stage("finalize")
# ---------------------------------------------------------------------------
# Brick plinths, doors and windows are part of their cutaway wall so no
# floating detail remains when the hall is opened for the isometric camera.
reassign(["DD_SouthBrickPlinth", "DD_SouthPlinthCap", "DD_BreachHeader",
          "DD_BrokenBrickEdge", "DD_BrokenHeaderBrick", "DD_ExposedRebar",
          "DD_DockDoor", "DD_Bay03", "DD_PersonDoor"], "DD_Factory_Wall_South")
reassign(["DD_EastBrickPlinth", "DD_EastClad", "DD_EastTrim",
          "DD_EastBrokenBrick"], "DD_Factory_Wall_East")

# A small emissive factor keeps the industrial lamp lenses legible without
# relying on extra realtime lights.  No maps are invented.
lamp_shader = MATS["lamp_glow"].node_tree.nodes.get("Principled BSDF")
if lamp_shader:
    for key in ("Emission Color", "Emission"):
        if key in lamp_shader.inputs:
            lamp_shader.inputs[key].default_value = srgb("#ffd6a0")
            break
    if "Emission Strength" in lamp_shader.inputs:
        lamp_shader.inputs["Emission Strength"].default_value = 1.6

# Freeze source measurements before joining.
raw_parts = {name: len(objects) for name, objects in GROUPS.items()}
raw_triangles = {}
for name, objects in GROUPS.items():
    total = 0
    for obj in objects:
        if obj.type != "MESH":
            continue
        obj.data.calc_loop_triangles()
        total += len(obj.data.loop_triangles)
    raw_triangles[name] = total

stage("join-start")
for name in list(GROUPS.keys()):
    stage("join " + name + " (" + str(len(GROUPS[name])) + " parts)")
    objects = [obj for obj in GROUPS[name] if obj.name in bpy.data.objects]
    if not objects:
        continue
    if len(objects) == 1:
        obj = objects[0]
        obj.name = name
    else:
        kit["join"](objects, name)
    # Keep the export readable and make the cutaway lookup deterministic.
    joined = bpy.data.objects.get(name)
    if joined:
        joined["dd_group"] = name
    stage("joined " + name)

bpy.context.scene["DD_asset"] = "factory_grounds"
bpy.context.scene["DD_location"] = "Abandoned Halvorsen Ironworks (standalone scene)"
bpy.context.scene["DD_units"] = "meters; Blender Z-up, forward -Y; GLB/Godot Y-up, forward +Z"
bpy.context.scene["DD_original"] = "Procedural original geometry; no third-party meshes or textures"

stage("uv-project-start")
SURFACES["project_uvs"]()
stage("save-blend-start")
bpy.ops.wm.save_as_mainfile(filepath=str(SOURCE / "factory_grounds.blend"))
stage("export-start")
# Blender's image encoder uses a TemporaryDirectory for packed textures.  On a
# few locked-down Windows profiles the cleanup chmod is denied after the file
# has already been consumed.  Keep the export deterministic by tolerating only
# that cleanup error; the exported GLB itself is complete.
import tempfile
_original_cleanup = tempfile.TemporaryDirectory.cleanup
def _safe_cleanup(self):
    try:
        _original_cleanup(self)
    except PermissionError:
        pass
tempfile.TemporaryDirectory.cleanup = _safe_cleanup
bpy.ops.export_scene.gltf(
    filepath=str(OUT / "factory_grounds.glb"),
    export_format="GLB",
    export_yup=True,
    export_texcoords=True,
    export_apply=True,
    export_animations=False,
    export_cameras=False,
    export_lights=False,
)
stage("canonical-uv-start")
SURFACES["canonical_uvs"](OUT / "factory_grounds.glb")
stage("metadata-start")

joined_groups = {}
total_triangles = 0
total_parts = 0
for name in sorted(GROUPS.keys()):
    obj = bpy.data.objects.get(name)
    if not obj or obj.type != "MESH":
        continue
    obj.data.calc_loop_triangles()
    triangles = len(obj.data.loop_triangles)
    total_triangles += triangles
    total_parts += raw_parts.get(name, 0)
    joined_groups[name] = {
        "triangles": triangles,
        "parts": raw_parts.get(name, 0),
        "surfaces": len(obj.data.materials),
    }

# Deterministic dry-grass scatter outside the working surfaces.  The Godot
# scene reuses the existing grass_clump.glb in one MultiMesh batch.
grass_rng = random.Random(20261026)
grass = []
while len(grass) < 290:
    x = grass_rng.uniform(-23.2, 23.2)
    y = grass_rng.uniform(-18.2, 18.2)
    if point_blocked(x, y):
        continue
    if abs(x) < 14.0 and -11.0 < y < 10.5:
        # Keep the working yard readable; grass clumps gather at edges,
        # cracks and fence lines instead of the centre of the apron.
        if grass_rng.random() > .10:
            continue
    if -23.5 < x < 23.5 and -19.0 < y < 19.0:
        if grass_rng.random() > .55:
            continue
    grass.append([round(x, 3), round(-y, 3), round(grass_rng.uniform(.65, 1.45), 3)])

lights = [
    {"id": "dock", "position": [-7.35, 4.02, 9.64], "color": "ffd2a0",
     "energy": 2.2, "range": 9.0, "shadow": False},
    {"id": "facade", "position": [-5.1, 4.82, 9.48], "color": "ffd2a0",
     "energy": 1.4, "range": 6.0, "shadow": False},
    {"id": "bay_west", "position": [-6.0, 4.16, .30], "color": "ffd7b4",
     "energy": 1.8, "range": 8.5, "shadow": False},
    {"id": "bay_mid", "position": [2.0, 4.16, .30], "color": "ffd7b4",
     "energy": 1.8, "range": 8.5, "shadow": False},
    {"id": "bay_east", "position": [10.0, 4.16, .30], "color": "ffd7b4",
     "energy": 1.65, "range": 8.0, "shadow": False},
    {"id": "stack_beacon", "position": [19.3, 20.38, -3.1], "color": "ff4a33",
     "energy": .8, "range": 5.0, "shadow": False},
]

layout = {
    "version": 1,
    "asset": "factory_grounds",
    "name": "废弃的哈尔沃森铁工厂",
    "name_en": "Abandoned Halvorsen Ironworks",
    "units": "meters / Godot Y-up",
    "source": "art/source/factory_grounds.blend",
    "triangles": total_triangles,
    "parts": total_parts,
    "groups": joined_groups,
    "spawn": [2.1, .12, 14.6],
    "spawn_yaw": 180.0,
    "camera": {
        "offset": [13.0, 16.0, 15.0],
        "exterior_size": 27.0,
        "interior_size": 12.4,
        "min_zoom": 12.0,
        "max_zoom": 38.0,
        "focus_height": .65,
        "inside_bounds": {"min_x": -12.55, "max_x": 12.55,
                          "min_z": -6.75, "max_z": 7.45}
    },
    "bounds": {"min_x": -25.0, "max_x": 25.0, "min_z": -20.0, "max_z": 20.0},
    "colliders": COLLIDERS,
    "lights": lights,
    "grass": grass,
    "features": {
        "sawtooth_bays": 4,
        "silos": 2,
        "overhead_crane": 1,
        "stamping_presses": 1,
        "lathes": 1,
        "conveyor_lines": 1,
        "forklifts": 1,
        "loading_dock_bays": 3,
        "vehicles": 1,
        "dead_trees": 3,
    },
    "cutaway": {
        "roof": "DD_Factory_Roof",
        "south_wall": "DD_Factory_Wall_South",
        "east_wall": "DD_Factory_Wall_East"
    },
    "notes": "Standalone additive scene. Existing street, saves, rules and gameplay scripts are not modified.",
}

(DATA / "factory_layout.json").write_text(
    json.dumps(layout, indent=2, ensure_ascii=False) + "\n",
    encoding="utf-8", newline="\n")
print("FACTORY_PIPELINE_OK", total_triangles, total_parts,
      len(COLLIDERS), len(grass), flush=True)
for name in sorted(joined_groups):
    print("FACTORY_GROUP", name, joined_groups[name]["triangles"],
          joined_groups[name]["parts"], flush=True)






