#!/usr/bin/env python3
"""Keep delivered screenshots upright in every viewer.

An iPad screenshot taken through XCUITest stores a portrait pixel buffer and
records the rotation in EXIF instead (Orientation=8). Viewers disagree about
that tag: a browser rotates by it, other previewers ignore it, so one file
renders two ways. Rotating the pixels without clearing the tag does not fix
it -- it moves the tilt to the viewers that were previously right.

The rule this script enforces: a delivered PNG carries NO EXIF orientation
tag (or 1), so its pixels are the whole truth and no viewer has a choice to
make. `xcrun simctl io <udid> screenshot` already produces that shape; use it
for deliverables. `fix` is for files that came from somewhere else.

    check    <png...> [--expect landscape|portrait]  verify, exit 1 on failure
    fix      <png...> [--expect ...] [--tag-only]    rotate per tag, strip tag
    selftest                                         prove the rotations are right

Use --tag-only for a file whose pixels someone already turned by hand while
the tag stayed behind: the picture is right and only the tag is lying, so
rotating again would break it. Pair it with --expect, which is what proves
the pixels really were already right.

`selftest` exists because a wrong rotation is invisible to every other check
here: turning 90 degrees instead of 270 swaps the same dimensions and leaves
no tag behind, so the file passes while the picture is on its side. It builds
a fixture with four known corners, runs every supported orientation through
`fix`, and asserts where the corners landed. A review mutant that flipped
ROTATION_FOR went unnoticed by all the other guards; this is what catches it.

No third-party dependencies: EXIF parsing is done here, rotation via sips.
"""

import contextlib
import io
import os
import struct
import subprocess
import sys
import tempfile
import zlib

ORIENTATION_TAG = 0x0112

# Clockwise degrees that bring the stored buffer upright, per EXIF value.
# Mirrored orientations (2/4/5/7) are absent on purpose: a screenshot has no
# reason to be mirrored, so meeting one means an assumption broke and this
# script should stop rather than guess a rotation.
ROTATION_FOR = {1: 0, 3: 180, 6: 90, 8: 270}


def read_chunks(path):
    """Parse a PNG, refusing anything a real decoder would refuse.

    The CRC check is not pedantry: `strip_exif` rewrites every chunk, so a
    bug in that rewrite produces a file that opens nowhere. Without verifying
    here, this script would hand back an unreadable PNG and call it ok -- a
    review mutant that always wrote CRC 0 did exactly that.
    """
    data = open(path, "rb").read()
    if data[:8] != b"\x89PNG\r\n\x1a\n":
        raise ValueError(f"{path}: not a PNG")
    chunks = []
    i = 8
    while i < len(data):
        if i + 8 > len(data):
            raise ValueError(f"{path}: truncated chunk header")
        length = struct.unpack(">I", data[i : i + 4])[0]
        kind = data[i + 4 : i + 8]
        end = i + 8 + length
        if end + 4 > len(data):
            raise ValueError(f"{path}: truncated {kind.decode('latin1')} chunk")
        body = data[i + 8 : end]
        stored = struct.unpack(">I", data[end : end + 4])[0]
        if stored != crc32(kind + body):
            raise ValueError(f"{path}: bad CRC on {kind.decode('latin1')}")
        chunks.append((kind, body))
        i = end + 4
        if kind == b"IEND":
            break
    return chunks


def size_and_orientation(path):
    """Return (width, height, orientation or None)."""
    width = height = orientation = None
    for kind, body in read_chunks(path):
        if kind == b"IHDR":
            width, height = struct.unpack(">II", body[:8])
        elif kind == b"eXIf":
            orientation = orientation_in_exif(body)
    if width is None:
        raise ValueError(f"{path}: no IHDR")
    return width, height, orientation


def orientation_in_exif(exif):
    # PNG says an eXIf chunk holds the bare TIFF stream, but writers exist
    # that keep JPEG's "Exif\0\0" header. Skipping it costs nothing and the
    # alternative is the worst failure this script has: reporting "no
    # orientation tag" for a file that carries one, which is a green light
    # on precisely the thing the tool exists to stop.
    if exif[:6] == b"Exif\x00\x00":
        exif = exif[6:]
    if len(exif) < 8 or exif[:2] not in (b"MM", b"II"):
        return None
    byte_order = ">" if exif[:2] == b"MM" else "<"
    offset = struct.unpack(byte_order + "I", exif[4:8])[0]
    if offset + 2 > len(exif):
        return None
    count = struct.unpack(byte_order + "H", exif[offset : offset + 2])[0]
    for index in range(count):
        entry = offset + 2 + index * 12
        if entry + 12 > len(exif):
            return None
        tag = struct.unpack(byte_order + "H", exif[entry : entry + 2])[0]
        if tag == ORIENTATION_TAG:
            return struct.unpack(byte_order + "H", exif[entry + 8 : entry + 10])[0]
    return None


def strip_exif(path):
    """Drop the whole eXIf chunk. Screenshots keep nothing else in it worth
    saving, and rewriting a tag in place would mean re-encoding the IFD."""
    out = bytearray(b"\x89PNG\r\n\x1a\n")
    for kind, body in read_chunks(path):
        if kind == b"eXIf":
            continue
        out += struct.pack(">I", len(body)) + kind + body
        out += struct.pack(">I", crc32(kind + body))
    open(path, "wb").write(bytes(out))


def crc32(data):
    return zlib.crc32(data) & 0xFFFFFFFF


def decode_rgb(path):
    """Return (width, height, rows) for an 8-bit truecolour PNG.

    Only what the self-test fixture needs -- sips may re-encode with any
    filter, so all five filter types are handled, but interlacing, palettes
    and alpha are refused rather than guessed at.
    """
    width = height = None
    idat = b""
    for kind, body in read_chunks(path):
        if kind == b"IHDR":
            width, height, depth, colour, _, _, interlace = struct.unpack(">IIBBBBB", body[:13])
            if (depth, colour, interlace) != (8, 2, 0):
                raise ValueError(f"{path}: need 8-bit RGB, non-interlaced")
        elif kind == b"IDAT":
            idat += body
    raw = zlib.decompress(idat)
    stride = width * 3
    rows, previous = [], bytearray(stride)
    at = 0
    for _ in range(height):
        filter_type = raw[at]
        line = bytearray(raw[at + 1 : at + 1 + stride])
        at += 1 + stride
        for x in range(stride):
            left = line[x - 3] if x >= 3 else 0
            up = previous[x]
            upleft = previous[x - 3] if x >= 3 else 0
            if filter_type == 1:
                line[x] = (line[x] + left) & 0xFF
            elif filter_type == 2:
                line[x] = (line[x] + up) & 0xFF
            elif filter_type == 3:
                line[x] = (line[x] + (left + up) // 2) & 0xFF
            elif filter_type == 4:
                p = left + up - upleft
                pa, pb, pc = abs(p - left), abs(p - up), abs(p - upleft)
                best = left if (pa <= pb and pa <= pc) else (up if pb <= pc else upleft)
                line[x] = (line[x] + best) & 0xFF
            elif filter_type != 0:
                raise ValueError(f"{path}: unknown filter {filter_type}")
        rows.append(bytes(line))
        previous = line
    return width, height, rows


def exif_blob(orientation, flavour="MM"):
    """Build a one-tag EXIF stream in one of the encodings seen in the wild."""
    if flavour == "II":
        body = (
            b"II*\x00\x08\x00\x00\x00\x01\x00"
            + struct.pack("<HHIHH", ORIENTATION_TAG, 3, 1, orientation, 0)
            + b"\x00\x00\x00\x00"
        )
    else:
        body = (
            b"MM\x00*\x00\x00\x00\x08\x00\x01"
            + struct.pack(">HHIHH", ORIENTATION_TAG, 3, 1, orientation, 0)
            + b"\x00\x00\x00\x00"
        )
    return b"Exif\x00\x00" + body if flavour == "prefixed" else body


def encode_rgb(path, width, height, pixel_at, orientation, flavour="MM"):
    raw = b"".join(
        b"\x00" + b"".join(bytes(pixel_at(x, y)) for x in range(width)) for y in range(height)
    )
    exif = exif_blob(orientation, flavour)
    out = bytearray(b"\x89PNG\r\n\x1a\n")
    for kind, body in (
        (b"IHDR", struct.pack(">IIBBBBB", width, height, 8, 2, 0, 0, 0)),
        (b"eXIf", exif),
        (b"IDAT", zlib.compress(raw)),
        (b"IEND", b""),
    ):
        out += struct.pack(">I", len(body)) + kind + body + struct.pack(">I", crc32(kind + body))
    open(path, "wb").write(bytes(out))


RED, GREEN, BLUE, WHITE = (255, 0, 0), (0, 255, 0), (0, 0, 255), (255, 255, 255)

# Where each corner of the ORIGINAL picture must end up once `fix` has applied
# the rotation the tag asked for. Keys are EXIF orientation values; each value
# maps original corner -> corner it should occupy afterwards.
EXPECTED_CORNERS = {
    3: {"tl": "br", "tr": "bl", "bl": "tr", "br": "tl"},
    6: {"tl": "tr", "tr": "br", "br": "bl", "bl": "tl"},
    8: {"tl": "bl", "bl": "br", "br": "tr", "tr": "tl"},
}


def selftest():
    """Build a marked fixture, rotate it, and check the corners moved right."""
    failures = 0
    colours = {"tl": RED, "tr": GREEN, "bl": BLUE, "br": WHITE}
    width, height = 60, 40

    def pixel_at(x, y):
        vertical = "t" if y < height // 2 else "b"
        horizontal = "l" if x < width // 2 else "r"
        return colours[vertical + horizontal]

    with tempfile.TemporaryDirectory() as work:
        for orientation, expected in sorted(EXPECTED_CORNERS.items()):
            path = os.path.join(work, f"o{orientation}.png")
            encode_rgb(path, width, height, pixel_at, orientation)
            if fix([path]) != 0:
                failures += 1
                print(f"FAIL selftest orientation={orientation}: fix reported failure")
                continue
            got_width, got_height, rows = decode_rgb(path)

            def colour_at(corner):
                x = 1 if corner[1] == "l" else got_width - 2
                y = 1 if corner[0] == "t" else got_height - 2
                return tuple(rows[y][x * 3 : x * 3 + 3])

            wrong = [
                f"{source}->{target}"
                for source, target in expected.items()
                if colour_at(target) != colours[source]
            ]
            if wrong:
                failures += 1
                print(f"FAIL selftest orientation={orientation}: corners wrong ({', '.join(wrong)})")
            else:
                print(f"ok   selftest orientation={orientation}: corners land where they should")

        # A tag this parser cannot read is reported as no tag at all, which is
        # a green light on the one thing the tool exists to stop. Each byte
        # layout gets its own fixture so dropping support for one of them
        # fails here instead of in a delivered screenshot.
        for flavour in ("MM", "II", "prefixed"):
            path = os.path.join(work, f"exif-{flavour}.png")
            encode_rgb(path, width, height, pixel_at, 8, flavour)
            # These checks are meant to fail; letting their FAIL lines through
            # would put failures in the output of a passing run, which is how
            # people learn to skim past the word.
            with contextlib.redirect_stdout(io.StringIO()):
                rejected = check([path])
            if rejected == 0:
                failures += 1
                print(f"FAIL selftest exif-{flavour}: Orientation=8 was not seen")
            else:
                print(f"ok   selftest exif-{flavour}: Orientation=8 is seen")
    return 1 if failures else 0


def check(paths, expect=None):
    failures = 0
    for path in paths:
        try:
            width, height, orientation = size_and_orientation(path)
        except (ValueError, OSError) as unreadable:
            # A malformed file must be a named failure, not a traceback: this
            # runs as a delivery gate, and a stack trace in the middle of a
            # batch reads like the tool broke rather than the file.
            failures += 1
            print(f"FAIL {path}: unreadable ({unreadable})")
            continue
        problems = []
        if orientation not in (None, 1):
            problems.append(f"EXIF Orientation={orientation} (viewers will disagree)")
        if expect == "landscape" and width <= height:
            problems.append(f"pixels are not landscape ({width}x{height})")
        if expect == "portrait" and height <= width:
            problems.append(f"pixels are not portrait ({width}x{height})")
        if problems:
            failures += 1
            print(f"FAIL {path}: " + "; ".join(problems))
        else:
            print(f"ok   {path}: {width}x{height}, no orientation tag")
    return 1 if failures else 0


def fix(paths, expect=None, tag_only=False):
    """Apply the rotation the tag asks for, then drop the tag.

    Pass --expect when you know which way the picture should read. `fix`
    trusts the tag, and a file whose pixels were already turned by hand while
    the tag stayed behind will be turned a second time -- exactly the shape
    of the screenshots that were delivered before this script existed. The
    expectation is the only thing that tells those apart from an untouched
    capture, so without it a second rotation is written out silently.
    """
    failures = 0
    for path in paths:
        try:
            width, height, orientation = size_and_orientation(path)
        except (ValueError, OSError) as unreadable:
            failures += 1
            print(f"FAIL {path}: unreadable ({unreadable})")
            continue
        if orientation is None or orientation == 1:
            strip_exif(path)
            if check([path], expect) != 0:
                failures += 1
                continue
            print(f"ok   {path}: already upright ({width}x{height})")
            continue
        if orientation not in ROTATION_FOR and not tag_only:
            failures += 1
            print(f"FAIL {path}: EXIF Orientation={orientation} is mirrored, not rotating")
            continue
        degrees = 0 if tag_only else ROTATION_FOR[orientation]
        try:
            if degrees:
                subprocess.run(
                    ["sips", "-r", str(degrees), path],
                    check=True,
                    stdout=subprocess.DEVNULL,
                    stderr=subprocess.DEVNULL,
                )
            strip_exif(path)
            new_width, new_height, left = size_and_orientation(path)
        except (ValueError, OSError, subprocess.CalledProcessError) as broke:
            failures += 1
            print(f"FAIL {path}: rotate/strip failed ({broke})")
            continue
        if left is not None:
            # The strip is the whole point; a survivor means the file still
            # renders two ways and must not be reported as fixed.
            failures += 1
            print(f"FAIL {path}: orientation tag survived the strip")
            continue
        if expect is not None and check([path], expect) != 0:
            failures += 1
            continue
        turned = "tag removed, pixels left alone" if tag_only else f"rotated {degrees} deg, tag removed"
        print(f"ok   {path}: {turned}, now {new_width}x{new_height}")
    return 1 if failures else 0


def main(argv):
    if len(argv) < 2 or argv[1] not in ("check", "fix", "selftest"):
        print(__doc__)
        return 2
    command, rest = argv[1], argv[2:]
    if command == "selftest":
        if rest:
            print("selftest takes no arguments")
            return 2
        return selftest()
    tag_only = "--tag-only" in rest
    if tag_only:
        if command != "fix":
            print("--tag-only only applies to fix")
            return 2
        rest = [item for item in rest if item != "--tag-only"]
    expect = None
    if "--expect" in rest:
        at = rest.index("--expect")
        if at + 1 >= len(rest):
            print("--expect needs a value")
            return 2
        expect = rest[at + 1]
        rest = rest[:at] + rest[at + 2 :]
        if expect not in ("landscape", "portrait"):
            print(f"unknown --expect {expect}")
            return 2
    if not rest:
        print("no files given")
        return 2
    return check(rest, expect) if command == "check" else fix(rest, expect, tag_only)


if __name__ == "__main__":
    sys.exit(main(sys.argv))
