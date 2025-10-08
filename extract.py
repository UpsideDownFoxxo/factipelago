import sys
from zipfile import ZipFile
import base64
import json
import re
from lz4 import block


def read_txt(zipfile: ZipFile, path: str):
    with zipfile.open(path) as f:
        return f.read().decode()


def extract_team_data(zipfile: ZipFile, mod_name: str):
    with zipfile.open(mod_name) as mod:
        nested_zip = ZipFile(mod)

        data_final_fixes = next(
            name
            for name in nested_zip.namelist()
            if name.endswith("data-final-fixes.lua")
        )

        return read_txt(nested_zip, data_final_fixes)


def extract_multiworld_data(input):
    with ZipFile(input) as outer:
        zip_contents = outer.namelist()

        spoilers_name = next(name for name in zip_contents if name.endswith(".txt"))
        data = {
            "spoilers": read_txt(outer, spoilers_name),
            "player_mods": {},
        }

        player_mod_names = [name for name in zip_contents if name.endswith(".zip")]

        for mod_name in player_mod_names:
            team_match = re.match(r"^AP-\d+-P\d+-([^_]+)", mod_name)
            if not team_match:
                print(f"Could not extract team name from {mod_name}")
                exit(-1)

            team = team_match.group(1)

            data["player_mods"][team] = extract_team_data(outer, mod_name)

        return data


if __name__ == "__main__":
    if len(sys.argv) < 2:
        print("Please provide a multiworld zip")
        exit(-1)
    path = sys.argv[1]
    json_str = json.dumps(extract_multiworld_data(path))

    comp = block.compress(json_str.encode("utf-8"), store_size=False)
    # print((comp.hex().upper()))

    compressed = base64.b64encode(comp).decode()

    print(f"{compressed}")
