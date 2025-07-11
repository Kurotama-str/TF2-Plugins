import csv
import sys
import os

def generate_hu_upgrades_cfg(csv_file):
    with open(csv_file, newline='', encoding='utf-8') as csvfile:
        reader = csv.DictReader(csvfile)
        lines = ['"Upgrades"\n{']
        for row in reader:
            if not row['name'].strip():
                continue  # Skip blank lines

            name = row['name']
            lines.append(f'\t"{name}"\n\t{{')
            if row['cost'].strip():
                lines.append(f'\t\t"Cost"\t"{row["cost"]}"')
            if row['costincrease'].strip():
                lines.append(f'\t\t"CostIncrease"\t"{row["costincrease"]}"')
            if row['increment'].strip():
                lines.append(f'\t\t"Increment"\t"{row["increment"]}"')
            if row['limit'].strip():
                lines.append(f'\t\t"Limit"\t"{row["limit"]}"')
            if row['alias'].strip():
                lines.append(f'\t\t"Alias"\t"{row["alias"]}"')
            if 'initvalue' in row and row['initvalue'].strip():
                lines.append(f'\t\t"InitValue"\t"{row["initvalue"]}"')
            lines.append('\t}')
        lines.append('}')

    output_file = 'hu_upgrades.cfg'
    with open(output_file, 'w', encoding='utf-8') as f:
        f.write('\n'.join(lines))
    print(f'Generated {output_file} successfully.')

def generate_hu_attributes_cfg(csv_file):
    with open(csv_file, newline='', encoding='utf-8') as csvfile:
        reader = csv.DictReader(csvfile)
        structure = {}

        for row in reader:
            if not row['upgradetype'].strip():
                continue  # Skip blank lines

            upgrade_type = row['upgradetype']
            upgrade_target = row['upgradetarget']
            submenu = row['submenu']
            upgrade_number = row['upgradenumber']
            upgrade_name = row['upgradename']

            structure.setdefault(upgrade_type, {}).setdefault(upgrade_target, {}).setdefault(submenu, {})[upgrade_number] = upgrade_name

        lines = ['"Upgrades"\n{']
        for upgrade_type, targets in structure.items():
            lines.append(f'\t"{upgrade_type}"\n\t{{')
            for target, submenus in targets.items():
                lines.append(f'\t\t"{target}"\n\t\t{{')
                for submenu, upgrades in submenus.items():
                    lines.append(f'\t\t\t"{submenu}"\n\t\t\t{{')
                    for number, name in sorted(upgrades.items(), key=lambda x: int(x[0])):
                        lines.append(f'\t\t\t\t"{number}"\t"{name}"')
                    lines.append('\t\t\t}')
                lines.append('\t\t}')
            lines.append('\t}')
        lines.append('}')

    output_file = 'hu_attributes.cfg'
    with open(output_file, 'w', encoding='utf-8') as f:
        f.write('\n'.join(lines))
    print(f'Generated {output_file} successfully.')

if __name__ == "__main__":
    if len(sys.argv) != 3:
        print("Usage: python3 hu_config_generator.py <mode> <input_csv>")
        print("Modes: upgrades / attributes")
        sys.exit(1)

    mode = sys.argv[1].lower()
    input_csv = sys.argv[2]

    if not os.path.exists(input_csv):
        print(f"Error: Input file '{input_csv}' does not exist.")
        sys.exit(1)

    if mode == "upgrades":
        generate_hu_upgrades_cfg(input_csv)
    elif mode == "attributes":
        generate_hu_attributes_cfg(input_csv)
    else:
        print("Unknown mode. Use 'upgrades' or 'attributes'.")
