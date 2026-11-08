# ffdec_lib.py
# Runs java/Render.java, the driver that renders frames through ffdec's Java
# library with per-instance visibility and frame overrides. See that file's
# header for the job format and what each override does.
#
# The driver runs against the jars of the same jpexs build the ffdec CLI uses,
# found by following ~/.local/bin/ffdec to its dist/ directory, so the CLI
# and the library always render with the same code.
from __future__ import annotations

import json
import subprocess
import tempfile
from pathlib import Path

from urchin_dev import FFDEC

DRIVER = Path(__file__).with_name("java") / "Render.java"
JPEXS_LIB = FFDEC.resolve().parent / "lib"


def render(swf: Path, jobs: list[dict]) -> list[dict]:
    """Render every job from one load of `swf` and return each job's result
    line: out, width, height and the displayRect (xmin, ymin, xmax, ymax) in
    twips. Raises with the driver's output when any job fails."""
    with tempfile.TemporaryDirectory(prefix="ffdec_lib_") as tmp:
        job_file = Path(tmp) / "job.json"
        job_file.write_text(json.dumps({"swf": str(swf), "jobs": jobs}))
        command = ["java", "-cp", f"{JPEXS_LIB}/*", str(DRIVER), str(job_file)]
        proc = subprocess.run(command, capture_output=True, text=True)
    if proc.returncode != 0:
        raise RuntimeError(
            f"{' '.join(command)} exited {proc.returncode}\n"
            f"stdout:\n{proc.stdout}\nstderr:\n{proc.stderr}"
        )
    results = [json.loads(line) for line in proc.stdout.splitlines() if line]
    if len(results) != len(jobs):
        raise RuntimeError(f"{len(jobs)} jobs but {len(results)} results")
    return results
