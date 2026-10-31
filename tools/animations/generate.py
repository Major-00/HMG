#!/usr/bin/env python3
"""Fungo swing animations: builds the KeyframeSequences from readable pose specs.

Run from the repo root:  python3 tools/animations/generate.py

Writes
  assets/Animations/*.rbxmx               KeyframeSequences (Rojo syncs them to
                                          ReplicatedStorage.Animations; publish these)
  src/client/Modules/SwingData.luau       timing and contact points the client reads

Each pose is written in the batter's own frame ("B"): the batter stands side-on, a
right-handed hitter, chest toward -Z, the field toward -X (their left), +Y up, the root part
at the origin, the ground at y = -2.95. The character's root faces the field, so B is the root
turned 90 degrees to the right (the Root joint carries that turn).
For every pose the script solves the joints: legs reach planted feet (no foot sliding), both
arms reach the bat grip, the head looks at a target, the bat follows the hands. Visual only:
nothing here changes a result (CLAUDE.md guardrail 4).

Timing comes from src/shared/Config/Tuning.luau (Fungo.CONTACT_AT and each tier's hitStop), so
the "Contact" marker always sits at CONTACT_AT - hitStop and the ball always launches at
CONTACT_AT, the same at every tier.
"""

import json
import math
import os
import re

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
RIG = json.load(open(os.path.join(ROOT, "tools/animations/rig.json")))
OUT_DIR = os.path.join(ROOT, "assets/Animations")
DATA_OUT = os.path.join(ROOT, "src/client/Modules/SwingData.luau")

# --- vector / matrix math -------------------------------------------------------------------


def add(a, b):
    return (a[0] + b[0], a[1] + b[1], a[2] + b[2])


def sub(a, b):
    return (a[0] - b[0], a[1] - b[1], a[2] - b[2])


def mul(a, s):
    return (a[0] * s, a[1] * s, a[2] * s)


def dot(a, b):
    return a[0] * b[0] + a[1] * b[1] + a[2] * b[2]


def cross(a, b):
    return (a[1] * b[2] - a[2] * b[1], a[2] * b[0] - a[0] * b[2], a[0] * b[1] - a[1] * b[0])


def length(a):
    return math.sqrt(dot(a, a))


def unit(a):
    n = length(a)
    return (a[0] / n, a[1] / n, a[2] / n) if n > 1e-9 else (0.0, 0.0, 0.0)


def perp(a, axis):
    """a without its component along unit `axis`."""
    return sub(a, mul(axis, dot(a, axis)))


# 3x3 matrices as tuples of rows.
I3 = ((1, 0, 0), (0, 1, 0), (0, 0, 1))


def mm(a, b):
    return tuple(tuple(sum(a[i][k] * b[k][j] for k in range(3)) for j in range(3)) for i in range(3))


def mv(m, v):
    return tuple(sum(m[i][k] * v[k] for k in range(3)) for i in range(3))


def tr(m):
    return tuple(tuple(m[j][i] for j in range(3)) for i in range(3))


def from_cols(c0, c1, c2):
    return ((c0[0], c1[0], c2[0]), (c0[1], c1[1], c2[1]), (c0[2], c1[2], c2[2]))


def rx(deg):
    a = math.radians(deg)
    c, s = math.cos(a), math.sin(a)
    return ((1, 0, 0), (0, c, -s), (0, s, c))


def ry(deg):
    a = math.radians(deg)
    c, s = math.cos(a), math.sin(a)
    return ((c, 0, s), (0, 1, 0), (-s, 0, c))


def rz(deg):
    a = math.radians(deg)
    c, s = math.cos(a), math.sin(a)
    return ((c, -s, 0), (s, c, 0), (0, 0, 1))


def euler(yaw=0, pitch=0, roll=0):
    """Turn left by `yaw`, then lean forward by `pitch`, then tilt by `roll` (degrees)."""
    return mm(mm(ry(yaw), rx(-pitch)), rz(roll))


def frame_map(a0, b0, a1, b1):
    """Rotation taking unit a0 -> a1 and the perpendicular b0 -> b1."""
    c0 = (a0, b0, cross(a0, b0))
    c1 = (a1, b1, cross(a1, b1))
    return mm(from_cols(*c1), tr(from_cols(*c0)))


def look_at_rot(look, up=(0, 1, 0)):
    """Roblox CFrame.lookAt rotation: -Z column = look."""
    look = unit(look)
    right = unit(cross(look, up))
    if length(right) < 1e-6:
        right = (1, 0, 0)
    up2 = cross(right, look)
    return from_cols(right, up2, mul(look, -1))


class CF:
    def __init__(self, r=I3, p=(0, 0, 0)):
        self.r = r
        self.p = p

    def __mul__(self, o):
        return CF(mm(self.r, o.r), add(self.p, mv(self.r, o.p)))

    def inv(self):
        rt = tr(self.r)
        return CF(rt, mul(mv(rt, self.p), -1))

    def point(self, v):
        return add(self.p, mv(self.r, v))


def pos(p):
    return CF(I3, tuple(p))


# --- rig ------------------------------------------------------------------------------------

JOINTS = {name: (j[0], tuple(j[1]), tuple(j[2])) for name, j in RIG["joints"].items()}
GROUND_Y = -RIG["rootHeight"]
FOOT_HALF = RIG["footHalfHeight"]
ANKLE_Y = GROUND_Y + 2 * FOOT_HALF  # ankle joint height with the foot flat (foot c1 y = 0.125)

# The bat's Motor6D: same grip as BatPose.grip(BatPose.READY, false) in shared/BatPose.luau.
HANDLE_LENGTH = 1.8
BAT_READY = (0.55, 1, 0.45)


def bat_c0():
    d = unit(BAT_READY)
    return pos((0, -0.1, 0)) * CF(look_at_rot(d)) * CF(ry(90)) * pos((HANDLE_LENGTH / 2 - 0.3, 0, 0))


BAT_C0 = bat_c0()
LEFT_HAND_BELOW = 0.3  # the bottom (left) hand sits this far down the handle (at the knob)
SWEET_SPOT = 2.45  # studs from the bat part's centre along the bat to the barrel's sweet spot

# The root faces the field; the batter's frame B is that turned 90 degrees right.
B_TO_ROOT = ry(-90)


def b2r(v):
    return mv(B_TO_ROOT, v)


def r2b(v):
    """Root space (right +X, forward -Z) to B."""
    return mv(ry(90), v)


# --- solver ---------------------------------------------------------------------------------

ARM_U1 = sub(JOINTS["RightLowerArm"][1], JOINTS["RightUpperArm"][2])  # shoulder -> elbow
ARM_U2 = sub(JOINTS["RightHand"][1], JOINTS["RightLowerArm"][2])  # elbow -> wrist
LEG_U1 = sub(JOINTS["RightLowerLeg"][1], JOINTS["RightUpperLeg"][2])  # hip -> knee
LEG_U2 = sub(JOINTS["RightFoot"][1], JOINTS["RightLowerLeg"][2])  # knee -> ankle
MAX_SHOULDER_SHIFT = 0.5
warnings = []


def two_bone(u1, u2, bend_axis_rot, dist):
    """Bend angle (degrees, 0 = straight) so |u1 + R(bend) u2| == dist, clamped to what's reachable."""
    a, b = length(u1), length(u2)
    # |u1 + R u2|^2 = a^2 + b^2 + 2 u1.(R u2); u1.(R u2) = a b cos(theta) for these straight bones
    c = (dist * dist - a * a - b * b) / (2 * a * b)
    c = max(-1.0, min(1.0, c))
    return math.degrees(math.acos(c))


def solve_arm(side, ut, wrist_target, hand_rot, pole, label):
    """Transforms for <side>UpperArm, LowerArm, Hand reaching wrist_target (root space)."""
    up_name, low_name, hand_name = f"{side}UpperArm", f"{side}LowerArm", f"{side}Hand"
    c0 = JOINTS[up_name][1]
    shoulder = ut.point(c0)
    to_t = sub(wrist_target, shoulder)
    d = length(to_t)
    reach_max = length(ARM_U1) + length(ARM_U2)
    reach_min = abs(length(ARM_U2) - length(ARM_U1))
    want = min(max(d, reach_min + 0.02), reach_max - 0.01)
    shift_world = (0, 0, 0)
    miss = 0.0
    if abs(d - want) > 1e-6:
        # move the shoulder (in the torso) toward or away from the target, a little
        amount = max(-MAX_SHOULDER_SHIFT, min(MAX_SHOULDER_SHIFT, d - want))
        shift_world = mul(unit(to_t), amount)
        shoulder = add(shoulder, shift_world)
        to_t = sub(wrist_target, shoulder)
        d = length(to_t)
    miss = abs(d - want)
    bend = two_bone(ARM_U1, ARM_U2, None, max(min(d, reach_max - 1e-4), reach_min + 1e-4))
    re = rx(bend)  # forearm bends forward (-Z) about +X
    v = add(ARM_U1, mv(re, ARM_U2))
    a0 = unit(v)
    b0 = unit(perp((0, 0, 1), a0))  # the back of the arm: where the elbow points
    a1 = unit(to_t)
    b1 = unit(perp(pole, a1))
    if length(b1) < 1e-6:
        b1 = unit(perp((0, 0, 1), a1))
    r_world = frame_map(a0, b0, a1, b1)
    # Upper arm transform in the torso's frame (C0 has no rotation).
    r_local = mm(tr(ut.r), r_world)
    shift_local = mv(tr(ut.r), shift_world)
    t_up = CF(r_local, shift_local)
    upper = ut * pos(c0) * t_up * pos(JOINTS[up_name][2]).inv()
    t_low = CF(re)
    lower = upper * pos(JOINTS[low_name][1]) * t_low * pos(JOINTS[low_name][2]).inv()
    t_hand = CF(mm(tr(lower.r), hand_rot))
    hand = lower * pos(JOINTS[hand_name][1]) * t_hand * pos(JOINTS[hand_name][2]).inv()
    return {up_name: t_up, low_name: t_low, hand_name: t_hand}, hand, miss


def solve_leg(side, lt, foot, label):
    """Transforms for <side>UpperLeg, LowerLeg, Foot planting the foot (B-space spec)."""
    up_name, low_name, foot_name = f"{side}UpperLeg", f"{side}LowerLeg", f"{side}Foot"
    fx, fz = foot["at"]
    lift = foot.get("lift", 0)
    # "toe": degrees the heel is up (pivoting on the toe); euler's pitch tips the toe down
    foot_rot = mm(B_TO_ROOT, euler(foot.get("yaw", 0), foot.get("toe", 0), 0))
    if foot.get("toe", 0) > 0:
        # Heel up, pivoting on the toe: the toe stays where it was.
        toe_local = (0, -FOOT_HALF, -0.5)
        flat_rot = mm(B_TO_ROOT, euler(foot.get("yaw", 0), 0, 0))
        toe_world = add(b2r((fx, GROUND_Y + FOOT_HALF + lift, fz)), mv(flat_rot, toe_local))
        center = sub(toe_world, mv(foot_rot, toe_local))
    else:
        center = b2r((fx, GROUND_Y + FOOT_HALF + lift, fz))
    ankle = add(center, mv(foot_rot, JOINTS[foot_name][2]))
    c0 = JOINTS[up_name][1]
    hip = lt.point(c0)
    to_a = sub(ankle, hip)
    d = length(to_a)
    reach_max = length(LEG_U1) + length(LEG_U2)
    if d > reach_max - 0.005:
        warnings.append(f"{label}: {side} leg overreaches by {d - reach_max:.2f} (foot would slide)")
    inner = two_bone(LEG_U1, LEG_U2, None, max(min(d, reach_max - 1e-4), 0.8))
    knee = inner
    rk = rx(-knee)  # shin goes back (+Z) about -X
    v = add(LEG_U1, mv(rk, LEG_U2))
    a0 = unit(v)
    b0 = unit(perp((0, 0, -1), a0))  # front of the thigh: where the knee points
    a1 = unit(to_a)
    knee_dir = foot.get("knee")
    if knee_dir is None:
        knee_dir = mv(foot_rot, (0, 0, -1))
    else:
        knee_dir = b2r(knee_dir)
    b1 = unit(perp(knee_dir, a1))
    r_world = frame_map(a0, b0, a1, b1)
    t_up = CF(mm(tr(lt.r), r_world))
    upper = lt * pos(c0) * t_up * pos(JOINTS[up_name][2]).inv()
    t_low = CF(rk)
    lower = upper * pos(JOINTS[low_name][1]) * t_low * pos(JOINTS[low_name][2]).inv()
    t_foot = CF(mm(tr(lower.r), foot_rot))
    return {up_name: t_up, low_name: t_low, foot_name: t_foot}


def solve_neck(ut, look_at_b):
    head_joint = ut.point(JOINTS["Head"][1])
    d_world = unit(sub(b2r(look_at_b), head_joint))
    d = mv(tr(ut.r), d_world)
    yaw = math.degrees(math.atan2(-d[0], -d[2]))
    pitch = math.degrees(math.asin(max(-1, min(1, d[1]))))
    yaw = max(-75, min(75, yaw))
    pitch = max(-55, min(55, pitch))
    return CF(mm(ry(yaw), rx(pitch)))


def bat_rot(direction_b, up_hint_b):
    x = unit(b2r(direction_b))
    y = unit(perp(b2r(up_hint_b), x))
    if length(y) < 1e-6:
        y = unit(perp(b2r((0, 0, 1)), x))
    return from_cols(x, y, cross(x, y))


def torso(p):
    """Root and Waist transforms and the lower/upper torso frames (root space) for a spec."""
    root_shift = b2r(p.get("root", (0, 0, 0)))
    hips = p.get("hips", (0, 0, 0))  # yaw, pitch, roll in B
    t_root = CF(mm(B_TO_ROOT, euler(*hips)), root_shift)
    lt = CF() * pos(JOINTS["LowerTorso"][1]) * t_root * pos(JOINTS["LowerTorso"][2]).inv()
    t_waist = CF(euler(*p.get("waist", (0, 0, 0))))
    ut = lt * pos(JOINTS["UpperTorso"][1]) * t_waist * pos(JOINTS["UpperTorso"][2]).inv()
    return t_root, t_waist, lt, ut


def torso_relative(p):
    """Turns "gripT"/"batT"/"batUpT" (in the upper torso's own frame: right +X, up +Y, chest -Z)
    into the B-space "grip"/"bat"/"batUp" the solver uses."""
    if "gripT" not in p and "batT" not in p:
        return p
    p = dict(p)
    _, _, _, ut = torso(p)
    if "gripT" in p:
        p["grip"] = r2b(ut.point(p.pop("gripT")))
    if "batT" in p:
        p["bat"] = r2b(mv(ut.r, unit(p.pop("batT"))))
    if "batUpT" in p:
        p["batUp"] = r2b(mv(ut.r, p.pop("batUpT")))
    return p


def solve_pose(p, label):
    """p: pose spec in B space. Returns ({part: CF transform}, contact point in root space)."""
    p = torso_relative(p)
    t = {}
    t["LowerTorso"], t["UpperTorso"], lt, ut = torso(p)

    for side, key in (("Left", "front"), ("Right", "back")):
        t.update(solve_leg(side, lt, p[key], label))

    # Bat and hands. The right (top) hand holds the bat; its centre is at `grip`. With both hands
    # on the bat, the left (bottom) hand goes at the knob of the bat the right hand actually
    # holds; if the left arm can't reach it, the grip moves toward the left shoulder and both
    # arms are solved again.
    rbat = bat_rot(p["bat"], p.get("batUp", (0, 1, 0)))
    hand_rot = mm(rbat, tr(BAT_C0.r))
    grip = b2r(p["grip"])
    left = p.get("left", "bat")
    right_pole = b2r(p.get("rightElbow", (0.3, -1, 0.5)))
    left_pole = b2r(p.get("leftElbow", (-0.3, -1, 0.3)))
    for _ in range(4):
        wrist = CF(hand_rot, grip).point(JOINTS["RightHand"][2])
        r_arms, right_hand, r_miss = solve_arm("Right", ut, wrist, hand_rot, right_pole, label)
        if left == "bat":
            bat_dir = mv((right_hand * BAT_C0).r, (1, 0, 0))
            lgrip = sub(right_hand.p, mul(bat_dir, LEFT_HAND_BELOW))
            lhand_rot = right_hand.r
        elif "rotm" in left:
            lgrip = b2r(left["at"])
            lhand_rot = left["rotm"]
        else:
            lgrip = b2r(left["at"])
            lhand_rot = mm(B_TO_ROOT, euler(*left.get("rot", (0, 0, 0))))
        lwrist = CF(lhand_rot, lgrip).point(JOINTS["LeftHand"][2])
        l_arms, _, l_miss = solve_arm("Left", ut, lwrist, lhand_rot, left_pole, label)
        if left != "bat" or l_miss <= 0.08:
            break
        shoulder = ut.point(JOINTS["LeftUpperArm"][1])
        grip = add(grip, mul(unit(sub(shoulder, lgrip)), l_miss))
    t.update(r_arms)
    t.update(l_arms)
    if r_miss > 0.12:
        warnings.append(f"{label}: right hand misses its grip by {r_miss:.2f}")
    if left == "bat" and l_miss > 0.12:
        warnings.append(f"{label}: left hand misses the bat by {l_miss:.2f}")

    t["Head"] = solve_neck(ut, p["look"])

    spin = p.get("spin", 0)
    t["Bat"] = CF(rz(spin)) if spin else CF()
    bat_cf = right_hand * BAT_C0 * t["Bat"]
    contact = bat_cf.point((SWEET_SPOT, 0, 0))
    return t, contact


# --- keyframe sequences -----------------------------------------------------------------------

HIERARCHY = {
    "HumanoidRootPart": ["LowerTorso"],
    "LowerTorso": ["UpperTorso", "LeftUpperLeg", "RightUpperLeg"],
    "UpperTorso": ["Head", "LeftUpperArm", "RightUpperArm"],
    "LeftUpperArm": ["LeftLowerArm"],
    "LeftLowerArm": ["LeftHand"],
    "RightUpperArm": ["RightLowerArm"],
    "RightLowerArm": ["RightHand"],
    "RightHand": ["Bat"],
    "LeftUpperLeg": ["LeftLowerLeg"],
    "LeftLowerLeg": ["LeftFoot"],
    "RightUpperLeg": ["RightLowerLeg"],
    "RightLowerLeg": ["RightFoot"],
}
UPPER_BODY = {"UpperTorso", "Head", "LeftUpperArm", "LeftLowerArm", "LeftHand", "RightUpperArm",
              "RightLowerArm", "RightHand", "Bat"}
PRIORITY = {"Idle": 0, "Movement": 1, "Action": 2, "Action2": 3, "Action3": 4, "Action4": 5}
EASE_STYLE = {"Linear": 0, "Constant": 1, "Elastic": 2, "Cubic": 3, "Bounce": 4}
EASE_DIR = {"In": 0, "Out": 1, "InOut": 2}
_ref = [0]


def ref():
    _ref[0] += 1
    return f"RBX{_ref[0]:06d}"


def cf_xml(cf):
    r = cf.r
    vals = [cf.p[0], cf.p[1], cf.p[2], r[0][0], r[0][1], r[0][2], r[1][0], r[1][1], r[1][2], r[2][0], r[2][1], r[2][2]]
    names = ["X", "Y", "Z", "R00", "R01", "R02", "R10", "R11", "R12", "R20", "R21", "R22"]
    return "".join(f"<{n}>{v:.5f}</{n}>" for n, v in zip(names, vals))


def pose_xml(name, transforms, animated, ease):
    cf = transforms.get(name, CF())
    weight = 1 if name in animated else 0
    style, direction = ease
    children = "".join(pose_xml(c, transforms, animated, ease) for c in HIERARCHY.get(name, []))
    return (
        f'<Item class="Pose" referent="{ref()}"><Properties>'
        f'<string name="Name">{name}</string>'
        f'<CoordinateFrame name="CFrame">{cf_xml(cf)}</CoordinateFrame>'
        f'<token name="EasingDirection">{EASE_DIR[direction]}</token>'
        f'<token name="EasingStyle">{EASE_STYLE[style]}</token>'
        f'<float name="Weight">{weight}</float>'
        f"</Properties>{children}</Item>"
    )


def write_kfs(name, keyframes, loop, priority, animated):
    """keyframes: list of (time, transforms, markers, ease)."""
    items = []
    for time, transforms, markers, ease in keyframes:
        marker_xml = "".join(
            f'<Item class="KeyframeMarker" referent="{ref()}"><Properties>'
            f'<string name="Name">{m}</string><string name="Value"></string></Properties></Item>'
            for m in markers
        )
        items.append(
            f'<Item class="Keyframe" referent="{ref()}"><Properties>'
            f'<string name="Name">Keyframe</string><float name="Time">{time:.4f}</float></Properties>'
            f'{pose_xml("HumanoidRootPart", transforms, animated, ease)}{marker_xml}</Item>'
        )
    xml = (
        '<roblox xmlns:xmime="http://www.w3.org/2005/05/xmlmime" '
        'xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" '
        'xsi:noNamespaceSchemaLocation="http://www.roblox.com/roblox.xsd" version="4">'
        f'<Item class="KeyframeSequence" referent="{ref()}"><Properties>'
        f'<string name="Name">{name}</string>'
        f'<bool name="Loop">{"true" if loop else "false"}</bool>'
        f'<token name="Priority">{PRIORITY[priority]}</token>'
        f'<float name="AuthoredHipHeight">2</float>'
        f"</Properties>{''.join(items)}</Item></roblox>\n"
    )
    with open(os.path.join(OUT_DIR, f"{name}.rbxmx"), "w") as f:
        f.write(xml)


ALL_PARTS = set(JOINTS) | {"Bat"}

# --- timing from Tuning -----------------------------------------------------------------------

tuning = open(os.path.join(ROOT, "src/shared/Config/Tuning.luau")).read()
fungo = tuning[tuning.index("Fungo = {"):]
CONTACT_AT = float(re.search(r"CONTACT_AT = ([0-9.]+)", fungo).group(1))
HIT_STOPS = [float(x) for x in re.findall(r"hitStop = ([0-9.]+)", fungo)]
assert len(HIT_STOPS) == 5, "expected 5 swing tiers in Tuning.Fungo.TIERS"

# --- the poses (B space; see the module docstring) ------------------------------------------

FEET_FRONT = (-1.2, 0.05)
FEET_BACK = (1.2, 0.05)
LOOK_FIELD = (-12, 1.5, -3)


def stance(breath=0.0, sway=0.0):
    return {
        "root": (0.05 + sway, -0.3 - breath * 0.3, 0),
        "hips": (-5, 4, 0),
        "waist": (-12, 8 + breath * 6, 0),
        "front": {"at": FEET_FRONT, "yaw": -15},
        "back": {"at": FEET_BACK, "yaw": 5},
        "grip": (0.45, 0.35 + breath * 0.5, -0.95),
        "bat": (0.45, 0.62, 0.64),
        "batUp": (0.4, 0.5, -1),
        "look": LOOK_FIELD,
    }


# The swing's core, shaped per tier:
#   lift: front knee lift at the load (studs); coil: hips turned back at the load (degrees);
#   fire: hips open at contact; finish: the follow-through pose for the tier.
TIERS = [
    {"name": "Pop", "lift": 0.15, "coil": 14, "fire": 38},
    {"name": "Solid", "lift": 0.28, "coil": 20, "fire": 45},
    {"name": "Crush", "lift": 0.4, "coil": 26, "fire": 52},
    {"name": "Blast", "lift": 0.55, "coil": 31, "fire": 58},
    {"name": "Launch", "lift": 0.7, "coil": 36, "fire": 64},
]
CONTACT_GRIP = (-0.25, -0.45, -1.2)
CONTACT_BAT = (0.12, 0.06, -1)


def toss_pose(tier):
    return {
        "root": (0.0, -0.45, 0),
        "hips": (-3, 6, 0),
        "waist": (-10, 6, 0),
        "front": {"at": FEET_FRONT, "yaw": -15},
        "back": {"at": FEET_BACK, "yaw": 5},
        "grip": (0.6, 0.6, -0.65),
        "bat": (0.3, 0.86, 0.42),
        "batUp": (0.4, 0.4, -1),
        "left": {"at": (-0.35, 0.55, -1.25), "rot": (0, 0, -20)},
        "leftElbow": (-0.6, -1, 0.2),
        "look": (-0.6, 3.0, -2.6),
    }


def load_pose(tier):
    return {
        "root": (0.35, -0.32, 0),
        "hips": (-tier["coil"], 4, -3),
        "waist": (-tier["coil"] * 0.6 - 8, 6, 0),
        "front": {"at": (-0.9, 0.0), "lift": tier["lift"], "yaw": -10, "toe": 12,
                  "knee": (0.2, 0.3, -1)},
        "back": {"at": FEET_BACK, "yaw": 5},
        "grip": (0.75, 0.5, -0.45),
        "bat": (0.25, 0.78, 0.6),
        "batUp": (0.4, 0.3, -1),
        "look": (-0.4, 1.0, -2.8),
    }


def plant_pose(tier):
    return {
        "root": (0.0, -0.45, 0),
        "hips": (tier["fire"] * 0.5, 6, 0),
        "waist": (-tier["fire"] * 0.5 - 18, 8, 0),
        "front": {"at": (-1.45, 0.0), "yaw": -5},
        "back": {"at": FEET_BACK, "yaw": 5, "knee": (-0.3, 0, -1)},
        "grip": (0.55, 0.1, -0.7),
        "bat": (0.55, 0.42, 0.72),
        "batUp": (0.3, 0.5, -1),
        "look": (-0.3, -0.2, -2.8),
    }


def contact_pose(tier):
    return {
        "root": (-0.25, -0.5, 0),
        "hips": (tier["fire"], 8, 0),
        "waist": (18, 14, -4),
        "front": {"at": (-1.45, 0.0), "yaw": 5},
        "back": {"at": FEET_BACK, "yaw": 25, "toe": 10, "knee": (-0.5, 0, -1)},
        "grip": CONTACT_GRIP,
        "bat": CONTACT_BAT,
        "batUp": (0, 1, 0.1),
        "look": (0.0, -2.2, -3.0),
    }


def wrap_pose(tier):
    return {
        "root": (-0.4, -0.45, 0),
        "hips": (tier["fire"] + 18, 6, 0),
        "waist": (32, 6, -2),
        "front": {"at": (-1.45, 0.0), "yaw": 10},
        "back": {"at": FEET_BACK, "yaw": 55, "toe": 30, "knee": (-0.8, 0, -1)},
        "gripT": (-0.25, -0.25, -1.05),
        "batT": (-0.9, 0.15, 0.4),
        "batUpT": (0, 1, 0),
        "look": (-8, 0.5, -3),
    }


def finish_pose(tier, i):
    base = {
        "root": (-0.45, -0.5, 0),
        "front": {"at": (-1.45, 0.0), "yaw": 15},
        "back": {"at": FEET_BACK, "yaw": 80, "toe": 45, "knee": (-1, 0, -0.5)},
        "look": (-12, 2.5, -1),
    }
    # Hands in the upper torso's frame (both arms can reach in front of the chest); the bat
    # wraps over the front (left) shoulder, further for bigger tiers.
    if i == 0:  # Pop: short, low finish
        base.update(hips=(62, 4, 0), waist=(20, 4, 0), gripT=(-0.3, -0.15, -1.05), batT=(-0.85, 0.45, 0.3),
                    batUpT=(0, 1, 0))
        base["back"] = {"at": FEET_BACK, "yaw": 50, "toe": 25, "knee": (-0.7, 0, -1)}
    elif i == 1:  # Solid: over the front shoulder
        base.update(hips=(76, 2, 0), waist=(22, 0, 0), gripT=(-0.25, 0.25, -1.0), batT=(-0.6, 0.55, 0.6),
                    batUpT=(0, 1, 0))
    elif i == 2:  # Crush: full wrap behind the back, chest to the field
        base.update(hips=(88, 0, 0), waist=(18, -2, 0), gripT=(-0.15, 0.5, -0.9), batT=(-0.45, 0.45, 0.77),
                    batUpT=(0, 1, 0))
    elif i == 3:  # Blast: high wrap, leaning back
        base.update(hips=(94, -6, 0), waist=(16, -10, 0), gripT=(-0.05, 0.75, -0.85), batT=(-0.35, 0.3, 0.89),
                    batUpT=(0, 1, 0), look=(-12, 4, -1))
    else:  # Launch: right arm up, bat pointing at the sky, the other hand off the bat
        base.update(hips=(90, -4, 0), waist=(10, -8, 0), gripT=(0.95, 1.6, -0.35), bat=(0.05, 1, 0.08),
                    batUp=(-1, 0, 0), look=(-12, 6, -1), rightElbow=(1, 0, 0.3),
                    left={"at": (-1.6, 0.4, -0.6), "rot": (0, 0, -60)}, leftElbow=(-1, -0.5, 0))
    return base


def solve(spec, label):
    transforms, contact = solve_pose(spec, label)
    return transforms, contact


# --- baking: solve the pose at a steady rate, so hands stay on the bat and feet stay planted ---

BAKE_RATE = 30  # samples per second


def quat_from(m):
    t = m[0][0] + m[1][1] + m[2][2]
    if t > 0:
        s_ = math.sqrt(t + 1) * 2
        return ((m[2][1] - m[1][2]) / s_, (m[0][2] - m[2][0]) / s_, (m[1][0] - m[0][1]) / s_, s_ / 4)
    if m[0][0] > m[1][1] and m[0][0] > m[2][2]:
        s_ = math.sqrt(1 + m[0][0] - m[1][1] - m[2][2]) * 2
        return (s_ / 4, (m[0][1] + m[1][0]) / s_, (m[0][2] + m[2][0]) / s_, (m[2][1] - m[1][2]) / s_)
    if m[1][1] > m[2][2]:
        s_ = math.sqrt(1 + m[1][1] - m[0][0] - m[2][2]) * 2
        return ((m[0][1] + m[1][0]) / s_, s_ / 4, (m[1][2] + m[2][1]) / s_, (m[0][2] - m[2][0]) / s_)
    s_ = math.sqrt(1 + m[2][2] - m[0][0] - m[1][1]) * 2
    return ((m[0][2] + m[2][0]) / s_, (m[1][2] + m[2][1]) / s_, s_ / 4, (m[1][0] - m[0][1]) / s_)


def mat_from(q):
    x, y, z, w = q
    return ((1 - 2 * (y * y + z * z), 2 * (x * y - z * w), 2 * (x * z + y * w)),
            (2 * (x * y + z * w), 1 - 2 * (x * x + z * z), 2 * (y * z - x * w)),
            (2 * (x * z - y * w), 2 * (y * z + x * w), 1 - 2 * (x * x + y * y)))


def slerp_mat(a, b, t):
    qa, qb = quat_from(a), quat_from(b)
    d = sum(i * j for i, j in zip(qa, qb))
    if d < 0:
        qb = tuple(-i for i in qb)
        d = -d
    if d > 0.9995:
        q = tuple(i + (j - i) * t for i, j in zip(qa, qb))
    else:
        th = math.acos(d)
        sa, sb = math.sin((1 - t) * th) / math.sin(th), math.sin(t * th) / math.sin(th)
        q = tuple(i * sa + j * sb for i, j in zip(qa, qb))
    n = math.sqrt(sum(i * i for i in q))
    return mat_from(tuple(i / n for i in q))


def resolve_spec(p):
    """Fill every optional field so two specs can be blended."""
    p = torso_relative(dict(p))
    p.setdefault("root", (0, 0, 0))
    p.setdefault("hips", (0, 0, 0))
    p.setdefault("waist", (0, 0, 0))
    p.setdefault("batUp", (0, 1, 0))
    p.setdefault("rightElbow", (0.3, -1, 0.5))
    p.setdefault("leftElbow", (-0.3, -1, 0.3))
    p.setdefault("spin", 0)
    for key in ("front", "back"):
        f = dict(p[key])
        f.setdefault("lift", 0)
        f.setdefault("yaw", 0)
        f.setdefault("toe", 0)
        if f.get("knee") is None:
            f["knee"] = mv(euler(f["yaw"], 0, 0), (0, 0, -1))
        p[key] = f
    left = p.get("left", "bat")
    if left == "bat":
        d = unit(p["bat"])
        rbat = bat_rot(p["bat"], p["batUp"])
        p["left"] = {"at": sub(p["grip"], mul(d, LEFT_HAND_BELOW)), "rotm": mm(rbat, tr(BAT_C0.r)), "bat": True}
    else:
        p["left"] = {"at": left["at"], "rotm": mm(B_TO_ROOT, euler(*left.get("rot", (0, 0, 0)))), "bat": False}
    return p


def lerp(a, b, t):
    if isinstance(a, (int, float)):
        return a + (b - a) * t
    return tuple(i + (j - i) * t for i, j in zip(a, b))


def blend(a, b, t):
    out = {}
    for key in ("root", "hips", "waist", "grip", "look", "rightElbow", "leftElbow", "spin"):
        out[key] = lerp(a[key], b[key], t)
    for key in ("bat", "batUp"):
        out[key] = unit(lerp(unit(a[key]), unit(b[key]), t))
    for key in ("front", "back"):
        fa, fb = a[key], b[key]
        out[key] = {k: lerp(fa[k], fb[k], t) for k in ("at", "lift", "yaw", "toe")}
        out[key]["knee"] = unit(lerp(unit(fa["knee"]), unit(fb["knee"]), t))
    la, lb = a["left"], b["left"]
    out["left"] = {"at": lerp(la["at"], lb["at"], t), "rotm": slerp_mat(la["rotm"], lb["rotm"], t)}
    if la["bat"] and lb["bat"]:
        out["left"] = "bat"
    return out


def ease(style, t):
    if style == "in":  # speeding up (into contact)
        return t * t
    if style == "out":  # slowing down
        return 1 - (1 - t) * (1 - t)
    if style == "hold":
        return 0.0
    return t * t * (3 - 2 * t)  # smooth


def bake(keys, label, rate=BAKE_RATE):
    """keys: [(time, spec, markers, ease to next)]. Returns frames for write_kfs, and the solved
    contact point of the key that has the "Contact" marker."""
    keys = [(t, resolve_spec(sp), m, e) for t, sp, m, e in keys]
    frames, contact = [], None
    linear = ("Linear", "In")
    for i, (t0, a, markers, style) in enumerate(keys):
        transforms, point = solve(a, f"{label} @{t0:.3f}")
        if "Contact" in markers:
            contact = point
        frames.append((t0, transforms, markers, linear))
        if i + 1 == len(keys):
            break
        t1, b = keys[i + 1][0], keys[i + 1][1]
        steps = max(1, round((t1 - t0) * rate))
        for n in range(1, steps):
            u = n / steps
            spec = blend(a, b, ease(style, u))
            transforms, _ = solve(spec, f"{label} @{t0 + (t1 - t0) * u:.3f}")
            frames.append((t0 + (t1 - t0) * u, transforms, [], linear))
    return frames, contact


def main():
    os.makedirs(OUT_DIR, exist_ok=True)
    for f in os.listdir(OUT_DIR):
        if f.endswith(".rbxmx"):
            os.remove(os.path.join(OUT_DIR, f))

    # Stance: idle loop, whole body, Idle priority. The default walk and jump are Core priority
    # (below Idle), so SwingAnimator stops the stance while moving or in the air.
    frames, _ = bake([(0, stance(), [], "smooth"), (1.2, stance(breath=1, sway=0.05), [], "smooth"),
                      (2.2, stance(breath=0.3, sway=-0.04), [], "smooth"), (3.2, stance(), [], "smooth")], "Stance",
                     rate=4)
    write_kfs("FungoStance", frames, True, "Idle", ALL_PARTS)

    # Carry: walking with the bat on the shoulder, upper body only (the walk drives the legs).
    # Authored in the walking frame (root space: right +X, forward -Z), turned into B by r2b;
    # hips +90 in B undo the side-on turn so the torso faces where the player walks.
    def carry(lift):
        return {
            "root": (0, -0.3, 0), "hips": (90, 0, 0), "waist": (0, 0, 0),
            "front": {"at": (0, -0.5)}, "back": {"at": (0, 0.5)},
            "grip": r2b((0.75, 0.55 + lift, -0.5)), "bat": r2b((0.2, 0.75, 0.62)), "batUp": r2b((-0.4, 0.4, -1)),
            "left": {"at": r2b((-1.55, -0.8, -0.15)), "rot": (90, 0, 0)}, "leftElbow": r2b((-0.2, -1, 1)),
            "rightElbow": r2b((0.6, -1, 0.3)),
            "look": r2b((0, 1.2, -10)),
        }

    frames, _ = bake([(0, carry(0), [], "smooth"), (0.9, carry(0.05), [], "smooth"), (1.8, carry(0), [], "smooth")],
                     "Carry", rate=4)
    write_kfs("FungoCarry", frames, True, "Action", UPPER_BODY)

    data_tiers = []
    for i, tier in enumerate(TIERS):
        h = HIT_STOPS[i]
        t_contact = round(CONTACT_AT - h, 4)
        t_release, t_load, t_plant = 0.06, 0.13, 0.19
        if t_plant >= t_contact - 0.02:
            t_plant = t_contact - 0.03
            t_load = min(t_load, t_plant - 0.05)
        label = tier["name"]
        fin_spec = finish_pose(tier, i)
        keys = [
            (0.0, stance(), [], "smooth"),
            (t_release, toss_pose(tier), ["Release"], "smooth"),
            (t_load, load_pose(tier), [], "smooth"),
            (t_plant, plant_pose(tier), [], "in"),
            (t_contact, contact_pose(tier), ["Contact"], "hold" if h > 0 else "out"),
        ]
        if h > 0:
            keys.append((CONTACT_AT, contact_pose(tier), [], "out"))
        t_wrap = CONTACT_AT + 0.1
        t_finish = CONTACT_AT + 0.3
        keys.append((t_wrap, wrap_pose(tier), [], "out"))
        if i == 4:
            # Point at the sky, then flip the bat: one turn in the hand, in thirds so it spins
            # the long way round.
            keys.append((t_finish, fin_spec, [], "smooth"))
            for n, spin in enumerate((120, 240, 360), start=1):
                keys.append((t_finish + 0.1 * n, dict(fin_spec, spin=spin), ["Finish"] if n == 3 else [], "smooth"))
            t_end = t_finish + 0.3
        else:
            keys.append((t_finish, fin_spec, ["Finish"], "smooth"))
            t_end = t_finish
        # A tail after Finish, so the held pose is never the track's last instant.
        keys.append((t_end + 0.25, dict(fin_spec, spin=360 if i == 4 else 0), [], "smooth"))
        frames, contact = bake(keys, label)
        write_kfs(f"FungoSwing{label}", frames, False, "Action4", ALL_PARTS)
        data_tiers.append({"name": f"FungoSwing{label}", "release": t_release, "contact": t_contact,
                           "finish": t_end, "point": contact})

    write_data(data_tiers)
    for w in warnings:
        print("warning:", w)
    print(f"wrote {len(TIERS) + 2} animations; CONTACT_AT {CONTACT_AT}, hit-stops {HIT_STOPS}")


def write_data(tiers):
    lines = [
        "--!strict",
        "-- SwingData: GENERATED by tools/animations/generate.py; don't edit by hand.",
        "-- For each Fungo swing tier (Tuning.Fungo.TIERS order): its KeyframeSequence name, marker",
        "-- times (seconds from the tap) and where the bat meets the ball, in the root part's space",
        "-- with the root facing the field. Visual only.",
        "",
        "export type Tier = {",
        "\tname: string,",
        "\trelease: number, -- the glove hand lets go of the ball",
        "\tcontact: number, -- bat on ball: the hit-stop starts (the ball launches at Fungo.CONTACT_AT)",
        "\tfinish: number, -- the follow-through's last pose",
        "\tpoint: Vector3,",
        "}",
        "",
        "return {",
        '\tSTANCE = "FungoStance",',
        '\tCARRY = "FungoCarry",',
        "\tTIERS = {",
    ]
    for t in tiers:
        p = t["point"]
        lines.append(
            f'\t\t{{ name = "{t["name"]}", release = {t["release"]}, contact = {t["contact"]}, '
            f'finish = {round(t["finish"], 4)}, point = Vector3.new({p[0]:.3f}, {p[1]:.3f}, {p[2]:.3f}) }},'
        )
    lines += ["\t} :: { Tier },", "}", ""]
    with open(DATA_OUT, "w") as f:
        f.write("\n".join(lines))


if __name__ == "__main__":
    main()
