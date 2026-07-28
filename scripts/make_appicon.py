#!/usr/bin/env python3
"""Render the app icon from the OffiCraft brand mark.

The mark is the same geometry as `frontend/public/logo.svg`: three nodes with
two connectors, on the charcoal tile. Drawn here rather than checked in as a
binary so it stays in sync with the SVG and can be regenerated at any size.

Usage:  python3 scripts/make_appicon.py
"""

from PIL import Image, ImageDraw

SIZE = 1024
VIEWBOX = 24.0
SCALE = SIZE / VIEWBOX

BACKGROUND = (10, 10, 11)     # #0A0A0B
FOREGROUND = (255, 255, 255)

# Node centres and radius, in viewBox units.
NODES = [(12, 6), (6.5, 16), (17.5, 16)]
NODE_RADIUS = 2.2

# The two connectors, as polylines in viewBox units.
CONNECTORS = [
    [(12, 8), (12, 10.5), (7, 14.5)],
    [(12, 10.5), (17, 14.5)],
]
STROKE_WIDTH = 1.6

# Supersample, then downscale — Pillow has no built-in antialiasing for
# primitives, and the connectors are thin enough to alias badly without it.
SUPERSAMPLE = 4


# Fraction of the canvas the mark should span. The SVG fills its viewBox edge
# to edge, which is right for a 26pt sidebar glyph and too tight for a home
# screen icon, so the mark is inset and re-centred here.
MARK_SPAN = 0.62

# Bounding box of the mark in viewBox units, node radii and stroke included.
_MARK_MIN_X = min(x for x, _ in NODES) - NODE_RADIUS
_MARK_MAX_X = max(x for x, _ in NODES) + NODE_RADIUS
_MARK_MIN_Y = min(y for _, y in NODES) - NODE_RADIUS
_MARK_MAX_Y = max(y for _, y in NODES) + NODE_RADIUS
_MARK_WIDTH = _MARK_MAX_X - _MARK_MIN_X
_MARK_HEIGHT = _MARK_MAX_Y - _MARK_MIN_Y
_MARK_CENTRE = ((_MARK_MIN_X + _MARK_MAX_X) / 2, (_MARK_MIN_Y + _MARK_MAX_Y) / 2)


def to_px(point, scale):
    """viewBox point → pixel, inset and centred on the canvas."""
    canvas = SIZE * SUPERSAMPLE
    fit = canvas * MARK_SPAN / max(_MARK_WIDTH, _MARK_HEIGHT)
    return (
        canvas / 2 + (point[0] - _MARK_CENTRE[0]) * fit,
        canvas / 2 + (point[1] - _MARK_CENTRE[1]) * fit,
    )


def mark_scale() -> float:
    canvas = SIZE * SUPERSAMPLE
    return canvas * MARK_SPAN / max(_MARK_WIDTH, _MARK_HEIGHT)


def render(path: str) -> None:
    scale = mark_scale()
    canvas = Image.new("RGB", (SIZE * SUPERSAMPLE, SIZE * SUPERSAMPLE), BACKGROUND)
    draw = ImageDraw.Draw(canvas)

    width = STROKE_WIDTH * scale
    for polyline in CONNECTORS:
        points = [to_px(p, scale) for p in polyline]
        draw.line(points, fill=FOREGROUND, width=int(round(width)), joint="curve")
        # Round caps: Pillow's line() has none, so the ends get a disc.
        for point in (points[0], points[-1]):
            radius = width / 2
            draw.ellipse(
                [point[0] - radius, point[1] - radius,
                 point[0] + radius, point[1] + radius],
                fill=FOREGROUND,
            )

    for node in NODES:
        centre = to_px(node, scale)
        radius = NODE_RADIUS * scale
        draw.ellipse(
            [centre[0] - radius, centre[1] - radius,
             centre[0] + radius, centre[1] + radius],
            fill=FOREGROUND,
        )

    canvas.resize((SIZE, SIZE), Image.LANCZOS).save(path, "PNG")
    print(f"wrote {path} ({SIZE}x{SIZE})")


if __name__ == "__main__":
    import os
    target = os.path.join(
        os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
        "OffiCraft", "Resources", "Assets.xcassets", "AppIcon.appiconset", "icon-1024.png",
    )
    os.makedirs(os.path.dirname(target), exist_ok=True)
    render(target)
