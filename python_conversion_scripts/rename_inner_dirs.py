import json
import re
import shutil
from pathlib import Path

KRIN_SHOP_ITEMS: dict[int, list[int]] = {
    # JAIL/PRISON
    0: [508, 509, 510, 511, 512, 513, 502, 514, 0, 0, 0, 0, 0, 0, 0],
    # "VILLAGE"
    1: [326, 327, 328, 382, 329, 526, 524, 523, 352, 353, 354, 350, 0, 0, 0],
    # "TRAIN"
    2: [528, 529, 530, 531, 532, 533, 534, 535, 536, 537, 557, 558, 560, 554, 556],
    # "TUNNELS"
    3: [598, 599, 600, 601, 604, 574, 576, 580, 582, 583, 586, 590, 592, 593, 594],
    # "CITY"
    4: [650, 652, 653, 654, 656, 609, 614, 619, 629, 634, 611, 616, 621, 631, 636],
    # "ROME"
    5: [689, 690, 691, 692, 693, 694, 695, 696, 697, 698, 699, 700, 701, 702, 703],
    # "JAPAN"
    6: [659, 668, 669, 674, 677, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0],
    # "UTOPIA"
    7: [689, 690, 691, 692, 693, 694, 695, 696, 697, 698, 699, 700, 701, 702, 703],
}


def load_items_by_id() -> dict[str, str]:
    with open("converted_json/converted_item_by_id.json", "r") as f:
        content = json.load(f)
    return content


def rename_single_png_files():
    # Walk through all directories and subdirectories
    root_directory = Path("/Users/sweetjp/Documents/DEVELOPER/urchin/sprites")
    new_root_dir = Path("/Users/sweetjp/Documents/DEVELOPER/godot/urchin/resources/sprites")
    for dir_path in root_directory.rglob("*"):
        if not dir_path.is_dir():
            continue

        # Find all PNG files in current directory
        png_files = list(dir_path.glob("*.png"))

        # Only process if there's exactly one PNG file
        if len(png_files) == 1:
            png_file = png_files[0]
            parent_dir: str = dir_path.name
            parent_dir_und = parent_dir.split("_")
            parent_no_num: str = "_".join(parent_dir_und[2:])

            # Check if directory name matches the pattern (DefineSprite_XXX_...)
            if parent_dir.startswith("DefineSprite_") and len(parent_dir_und) >= 4:
                # Create new filename from parent directory name
                new_path = new_root_dir / f"{parent_no_num}.png"
                print(f"Found dir with single png, {parent_dir}, new png -> [{new_path}]")

                # Rename file if the names are different
                if png_file.name != new_path.name:
                    try:
                        png_file.rename(new_path)
                        print(f"Renamed: {png_file} -> {new_path}")
                    except Exception as e:
                        print(f"Error renaming {png_file}: {e}")


def print_items_for_replacing_store():
    content: list[str] = list(load_items_by_id().keys())
    new_arr = []
    for i_idx in content:
        if int(i_idx) >= 300:
            new_arr.append(int(i_idx))

    out_d = {}
    arr = []

    for idx in new_arr:
        arr.append(idx)
        # if len(arr) == 15:
        # print("New Shop array: ", arr)
        if len(arr) == 37:
            for index, _i in enumerate(arr):
                out_d[str(index)] = _i
            print("\nItem Array to replace inventory:\n")
            print(json.dumps(out_d))
            arr = []


def convert_item_shop():
    items_by_id = load_items_by_id()
    items = {}
    for shop_id, item_array in KRIN_SHOP_ITEMS.items():
        found_items = [items_by_id.get(str(item_id)) for item_id in item_array]
        new_shop_items = {str(shop_id): found_items}
        items.update(new_shop_items)
        print(new_shop_items)


def rename_weapon_pngs():
    root_directory = Path("/Users/sweetjp/Documents/DEVELOPER/urchin/item_icons_2000/WEAPONS")
    weapons_items_txt = Path("/Users/sweetjp/Documents/DEVELOPER/urchin/weapons_rename.txt")
    # Find all PNG files in current directory
    png_files = sorted(list(root_directory.glob("*.png")))

    weapons = {}

    with weapons_items_txt.open(mode="r") as weapons_f:
        # 712: EMD Blade
        # 719: Medic-B Gloves, Surgeon Gloves
        content: list[str] = weapons_f.readlines()

    for line in content:
        # 0-> 712
        # 1 -> EMD Blade
        line_split = line.split(":")
        _id = line_split[0]
        line_weapons = [_l.strip().replace(" ", "_").replace("'", "") for _l in line_split[1].split(",")]
        weapons[str(_id)] = line_weapons

    png_file: Path
    for png_file in png_files:
        if re.match("^[1-9]+", png_file.name):
            new_name: list[str] = weapons.get(png_file.name.replace(".png", ""), [])
            if len(new_name) == 0:
                continue
            if len(new_name) == 2:
                second_file_path = png_file.parent / f"{new_name[1]}.png"
                second_file: Path = shutil.copyfile(png_file, second_file_path)
                print(f"Copied second file -> [{str(second_file)}]")
            first_file_path = png_file.parent / f"{new_name[0]}.png"
            png_file.rename(first_file_path)
            print(f"Renamed first file -> [{str(first_file_path)}]")


if __name__ == "__main__":
    # print_items_for_replacing_store()
    # rename_single_png_files()
    # convert_item_shop()
    rename_weapon_pngs()
    print("done")
