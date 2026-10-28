"""Three lightweight standalone location studies: track field, market, villa.

All geometry is original and procedural.  The scenes use the project's shared
PBR library and metric scale, and never add collision, rules or save data to the
existing street.

Run:
    D:/Blender/blender.exe --background --factory-startup \
        --python tools/generate_simple_locations.py

Outputs:
    art/source/track_field.blend + godot/assets/track_field.glb
    art/source/market_square.blend + godot/assets/market_square.glb
    art/source/villa_courtyard.blend + godot/assets/villa_courtyard.glb
    godot/data/simple_locations.json
"""
from pathlib import Path
import json
import math
import runpy
import tempfile
import bpy
import bmesh
from mathutils import Vector, Euler

ROOT = Path(__file__).resolve().parents[1]
kit = runpy.run_path(str(ROOT / "tools/generate_assets.py"))
MATERIAL_LIBRARY = kit["MATERIAL_LIBRARY"]
SURFACES = kit["SURFACES"]
OUT = ROOT / "godot" / "assets"
SOURCE = ROOT / "art" / "source"
DATA = ROOT / "godot" / "data"
OUT.mkdir(parents=True, exist_ok=True)
SOURCE.mkdir(parents=True, exist_ok=True)
DATA.mkdir(parents=True, exist_ok=True)

# Work around a Windows-only Blender 5.2 temp-image cleanup permission issue.
_orig_cleanup = tempfile.TemporaryDirectory.cleanup
def _safe_cleanup(self):
    try:
        _orig_cleanup(self)
    except PermissionError:
        pass
tempfile.TemporaryDirectory.cleanup = _safe_cleanup

PARTS = []
MATS = {}
COLLIDERS = []
LAYOUTS = {}


def srgb(value):
    value = value.lstrip("#")
    channels = [int(value[i:i + 2], 16) / 255.0 for i in (0, 2, 4)]
    return tuple(c / 12.92 if c <= .04045 else ((c + .055) / 1.055) ** 2.4 for c in channels) + (1.0,)


def add_material(name, color, roughness=.88, metallic=0.0, alias=None):
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


def prepare_materials():
    global MATS
    MATS = kit["MATS"]
    add_material("paving", "#77756b", alias="concrete")
    add_material("tarmac", "#414547", alias="road_patch")
    add_material("track", "#87473c", .90)
    add_material("lane", "#ddd6c3", .88)
    add_material("turf", "#586a46", .96)
    add_material("soil", "#635c45", alias="soil")
    add_material("foliage", "#5d704b", .95)
    add_material("concrete_dark", "#575a52", .93)
    add_material("pool", "#3f7e88", .16, .05)
    add_material("pool_tile", "#c3cdc7", .55)
    add_material("stucco", "#c9bea9", .92)
    add_material("awning_a", "#8f4639", .91)
    add_material("awning_b", "#d5c9ad", .93)
    add_material("hedge", "#4d6040", .96)
    add_material("lamp", "#ffd8a2", .38)
    MATS["lamp"].node_tree.nodes["Principled BSDF"].inputs["Emission Color"].default_value = srgb("#ffd39a")
    MATS["lamp"].node_tree.nodes["Principled BSDF"].inputs["Emission Strength"].default_value = 1.4


def stage_reset():
    kit["reset"]()
    PARTS.clear()
    COLLIDERS.clear()
    prepare_materials()


def mesh_obj(name, verts, faces, material, smooth=False):
    data = bpy.data.meshes.new(name)
    data.from_pydata(verts, [], faces)
    data.validate(verbose=False)
    bm = bmesh.new()
    bm.from_mesh(data)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bm.to_mesh(data)
    bm.free()
    obj = bpy.data.objects.new(name, data)
    bpy.context.collection.objects.link(obj)
    data.materials.append(MATS[material])
    for polygon in data.polygons:
        polygon.use_smooth = smooth
    PARTS.append(obj)
    return obj


def box(name, at, size, material, bevel=0.0, rotation=(0, 0, 0), smooth=False):
    bm = bmesh.new()
    bmesh.ops.create_cube(bm, size=1.0)
    bmesh.ops.scale(bm, vec=Vector(size), verts=bm.verts)
    if bevel > 0:
        bmesh.ops.bevel(bm, geom=list(bm.edges), offset=min(bevel, min(size) * .42),
                        segments=1, affect="EDGES", clamp_overlap=True)
    matrix = Euler(rotation, "XYZ").to_matrix()
    local = [matrix @ v.co + Vector(at) for v in bm.verts]
    faces = [tuple(v.index for v in f.verts) for f in bm.faces]
    bm.free()
    return mesh_obj(name, [tuple(p) for p in local], faces, material, smooth)


def cyl(name, at, radius, depth, material, axis="Z", vertices=12, smooth=True):
    rings = [(radius, -depth * .5), (radius, depth * .5)]
    verts = []
    for r, z in rings:
        for i in range(vertices):
            a = math.tau * i / vertices
            verts.append((r * math.cos(a), r * math.sin(a), z))
    faces = []
    for i in range(vertices):
        faces.append((i, (i + 1) % vertices, vertices + (i + 1) % vertices, vertices + i))
    faces.append(tuple(reversed(range(vertices))))
    faces.append(tuple(vertices + i for i in range(vertices)))
    rot = Euler((0, 0, 0), "XYZ").to_matrix()
    if axis == "X":
        rot = Euler((0, math.pi * .5, 0), "XYZ").to_matrix()
    elif axis == "Y":
        rot = Euler((math.pi * .5, 0, 0), "XYZ").to_matrix()
    points = [tuple(rot @ Vector(p) + Vector(at)) for p in verts]
    return mesh_obj(name, points, faces, material, smooth)


def tube(name, points, radius, material, sides=8, smooth=True):
    pts = [Vector(p) for p in points]
    verts = []
    for j, center in enumerate(pts):
        if j == 0:
            tangent = (pts[1] - pts[0]).normalized()
        elif j == len(pts) - 1:
            tangent = (pts[-1] - pts[-2]).normalized()
        else:
            tangent = (pts[j + 1] - pts[j - 1]).normalized()
        ref = Vector((0, 1, 0)) if abs(tangent.dot(Vector((0, 1, 0)))) < .9 else Vector((1, 0, 0))
        u = tangent.cross(ref).normalized()
        v = tangent.cross(u).normalized()
        for i in range(sides):
            a = math.tau * i / sides
            verts.append(tuple(center + u * (math.cos(a) * radius) + v * (math.sin(a) * radius)))
    faces = []
    for j in range(len(pts) - 1):
        for i in range(sides):
            faces.append((j * sides + i, j * sides + (i + 1) % sides,
                          (j + 1) * sides + (i + 1) % sides, (j + 1) * sides + i))
    faces.append(tuple(reversed(range(sides))))
    faces.append(tuple((len(pts) - 1) * sides + i for i in range(sides)))
    return mesh_obj(name, verts, faces, material, smooth)


def ico(name, at, radius, material, scale=(1, 1, 1), smooth=False):
    bm = bmesh.new()
    bmesh.ops.create_icosphere(bm, subdivisions=1, radius=radius)
    verts = [(v.co.x * scale[0] + at[0], v.co.y * scale[1] + at[1], v.co.z * scale[2] + at[2])
             for v in bm.verts]
    faces = [tuple(v.index for v in f.verts) for f in bm.faces]
    bm.free()
    return mesh_obj(name, verts, faces, material, smooth)


def text_sign(name, text, at, size, material, rotation=(math.pi * .5, 0, 0), extrude=.006):
    bpy.ops.object.text_add(location=at, rotation=rotation)
    obj = bpy.context.object
    obj.name = name
    obj.data.body = text
    obj.data.size = size
    obj.data.extrude = extrude
    obj.data.align_x = "CENTER"
    obj.data.align_y = "CENTER"
    obj.data.materials.append(MATS[material])
    bpy.context.view_layer.objects.active = obj
    obj.select_set(True)
    bpy.ops.object.convert(target="MESH")
    converted = bpy.context.object
    converted["dd_text"] = True
    PARTS.append(converted)
    return converted


def collider(name, center, size):
    cx, cy, cz = center
    sx, sy, sz = size
    COLLIDERS.append({
        "id": name,
        # The scene is mirrored across Blender Y before export so the open
        # entrance faces the +Z gameplay camera. Godot z therefore equals
        # the authored Blender y.
        "position": [round(cx, 3), round(cz, 3), round(cy, 3)],
        "size": [round(sx, 3), round(sz, 3), round(sy, 3)],
    })


def rounded_rect(hw, hd, radius, seg=8):
    points = []
    corners = [(hw - radius, -hd + radius, -90, 0),
               (hw - radius, hd - radius, 0, 90),
               (-hw + radius, hd - radius, 90, 180),
               (-hw + radius, -hd + radius, 180, 270)]
    for cx, cy, a0, a1 in corners:
        for i in range(seg + 1):
            angle = math.radians(a0 + (a1 - a0) * i / seg)
            points.append((cx + math.cos(angle) * radius, cy + math.sin(angle) * radius))
    return points


def extrude_polygon(name, points, z0, z1, material):
    count = len(points)
    top = [(x, y, z1) for x, y in points]
    bottom = [(x, y, z0) for x, y in points]
    faces = [tuple(range(count)), tuple(reversed(range(count, count * 2)))]
    for i in range(count):
        j = (i + 1) % count
        faces.append((i, j, count + j, count + i))
    return mesh_obj(name, top + bottom, faces, material, False)


def ring_solid(name, outer, inner, z0, z1, material):
    count = len(outer)
    verts = []
    for z in (z0, z1):
        for x, y in outer:
            verts.append((x, y, z))
        for x, y in inner:
            verts.append((x, y, z))
    faces = []
    # Top and bottom rings.
    for i in range(count):
        j = (i + 1) % count
        faces.append((count + i, count + j, count * 3 + j, count * 3 + i))
        faces.append((i, 2 * count + i, 2 * count + j, j))
    # Outer and inner vertical walls.
    for i in range(count):
        j = (i + 1) % count
        faces.append((i, count + i, count + j, j))
        faces.append((2 * count + i, 2 * count + j, 3 * count + j, 3 * count + i))
    return mesh_obj(name, verts, faces, material, False)


def lane_ring(name, hw, hd, radius, width, z, material):
    outer = rounded_rect(hw, hd, radius)
    inner = rounded_rect(hw - width, hd - width, max(.8, radius - width))
    return ring_solid(name, outer, inner, z, z + .006, material)


def tree(name, x, y, scale=1.0):
    cyl(name + "_Trunk", (x, y, 1.55 * scale), .18 * scale, 3.1 * scale,
        "wood", 9)
    ico(name + "_CrownA", (x, y, 3.35 * scale), 1.45 * scale, "foliage",
        (1.0, 1.0, .76))
    ico(name + "_CrownB", (x - .75 * scale, y + .35 * scale, 3.9 * scale),
        1.05 * scale, "foliage", (1.0, 1.0, .72))
    ico(name + "_CrownC", (x + .72 * scale, y - .40 * scale, 4.05 * scale),
        1.0 * scale, "foliage", (1.0, 1.0, .68))
    collider(name + "_trunk", (x, y, 1.2 * scale), (.55 * scale, .55 * scale, 2.4 * scale))


def mirror_entrance_to_camera():
    """Put authored entrances on Blender -Y, which exports toward Godot +Z.

    Text is translated but not mirrored, so signs remain readable from the
    gameplay camera. Solid meshes are mirrored and normals recalculated.
    """
    for obj in PARTS:
        if obj.get("dd_text"):
            obj.location.y = -obj.location.y
            continue
        bm = bmesh.new()
        bm.from_mesh(obj.data)
        for vertex in bm.verts:
            vertex.co.y = -vertex.co.y
        bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
        bm.to_mesh(obj.data)
        bm.free()


def join_scene(asset):
    mirror_entrance_to_camera()
    joined = kit["join"](PARTS.copy(), "DD_" + asset)
    joined.name = "DD_" + asset
    return joined


def join_villa_groups():
    mirror_entrance_to_camera()

    def take(prefixes):
        selected = [obj for obj in list(PARTS)
                    if any(obj.name.startswith(prefix) for prefix in prefixes)]
        for obj in selected:
            PARTS.remove(obj)
        return selected

    groups = {
        "DD_Villa_Roof": take(("VillaMainRoof", "VillaSideRoof", "RoofEdge")),
        "DD_Villa_FrontWall": take(("FrontWall", "FrontGlazing", "FrontMullion",
                                    "FrontTransom", "FrontSill", "FrontHeader",
                                    "FrontUpper", "FrontBalcony",
                                    "FrontDoor", "DoorFrame", "DoorHandle",
                                    "EntryCanopy", "CanopyPost", "EntryStep",
                                    "VillaSign", "GarageDoor", "GarageRib",
                                    "TimberSlat", "SlatFrame")),
        "DD_Villa_EastWall": take(("EastWall", "EastWindow", "EastGlazing",
                                    "EastMullion")),
        "DD_Villa_UpperFloor": take(("Upper",)),
        "DD_Villa_Body": list(PARTS),
    }
    for name, objects in groups.items():
        if objects:
            joined = kit["join"](objects, name)
            joined.name = name


def save_scene(asset, info, register=True):
    SURFACES["project_uvs"]()
    bpy.ops.wm.save_as_mainfile(filepath=str(SOURCE / (asset + ".blend")))
    bpy.ops.export_scene.gltf(
        filepath=str(OUT / (asset + ".glb")), export_format="GLB",
        export_yup=True, export_texcoords=True, export_apply=True,
        export_animations=False, export_cameras=False, export_lights=False)
    SURFACES["canonical_uvs"](OUT / (asset + ".glb"))
    meshes = [obj for obj in bpy.data.objects if obj.type == "MESH"]
    triangles = 0
    for obj in meshes:
        obj.data.calc_loop_triangles()
        triangles += len(obj.data.loop_triangles)
    info.update({"asset": asset, "triangles": triangles, "meshes": len(meshes),
                 "collider_count": len(COLLIDERS),
                 "colliders": [dict(item) for item in COLLIDERS]})
    if register:
        LAYOUTS[asset] = info
    print("LOCATION_OK", asset, triangles, len(COLLIDERS), flush=True)


# ---------------------------------------------------------------------------
# 1. Track and field
# ---------------------------------------------------------------------------
def build_track_field():
    stage_reset()
    box("Ground", (0, 0, -.08), (56, 46, .16), "turf", 0)
    box("EntranceApron", (0, 20.0, .015), (12, 5.5, .05), "paving", .02)
    outer = rounded_rect(22.5, 15.5, 7.5, 12)
    inner = rounded_rect(15.4, 8.4, 3.9, 12)
    ring_solid("TrackSurface", outer, inner, .018, .045, "track")
    extrude_polygon("Infield", rounded_rect(15.38, 8.38, 3.88, 12), .015, .030, "turf")
    for d in (1.15, 2.3, 3.45, 4.6, 5.75, 6.9):
        lane_ring("LaneLine", 22.5 - d, 15.5 - d, max(1.8, 7.5 - d), .055, .048, "lane")
    lane_ring("TrackOuterEdge", 22.56, 15.56, 7.56, .05, .046, "lane")
    lane_ring("TrackInnerEdge", 15.34, 8.34, 3.84, .05, .046, "lane")
    for y in (-11.95, 11.95):
        box("StartLine", (0, y, .052), (.12, 7.2, .008), "lane")
    # Football / athletics infield markings.
    for x in (-13.4, 13.4):
        box("PitchSide", (x, 0, .034), (.08, 14.0, .006), "lane")
    for y in (-7.0, 7.0):
        box("PitchEnd", (0, y, .034), (26.8, .08, .006), "lane")
    box("Halfway", (0, 0, .034), (.08, 14.0, .006), "lane")
    tube("CentreCircle", [(math.cos(a * math.tau / 32) * 3, math.sin(a * math.tau / 32) * 3, .036)
                          for a in range(33)], .035, "lane", 6)
    for side in (-1, 1):
        box("PenaltyBoxLong", (side * 11.0, 0, .034), (.06, 8.0, .006), "lane")
        box("PenaltyBoxEnd", (side * 8.4, 0, .034), (5.2, .06, .006), "lane")
        # Goal frame, facing the infield.
        for sy in (-3.66, 3.66):
            cyl("GoalPost", (side * 14.1, sy, 1.22), .07, 2.44, "lane", "Z", 10)
        tube("GoalCrossbar", [(side * 14.1, -3.66, 2.44), (side * 14.1, 3.66, 2.44)],
             .07, "lane", 10)
        for sy in (-3.66, 3.66):
            tube("GoalStay", [(side * 14.1, sy, 2.44),
                               (side * 15.25, sy * .72, .08)], .035, "lane", 6)
    # Five-row concrete bleacher with timber benches and a central aisle.
    for row in range(5):
        top = .28 + row * .30
        y = -16.0 - row * .78
        for side in (-1, 1):
            box("BleacherStep", (side * 6.1, y, top * .5), (11.6, .78, top),
                "foundation", .015)
            box("BleacherBench", (side * 6.1, y - .15, top + .04), (11.0, .38, .07),
                "wood_light", .01)
    collider("bleachers", (0, -18.0, .95), (24.0, 4.4, 1.9))
    for side in (-1, 1):
        tube("BleacherRail", [(side * 12.2, -15.7, 0.05),
                              (side * 12.2, -15.7, 2.1),
                              (side * 12.2, -19.6, 2.1)], .04, "steel", 8)
    # Perimeter fence with an open south gate.
    fence_y = 22.0
    for side in (-1, 1):
        x = side * 27.0
        for k in range(13):
            y0 = -21.5 + k * 3.55
            cyl("FencePost", (x, y0, .95), .055, 1.9, "steel", "Z", 8)
        for z in (.35, 1.0, 1.75):
            tube("FenceRail", [(x, -22.0, z), (x, 22.0, z)], .018, "steel", 6)
        collider("fence_side", (x, 0, .9), (.12, 44.0, 1.8))
    for side in (-1, 1):
        y = side * fence_y
        x0, x1 = (-27.0, -2.2) if side > 0 else (-27.0, 27.0)
        if side > 0:
            segments = [(-27.0, -2.2), (2.2, 27.0)]
        else:
            segments = [(-27.0, 27.0)]
        for a, b in segments:
            count = max(1, int((b - a) / 3.5))
            for k in range(count + 1):
                x = a + (b - a) * k / count
                cyl("FencePost", (x, y, .95), .055, 1.9, "steel", "Z", 8)
            for z in (.35, 1.0, 1.75):
                tube("FenceRail", [(a, y, z), (b, y, z)], .018, "steel", 6)
        if side > 0:
            for a, b in segments:
                collider("fence_south", ((a + b) * .5, y, .9), (b - a, .12, 1.8))
        else:
            collider("fence_north", (0, y, .9), (54.0, .12, 1.8))
    # Gate sign.
    box("GateSignBoard", (0, 22.05, 2.35), (5.2, .12, .8), "roof", .02)
    text_sign("GateSign", "TRACK 01  /  ATHLETICS FIELD", (0, 21.96, 2.35),
              .28, "lane")
    # Floodlight poles at the four corners.
    for x, y in [(-24.0, -19.0), (24.0, -19.0), (-24.0, 18.5), (24.0, 18.5)]:
        cyl("FloodPole", (x, y, 4.5), .11, 9.0, "steel", "Z", 10)
        box("FloodArm", (x, y, 8.8), (1.0, .12, .12), "steel")
        for d in (-.38, 0, .38):
            box("FloodHead", (x + d, y - .18, 8.65), (.26, .40, .16), "steel")
            box("FloodLens", (x + d, y - .39, 8.65), (.20, .025, .10), "lamp")
        collider("flood_pole", (x, y, 4.5), (.35, .35, 9.0))
    # Scoreboard behind the bleachers.
    for side in (-1, 1):
        box("ScorePost", (side * 2.4, -21.8, 2.1), (.18, .18, 4.2), "steel")
    box("ScoreBoard", (0, -21.8, 4.2), (6.2, .18, 1.5), "roof", .02)
    text_sign("ScoreText", "NORTH DISTRICT  /  TRACK 01", (0, -21.9, 4.25),
              .23, "lane")
    collider("scoreboard", (0, -21.8, 2.1), (6.3, .5, 4.3))
    tree("TrackTreeA", -25.0, 3.0, .9)
    tree("TrackTreeB", 25.0, -4.5, .85)
    tree("TrackTreeC", -24.6, 12.0, .75)
    info = {
        "name": "田径场 / TRACK & FIELD",
        "spawn": [0, .12, 19.5],
        "spawn_yaw": 180.0,
        "camera": {"offset": [21, 25, 23], "size": 44.0, "min_zoom": 28.0,
                   "max_zoom": 58.0, "focus_height": .60},
        "environment": {"sun_rotation": [-52, -32, 0], "sun_color": "fff2df",
                        "sun_energy": 1.08, "ambient_color": "b7c9ce",
                        "ambient_energy": .52, "background": "1d282e",
                        "fog_density": .004},
        "lights": [
            {"id": "gate", "position": [0, 3.0, 21.0], "color": "ffd7a6",
             "energy": 1.0, "range": 7.0},
        ],
    }
    join_scene("track_field")
    save_scene("track_field", info)


# ---------------------------------------------------------------------------
# 2. Market square
# ---------------------------------------------------------------------------
def market_stall(name, x, y, produce_material, accent):
    # Posts and a two-tone canopy.
    for sx in (-1.55, 1.55):
        for sy in (-1.25, 1.25):
            cyl(name + "_Post", (x + sx, y + sy, 1.35), .045, 2.7, "steel", "Z", 8)
    box(name + "_TopFrame", (x, y, 2.52), (3.35, 2.7, .10), "wood", .01)
    for i in range(5):
        box(name + "_Canopy", (x - 1.35 + i * .675, y, 2.63),
            (.665, 2.6, .06), "awning_a" if i % 2 == 0 else "awning_b", .01)
    for i in range(5):
        box(name + "_Valance", (x - 1.35 + i * .675, y + 1.36, 2.42),
            (.665, .07, .34), "awning_a" if i % 2 == 0 else "awning_b")
    box(name + "_CounterTop", (x, y + .15, .92), (2.7, 1.0, .10), "wood_light", .012)
    for sx in (-1.2, 1.2):
        box(name + "_CounterLeg", (x + sx, y + .15, .45), (.10, .82, .85), "wood", .008)
    box(name + "_BackPanel", (x, y - 1.18, 1.05), (2.8, .08, 1.9), "wood", .01)
    # Produce crates and a few loose items.
    for i in range(3):
        cx = x - .85 + i * .85
        box(name + "_Crate", (cx, y + .18, 1.04), (.62, .62, .22), "wood", .012)
        for j in range(3):
            for k in range(2):
                ico(name + "_Produce", (cx - .18 + j * .18, y + .05 + k * .20, 1.20),
                    .075, produce_material, (.9, .9, .9))
        box(name + "_CrateSign", (cx, y + .51, 1.13), (.36, .02, .18), "cream", .004)
        text_sign(name + "_Price", "2.0", (cx, y + .495, 1.13), .09, "roof")
    box(name + "_Accent", (x + 1.15, y + .70, 1.02), (.18, .20, .05), accent, .004)
    collider(name, (x, y + .1, 1.0), (3.4, 2.8, 2.0))


def build_market_square():
    stage_reset()
    box("Ground", (0, 0, -.06), (32, 26, .12), "paving", 0)
    box("MarketLane", (0, 1.0, .008), (8.5, 22, .02), "tarmac", 0)
    # Three open-front shop interiors.  The player walks in between the front
    # columns; the roof is deliberately open so the isometric camera can see in.
    box("ShopBackWall", (0, -12.55, 1.90), (24.2, .30, 3.8), "stucco", .02)
    box("ShopFloor", (0, -10.55, .035), (23.9, 3.9, .07), "paving", 0)
    for x in (-12.0, -4.0, 4.0, 12.0):
        box("ShopPartition", (x, -10.55, 1.78), (.22, 3.9, 3.55),
            "stucco", .02)
        collider("shop_partition", (x, -10.55, 1.78), (.35, 3.9, 3.55))
        box("ShopColumn", (x, -8.55, 1.86), (.36, .36, 3.72), "wood", .015)
        collider("shop_column", (x, -8.55, 1.86), (.48, .48, 3.72))
    collider("shop_back", (0, -12.55, 1.90), (24.2, .45, 3.8))
    box("ShopHeader", (0, -8.55, 3.62), (24.1, .34, .30), "roof", .02)
    for i, x in enumerate((-8.0, 0.0, 8.0)):
        box("ShopCounter", (x, -11.88, .56), (4.8, .65, 1.12), "wood", .02)
        box("ShopCounterTop", (x, -11.88, 1.15), (5.0, .76, .08),
            "wood_light", .012)
        collider("shop_counter", (x, -11.88, .56), (5.0, .8, 1.12))
        box("ShopBackShelf", (x, -12.28, 1.55), (4.6, .28, 2.2),
            "wood", .02)
        for k in range(4):
            box("ShopShelfBoard", (x, -12.10, .55 + k * .48),
                (4.4, .04, .05), "wood_light", .004)
        for k in range(5):
            cx = x - 1.8 + k * .9
            box("ShopCrate", (cx, -11.80, 1.28), (.55, .50, .22), "wood", .01)
            ico("ShopProduce", (cx, -11.80, 1.44), .16,
                "cross" if (k + i) % 2 == 0 else "hard_hat", (1, 1, 1.15))
        box("ShopAwning", (x, -7.65, 3.35), (7.0, 2.1, .08),
            "awning_a" if i % 2 == 0 else "awning_b", .01,
            rotation=(.13, 0, 0))
        box("ShopSign", (x, -8.50, 3.95), (4.6, .10, .46), "roof", .01)
        text_sign("ShopSignText", ["MARKET  A", "MARKET  B", "MARKET  C"][i],
                  (x, -8.58, 3.95), .24, "lane")
        cyl("ShopInteriorLight", (x, -9.6, 3.05), .10, .22, "lamp", "Z", 8)
    # Low display tables inside each shop, leaving the entrance and lane clear.
    for i, x in enumerate((-8.0, 0.0, 8.0)):
        box("ShopDisplay", (x - 1.5, -9.75, .48), (1.5, 1.1, .92),
            "wood_light", .015)
        box("ShopDisplayTop", (x - 1.5, -9.75, .96), (1.7, 1.25, .08),
            "wood_light", .008)
        collider("shop_display", (x - 1.5, -9.75, .48), (1.7, 1.3, .95))
    # Stalls leave a clear central lane.
    stall_data = [(-9.5, -5.0, "cross", "hard_hat"),
                  (-3.6, -5.0, "jacket", "safety_vest"),
                  (2.5, -5.0, "safety_vest", "jacket"),
                  (8.6, -5.0, "hard_hat", "cross"),
                  (-7.0, 4.5, "jacket", "safety_vest"),
                  (6.5, 4.5, "cross", "jacket")]
    for i, (x, y, produce, accent) in enumerate(stall_data):
        market_stall("Stall_%d" % i, x, y, produce, accent)
    # String lights across the lane.
    for side in (-1, 1):
        cyl("LightPole", (side * 14.0, 0, 2.0), .10, 4.0, "wood", "Z", 10)
        collider("light_pole", (side * 14.0, 0, 2.0), (.3, .3, 4.0))
    cable_points = []
    for i in range(21):
        t = i / 20.0
        cable_points.append((-14.0 + 28.0 * t, -.4, 4.0 - math.sin(t * math.pi) * .65))
    tube("StringCable", cable_points, .018, "steel", 5)
    for i in range(11):
        t = (i + .5) / 11.0
        x = -14 + 28 * t
        z = 4.0 - math.sin(t * math.pi) * .65
        tube("BulbDrop", [(x, -.4, z), (x, -.4, z - .22)], .008, "steel", 4)
        ico("Bulb", (x, -.4, z - .28), .10, "lamp", (1.0, 1.0, 1.15), True)
    # Planters, benches, crates and a tree.
    for x, y in [(-13.4, 10.5), (13.4, 10.5), (-13.4, -10.0), (13.4, -10.0)]:
        box("Planter", (x, y, .30), (1.3, .75, .60), "foundation", .03)
        box("PlanterSoil", (x, y, .59), (1.12, .58, .06), "soil")
        for k in range(5):
            ico("PlanterPlant", (x - .4 + k * .2, y, .82), .22, "hedge",
                (1, 1, 1.25))
        collider("planter", (x, y, .35), (1.35, .8, .7))
    for x, y, yaw in [(-12.6, 1.8, 1.57), (12.6, 1.8, -1.57)]:
        box("BenchSeat", (x, y, .52), (.55, 2.3, .10), "wood_light", .015,
            rotation=(0, 0, yaw))
        for d in (-.9, .9):
            box("BenchLeg", (x + d * math.sin(yaw), y + d * math.cos(yaw), .26),
                (.45, .16, .52), "steel", .01)
        collider("bench", (x, y, .3), (.7, 2.4, .6))
    tree("MarketTreeA", -13.2, 8.0, .72)
    tree("MarketTreeB", 13.0, -8.0, .68)
    for i in range(8):
        x = -14.3 + (i % 4) * .55
        y = 11.0 + (i // 4) * .55
        box("LooseCrate", (x, y, .32 + (i % 2) * .28), (.48, .48, .48),
            "wood", .012)
    # Boundary planters / low walls.
    for side in (-1, 1):
        box("BoundaryWall", (side * 15.6, 0, .42), (.45, 24.0, .84), "stucco", .03)
        collider("boundary_side", (side * 15.6, 0, .42), (.55, 24.0, .9))
    for side in (-1, 1):
        box("BoundaryFront", (side * 9.0, 12.6, .36), (12.0, .45, .72), "stucco", .03)
        collider("boundary_front", (side * 9.0, 12.6, .36), (12.0, .55, .8))
    info = {
        "name": "市集 / MARKET SQUARE",
        "spawn": [0, .12, 10.2],
        "spawn_yaw": 180.0,
        "camera": {"offset": [14, 18, 18], "size": 30.0, "min_zoom": 20.0,
                   "max_zoom": 42.0, "focus_height": .55},
        "environment": {"sun_rotation": [-44, -36, 0], "sun_color": "ffe3c3",
                        "sun_energy": 1.02, "ambient_color": "b6c5c5",
                        "ambient_energy": .48, "background": "1a2329",
                        "fog_density": .005},
        "lights": [
            {"id": "lane_w", "position": [-8.0, 3.7, .4], "color": "ffd7a2",
             "energy": 1.4, "range": 8.0},
            {"id": "lane_e", "position": [8.0, 3.7, .4], "color": "ffd7a2",
             "energy": 1.4, "range": 8.0},
            {"id": "shop", "position": [0, 3.2, -9.8], "color": "ffd0a0",
             "energy": 1.0, "range": 7.0},
        ],
    }
    join_scene("market_square")
    save_scene("market_square", info)


# ---------------------------------------------------------------------------
# 3. Villa courtyard
# ---------------------------------------------------------------------------
def build_villa_courtyard_legacy():
    stage_reset()
    box("Ground", (0, 0, -.08), (34, 26, .16), "turf", 0)
    box("Driveway", (-7.8, 5.0, .015), (5.0, 15.0, .05), "paving", .02)
    box("EntryPath", (-1.2, 5.2, .018), (2.0, 15.0, .05), "paving", .02)
    box("PoolDeck", (9.0, 3.8, .022), (8.2, 8.2, .06), "paving", .02)
    # Main house volume and a lower side/garage volume.
    box("VillaMain", (2.0, -7.5, 2.1), (13.0, 9.0, 4.2), "stucco", .04)
    box("VillaSide", (-8.0, -7.0, 2.6), (5.0, 7.0, 5.2), "stucco", .04)
    box("VillaMainRoof", (2.0, -7.5, 4.28), (14.2, 10.2, .22), "concrete_dark", .02)
    box("VillaSideRoof", (-8.0, -7.0, 5.28), (6.2, 8.2, .22), "concrete_dark", .02)
    # Front glazing and mullions.
    box("GlazingDark", (2.0, -2.96, 2.0), (7.0, .05, 2.7), "glass")
    for x in (-1.2, .8, 2.8, 4.8):
        box("Mullion", (x, -3.02, 2.0), (.07, .10, 2.8), "steel", .004)
    box("Transom", (2.0, -3.02, 2.95), (7.2, .07, .07), "steel", .004)
    # Door and canopy.
    box("FrontDoor", (5.8, -3.00, 1.10), (1.15, .08, 2.2), "wood", .012)
    box("DoorFrame", (5.8, -2.96, 2.24), (1.35, .12, .10), "steel", .006)
    box("DoorHandle", (6.22, -3.08, 1.08), (.06, .06, .09), "metal"
        if "metal" in MATS else "steel", .007)
    box("EntryCanopy", (5.8, -2.35, 3.05), (2.6, 1.4, .12), "roof", .015)
    for x in (4.6, 7.0):
        cyl("CanopyPost", (x, -1.75, 1.52), .055, 3.0, "steel", "Z", 8)
    box("EntryStep", (5.8, -1.95, .10), (2.7, .55, .18), "foundation", .012)
    # Garage door on the side volume.
    box("GarageDoor", (-8.0, -3.48, 1.30), (3.6, .08, 2.6), "roof", .015)
    for z in (.40, .95, 1.50, 2.05):
        box("GarageRib", (-8.0, -3.54, z), (3.5, .035, .08), "steel", .004)
    # Timber slat screen.
    for i in range(12):
        box("TimberSlat", (7.2 + i * .10, -3.14, 2.15), (.045, .06, 3.2),
            "wood", .003)
    box("SlatFrame", (7.85, -3.12, 2.15), (1.5, .10, .10), "steel", .004)
    # House sign.
    box("VillaSign", (-3.0, -3.00, 3.55), (2.0, .06, .55), "roof", .006)
    text_sign("VillaSignText", "VILLA  07", (-3.0, -3.06, 3.56), .26, "lane")
    collider("villa_main", (2.0, -7.5, 2.1), (13.2, 9.2, 4.3))
    collider("villa_side", (-8.0, -7.0, 2.6), (5.2, 7.2, 5.3))
    # Pool.
    box("PoolCoping", (9.3, 3.7, .06), (7.3, 4.8, .12), "pool_tile", .02)
    box("PoolWater", (9.3, 3.7, .13), (6.7, 4.2, .03), "pool", 0)
    box("PoolInner", (9.3, 3.7, .02), (6.8, 4.3, .03), "concrete_dark", 0)
    for x in (5.75, 12.85):
        box("PoolEdge", (x, 3.7, .10), (.18, 5.0, .20), "pool_tile", .01)
    for y in (1.25, 6.15):
        box("PoolEdge", (9.3, y, .10), (7.4, .18, .20), "pool_tile", .01)
    collider("pool", (9.3, 3.7, .2), (7.4, 4.9, .4))
    # Loungers and parasol.
    for x in (6.6, 8.4):
        box("Lounger", (x, 8.3, .46), (.75, 1.9, .12), "wood_light", .02)
        box("LoungerBack", (x, 7.25, .80), (.75, .65, .12), "wood_light", .02,
            rotation=(.55, 0, 0))
        for d in (-.32, .32):
            for y in (7.55, 9.05):
                box("LoungerLeg", (x + d, y, .22), (.06, .06, .44), "steel", .004)
    cyl("ParasolPole", (10.8, 8.4, 1.45), .045, 2.9, "metal"
        if "metal" in MATS else "steel", "Z", 8)
    cyl("ParasolRoof", (10.8, 8.4, 2.90), 1.35, .12, "awning_b", "Z", 8, False)
    box("OutdoorTable", (2.7, 7.6, .76), (2.0, .9, .08), "wood_light", .012)
    for x in (1.9, 3.5):
        box("TableLeg", (x, 7.6, .38), (.10, .10, .76), "steel", .004)
    for x in (1.6, 3.8):
        box("ChairSeat", (x, 7.6, .48), (.55, .55, .08), "wood_light", .008)
        box("ChairBack", (x, 7.35, .78), (.55, .08, .62), "wood_light", .008)
    collider("outdoor_table", (2.7, 7.6, .45), (2.8, 1.2, .9))
    # Perimeter wall with a south gate.
    wall_h = 1.55
    for side in (-1, 1):
        box("BoundaryWall", (side * 16.0, 0, wall_h * .5), (.50, 24.0, wall_h),
            "stucco", .03)
        collider("boundary_side", (side * 16.0, 0, wall_h * .5), (.6, 24.0, wall_h))
    box("BoundaryBack", (0, -12.0, wall_h * .5), (32.0, .50, wall_h),
        "stucco", .03)
    collider("boundary_back", (0, -12.0, wall_h * .5), (32.0, .6, wall_h))
    # Front wall: a vehicle gate at the driveway and a pedestrian gate on the
    # entry path. This keeps both approach routes visually legible.
    for x0, x1 in [(-16.0, -10.2), (-5.6, -2.2), (0.2, 16.0)]:
        box("GateWall", ((x0 + x1) * .5, 12.0, wall_h * .5), (x1 - x0, .5, wall_h),
            "stucco", .03)
        collider("gate_wall", ((x0 + x1) * .5, 12.0, wall_h * .5),
                 (x1 - x0, .6, wall_h))
    for x in (-10.2, -5.6, -2.2, 0.2):
        box("GatePillar", (x, 12.0, 1.15), (.55, .55, 2.3), "concrete_dark", .02)
        collider("gate_pillar", (x, 12.0, 1.15), (.65, .65, 2.3))
    # Trees and hedges.
    tree("VillaTreeA", -13.0, 7.2, .95)
    tree("VillaTreeB", 12.7, -9.2, .90)
    tree("VillaTreeC", 12.8, 10.0, .78)
    for x in (-14.3, -12.0, 9.0, 13.8):
        box("Hedge", (x, 9.8, .60), (1.6, .8, 1.2), "hedge", .05)
        collider("hedge", (x, 9.8, .60), (1.7, .9, 1.3))
    box("GardenPlanter", (-5.0, 8.6, .35), (2.6, .8, .70), "foundation", .02)
    box("GardenSoil", (-5.0, 8.6, .72), (2.3, .55, .06), "soil")
    for i in range(7):
        ico("GardenPlant", (-6.0 + i * .32, 8.6, .92), .22, "hedge", (1, 1, 1.3))
    info = {
        "name": "别墅 / VILLA COURTYARD",
        "spawn": [-1.2, .12, 10.6],
        "spawn_yaw": 180.0,
        "camera": {"offset": [13, 18, 18], "size": 31.0, "min_zoom": 20.0,
                   "max_zoom": 44.0, "focus_height": .55},
        "environment": {"sun_rotation": [-42, -42, 0], "sun_color": "ffe0bd",
                        "sun_energy": 1.06, "ambient_color": "b8c7ca",
                        "ambient_energy": .50, "background": "1a2329",
                        "fog_density": .0045},
        "lights": [
            {"id": "door", "position": [5.8, 2.7, -1.6], "color": "ffd2a0",
             "energy": 1.3, "range": 6.0},
            {"id": "pool", "position": [9.3, .6, 3.7], "color": "8fdce7",
             "energy": .8, "range": 5.5},
        ],
    }
    join_scene("villa_courtyard")
    save_scene("villa_courtyard", info)


def build_villa_courtyard():
    """Enterable one-storey villa with a small lived-in interior."""
    stage_reset()
    box("Ground", (0, 0, -.08), (34, 26, .16), "turf", 0)
    box("Driveway", (-7.8, 5.2, .015), (5.0, 14.5, .05), "paving", .02)
    box("EntryPath", (-1.2, 5.2, .018), (2.0, 14.5, .05), "paving", .02)
    box("PoolDeck", (9.3, 3.7, .022), (8.2, 8.0, .06), "paving", .02)
    # Floor, walls and roof are deliberately separate groups for the cutaway.
    box("HouseFloor", (2.0, -7.5, .0), (13.0, 9.0, .09), "wood_light", 0)
    box("GarageFloor", (-7.5, -7.5, .0), (6.0, 7.0, .09), "foundation", 0)
    box("GarageBody", (-8.0, -7.0, 2.70), (5.0, 7.0, 5.4), "stucco", .035)
    box("GarageDoor", (-8.0, -3.46, 1.45), (3.6, .08, 2.9), "roof", .012)
    for z in (.35, .95, 1.55, 2.15, 2.75):
        box("GarageRib", (-8.0, -3.51, z), (3.5, .035, .08), "steel", .003)
    # Two-storey outer shell. The upper front/east glazing is separate so the
    # whole facade can be cut away while the player is inside.
    box("BackWall", (2.0, -12.0, 3.35), (13.2, .22, 6.70), "stucco", .02)
    box("WestWall", (-4.5, -7.5, 3.35), (.22, 9.2, 6.70), "stucco", .02)
    box("EastWall", (8.5, -7.5, 3.35), (.22, 9.2, 6.70), "stucco", .02)
    box("FrontWallLeft", (-3.15, -3.0, 3.35), (2.7, .22, 6.70), "stucco", .02)
    box("FrontSill", (3.95, -3.0, .32), (8.9, .22, .64), "stucco", .02)
    box("FrontHeader", (3.95, -3.0, 3.55), (8.9, .22, .42), "stucco", .02)
    box("FrontUpperWall", (3.95, -3.0, 5.18), (8.9, .22, 3.02), "stucco", .02)
    box("FrontUpperBand", (3.95, -2.84, 3.53), (8.9, .08, .16), "concrete_dark", .01)
    box("FrontUpperWindowA", (1.75, -2.83, 4.95), (2.55, .05, 1.55), "glass")
    box("FrontUpperWindowB", (6.10, -2.83, 4.95), (2.55, .05, 1.55), "glass")
    for x in (0.50, 1.72, 2.98, 4.85, 6.10, 7.35):
        box("FrontUpperMullion", (x, -2.79, 4.95), (.06, .06, 1.62),
            "steel", .003)
    box("FrontUpperSill", (3.95, -2.79, 4.14), (7.2, .08, .08), "steel", .004)
    box("EastUpperWindow", (8.63, -8.70, 4.95), (.05, 2.10, 1.55), "glass")
    box("EastUpperBand", (8.63, -7.50, 3.53), (.08, 9.0, .16),
        "concrete_dark", .01)
    box("FrontBalconySlab", (5.70, -2.08, 3.56), (4.1, 1.9, .18),
        "concrete_dark", .015)
    box("FrontBalconyFascia", (5.70, -1.18, 3.38), (4.2, .12, .30),
        "concrete_dark", .012)
    box("FrontBalconyGlass", (5.70, -1.22, 4.12), (4.05, .05, 1.00), "glass")
    box("FrontBalconyTop", (5.70, -1.22, 4.64), (4.12, .08, .07), "steel", .004)
    for x in (3.75, 5.70, 7.65):
        cyl("FrontBalconyPost", (x, -1.22, 4.12), .035, 1.0, "steel", "Z", 8)
    for x in (3.85, 7.55):
        box("FrontBalconyBracket", (x, -2.60, 3.30), (.10, .14, .55),
            "steel", .006, rotation=(.35, 0, 0))
    box("FrontBalconyDoor", (5.70, -2.81, 4.62), (1.55, .05, 2.05), "glass")
    box("FrontBalconyDoorFrame", (5.70, -2.77, 4.62), (1.72, .06, 2.18),
        "roof", .008)
    box("FrontTransom", (3.95, -3.04, 3.28), (8.9, .10, .10), "steel", .006)
    for x0, x1 in [(-.38, 1.30), (1.30, 2.98), (2.98, 4.66),
                   (4.66, 6.34), (6.34, 8.12)]:
        box("FrontGlazing", ((x0 + x1) * .5, -3.02, 1.95),
            (x1 - x0 - .035, .05, 2.95), "glass")
    for x in (-.38, 1.30, 2.98, 4.66, 6.34, 8.12):
        box("FrontMullion", (x, -3.07, 2.02), (.065, .11, 3.02), "steel", .004)
    box("DoorFrameL", (-1.85, -3.0, 1.95), (.11, .24, 3.9), "steel", .008)
    box("DoorFrameR", (-.55, -3.0, 1.95), (.11, .24, 3.9), "steel", .008)
    box("DoorFrameTop", (-1.2, -3.0, 3.86), (1.42, .24, .16), "steel", .008)
    box("EntryStep", (-1.2, -2.68, .06), (1.8, .60, .12), "foundation", .012)
    box("EntryCanopy", (-1.2, -2.18, 3.95), (2.4, 1.55, .12), "roof", .015)
    for x in (-2.10, -.30):
        cyl("CanopyPost", (x, -1.55, 1.98), .045, 3.9, "steel", "Z", 8)
    for i in range(10):
        box("TimberSlat", (7.27 + i * .13, -3.17, 2.08),
            (.045, .07, 3.35), "wood", .003)
    box("SlatFrame", (7.98, -3.13, 2.08), (1.55, .10, .10), "steel", .004)
    box("VillaSign", (-3.1, -3.02, 3.45), (2.1, .06, .50), "roof", .006)
    text_sign("VillaSignText", "VILLA  07", (-3.1, -3.08, 3.46), .25, "lane")
    box("VillaMainRoof", (2.0, -7.5, 6.82), (14.3, 10.3, .22), "concrete_dark", .02)
    box("VillaSideRoof", (-8.0, -7.0, 5.30), (6.2, 8.2, .22), "concrete_dark", .02)
    box("RoofEdgeMain", (2.0, -2.23, 6.75), (14.4, .18, .20), "steel", .006)
    # Interior partitions: one bedroom and one media wall.
    box("PartitionX_A", (2.2, -11.10, 1.55), (.16, 1.80, 3.0), "stucco", .012)
    box("PartitionX_B", (2.2, -8.75, 1.55), (.16, .90, 3.0), "stucco", .012)
    box("PartitionY_A", (3.40, -8.30, 1.55), (2.40, .16, 3.0), "stucco", .012)
    box("PartitionY_B", (7.05, -8.30, 1.55), (2.90, .16, 3.0), "stucco", .012)
    box("MediaWall", (2.15, -6.05, 1.35), (.16, 3.4, 2.55), "stucco", .012)
    # Living room.
    box("LivingRug", (-1.45, -5.65, .055), (2.9, 3.5, .02), "cloth", 0)
    box("SofaBase", (1.00, -6.00, .28), (.90, 2.45, .36), "cloth", .02)
    box("SofaBack", (1.45, -6.00, .72), (.22, 2.45, .95), "cloth", .03)
    box("SofaArmA", (1.00, -7.28, .58), (.90, .22, .55), "cloth", .03)
    box("SofaArmB", (1.00, -4.72, .58), (.90, .22, .55), "cloth", .03)
    for y in (-6.85, -6.00, -5.15):
        box("SofaCushion", (.88, y, .58), (.68, .74, .20), "linen", .025)
    box("CoffeeTableTop", (-1.55, -5.65, .48), (1.15, 1.65, .08), "wood_light", .01)
    for x in (-2.00, -1.10):
        for y in (-6.35, -4.95):
            box("CoffeeTableLeg", (x, y, .25), (.07, .07, .46), "steel", .006)
    box("TVConsole", (1.82, -6.05, .36), (.34, 2.0, .58), "wood", .02)
    box("TVScreen", (1.62, -6.05, 1.42), (.055, 1.65, .88), "roof", .01)
    box("TVStand", (1.62, -6.05, 1.35), (.12, .10, .10), "steel", .005)
    box("Bookshelf", (-4.25, -9.20, 1.15), (.38, 1.6, 2.2), "wood", .02)
    for z in (.32, .72, 1.12, 1.52, 1.92):
        box("BookshelfShelf", (-4.04, -9.20, z), (.04, 1.5, .05), "wood_light", .006)
        for i in range(5):
            box("Book", (-4.00, -9.75 + i * .25, z + .12), (.16, .16, .23),
                "cross" if i % 2 else "canvas", .004)
    box("FloorLampBase", (-3.9, -3.7, .10), (.34, .34, .08), "steel", .02)
    cyl("FloorLampPole", (-3.9, -3.7, 1.20), .035, 2.2, "steel", "Z", 8)
    cyl("FloorLampShade", (-3.9, -3.7, 2.25), .33, .38, "lamp", "Z", 10)
    # Dining area.
    box("DiningTop", (5.25, -5.45, .75), (1.75, 1.20, .08), "wood_light", .012)
    for x in (4.55, 5.95):
        for y in (-5.85, -5.05):
            box("DiningLeg", (x, y, .38), (.09, .09, .74), "steel", .006)
    for y in (-6.45, -4.45):
        for x in (4.65, 5.85):
            box("DiningChair", (x, y, .45), (.48, .48, .08), "wood", .012)
            box("DiningChairBack", (x, y + (-.22 if y < -5 else .22), .75),
                (.48, .07, .62), "wood", .012)
    # Kitchen.
    box("KitchenCounter", (-1.25, -11.65, .48), (5.7, .62, .88), "foundation", .02)
    box("KitchenTop", (-1.25, -11.65, .94), (5.8, .70, .08), "wood_light", .012)
    box("KitchenBack", (-1.25, -11.98, 1.72), (5.7, .10, 1.45), "cream", .01)
    for x in (-3.4, -2.2, -1.0, .2):
        box("KitchenDoor", (x, -11.29, .48), (.95, .04, .72), "wood", .006)
        box("KitchenHandle", (x + .30, -11.25, .58), (.04, .03, .14), "steel", .003)
    box("KitchenSink", (-2.75, -11.61, .98), (.75, .45, .03), "steel", .01)
    box("KitchenFaucet", (-2.75, -11.85, 1.15), (.05, .10, .28), "steel", .006)
    box("KitchenStove", (-.35, -11.61, .99), (.85, .50, .03), "roof", .01)
    for x in (-.65, -.35, -.05):
        cyl("StoveBurner", (x, -11.70, 1.02), .10, .02, "roof", "Z", 10)
    box("Fridge", (1.95, -11.55, 1.20), (.85, .75, 2.3), "white", .03)
    box("FridgeDoor", (1.95, -11.15, 1.20), (.78, .04, 2.1), "white", .01)
    box("FridgeHandle", (1.58, -11.10, 1.42), (.05, .06, .55), "steel", .006)
    box("KitchenIsland", (-1.3, -9.55, .52), (2.3, .95, .95), "wood", .02)
    box("IslandTop", (-1.3, -9.55, 1.02), (2.4, 1.05, .08), "wood_light", .012)
    for x in (-2.0, -1.3, -.6):
        cyl("BarStoolSeat", (x, -8.75, .72), .25, .08, "cloth", "Z", 12)
        cyl("BarStoolLeg", (x, -8.75, .36), .04, .65, "steel", "Z", 8)
    # Bedroom.
    box("BedBase", (5.55, -10.25, .26), (1.75, 2.15, .36), "wood", .025)
    box("BedMattress", (5.55, -10.25, .52), (1.65, 2.05, .26), "linen", .03)
    box("BedHeadboard", (5.55, -11.30, .90), (1.85, .12, 1.45), "wood", .02)
    box("BedPillowA", (4.98, -10.95, .70), (.58, .32, .16), "cream", .03)
    box("BedPillowB", (6.12, -10.95, .70), (.58, .32, .16), "cream", .03)
    box("BedDuvet", (5.55, -9.95, .66), (1.66, 1.18, .10), "canvas", .02)
    box("BedsideLeft", (4.30, -11.10, .38), (.55, .55, .55), "wood", .02)
    box("BedsideRight", (6.80, -11.10, .38), (.55, .55, .55), "wood", .02)
    cyl("BedLamp", (4.30, -11.10, .82), .22, .22, "lamp", "Z", 10)
    box("BedroomRug", (6.15, -9.90, .055), (2.55, 2.55, .02), "canvas", 0)
    box("Wardrobe", (8.05, -9.55, 1.25), (.55, 1.9, 2.4), "wood", .02)
    for y in (-10.10, -9.45, -8.80):
        box("WardrobeDoor", (7.75, y, 1.25), (.04, .58, 2.1), "wood_light", .006)
        box("WardrobeHandle", (7.70, y + .22, 1.25), (.03, .035, .20), "steel", .003)
    box("ArtFrame", (2.07, -4.85, 2.15), (.06, 1.25, .78), "roof", .01)
    box("ArtCanvas", (2.02, -4.85, 2.15), (.03, 1.10, .64), "canvas")
    for x, y in [(-3.9, -3.2), (4.3, -7.4), (7.9, -4.0)]:
        cyl("PlantPot", (x, y, .18), .22, .32, "rust", "Z", 10)
        ico("HousePlant", (x, y, .55), .35, "hedge", (1, 1, 1.25))
    box("DiningVase", (5.25, -5.45, .90), (.14, .14, .20), "white", .015)
    # Stair flight along the west wall.  The matching ramp collider is declared
    # in the layout so every viewer can actually climb it.
    for i in range(12):
        box("StairStep", (-3.60, -3.90 - i * .42, .145 + i * .287),
            (1.20, .44, .287), "wood_light", .008)
    box("StairStringer", (-4.20, -6.20, 1.72), (.12, 5.8, .16), "steel", .008,
        rotation=(-.60, 0, 0))
    # Upper floor, railings and loft furniture.  The whole group is hidden while
    # the player is downstairs so the isometric camera can see the ground floor.
    box("UpperFloorMain", (2.95, -7.50, 3.46), (11.10, 9.0, .16),
        "wood_light", .008)
    box("UpperFloorFrontStrip", (-3.55, -4.05, 3.46), (1.90, 2.10, .16),
        "wood_light", .008)
    box("UpperFloorBackStrip", (-3.55, -10.45, 3.46), (1.90, 3.10, .16),
        "wood_light", .008)
    box("UpperSubfloorEdge", (2.95, -2.95, 3.38), (11.2, .16, .12), "steel", .006)
    box("UpperRailingGlass", (-2.58, -7.00, 4.02), (.04, 3.80, 1.00), "glass")
    box("UpperRailingTop", (-2.58, -7.00, 4.54), (.08, 3.90, .07), "steel", .004)
    for z in (-8.85, -7.80, -6.75, -5.70):
        cyl("UpperRailingPost", (-2.58, z, 4.02), .035, 1.02, "steel", "Z", 8)
    box("UpperPartitionA", (2.20, -10.80, 4.62), (.16, 2.40, 2.30),
        "stucco", .012)
    box("UpperPartitionB", (2.20, -8.45, 4.62), (.16, .50, 2.30),
        "stucco", .012)
    box("UpperRug", (4.30, -6.60, 3.58), (3.3, 3.0, .02), "cloth", 0)
    box("UpperBedBase", (5.55, -10.28, 3.78), (1.80, 2.10, .36), "wood", .025)
    box("UpperMattress", (5.55, -10.28, 4.02), (1.68, 2.00, .24),
        "linen", .03)
    box("UpperHeadboard", (5.55, -11.30, 4.62), (1.90, .12, 1.55), "wood", .02)
    box("UpperPillowA", (4.98, -11.00, 4.18), (.60, .32, .16), "cream", .03)
    box("UpperPillowB", (6.12, -11.00, 4.18), (.60, .32, .16), "cream", .03)
    box("UpperDuvet", (5.55, -9.95, 4.16), (1.70, 1.20, .10), "canvas", .02)
    box("UpperWardrobe", (8.02, -10.10, 4.75), (.55, 1.85, 2.35), "wood", .02)
    for y in (-10.62, -9.98, -9.34):
        box("UpperWardrobeDoor", (7.72, y, 4.75), (.04, .55, 2.05),
            "wood_light", .006)
    box("UpperDesk", (0.40, -6.00, 4.18), (2.2, .85, .08), "wood_light", .012)
    for x in (-.40, 1.20):
        box("UpperDeskLeg", (x, -6.00, 3.82), (.08, .08, .72), "steel", .004)
    box("UpperDeskChair", (0.40, -5.15, 3.90), (.55, .55, .08), "cloth", .01)
    box("UpperDeskChairBack", (0.40, -4.80, 4.22), (.55, .08, .62), "cloth", .01)
    box("UpperShelf", (-2.10, -10.60, 4.35), (.35, 1.5, 1.8), "wood", .02)
    for z in (4.08, 4.48, 4.88):
        box("UpperShelfBoard", (-1.92, -10.60, z), (.04, 1.4, .05),
            "wood_light", .005)
    box("UpperLounge", (5.70, -4.50, 3.86), (.75, 1.75, .75), "cloth", .02)
    box("UpperLoungeBack", (6.05, -4.50, 4.22), (.20, 1.75, .80), "cloth", .02)
    cyl("UpperLampBase", (-2.05, -3.65, 3.62), .20, .10, "steel", "Z", 10)
    cyl("UpperLampPole", (-2.05, -3.65, 4.10), .03, 1.0, "steel", "Z", 8)
    cyl("UpperLampShade", (-2.05, -3.65, 4.68), .28, .35, "lamp", "Z", 10)
    for x, y in [(7.55, -3.55), (-2.10, -5.10)]:
        cyl("UpperPlantPot", (x, y, 3.68), .22, .30, "rust", "Z", 10)
        ico("UpperPlant", (x, y, 4.02), .34, "hedge", (1, 1, 1.25))
    # Pool and exterior lounge.
    box("PoolCoping", (9.3, 3.7, .06), (7.3, 4.8, .12), "pool_tile", .02)
    box("PoolWater", (9.3, 3.7, .13), (6.7, 4.2, .03), "pool", 0)
    for x in (5.75, 12.85):
        box("PoolEdge", (x, 3.7, .10), (.18, 5.0, .20), "pool_tile", .01)
    for y in (1.25, 6.15):
        box("PoolEdge", (9.3, y, .10), (7.4, .18, .20), "pool_tile", .01)
    for x in (6.6, 8.4):
        box("Lounger", (x, 8.3, .46), (.75, 1.9, .12), "wood_light", .02)
        box("LoungerBack", (x, 7.25, .80), (.75, .65, .12), "wood_light", .02,
            rotation=(.55, 0, 0))
        for d in (-.32, .32):
            for y in (7.55, 9.05):
                box("LoungerLeg", (x + d, y, .22), (.06, .06, .44), "steel", .004)
    cyl("ParasolPole", (10.8, 8.4, 1.45), .045, 2.9, "steel", "Z", 8)
    cyl("ParasolRoof", (10.8, 8.4, 2.90), 1.35, .12, "awning_b", "Z", 8, False)
    box("OutdoorTable", (2.7, 7.6, .76), (2.0, .9, .08), "wood_light", .012)
    for x in (1.9, 3.5):
        box("TableLeg", (x, 7.6, .38), (.10, .10, .76), "steel", .004)
    for x in (1.6, 3.8):
        box("ChairSeat", (x, 7.6, .48), (.55, .55, .08), "wood_light", .008)
        box("ChairBack", (x, 7.35, .78), (.55, .08, .62), "wood_light", .008)
    # Perimeter and landscaping.
    wall_h = 1.55
    for side in (-1, 1):
        box("BoundaryWall", (side * 16.0, 0, wall_h * .5), (.50, 24.0, wall_h),
            "stucco", .03)
        collider("boundary_side", (side * 16.0, 0, wall_h * .5), (.6, 24.0, wall_h))
    box("BoundaryBack", (0, -12.0, wall_h * .5), (32.0, .50, wall_h),
        "stucco", .03)
    collider("boundary_back", (0, -12.0, wall_h * .5), (32.0, .6, wall_h))
    for x0, x1 in [(-16.0, -10.2), (-5.6, -2.2), (0.2, 16.0)]:
        box("GateWall", ((x0 + x1) * .5, 12.0, wall_h * .5), (x1 - x0, .5, wall_h),
            "stucco", .03)
        collider("gate_wall", ((x0 + x1) * .5, 12.0, wall_h * .5),
                 (x1 - x0, .6, wall_h))
    for x in (-10.2, -5.6, -2.2, 0.2):
        box("GatePillar", (x, 12.0, 1.15), (.55, .55, 2.3), "concrete_dark", .02)
        collider("gate_pillar", (x, 12.0, 1.15), (.65, .65, 2.3))
    tree("VillaTreeA", -13.0, 7.2, .95)
    tree("VillaTreeB", 12.7, -9.2, .90)
    tree("VillaTreeC", 12.8, 10.0, .78)
    for x in (-14.3, -12.0, 9.0, 13.8):
        box("Hedge", (x, 9.8, .60), (1.6, .8, 1.2), "hedge", .05)
        collider("hedge", (x, 9.8, .60), (1.7, .9, 1.3))
    box("GardenPlanter", (-5.0, 8.6, .35), (2.6, .8, .70), "foundation", .02)
    box("GardenSoil", (-5.0, 8.6, .72), (2.3, .55, .06), "soil")
    for i in range(7):
        ico("GardenPlant", (-6.0 + i * .32, 8.6, .92), .22, "hedge", (1, 1, 1.3))
    # Collision for the enterable shell, with an open front door.
    collider("house_front_left", (-3.15, -3.0, 3.35), (2.7, .3, 6.7))
    collider("house_front_glass", (3.95, -3.0, 3.35), (8.9, .3, 6.7))
    collider("house_east", (8.5, -7.5, 3.35), (.3, 9.2, 6.7))
    collider("house_west", (-4.5, -7.5, 3.35), (.3, 9.2, 6.7))
    collider("house_back", (2.0, -12.0, 3.35), (13.2, .3, 6.7))
    collider("garage_body", (-8.0, -7.0, 2.7), (5.2, 7.2, 5.4))
    collider("partition_x_a", (2.2, -11.10, 1.5), (.25, 1.8, 3.0))
    collider("partition_x_b", (2.2, -8.75, 1.5), (.25, .9, 3.0))
    collider("partition_y_a", (3.40, -8.30, 1.5), (2.4, .25, 3.0))
    collider("partition_y_b", (7.05, -8.30, 1.5), (2.9, .25, 3.0))
    collider("media_wall", (2.15, -6.05, 1.3), (.25, 3.4, 2.6))
    collider("sofa", (1.00, -6.00, .55), (1.1, 2.8, 1.1))
    collider("coffee_table", (-1.55, -5.65, .40), (1.3, 1.8, .8))
    collider("dining_table", (5.25, -5.45, .48), (2.7, 2.5, .9))
    collider("kitchen_counter", (-1.25, -11.65, .55), (5.8, .8, 1.1))
    collider("kitchen_island", (-1.3, -9.55, .55), (2.5, 1.2, 1.1))
    collider("fridge", (1.95, -11.55, 1.2), (.9, .8, 2.4))
    collider("bed", (5.55, -10.25, .55), (1.9, 2.3, 1.1))
    collider("wardrobe", (8.05, -9.55, 1.25), (.7, 2.0, 2.5))
    collider("pool", (9.3, 3.7, .2), (7.4, 4.9, .4))
    collider("outdoor_table", (2.7, 7.6, .45), (2.8, 1.2, .9))
    collider("upper_floor_main", (2.95, -7.50, 3.46), (11.10, 9.0, .20))
    collider("upper_floor_front", (-3.55, -4.05, 3.46), (1.90, 2.10, .20))
    collider("upper_floor_back", (-3.55, -10.45, 3.46), (1.90, 3.10, .20))
    collider("upper_partition_a", (2.20, -10.80, 4.62), (.25, 2.40, 2.30))
    collider("upper_partition_b", (2.20, -8.45, 4.62), (.25, .50, 2.30))
    collider("upper_bed", (5.55, -10.28, 3.78), (1.9, 2.3, 1.0))
    collider("upper_wardrobe", (8.02, -10.10, 4.75), (.7, 2.0, 2.4))
    collider("upper_desk", (0.40, -6.00, 4.18), (2.3, .9, .8))
    collider("upper_railing", (-2.58, -7.00, 4.02), (.12, 3.9, 1.0))
    info = {
        "name": "别墅 / VILLA COURTYARD",
        "spawn": [-1.2, .12, 10.6],
        "spawn_yaw": 180.0,
        "camera": {"offset": [13, 18, 18], "size": 31.0, "min_zoom": 20.0,
                   "max_zoom": 44.0, "focus_height": .55,
                   "interior_size": 13.5,
                   "interior_focus": [2.0, 1.2, -7.4],
                   "upper_size": 13.5,
                   "upper_focus": [2.0, 4.55, -7.4]},
        "inside_bounds": {"min_x": -4.35, "max_x": 8.35,
                          "min_z": -11.85, "max_z": -3.15},
        "upper_y": 2.15,
        "cutaway": {"roof": "DD_Villa_Roof",
                     "front": "DD_Villa_FrontWall",
                     "east": "DD_Villa_EastWall",
                     "upper": "DD_Villa_UpperFloor"},
        "ramps": [],
        "stair_wedge": {"x0": -4.20, "x1": -3.00,
                        "z0": -3.00, "z1": -8.60,
                        "y0": -.20, "y1": 3.56},
        "environment": {"sun_rotation": [-42, -42, 0], "sun_color": "ffe0bd",
                        "sun_energy": 1.06, "ambient_color": "b8c7ca",
                        "ambient_energy": .50, "background": "1a2329",
                        "fog_density": .0045},
        "lights": [
            {"id": "living", "position": [-1.0, 2.6, -5.4], "color": "ffd2a0",
             "energy": 2.2, "range": 6.5},
            {"id": "kitchen", "position": [-1.2, 2.5, -10.2], "color": "ffd2a0",
             "energy": 1.5, "range": 5.0},
            {"id": "upper", "position": [2.0, 5.4, -7.4], "color": "ffd2a0",
             "energy": 2.0, "range": 6.5},
            {"id": "pool", "position": [9.3, .6, 3.7], "color": "8fdce7",
             "energy": .8, "range": 5.5},
        ],
    }
    join_villa_groups()
    save_scene("villa_courtyard", info)


def build_district_commons():
    """Roads, gate and street furniture binding the three plots together."""
    stage_reset()
    box("Ground", (0, 0, -.12), (100, 98, .16), "turf", 0)
    box("MainStreet", (0, 25.5, .020), (96, 7.0, .06), "tarmac", 0)
    box("SouthRoad", (0, 36.0, .020), (8.0, 14.0, .06), "tarmac", 0)
    box("Promenade", (0, 9.3, .018), (10.0, 25.0, .06), "paving", 0)
    box("CrossingPlaza", (0, 20.0, .024), (14.0, 8.0, .06), "paving", 0)
    for z in (21.5, 29.5):
        box("Sidewalk", (0, z, .045), (94.0, 1.2, .08), "paving", .012)
    box("SouthSidewalkW", (-4.8, 36.0, .045), (1.6, 14.0, .08), "paving", .012)
    box("SouthSidewalkE", (4.8, 36.0, .045), (1.6, 14.0, .08), "paving", .012)
    for i in range(9):
        x = -40.0 + i * 10.0
        box("LaneDash", (x, 25.5, .054), (4.0, .10, .008), "lane")
    for i in range(5):
        box("SouthLaneDash", (0, 30.5 + i * 2.6, .054), (.10, 1.3, .008), "lane")
    # Parking bay south-west of the market.
    box("ParkingBay", (-39.0, 36.0, .018), (18.0, 10.0, .05), "tarmac", 0)
    for i in range(4):
        box("ParkingLine", (-46.0 + i * 4.2, 36.0, .045), (.08, 9.0, .008), "lane")
    # South entrance.
    gate_z = 46.0
    for x in (-4.4, 4.4):
        box("GatePillar", (x, gate_z, 1.45), (.65, .65, 2.9), "stucco", .03)
        collider("gate_pillar", (x, gate_z, 1.45), (.8, .8, 2.9))
    box("GateBeam", (0, gate_z, 3.05), (9.4, .55, .22), "concrete_dark", .02)
    box("GateSignBoard", (0, gate_z - .32, 3.05), (7.4, .10, .62), "roof", .01)
    text_sign("DistrictSign", "NORTH DISTRICT  /  DISTRICT 07", (0, gate_z - .39, 3.05),
              .34, "lane")
    for x0, x1 in [(-49.0, -16.75), (-16.75, -7.25), (7.25, 16.75), (16.75, 49.0)]:
        box("BoundaryWall", ((x0 + x1) * .5, gate_z, .60), (x1 - x0, .35, 1.2),
            "stucco", .02)
        collider("boundary_south", ((x0 + x1) * .5, gate_z, .60),
                 (x1 - x0, .5, 1.2))
    # Outer boundary walls close the district beyond each plot.
    for x in (-49.0, 49.0):
        for z0, z1 in [(-48.0, 20.4), (30.6, 48.0)]:
            box("BoundaryWall", (x, (z0 + z1) * .5, 1.25), (.35, z1 - z0, 2.5),
                "stucco", .02)
            collider("boundary_side", (x, (z0 + z1) * .5, 1.25),
                     (.5, z1 - z0, 2.5))
        for z in (20.4, 30.6):
            box("SideGatePillar", (x, z, 1.55), (.70, .70, 3.1), "stucco", .02)
            collider("side_gate_pillar", (x, z, 1.55), (.85, .85, 3.1))
        box("SideGateBeam", (x, 25.5, 3.10), (.50, 10.2, .55),
            "concrete_dark", .02)
    box("BoundaryNorth", (0, -49.0, 1.25), (98.0, .35, 2.5), "stucco", .02)
    collider("boundary_north", (0, -49.0, 1.25), (98.0, .5, 2.5))
    # Street trees, lamps, bins and benches.
    for x in (-39.0, -15.0, 15.0, 39.0):
        tree("StreetTree", x, 30.0, .70)
    for x in (-32.0, -8.0, 8.0, 32.0):
        cyl("StreetLamp", (x, 29.7, 2.5), .09, 5.0, "steel", "Z", 8)
        for d in (-.25, 0, .25):
            box("LampHead", (x + d, 29.45, 4.95), (.22, .36, .14), "steel")
            box("LampLens", (x + d, 29.25, 4.95), (.16, .025, .09), "lamp")
        collider("street_lamp", (x, 29.7, 2.5), (.3, .3, 5.0))
    for x, y in [(-27.0, 30.2), (27.0, 30.2)]:
        box("DistrictBench", (x, y, .48), (2.1, .55, .10), "wood_light", .015)
        for d in (-.8, .8):
            box("BenchLeg", (x + d, y, .24), (.14, .45, .48), "steel", .006)
        collider("bench", (x, y, .3), (2.2, .7, .6))
    for x, y in [(-11.5, 31.5), (11.5, 31.5)]:
        cyl("Bin", (x, y, .38), .26, .76, "steel", "Z", 10)
        box("BinLid", (x, y, .78), (.38, .38, .06), "roof", .01)
        collider("bin", (x, y, .38), (.5, .5, .8))
    for x in (-5.8, 5.8):
        box("PromenadePlanter", (x, 8.0, .38), (1.2, 4.5, .66), "foundation", .03)
        box("PlanterSoil", (x, 8.0, .70), (1.0, 4.2, .06), "soil")
        for i in range(4):
            ico("PromenadePlant", (x, 6.4 + i * 1.1, .95), .26, "hedge",
                (1, 1, 1.2))
        collider("promenade_planter", (x, 8.0, .4), (1.4, 4.6, .8))
    # A small map board at the junction.
    for x in (-1.8, 1.8):
        cyl("MapPost", (x, 18.1, 1.0), .04, 2.0, "steel", "Z", 6)
    box("MapBoard", (0, 18.1, 2.0), (3.8, .10, 1.0), "roof", .01)
    text_sign("MapText", "TRACK  ↑   MARKET  ←   VILLA  →", (0, 18.02, 2.0),
              .16, "lane")
    info = {
        "name": "北区 / NORTH DISTRICT 07",
        "spawn": [0, .12, 40.0],
        "spawn_yaw": 180.0,
        "camera": {"offset": [24, 32, 30], "size": 58.0, "min_zoom": 32.0,
                   "max_zoom": 92.0, "focus_height": .60},
        "environment": {"sun_rotation": [-48, -35, 0], "sun_color": "ffe4c4",
                        "sun_energy": 1.03, "ambient_color": "b7c7cb",
                        "ambient_energy": .50, "background": "1c272d",
                        "fog_density": .0045},
        "lights": [
            {"id": "gate", "position": [0, 3.4, 44.0], "color": "ffd3a0",
             "energy": 1.4, "range": 8.0},
            {"id": "street_w", "position": [-20, 4.6, 28.8], "color": "ffd3a0",
             "energy": 1.1, "range": 7.0},
            {"id": "street_e", "position": [20, 4.6, 28.8], "color": "ffd3a0",
             "energy": 1.1, "range": 7.0},
        ],
    }
    join_scene("district_commons")
    save_scene("district_commons", info, register=False)
    return info


# ---------------------------------------------------------------------------
if __name__ == "__main__":
    if not bpy.app.background:
        raise RuntimeError("Background mode required")
    build_track_field()
    build_market_square()
    build_villa_courtyard()
    commons = build_district_commons()
    (DATA / "simple_locations.json").write_text(
        json.dumps({"version": 1, "locations": LAYOUTS}, indent=2,
                   ensure_ascii=False) + "\n", encoding="utf-8", newline="\n")
    placements = [
        {"asset": "district_commons", "position": [0, 0, 0]},
        {"asset": "track_field", "position": [0, 0, -25]},
        {"asset": "market_square", "position": [-23, 0, 8]},
        {"asset": "villa_courtyard", "position": [24, 0, 8]},
    ]
    villa = LAYOUTS["villa_courtyard"]
    b = villa["inside_bounds"]
    villa_world = {
        "position": [24, 0, 8],
        "inside_bounds": {
            "min_x": b["min_x"] + 24, "max_x": b["max_x"] + 24,
            "min_z": b["min_z"] + 8, "max_z": b["max_z"] + 8,
        },
        "interior_focus": [26.0, 1.25, .6],
        "interior_size": 13.5,
        "upper_focus": [26.0, 4.55, .6],
        "upper_size": 13.5,
        "upper_y": float(villa.get("upper_y", 2.15)),
        "cutaway": villa["cutaway"],
    }
    district = {
        "version": 1,
        "name": "北区 / NORTH DISTRICT 07",
        "spawn": [0, .12, 40.0],
        "spawn_yaw": 180.0,
        "camera": {"offset": [24, 32, 30], "size": 58.0, "min_zoom": 32.0,
                   "max_zoom": 92.0, "focus_height": .60},
        "environment": commons["environment"],
        "placements": placements,
        "module_layouts": "res://data/simple_locations.json",
        "commons_colliders": commons["colliders"],
        "lights": commons["lights"],
        "villa": villa_world,
    }
    (DATA / "district_layout.json").write_text(
        json.dumps(district, indent=2, ensure_ascii=False) + "\n",
        encoding="utf-8", newline="\n")
    print("DISTRICT_LAYOUT_OK", flush=True)
    print("SIMPLE_LOCATIONS_OK", flush=True)


