import sys
from pathlib import Path
import numpy as np
from PIL import Image

proto = (
    Path.home() / "tmp/2026-11-09-inner-shadow/proto/dev/prototypes/victory_containers"
)
real = np.asarray(Image.open(sys.argv[1]).convert("RGB"), dtype=int)
ref = np.asarray(
    Image.open(proto / "images/ref/win_panels_2x.png").convert("RGBA"), dtype=int
)
y = 390
cols = range(68, 92)
print("columns          ", list(cols))
print("real Flash 2x    ", [int(real[int(y * 2 + 64), x, 0]) for x in cols])
print("ffdec panels 2x  ", [int(ref[int(y * 2), x, 0]) for x in cols])
x = 150
rows = range(158, 182)
print("rows             ", list(rows))
print("real Flash 2x    ", [int(real[r + 64, x * 2, 0]) for r in rows])
print("ffdec panels 2x  ", [int(ref[r, x * 2, 0]) for r in rows])
