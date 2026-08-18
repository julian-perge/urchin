# Story cutscenes as playable video: each cutscene is one DefineSprite with
# its own independent timeline, gotoAndStop-jumped into from the main
# timeline by frame label (see frame_219/DoAction.as's afterCut assignments,
# and each cutscene sprite's own final-frame DoAction setting cutSceneEnd).
# Produces assets/cutscenes/CS_CUT{2,3,4,5}.ogv - Ogg Theora is Godot's only
# built-in video codec (WebM was removed from Godot core in 4.0).
#
# Every one of these sprites has a "guide overlay" clip placed as a direct
# child: a red bounding box + center crosshair + color-bar swatch the
# original animators used while blocking out the scene, left in the shipped
# SWF but never meant to be visible (confirmed by diffing a rendered frame
# with and without the strip - see task-1-report.md). ffdec's
# -removeCharacterWithDependencies was tried first and rejected: it cascades
# and deletes the *parent* cutscene sprite too, because the parent places
# the overlay as a child of itself. Plain -removeCharacter only drops that
# one placement.
#
# Sprite ids, frame counts, and guide-overlay ids in CUTSCENES below were
# read directly out of dev/source_files/swf_xml/sonny-2-2900.xml (frameCount
# attributes on each DefineSpriteTag, cross-checked against the FrameLabelTag
# names) - see .superpowers/sdd/plan_cutscenes/task-1-brief.md's Background
# table for the original battle-id survey that found these.
#
# ffdec's sprite:avi export renders video only (no audio track) - each
# cutscene's dialogue/music is a SoundStreamBlockTag-per-frame MP3 stream
# attached to the *sprite's* timeline (not the main timeline), so it has to
# be reconstructed by hand: per the SWF10 spec, an MP3-compressed stream
# block is a 4-byte header (2-byte sample count, 2-byte seek-samples)
# followed by raw MPEG frame bytes - stripping that header from every block
# in frame order and concatenating gives a valid, playable MP3.
#
# The exported AVI stores frames as PNG-in-AVI. Muxing that directly against
# ffmpeg2theora (whose bundled ffmpeg misreads the color matrix as GBR
# instead of RGB) produces a psychedelic, channel-swapped mess - confirmed
# by a visual diff. Re-encoding the video through a well-defined
# yuv420p/libx264 intermediate before handing it to ffmpeg2theora avoids
# that entirely and keeps the intermediate small (~1-2% the size of the raw
# PNG-per-frame AVI, several hundred MB per cutscene at 2000+ frames).
#
# No -shortest trim on the mux: a couple of these cutscenes' audio streams
# run somewhat short of their frame count (trailing silent frames with no
# new sound block), and trimming to the shorter stream would clip the tail
# of the video instead of just leaving it silent.
#
# CS_CUT4 originally shipped with ~11 frames of rendered static/noise near
# its tail (frames ~467-477 of 501, confirmed present in ffdec's export of
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
# alongside the guide overlay, so a similar dangling reference in another
# cutscene gets caught automatically instead of silently shipping noise
# again. (Scoped to each sprite's directly-placed children, same as the
# guide-overlay strip - does not recurse into nested sprites.)
#
# Requires ffdec (~/.local/bin/ffdec) for the character-strip and video
# export, and ffmpeg2theora (`brew install ffmpeg2theora`) for the final
# Theora/Vorbis transcode - this machine's plain ffmpeg build has no Theora
# encoder (libvpx/VP8/VP9 only), confirmed via `ffmpeg -encoders`. ffmpeg
# itself is used only for the intermediate mux/re-encode step, not for the
# final transcode.
# Run: uv run extract_cutscenes
from __future__ import annotations

import re
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

from PIL import Image, ImageChops, ImageFilter, ImageStat

from urchin_dev import FFDEC, REPO_ROOT, WEB_SWF, WEB_SWF_XML
from urchin_dev.swf import sprite_body

OUT_DIR = REPO_ROOT / "assets" / "cutscenes"


def _require_tool(name: str, hint: str) -> Path:
    """Resolve a tool on PATH instead of hardcoding a Homebrew-on-Apple-
    Silicon path - the previous version of this script fell back to a bare
    "/opt/homebrew/bin/ffmpeg2theora" string with no existence check, which
    breaks silently on Intel Homebrew (/usr/local) or Linux.
    """
    found = shutil.which(name)
    if found is None:
        raise SystemExit(f"required tool '{name}' not found on PATH ({hint})")
    return Path(found)


FFMPEG = _require_tool("ffmpeg", "used for the mux/re-encode step")
FFPROBE = _require_tool("ffprobe", "used for post-generation verification")
FFMPEG2THEORA = _require_tool(
    "ffmpeg2theora",
    "install with `brew install ffmpeg2theora` - this machine's ffmpeg has "
    "no Theora encoder",
)

# label -> (sprite chid, frame count, guide-overlay chid to strip)
CUTSCENES: dict[str, tuple[int, int, int]] = {
    "CS_CUT2": (3643, 2084, 3478),
    "CS_CUT3": (3928, 621, 3812),
    "CS_CUT4": (3960, 501, 3812),  # same overlay clip as CS_CUT3
    "CS_CUT5": (4038, 1237, 3962),
}

# Verification thresholds - see verify_output()'s docstring.
DURATION_TOLERANCE_S = 2.0
NOISE_RATIO_THRESHOLD = 0.35
NOISE_SAMPLE_INTERVAL_S = 1.0


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


def extract_mp3(xml: str, sprite_id: int, out_path: Path) -> int:
    """Reconstruct the sprite's dialogue/music track from its
    SoundStreamBlockTags and write it as a raw MP3 to out_path.

    Returns the number of blocks concatenated (0 means no audio stream).
    """
    body = sprite_body(xml, sprite_id)
    blocks = re.findall(
        r'<item type="SoundStreamBlockTag"[^>]*streamSoundData="([0-9a-fA-F]*)"',
        body,
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
    instead of leaving it blank. Confirmed as the root cause of CS_CUT4's
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


def _noise_ratio(png_path: Path) -> float:
    """How much of a frame's variance survives a heavy blur, relative to its
    own variance. Flat cel-shaded art (or a hard-edged vector shape) loses
    almost all its variance to a blur, since it's low-frequency content with
    a few sharp edges; true per-pixel random static barely changes under a
    blur (there's no low-frequency structure to preserve), so its residual
    stays close to its own original variance. Empirically: a clean gradient
    frame from these cutscenes scores ~0.12, a hard-edged shape (e.g. a
    solid circle on black) also ~0.13, and ffdec's rendered static for
    CS_CUT4's broken frames scored ~0.65 - a wide, comfortable margin either
    side of NOISE_RATIO_THRESHOLD.
    """
    img = Image.open(png_path).convert("L")
    blurred = img.filter(ImageFilter.GaussianBlur(radius=4))
    residual = ImageChops.difference(img, blurred)
    frame_std = ImageStat.Stat(img).stddev[0]
    residual_std = ImageStat.Stat(residual).stddev[0]
    return residual_std / (frame_std + 1e-6)


def verify_output(
    label: str, ogv_path: Path, expected_frames: int, has_audio: bool, work_dir: Path
) -> None:
    """Fail loudly instead of shipping a silently-corrupt file.

    Checks: exactly the expected stream types are present (Theora video,
    Vorbis audio if the source sprite had one), the container's reported
    duration is within tolerance of expected_frames/30fps, and - the check
    that would have actually caught CS_CUT4's corrupted tail before it
    shipped - a sweep of frames sampled roughly once per second across the
    FULL duration (not just a start/midpoint spot check) for suspiciously
    high-frequency noise via _noise_ratio().
    """
    probe = run(
        [
            str(FFPROBE),
            "-v", "error",
            "-show_entries", "stream=codec_type,codec_name:format=duration",
            "-of", "default=noprint_wrappers=0",
            str(ogv_path),
        ]
    ).stdout
    if "codec_name=theora" not in probe:
        raise RuntimeError(f"{label}: no theora video stream found in {ogv_path}\n{probe}")
    if has_audio and "codec_name=vorbis" not in probe:
        raise RuntimeError(
            f"{label}: expected a vorbis audio stream, none found in {ogv_path}\n{probe}"
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
                str(FFMPEG), "-y", "-v", "error",
                "-ss", f"{ts:.3f}", "-i", str(ogv_path),
                "-frames:v", "1", str(frame_path),
            ]
        )
        if not frame_path.exists():
            continue
        ratio = _noise_ratio(frame_path)
        if ratio > NOISE_RATIO_THRESHOLD:
            bad_frames.append((ts, ratio))
    if bad_frames:
        detail = ", ".join(f"{ts:.2f}s (noise ratio {r:.2f})" for ts, r in bad_frames)
        raise RuntimeError(
            f"{label}: {len(bad_frames)}/{n_samples} sampled frame(s) look like "
            f"corrupted static/noise rather than real content: {detail}"
        )


def process_cutscene(label: str, chid: int, frames: int, overlay_chid: int, xml: str) -> None:
    print(
        f"--- {label}: sprite {chid}, {frames} frames, stripping overlay {overlay_chid} ---",
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

        avi_dir = work_dir / "avi"
        run(
            [
                str(FFDEC),
                "-format", "sprite:avi",
                "-selectid", str(chid),
                "-export", "sprite", str(avi_dir),
                str(current_swf),
            ]
        )
        avi_path = avi_dir / f"DefineSprite_{chid}" / "frames.avi"
        if not avi_path.exists():
            raise RuntimeError(f"{label}: expected AVI not found at {avi_path}")

        mp3_path = work_dir / "audio.mp3"
        n_blocks = extract_mp3(xml, chid, mp3_path)
        print(
            f"{label}: {n_blocks} sound blocks -> {mp3_path.stat().st_size} bytes",
            file=sys.stderr,
        )

        muxed_path = work_dir / "muxed.mkv"
        mux_cmd = [str(FFMPEG), "-y", "-v", "error", "-i", str(avi_path)]
        if n_blocks:
            mux_cmd += ["-i", str(mp3_path), "-map", "0:v", "-map", "1:a"]
        mux_cmd += [
            # Odd sprite widths (e.g. 739px) aren't valid for yuv420p;
            # round up to even. Re-encoding through libx264/yuv420p (not
            # -c:v copy) is what avoids ffmpeg2theora's color-matrix
            # misdetection on the raw PNG-in-AVI frames (see file header).
            "-vf", "pad=ceil(iw/2)*2:ceil(ih/2)*2",
            "-c:v", "libx264",
            "-crf", "10",
            "-pix_fmt", "yuv420p",
        ]
        if n_blocks:
            mux_cmd += ["-c:a", "copy"]
        mux_cmd += [str(muxed_path)]
        run(mux_cmd)

        ogv_path = OUT_DIR / f"{label}.ogv"
        theora_cmd = [str(FFMPEG2THEORA), str(muxed_path), "-o", str(ogv_path)]
        if not n_blocks:
            theora_cmd.append("--noaudio")
        run(theora_cmd)
        print(
            f"{label}: wrote {ogv_path} ({ogv_path.stat().st_size} bytes) - verifying...",
            file=sys.stderr,
        )

        try:
            verify_output(label, ogv_path, frames, bool(n_blocks), work_dir)
        except Exception:
            ogv_path.unlink(missing_ok=True)  # don't leave a known-bad file behind
            raise
        print(f"{label}: verified OK", file=sys.stderr)
    finally:
        # Never hold more than one cutscene's raw AVI/stripped-SWF copy/
        # extracted MP3 in scratch space at once - each is several hundred
        # MB (CS_CUT2 alone: ~412MB for the raw AVI).
        shutil.rmtree(work_dir, ignore_errors=True)


def main():
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    xml = WEB_SWF_XML.read_text()

    for label, (chid, frames, overlay_chid) in CUTSCENES.items():
        process_cutscene(label, chid, frames, overlay_chid, xml)


if __name__ == "__main__":
    main()
