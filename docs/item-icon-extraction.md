# Item icon extraction

How `assets/ui/items/*.png` gets generated from the web SWF's item-icon sheet
(`DefineSprite 2064`), and how to run either the wrapped pipeline or the raw
`ffdec` step it wraps.

Note: this is a different asset tree from `assets/item_slot_icons/`. That
directory has no known SWF source - investigated and confirmed a dead end
(`KNOWN_GAPS.md`, "11 numeric-named asset stragglers are untraceable",
2026-07-18): no `ExportAssetsTag` linkage name, no frame-label timeline like
`DefineSprite 2064` has. It's legacy database-named fallback art, only still
used for the handful of items with no matching frame label in 2064 (or, via
`ICON_OVERRIDES` in the script below, for items where the 2064 frame content
is simply wrong for that item).

## The wrapped command

```sh
uv run extract_item_icons
```

Runs `dev/urchin_dev/swf/extract/item_icons.py`. Reads every labeled frame of
`DefineSprite 2064` (the game's own `itemSlot.inner.gotoAndStop(ITEMNAME[id])`
sheet) from the web SWF's `swf2xml` dump, composites each at 2x into
`assets/ui/items/<sanitized label>.png`, then repoints every matching
`resources/items/<id>_*.tres`'s `slot_image` at the new icon.

## Diagnosing one icon by hand

Same shape:png export the script runs, scoped to a single shape id, so you
can inspect one item without waiting on the full 408-shape batch. `-zoom 2`
matches the script's `ZOOM = 2.0` (icons composite at 2x the original 31x31
design-px slot); `-export shape <output_dir>` writes one `<id>.png` per
requested id, un-composited, so you can see exactly what that layer looks
like on its own.

```sh
ffdec -zoom 2.0 -format shape:png -selectid 1900 -export shape ./test_pipe sonny-2-2900.swf
```

`1900` is "A Broken Pipe"'s own unique art (frame 69 of `DefineSprite 2064`,
depth-4 child); `1912`/`1913` are the shared background/editor-chrome shapes
every icon frame carries at other depths (see the id lookup script below to
get a given item's full depth-to-shape-id list).

**The worked precedent - this is the exact pair of commands that found and
confirmed the ability-icon black-disc bug** (commit `ff6a028`; ability icons
live in `DefineSprite 2427`, not 2064):

```sh
# The real per-label art for the "ACIDIC" ability (frame 228, depth 5) -
# a clean, colorful icon on its own.
ffdec -zoom 2.0 -format shape:png -selectid 2296 -export shape ./test_acidic sonny-2-2900.swf

# The opaque black disc (frame 228, depth 11) that was sitting on top of it
# in every composited icon - present at the same depth on 103 of 104 labels.
ffdec -zoom 2.0 -format shape:png -selectid 2241 -export shape ./test_disc sonny-2-2900.swf
```

Comparing those two PNGs (real art vs. opaque disc) is what confirmed the
root cause before `2241` was added to `extract_ability_icons.py`'s
`SKIP_CIDS`.

## Extracting everything

The literal command the script runs (batched in groups of 400 ids to keep
the argument list sane - `DefineSprite 2064` currently needs 408 shape ids
across all 327 labeled frames, so two calls):

```sh
ffdec -zoom 2.0 -format shape:png -export shape ./all_item_shapes sonny-2-2900.swf -selectid 59,61,63,105,122,333,485,487,489,491,493,495,497,499,501,502,504,512,514,516,518,520,522,524,526,527,529,534,538,539,542,544,546,548,550,552,554,558,560,562,566,571,574,577,598,600,602,604,606,608,630,632,634,636,638,640,658,669,673,675,677,679,681,683,687,689,691,693,695,697,699,701,703,705,707,711,713,717,718,720,724,726,728,730,732,734,738,740,742,743,745,747,749,753,755,757,759,762,767,769,772,774,777,779,781,783,785,787,789,793,795,797,799,801,803,807,809,811,813,815,817,819,823,827,843,845,847,851,855,857,859,861,863,865,886,892,894,896,898,900,902,906,908,910,912,914,916,918,920,922,924,928,930,932,934,936,938,940,942,944,946,948,950,954,956,964,966,968,970,972,974,990,992,993,995,1000,1036,1042,1046,1048,1050,1052,1056,1098,1283,1285,1287,1289,1291,1293,1295,1299,1301,1303,1305,1307,1309,1310,1314,1316,1318,1320,1322,1324,1325,1329,1331,1333,1335,1337,1339,1340,1357,1395,1397,1399,1401,1403,1405,1407,1408,1426,1428,1430,1432,1434,1436,1437,1468,1470,1472,1474,1476,1479,1481,1483,1485,1487,1489,1493,1495,1497,1567,1575,1577,1579,1581,1585,1587,1605,1744,1745,1747,1749,1753,1755,1759,1761,1763,1765,1797,1800,1802,1804,1819,1821,1823,1825,1827,1831,1833,1835,1837,1840,1882,1884,1898,1900,1906,1912,1913,1915,1916,1917,1918,1919,1920,1921,1922,1923,1924,1925,1926,1927,1928,1929,1930,1931,1932,1933,1934,1935,1936,1937,1938,1939,1940,1941,1942,1943,1944,1945,1946,1947,1948,1949,1950,1951,1952,1953,1954,1955,1956,1957,1958,1959,1960,1961,1962,1963,1964,1966,1967,1968,1970,1971,1972,1973,1974,1975,1976,1977,1978,1979,1980,1981,1982,1983,1984,1985,1986,1987,1988,1989,1990,1991,1992,1993,1994,1995,1996,1997,1998,1999,2000,2001,2002,2003,2004,2006,2007,2009,2010,2011,2012,2013,2014,2015,2016,2018,2020,2022,2024,2027,2029,2032,2033,2034,2035,2037,2039,2040,2042,2044,2046,2048,2049,2051,2053,2054

ffdec -zoom 2.0 -format shape:png -export shape ./all_item_shapes sonny-2-2900.swf -selectid 2055,2056,2057,2058,2060,2061,2062,2063
```

This only dumps the raw, uncomposited shapes into `./all_item_shapes/<id>.png`
- it doesn't reassemble them into per-item icons (that needs the matrix math
`item_icons.py` does per frame) or repoint any `.tres`. For that, run
`uv run extract_item_icons` instead - this is purely for inspecting the raw
shape exports by hand. The id list is regenerated by the lookup script below
(it changes if `dev/source_files/swf_xml/sonny-2-2900.xml` is re-dumped from
a different SWF revision) - don't hardcode it elsewhere.

To find which shape ids a given item's frame actually uses, run this from
the repo root:

```sh
uv run python3 -c '
from urchin_dev import WEB_SWF_XML
from urchin_dev.swf import parse_swf_xml, snapshot_timeline

xml = WEB_SWF_XML.read_text()
shapes, sprites, _exports = parse_swf_xml(WEB_SWF_XML)
snaps, labels = snapshot_timeline(xml, 2064, set(range(1, 900)))

def collect(cid, out):
    if cid in shapes:
        out.add(cid)
    elif cid in sprites:
        for child, _mat in sprites[cid]:
            collect(child, out)

label = "A Broken Pipe"  # exact frame label, case-sensitive
frame = labels[label]
cids = set()
for entry in snaps[frame].values():
    collect(entry["cid"], cids)
print(sorted(cids))
'
```
