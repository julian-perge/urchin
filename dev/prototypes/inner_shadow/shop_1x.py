import numpy as np
from PIL import Image

p = "references/2026_07_18_flashpoint/zone1_itemshop_menu_Screenshot 2026-07-18 at 18.38.33.png"
a = np.asarray(Image.open(p).convert("RGB"), dtype=int)
print(a.shape)
# find strongly dark columns then print a horizontal slice through a panel at mid-height
for y in (300, 330):
    print("row", y, [int(v) for v in a[y, 0:120, 0]])
