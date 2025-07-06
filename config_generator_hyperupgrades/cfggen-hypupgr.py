import csv
import sys
import os

def generate_hu_upgrades_cfg(csv_file):
    with open(csv_file, newline='', encoding='utf-8') as csvfile:
        reader = csv.DictReader(csvfile)
        lines = ['"Upgrades"\n{']
        for row in reader:
            if not row['alias'].strip():
                continue  # Skip blank lines

            alias = row['alias']
            lines.append(f'\t"{alias}"\n\t{{')
            if row['cost'].strip():
                lines.append(f'\t\t"Cost"\t"{row["cost"]}"')
            if row['ratio'].strip():
                lines.append(f'\t\t"Ratio"\t"{row["ratio"]}"')
            if row['increment'].strip():
                lines.append(f'\t\t"Increment"\t"{row["increment"]}"')
            if row['limit'].strip():
                lines.append(f'\t\t"Limit"\t"{row["limit"]}"')
            if row['name'].strip():
                lines.append(f'\t\t"Name"\t"{row["name"]}"')
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
        reader = list(csv.DictReader(csvfile))
        structure = {}

        for idx, row in enumerate(reader):
            if not row['upgradetype'].strip():
                # Mark that we need to insert a blank line later at this CSV position
                row['__blank__'] = True
                continue

            upgrade_type = row['upgradetype']
            upgrade_target = row['upgradetarget']
            submenu = row['submenu']
            upgrade_number = row['upgradenumber']
            upgrade_alias = row['upgradealias']

            structure.setdefault(upgrade_type, {}).setdefault(upgrade_target, {}).setdefault(submenu, {})[upgrade_number] = upgrade_alias

        lines = ['"Upgrades"\n{']
        current_line = 0
        blank_lines = [idx for idx, row in enumerate(reader) if '__blank__' in row]

        for upgrade_type, targets in structure.items():
            lines.append(f'\t"{upgrade_type}"\n\t{{')
            for target, submenus in targets.items():
                lines.append(f'\t\t"{target}"\n\t\t{{')
                for submenu, upgrades in submenus.items():
                    lines.append(f'\t\t\t"{submenu}"\n\t\t\t{{')
                    sorted_upgrades = sorted(upgrades.items(), key=lambda x: int(x[0]))
                    for number, alias in sorted_upgrades:
                        lines.append(f'\t\t\t\t"{number}"\t"{alias}"')
                        if current_line in blank_lines:
                            lines.append('')  # Write empty line if needed
                        current_line += 1
                    lines.append(f'\t\t\t}}')
                lines.append(f'\t\t}}')
            lines.append(f'\t}}')
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
