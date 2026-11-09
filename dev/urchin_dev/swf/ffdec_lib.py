# ffdec_lib.py
# Runs java/Render.java, the driver that renders frames through ffdec's Java
# library with characters deleted in memory, per-instance visibility and frame
# overrides. See that file's header for the job format and what each override
# does.
#
# The driver runs against the jars of the same jpexs build the ffdec CLI uses,
# found by following ~/.local/bin/ffdec to its dist/ directory, so the CLI
# and the library always render with the same code.
from __future__ import annotations

import json
import tempfile
from pathlib import Path

from urchin_dev import FFDEC
from urchin_dev.run import run

DRIVER = Path(__file__).with_name("java") / "Render.java"
JPEXS_LIB = FFDEC.resolve().parent / "lib"


def loads(jobs: list[dict]) -> list[dict]:
    """-> the jobs grouped into one load per distinct strip_characters list,
    in the order each list first appears, so the driver parses and strips the
    SWF once per list rather than once per job."""
    grouped: dict[tuple[int, ...], list[dict]] = {}
    for job in jobs:
        strip = tuple(sorted(set(job.get("strip_characters", ()))))
        body = {k: v for k, v in job.items() if k != "strip_characters"}
        grouped.setdefault(strip, []).append(body)
    return [{"strip_characters": list(k), "jobs": v} for k, v in grouped.items()]


def render(swf: Path, jobs: list[dict]) -> list[dict]:
    """Render every job from `swf` in one driver run and return each job's
    result line, in the order of `jobs`: out, width, height, the rect the
    canvas was sized from (xmin, ymin, xmax, ymax) and the displayRect
    without the filter margin ("display"), all in twips. A job's
    strip_characters are deleted from the SWF before it renders."""
    grouped = loads(jobs)
    with tempfile.TemporaryDirectory(prefix="ffdec_lib_") as tmp:
        job_file = Path(tmp) / "job.json"
        job_file.write_text(json.dumps({"swf": str(swf), "loads": grouped}))
        proc = run(["java", "-cp", f"{JPEXS_LIB}/*", DRIVER, job_file])
    lines = [
        json.loads(line) for line in proc.stdout.splitlines() if line.startswith("{")
    ]
    if len(lines) != len(jobs):
        raise RuntimeError(f"{len(jobs)} jobs but {len(lines)} results")
    by_out = {line["out"]: line for line in lines}
    return [by_out[str(Path(job["out"]))] for job in jobs]
