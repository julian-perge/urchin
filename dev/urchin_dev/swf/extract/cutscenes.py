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

from urchin_dev import FFDEC, REPO_ROOT, WEB_SWF, WEB_SWF_XML
from urchin_dev.swf import sprite_body

OUT_DIR = REPO_ROOT / "assets" / "cutscenes"

FFMPEG2THEORA = shutil.which("ffmpeg2theora") or "/opt/homebrew/bin/ffmpeg2theora"

# label -> (sprite chid, frame count, guide-overlay chid to strip)
CUTSCENES: dict[str, tuple[int, int, int]] = {
    "CS_CUT2": (3643, 2084, 3478),
    "CS_CUT3": (3928, 621, 3812),
    "CS_CUT4": (3960, 501, 3812),  # same overlay clip as CS_CUT3
    "CS_CUT5": (4038, 1237, 3962),
}


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


def main():
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    xml = WEB_SWF_XML.read_text()

    for label, (chid, frames, overlay_chid) in CUTSCENES.items():
        print(f"--- {label}: sprite {chid}, {frames} frames, "
              f"stripping overlay {overlay_chid} ---", file=sys.stderr)
        work_dir = Path(tempfile.mkdtemp(prefix=f"cutscene_{label}_"))
        try:
            stripped_swf = work_dir / "stripped.swf"
            subprocess.run(
                [
                    str(FFDEC),
                    "-removeCharacter",
                    str(WEB_SWF),
                    str(stripped_swf),
                    str(overlay_chid),
                ],
                check=True,
                capture_output=True,
            )

            avi_dir = work_dir / "avi"
            subprocess.run(
                [
                    str(FFDEC),
                    "-format",
                    "sprite:avi",
                    "-selectid",
                    str(chid),
                    "-export",
                    "sprite",
                    str(avi_dir),
                    str(stripped_swf),
                ],
                check=True,
                capture_output=True,
            )
            avi_path = avi_dir / f"DefineSprite_{chid}" / "frames.avi"
            if not avi_path.exists():
                raise SystemExit(f"{label}: expected AVI not found at {avi_path}")

            mp3_path = work_dir / "audio.mp3"
            n_blocks = extract_mp3(xml, chid, mp3_path)
            print(f"{label}: {n_blocks} sound blocks -> {mp3_path.stat().st_size} bytes",
                  file=sys.stderr)

            muxed_path = work_dir / "muxed.mkv"
            mux_cmd = [
                "ffmpeg",
                "-y",
                "-v", "error",
                "-i", str(avi_path),
            ]
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
            subprocess.run(mux_cmd, check=True, capture_output=True)

            ogv_path = OUT_DIR / f"{label}.ogv"
            theora_cmd = [FFMPEG2THEORA, str(muxed_path), "-o", str(ogv_path)]
            if not n_blocks:
                theora_cmd.append("--noaudio")
            subprocess.run(theora_cmd, check=True, capture_output=True)
            print(f"{label}: wrote {ogv_path} ({ogv_path.stat().st_size} bytes)",
                  file=sys.stderr)
        finally:
            # Never hold more than one cutscene's raw AVI/stripped-SWF copy/
            # extracted MP3 in scratch space at once - each is several
            # hundred MB (CS_CUT2 alone: ~393MB for the raw AVI).
            shutil.rmtree(work_dir, ignore_errors=True)


if __name__ == "__main__":
    main()
