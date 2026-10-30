extends RefCounted
## Distance, storeys and audibility as pure functions.
##
## The point of keeping this out of the player node is testability: "how loud is
## a growl four metres away, and does the floor between us muffle it" has to be
## answerable without an audio device, a camera or a running scene.
##
## The curve is deliberately simple and readable in the mix: full volume inside
## `reference_distance`, then a fixed number of dB per doubling of distance, and
## hard silence past `max_distance`. A separate one-off penalty applies when the
## listener and the source are on different storeys, because a floor slab eats
## far more high frequency than four metres of open air does.
const FALLBACK := {
    "reference_distance": 3.0,
    "max_distance": 42.0,
    "rolloff_db": 7.0,
    "floor_db": -34.0,
    "floor_gap": 1.5,
    "floor_penalty_db": -12.0,
}

## Missing, absurd or hostile numbers fall back to something sane instead of
## producing NaN gains that silence the whole mix.
static func settings(source: Variant) -> Dictionary:
    var out: Dictionary = FALLBACK.duplicate()
    if source is Dictionary:
        for key in FALLBACK:
            var value: Variant = source.get(key)
            if (value is float or value is int) and is_finite(float(value)):
                out[key] = float(value)
    out.reference_distance = maxf(0.5, float(out.reference_distance))
    out.max_distance = maxf(float(out.reference_distance) + 1.0, float(out.max_distance))
    out.rolloff_db = clampf(float(out.rolloff_db), 0.0, 48.0)
    out.floor_db = clampf(float(out.floor_db), -120.0, 0.0)
    out.floor_gap = maxf(0.0, float(out.floor_gap))
    out.floor_penalty_db = clampf(float(out.floor_penalty_db), -60.0, 0.0)
    return out

## Top-down game: a storey is mostly "same XZ, different Y", so horizontal
## distance is what actually reads as far away.
static func planar_distance(from: Vector3, to: Vector3) -> float:
    return Vector2(from.x - to.x, from.z - to.z).length()

static func falloff_db(distance: float, space: Dictionary) -> float:
    var reference := float(space.get("reference_distance", FALLBACK.reference_distance))
    if not is_finite(distance) or distance <= reference:
        return 0.0
    var rolloff := float(space.get("rolloff_db", FALLBACK.rolloff_db))
    return -rolloff * (log(distance / reference) / log(2.0))

static func floor_db(from_y: float, to_y: float, space: Dictionary) -> float:
    if not is_finite(from_y) or not is_finite(to_y):
        return 0.0
    if absf(from_y - to_y) <= float(space.get("floor_gap", FALLBACK.floor_gap)):
        return 0.0
    return float(space.get("floor_penalty_db", FALLBACK.floor_penalty_db))

static func audible(distance: float, space: Dictionary) -> bool:
    if not is_finite(distance) or distance < 0.0:
        return false
    return distance < float(space.get("max_distance", FALLBACK.max_distance))

## Total gain in dB relative to the clip, floor clamped so a very distant source
## that is still technically audible never turns into a sub-audible -60 dB hiss.
static func level_db(distance: float, from_y: float, to_y: float, space: Dictionary) -> float:
    if not audible(distance, space):
        return -INF
    var total := falloff_db(distance, space) + floor_db(from_y, to_y, space)
    return maxf(float(space.get("floor_db", FALLBACK.floor_db)), total)
