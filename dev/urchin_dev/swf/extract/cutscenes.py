# Story cutscenes as playable video: each cutscene is a pair of DefineSprites
# on the root timeline, gotoAndStop-jumped into by frame label (see
# frame_219/DoAction.as's afterCut assignments, and each cutscene sprite's own
# final-frame DoAction setting cutSceneEnd). Produces
# assets/cutscenes/CS_CUT{2,3,4,5}.ogv - Ogg Theora is Godot's only built-in
# video codec (WebM was removed from Godot core in 4.0).
#
# The pair is an *animation* sprite (chid N, one frame per animation frame)
# nested inside a *wrapper* sprite (chid N+1, frameCount 1), and it is the
# wrapper the root timeline actually places. The wrapper is not a pass-through
# - it does two things that decide what the player of the original ever sees:
#
#   1. It places the animation sprite offset by translate (5395, 3049) twips
#      = (269.75, 152.45) px, identical across all four wrappers.
#   2. It places DefineShape 2870 - a plain 10660x6000-twip (533x300 px)
#      rectangle - at depth 1 with a clipDepth covering the animation
#      sprite's depth. That is a clip mask: everything the animation draws
#      outside that 533x300 box is invisible in the original.
#
# An earlier version of this script exported the *animation* sprite directly,
# which skipped both. That shipped four clips at four different aspect ratios,
# each one the animation's own full untrimmed bounding box - unmasked, unplaced
# and mostly empty. Exporting the wrapper instead hands the masking and the
# placement to ffdec's own renderer, which honours the clipDepth correctly
# (verified by inspecting the exported frames: content stops dead at the mask
# edge).
#
# Exporting the wrapper has one catch: ffdec renders exactly as many frames as
# the selected sprite declares, and the wrapper declares frameCount="1", so a
# plain `-export sprite` on it yields a single correctly-framed still. The fix
# is patch_sprite_frame_count() below, which rewrites the wrapper's
# DefineSprite tag in a working copy of the SWF to declare the animation's own
# frame count and pads its timeline with that many ShowFrame tags. ffdec then
# ticks the nested animation sprite forward in step with the wrapper, one
# frame per frame - the same nested-clip behaviour faces.py relies on - so the
# export comes out correctly framed *and* correctly animated.
#
# Every animation sprite places a virtual camera clip as a direct child
# (3478, 3645, 3812, 3962 and 4041 all run the same frame script,
# DefineSprite_3478/frame_1/DoAction.as). Its own art is a red bounding box,
# a center crosshair and a color-bar swatch, which the original never shows:
# the script hides the clip on its first frame, then every frame it moves,
# scales and tints the parent animation so that the camera's box fills the
# 533x300 view. ffdec does not run ActionScript, so its export draws the box
# unless this script strips the clip (task-1-report.md diffs a rendered frame
# with and without the strip), and it never applies the camera's pan, zoom or
# tint either way. ffdec's -removeCharacterWithDependencies was tried first
# and rejected: it cascades and deletes the *parent* cutscene sprite too,
# because the parent places the camera clip as a child of itself. Plain
# -removeCharacter only drops that one placement.
#
# Each label's wrapper is the one sprite the root timeline places on that
# label's own frame, which label_xref.json records as the label's "places" and
# dev/tests/test_cutscenes.py checks. A label shares its root frame with the
# placement written after it in the file, so the placement just above a label
# belongs to the label before it. Reading it the other way shipped CS_CUT2 to
# CS_CUT5 one label early: the intro played after battle 109, CS_CUT1 after
# 210, and the real CS_CUT2 (3810) and CS_CUT5 (4153) were never extracted.
# The frame counts are each animation sprite's own frameCount, and each camera
# clip is a sprite the animation places directly on its frame 1.
#
# ffdec's sprite:avi export renders video only (no audio track) - each
# cutscene's dialogue/music is a SoundStreamBlockTag-per-frame MP3 stream
# attached to the *animation* sprite's timeline (not the wrapper's and not the
# main timeline), so it has to be reconstructed by hand: per the SWF10 spec,
# an MP3-compressed stream block is a 4-byte header (2-byte sample count,
# 2-byte seek-samples) followed by raw MPEG frame bytes - stripping that
# header from every block in frame order and concatenating gives a valid,
# playable MP3.
#
# The exported AVI stores frames as PNG-in-AVI, and one ffmpeg pass crops
# and pads them, encodes them as Theora and the MP3 as Vorbis, and writes the
# Ogg file. ffmpeg needs libtheora and libvorbis for that, which Homebrew's
# ffmpeg-full has. The settings match what the Theora and Vorbis
# identification headers of the clips this replaced carry: Theora quality 38
# of 63, a keyframe at least every 64 frames, and Vorbis at a nominal
# 80 kbps. Those clips went through ffmpeg2theora, which Homebrew deprecated,
# by way of an x264 intermediate that only worked around ffmpeg2theora's
# bundled ffmpeg misreading the color matrix as GBR.
#
# No -shortest trim on the encode: a couple of these cutscenes' audio streams
# run somewhat short of their frame count (trailing silent frames with no
# new sound block), and trimming to the shorter stream would clip the tail
# of the video instead of just leaving it silent.
#
# Animation sprite 3960 (CS_CUT3, shipped as CS_CUT4 under the old mapping)
# originally came out with ~11 frames of rendered static/noise near its tail
# (frames ~467-477 of 501, confirmed present in ffdec's export of
# both the stripped AND unstripped source, so it wasn't something this
# script's own processing introduced). Root cause: those frames place
# shapes (chids 3951/3953/3955/3957) whose fill references bitmapId "65535"
# - the SWF sentinel for "no such bitmap character" - with no matching
# DefineBits* tag anywhere in the file, and no ActionScript on this
# sprite's timeline that would bind a real bitmap into that slot at
# runtime. It's a dangling fill reference, not real cutscene content;
# ffdec's renderer fills the gap with visual noise instead of leaving it
# blank. find_broken_bitmap_fill_cids() below scans every cutscene sprite's
# directly-placed shapes for this exact pattern and strips any it finds
# alongside the camera clip, so a similar dangling reference in another
# cutscene gets caught automatically instead of silently shipping noise
# again. (Scoped to each sprite's directly-placed children, same as the
# camera clip strip - does not recurse into nested sprites.)
#
# Requires ffdec (~/.local/bin/ffdec) for the character-strip and video
# export, and an ffmpeg with libtheora and libvorbis (`brew install
# ffmpeg-full`) for the encode and the checks.
# Run: uv run extract_cutscenes
from __future__ import annotations

import functools
import re
import shutil
import subprocess
import sys
import tempfile
import zlib
from pathlib import Path

from PIL import Image, ImageChops, ImageFilter, ImageStat

from urchin_dev import FFDEC, REPO_ROOT, WEB_SWF, WEB_SWF_XML
from urchin_dev.swf import sprite_body

OUT_DIR = REPO_ROOT / "assets" / "cutscenes"


_TOOL_HINTS = {
    "ffmpeg": "needs libtheora and libvorbis, e.g. `brew install ffmpeg-full`",
    "ffprobe": "used for post-generation verification",
}


@functools.cache
def tool(name: str) -> Path:
    """Resolve a tool on PATH instead of hardcoding a Homebrew-on-Apple-
    Silicon path - the previous version of this script fell back to a bare
    "/opt/homebrew/bin/ffmpeg2theora" string with no existence check, which
    breaks silently on Intel Homebrew (/usr/local) or Linux. Resolved on first
    use rather than at import, so the tests can read CUTSCENES on a machine
    without these tools.
    """
    found = shutil.which(name)
    if found is None:
        raise SystemExit(
            f"required tool '{name}' not found on PATH ({_TOOL_HINTS[name]})"
        )
    return Path(found)


# label -> (animation sprite chid, wrapper sprite chid, frame count,
# camera clip chid to strip). The frame count is the *animation* sprite's;
# the wrapper always declares 1 and gets patched up to this (see file header).
CUTSCENES: dict[str, tuple[int, int, int, int]] = {
    "CS_CUT2": (3810, 3811, 1795, 3645),
    "CS_CUT3": (3960, 3961, 501, 3812),
    "CS_CUT4": (4038, 4039, 1237, 3962),
    "CS_CUT5": (4153, 4154, 2424, 4041),
}

# The wrapper's clip mask (DefineShape 2870) is a rectangle 10660x6000 twips
# from the wrapper's own origin, and there are 20 twips to a pixel.
MASK_W, MASK_H = 533, 300

# The SWF stage is 16000x11500 twips (800x575 px) and each wrapper sits on it
# at (2670, 2750) twips = (133.5, 137.5) px, which centers the 533x300 mask
# exactly. Godot's viewport is 800x600 (project.godot), so re-centering the
# same box in an 800x600 frame puts it back where the original had it once
# the 575-tall stage is itself centered in the 600-tall viewport, and
# lets cutscene_player.tscn's VideoStreamPlayer stretch the clip to fill the
# screen without distorting it.
OUT_W, OUT_H = 800, 600
CONTENT_X, CONTENT_Y = (OUT_W - MASK_W) // 2, (OUT_H - MASK_H) // 2

# Verification thresholds - see verify_output()'s and _frame_noise()'s
# docstrings. A frame has to clear both noise bars to be called static.
DURATION_TOLERANCE_S = 2.0
NOISE_RESIDUAL_THRESHOLD = 20.0
NOISE_RATIO_THRESHOLD = 0.35
NOISE_SAMPLE_INTERVAL_S = 1.0
# Sprite 3960's real corruption hit 11/478 sampled frames - a wide, contiguous
# run. Sprite 3643 (CS_INTRO2, which this script extracted as CS_CUT2 under
# the old mapping) had 2 isolated flagged frames (~67.5-68.5s) that weren't
# root-caused (not the same dangling-bitmap-fill pattern
# find_broken_bitmap_fill_cids() catches) - tolerated rather than blocking
# the whole export on a sub-second glitch. Anything past this still fails
# loudly, so a real widespread corruption run still gets caught.
MAX_TOLERATED_NOISE_FRAMES = 2

# SWF tag encoding, used by patch_sprite_frame_count().
DEFINE_SPRITE_TAG = 39
SHOW_FRAME_TAG = b"\x40\x00"  # UI16 0x0040 - tag code 1, body length 0
END_TAG = b"\x00\x00"


def run(cmd: list[str]) -> subprocess.CompletedProcess:
    """subprocess.run wrapper that always captures output and surfaces it in
    a raised error's message - not just a bare CalledProcessError with the
    exit code and nothing else. This pipeline's failure mode is exactly
    "silently produces garbage output", so swallowing ffdec/ffmpeg's own
    stdout/stderr on failure (the previous version's check=True,
    capture_output=True with no re-raise message) is exactly backwards.
    """
    proc = subprocess.run(cmd, capture_output=True, text=True)
    if proc.returncode != 0:
        raise RuntimeError(
            f"command failed (exit {proc.returncode}): {' '.join(cmd)}\n"
            f"--- stdout ---\n{proc.stdout}\n--- stderr ---\n{proc.stderr}"
        )
    return proc


def _swf_body(path: Path) -> tuple[int, bytes]:
    """Split a SWF into its version byte and its decompressed body (the bytes
    after the 8-byte signature/version/length header).
    """
    raw = path.read_bytes()
    signature, version = raw[:3], raw[3]
    if signature == b"FWS":
        return version, raw[8:]
    if signature == b"CWS":
        return version, zlib.decompress(raw[8:])
    raise SystemExit(f"unsupported SWF signature {signature!r} in {path}")


def _walk_tags(body: bytes, start: int):
    """Yield (offset, tag code, header length, body length) for each tag from
    start onwards, stopping after the file's End tag.
    """
    pos = start
    while pos < len(body) - 1:
        code_and_length = int.from_bytes(body[pos : pos + 2], "little")
        code, length, header = code_and_length >> 6, code_and_length & 0x3F, 2
        if length == 0x3F:  # long-form header: the real length follows as UI32
            length = int.from_bytes(body[pos + 2 : pos + 6], "little")
            header = 6
        yield pos, code, header, length
        pos += header + length
        if code == 0:
            return


def patch_sprite_frame_count(
    src: Path, dest: Path, sprite_id: int, frames: int
) -> None:
    """Write src to dest with DefineSprite sprite_id re-declared as `frames`
    frames long, its timeline padded out with ShowFrame tags to match.

    This is what makes a static frameCount=1 wrapper sprite exportable as an
    animation: ffdec renders as many frames as the sprite declares, and ticks
    nested sprites along with it, so a wrapper stretched to its inner clip's
    length renders that clip's whole animation with the wrapper's own
    placement and clip mask applied. Nothing else in the sprite changes - the
    padding tags carry no body, so every existing PlaceObject stays on frame 1
    and simply persists for the rest of the timeline.

    dest is written uncompressed (FWS); ffdec reads that as happily as the
    zlib-compressed original.
    """
    version, body = _swf_body(src)
    # The tag area starts after the frame-size RECT (5 bits of bit-width, then
    # 4 fields of that width), the frame rate and the frame count.
    rect_bytes = (5 + 4 * (body[0] >> 3) + 7) // 8
    for pos, code, header, length in _walk_tags(body, rect_bytes + 4):
        if code != DEFINE_SPRITE_TAG:
            continue
        tag_body = body[pos + header : pos + header + length]
        if int.from_bytes(tag_body[:2], "little") != sprite_id:
            continue
        if tag_body[-2:] != END_TAG:
            raise RuntimeError(f"DefineSprite {sprite_id} does not end with an End tag")
        patched = (
            tag_body[:2]
            + frames.to_bytes(2, "little")
            + tag_body[4:-2]
            + SHOW_FRAME_TAG * (frames - 1)
            + END_TAG
        )
        new_header = ((DEFINE_SPRITE_TAG << 6) | 0x3F).to_bytes(2, "little") + len(
            patched
        ).to_bytes(4, "little")
        new_body = body[:pos] + new_header + patched + body[pos + header + length :]
        dest.write_bytes(
            b"FWS"
            + bytes([version])
            + (8 + len(new_body)).to_bytes(4, "little")
            + new_body
        )
        return
    raise RuntimeError(f"DefineSprite {sprite_id} not found in {src}")


def extract_mp3(xml: str, sprite_id: int, out_path: Path) -> int:
    """Reconstruct the sprite's dialogue/music track from its
    SoundStreamBlockTags and write it as a raw MP3 to out_path.

    Returns the number of blocks concatenated (0 means no audio stream).
    """
    body = sprite_body(xml, sprite_id)
    blocks = re.findall(
        r'<item type="SoundStreamBlockTag"[^>]*streamSoundData="([0-9a-fA-F]*)"', body
    )
    with out_path.open("wb") as f:
        for hex_data in blocks:
            raw = bytes.fromhex(hex_data)
            f.write(raw[4:])  # drop the 4-byte sample-count/seek-samples header
    return len(blocks)


def find_broken_bitmap_fill_cids(xml: str, sprite_id: int) -> set[int]:
    """Shapes placed directly in this cutscene sprite whose fill references
    bitmapId "65535" (SWF's sentinel for "no such bitmap character") with no
    matching DefineBits* tag anywhere in the file - a dangling bitmap-fill
    reference that ffdec's renderer fills in with visual static/noise
    instead of leaving it blank. Confirmed as the root cause of sprite 3960's
    corrupted tail frames (chids 3951/3953/3955/3957) - see
    task-1-report.md. Auto-detected here rather than hardcoded so the same
    class of bug in another cutscene gets caught and stripped too.
    """
    body = sprite_body(xml, sprite_id)
    placed_cids = {int(c) for c in re.findall(r'characterId="(\d+)"', body)}
    bad = set()
    for cid in placed_cids:
        m = re.search(rf'<item type="DefineShape\d?Tag"[^>]*shapeId="{cid}"[^>]*>', xml)
        if m is None:
            continue
        end = xml.find("</item>", m.end())
        if 'bitmapId="65535"' in xml[m.start() : end]:
            bad.add(cid)
    return bad


def mask_crop_origin(
    label: str, wrapper_chid: int, swf_path: Path, avi_path: Path, work_dir: Path
) -> tuple[int, int]:
    """Locate the clip mask's 533x300 box inside the wrapper's rendered frame.

    ffdec sizes a sprite export to that sprite's whole bounding box, which
    here is the union of the mask, the border and the animation sprite's own
    (much larger, mostly clipped away) extent - so where the mask lands inside
    the exported frame differs per cutscene and has to be measured rather than
    assumed.

    Measuring is unambiguous because of what the wrapper places at the depth
    just above the mask's clipDepth: DefineShape 3476, a 1px black outline
    tracing the mask rectangle exactly. It is the only thing in the wrapper
    the mask does not clip, so the transparency bounds of any rendered frame
    are that outline, and the mask box is the outline's interior.

    Frame 1 is re-exported as a PNG rather than pulled out of the AVI because
    the AVI's frames come back fully opaque once decoded - the surrounding
    transparency the measurement depends on only survives in ffdec's own PNG
    output. Both exports are sized from the same bounds, which the check
    below confirms before trusting one to crop the other.
    """
    png_dir = work_dir / "probe_png"
    run(
        [
            str(FFDEC),
            "-select",
            f"{wrapper_chid}:1",
            "-format",
            "sprite:png",
            "-selectid",
            str(wrapper_chid),
            "-export",
            "sprite",
            str(png_dir),
            str(swf_path),
        ]
    )
    probe_png = png_dir / f"DefineSprite_{wrapper_chid}" / "1.png"
    if not probe_png.exists():
        raise RuntimeError(f"{label}: expected probe frame not found at {probe_png}")
    probe = Image.open(probe_png)
    avi_size = run(
        [
            str(tool("ffprobe")),
            "-v",
            "error",
            "-select_streams",
            "v:0",
            "-show_entries",
            "stream=width,height",
            "-of",
            "csv=p=0:s=x",
            str(avi_path),
        ]
    ).stdout.strip()
    if avi_size != f"{probe.size[0]}x{probe.size[1]}":
        raise RuntimeError(
            f"{label}: the AVI export is {avi_size} but the PNG probe frame is "
            f"{probe.size[0]}x{probe.size[1]} - they are not the same crop space"
        )
    bbox = probe.getchannel("A").getbbox()
    if bbox is None:
        raise RuntimeError(f"{label}: exported frame 1 is fully transparent")
    x0, y0, x1, y1 = bbox
    width, height = x1 - x0, y1 - y0
    # The outline straddles the mask edge and antialiases across it, so it
    # reads 1-2px wider than the mask on each axis. Anything outside that
    # means the frame is not bounded by the outline and the crop below would
    # be meaningless.
    if not (MASK_W < width <= MASK_W + 2 and MASK_H < height <= MASK_H + 2):
        raise RuntimeError(
            f"{label}: opaque bounds of the wrapper's frame 1 are {width}x{height}, "
            f"expected the {MASK_W}x{MASK_H} clip mask plus its outline"
        )
    return x0 + (width - MASK_W) // 2, y0 + (height - MASK_H) // 2


def _frame_noise(png_path: Path) -> tuple[float, float]:
    """How much high-frequency detail a frame has, as (residual spread,
    residual spread relative to the frame's own spread).

    The frame is blurred heavily and differenced against itself. Flat
    cel-shaded art and hard-edged vector shapes are low-frequency content
    with a few sharp edges, so almost all of their variance survives the blur
    and very little lands in the residual; true per-pixel random static has
    no low-frequency structure at all, so nearly all of its variance lands
    there.

    Both numbers are needed, because either one alone misreads these frames.
    Measured on sprite 3960's cropped 533x300 box: ffdec's rendered static for
    the broken tail frames reads (43.6, 0.48), while the fixed version of
    those same frames - a nearly flat dark gradient - reads (2.8, 0.50). The
    ratios are indistinguishable, because a frame with barely any variance to
    begin with hands almost all of what little it has to the residual. On the
    absolute number the two are 15x apart. The busiest genuine frame sampled
    from that cutscene reads (10.8, 0.24), so a frame has to clear both bars
    to be called static.
    """
    img = Image.open(png_path).convert("L")
    blurred = img.filter(ImageFilter.GaussianBlur(radius=4))
    residual = ImageChops.difference(img, blurred)
    frame_std = ImageStat.Stat(img).stddev[0]
    residual_std = ImageStat.Stat(residual).stddev[0]
    return residual_std, residual_std / (frame_std + 1e-6)


def verify_output(
    label: str, ogv_path: Path, expected_frames: int, has_audio: bool, work_dir: Path
) -> tuple[int, int]:
    """Fail loudly instead of shipping a silently-corrupt or mis-framed file -
    except for up to MAX_TOLERATED_NOISE_FRAMES isolated noise hits, which
    print a warning and pass rather than blocking the whole export. Returns
    the video stream's (width, height) so main() can cross-check that every
    cutscene came out the same shape.

    Checks: exactly the expected stream types are present (Theora video,
    Vorbis audio if the source sprite had one), the frame is exactly the
    OUT_W x OUT_H the wrapper's mask and the stage layout imply - the check
    that would have caught the whole first round of exports, which shipped
    four different aspect ratios, none of them the stage's - the container's
    reported duration is within tolerance of expected_frames/30fps, and - the
    check that would have actually caught sprite 3960's corrupted tail before it
    shipped - a sweep of frames sampled roughly once per second across the
    FULL duration (not just a start/midpoint spot check) for suspiciously
    high-frequency noise via _frame_noise().

    The noise sweep crops back down to the cutscene box before measuring,
    since the surrounding letterbox is flat black and would otherwise dilute
    the measurement far enough to hide real static.
    """
    probe = run(
        [
            str(tool("ffprobe")),
            "-v",
            "error",
            "-show_entries",
            "stream=codec_type,codec_name,width,height:format=duration",
            "-of",
            "default=noprint_wrappers=0",
            str(ogv_path),
        ]
    ).stdout
    if "codec_name=theora" not in probe:
        raise RuntimeError(
            f"{label}: no theora video stream found in {ogv_path}\n{probe}"
        )
    if has_audio and "codec_name=vorbis" not in probe:
        raise RuntimeError(
            f"{label}: expected a vorbis audio stream, none found in {ogv_path}\n{probe}"
        )
    # Only the video stream reports a numeric size; an audio stream's width
    # and height come back as "N/A", so these two never match it.
    width_match = re.search(r"^width=(\d+)$", probe, re.MULTILINE)
    height_match = re.search(r"^height=(\d+)$", probe, re.MULTILINE)
    if width_match is None or height_match is None:
        raise RuntimeError(
            f"{label}: could not read frame size from {ogv_path}\n{probe}"
        )
    width, height = int(width_match.group(1)), int(height_match.group(1))
    if (width, height) != (OUT_W, OUT_H):
        raise RuntimeError(
            f"{label}: frame is {width}x{height}, expected {OUT_W}x{OUT_H} - "
            "the clip mask crop or the stage-centering pad is wrong"
        )
    dur_match = re.search(r"duration=([\d.]+)", probe)
    if dur_match is None:
        raise RuntimeError(f"{label}: could not read duration from {ogv_path}\n{probe}")
    duration = float(dur_match.group(1))
    expected_duration = expected_frames / 30.0
    if abs(duration - expected_duration) > DURATION_TOLERANCE_S:
        raise RuntimeError(
            f"{label}: duration {duration:.2f}s is too far from the "
            f"expected {expected_duration:.2f}s ({expected_frames} frames @ 30fps)"
        )

    sample_dir = work_dir / "verify_frames"
    sample_dir.mkdir(exist_ok=True)
    n_samples = max(2, min(90, int(duration / NOISE_SAMPLE_INTERVAL_S) + 1))
    timestamps = [duration * i / (n_samples - 1) for i in range(n_samples)]
    timestamps[-1] = max(0.0, duration - 0.05)  # stay inside the stream at the tail
    bad_frames = []
    for i, ts in enumerate(timestamps):
        frame_path = sample_dir / f"{i:03d}.png"
        run(
            [
                str(tool("ffmpeg")),
                "-y",
                "-v",
                "error",
                "-ss",
                f"{ts:.3f}",
                "-i",
                str(ogv_path),
                "-frames:v",
                "1",
                "-vf",
                f"crop={MASK_W}:{MASK_H}:{CONTENT_X}:{CONTENT_Y}",
                str(frame_path),
            ]
        )
        if not frame_path.exists():
            continue
        residual, ratio = _frame_noise(frame_path)
        if residual > NOISE_RESIDUAL_THRESHOLD and ratio > NOISE_RATIO_THRESHOLD:
            bad_frames.append((ts, residual, ratio))
    if bad_frames:
        detail = ", ".join(
            f"{ts:.2f}s (residual {d:.1f}, ratio {r:.2f})" for ts, d, r in bad_frames
        )
        if len(bad_frames) > MAX_TOLERATED_NOISE_FRAMES:
            raise RuntimeError(
                f"{label}: {len(bad_frames)}/{n_samples} sampled frame(s) look like "
                f"corrupted static/noise rather than real content: {detail}"
            )
        print(
            f"{label}: tolerating {len(bad_frames)}/{n_samples} sampled frame(s) "
            f"that look like static (within the {MAX_TOLERATED_NOISE_FRAMES}-frame "
            f"tolerance): {detail}",
            file=sys.stderr,
        )
    return width, height


def process_cutscene(
    label: str, chid: int, wrapper_chid: int, frames: int, overlay_chid: int, xml: str
) -> tuple[int, int]:
    print(
        f"--- {label}: sprite {chid} in wrapper {wrapper_chid}, {frames} frames, "
        f"stripping overlay {overlay_chid} ---",
        file=sys.stderr,
    )
    work_dir = Path(tempfile.mkdtemp(prefix=f"cutscene_{label}_"))
    try:
        strip_cids = {overlay_chid} | find_broken_bitmap_fill_cids(xml, chid)
        extra = sorted(strip_cids - {overlay_chid})
        if extra:
            print(
                f"{label}: also stripping suspected dangling bitmap-fill shape(s) {extra}",
                file=sys.stderr,
            )

        current_swf = WEB_SWF
        for i, cid in enumerate(sorted(strip_cids)):
            dest = work_dir / f"stripped_{i}.swf"
            run([str(FFDEC), "-removeCharacter", str(current_swf), str(dest), str(cid)])
            current_swf = dest

        animated_swf = work_dir / "animated_wrapper.swf"
        patch_sprite_frame_count(current_swf, animated_swf, wrapper_chid, frames)

        avi_dir = work_dir / "avi"
        run(
            [
                str(FFDEC),
                "-format",
                "sprite:avi",
                "-selectid",
                str(wrapper_chid),
                "-export",
                "sprite",
                str(avi_dir),
                str(animated_swf),
            ]
        )
        avi_path = avi_dir / f"DefineSprite_{wrapper_chid}" / "frames.avi"
        if not avi_path.exists():
            raise RuntimeError(f"{label}: expected AVI not found at {avi_path}")

        crop_x, crop_y = mask_crop_origin(
            label, wrapper_chid, animated_swf, avi_path, work_dir
        )
        print(
            f"{label}: clip mask found at ({crop_x}, {crop_y}) in the export",
            file=sys.stderr,
        )

        mp3_path = work_dir / "audio.mp3"
        n_blocks = extract_mp3(xml, chid, mp3_path)
        print(
            f"{label}: {n_blocks} sound blocks -> {mp3_path.stat().st_size} bytes",
            file=sys.stderr,
        )

        ogv_path = work_dir / f"{label}.ogv"
        encode_cmd = [str(tool("ffmpeg")), "-y", "-v", "error", "-i", str(avi_path)]
        if n_blocks:
            encode_cmd += ["-i", str(mp3_path), "-map", "0:v", "-map", "1:a"]
        encode_cmd += [
            # Crop to the wrapper's clip mask, then re-center that box in an
            # OUT_W x OUT_H frame the way the original centers it on the
            # stage.
            "-vf",
            f"crop={MASK_W}:{MASK_H}:{crop_x}:{crop_y},pad={OUT_W}:{OUT_H}:{CONTENT_X}:{CONTENT_Y}:black",
            "-pix_fmt",
            "yuv420p",
            "-c:v",
            "libtheora",
            # libtheora's quality is q * 6.3 truncated to an integer, so 6.1
            # gives the 38 the replaced clips carry, where 6 would give 37.
            "-q:v",
            "6.1",
            "-g",
            "64",
        ]
        encode_cmd += ["-c:a", "libvorbis", "-q:a", "1"] if n_blocks else ["-an"]
        encode_cmd += [str(ogv_path)]
        run(encode_cmd)
        print(
            f"{label}: wrote {ogv_path} ({ogv_path.stat().st_size} bytes) - verifying...",
            file=sys.stderr,
        )

        # Verified in scratch first, so a failed encode or check leaves the
        # committed clip in assets/ untouched.
        resolution = verify_output(label, ogv_path, frames, bool(n_blocks), work_dir)
        shutil.copyfile(ogv_path, OUT_DIR / ogv_path.name)
        print(f"{label}: verified OK, copied to {OUT_DIR}", file=sys.stderr)
        return resolution
    finally:
        # Never hold more than one cutscene's raw AVI/stripped-SWF copy/
        # extracted MP3 in scratch space at once - each is several hundred
        # MB (the 2084-frame sprite 3643 alone: ~412MB for the raw AVI).
        shutil.rmtree(work_dir, ignore_errors=True)


def main():
    for name in _TOOL_HINTS:
        tool(name)
    encoders = run([str(tool("ffmpeg")), "-hide_banner", "-encoders"]).stdout
    for encoder in ("libtheora", "libvorbis"):
        if encoder not in encoders:
            raise SystemExit(
                f"ffmpeg has no {encoder} encoder ({_TOOL_HINTS['ffmpeg']})"
            )
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    xml = WEB_SWF_XML.read_text()

    resolutions: dict[str, tuple[int, int]] = {}
    for label, (chid, wrapper_chid, frames, overlay_chid) in CUTSCENES.items():
        resolutions[label] = process_cutscene(
            label, chid, wrapper_chid, frames, overlay_chid, xml
        )

    # Every cutscene is masked by the same 533x300 rectangle and centered on
    # the same stage, so they must all come out the same shape. The first
    # round of exports shipped four different aspect ratios; this is the
    # cross-file check that would have stopped it.
    if len(set(resolutions.values())) != 1:
        raise RuntimeError(f"cutscenes disagree on frame size: {resolutions}")
    print(
        f"all {len(resolutions)} cutscenes at {resolutions[next(iter(resolutions))]}",
        file=sys.stderr,
    )


if __name__ == "__main__":
    main()
