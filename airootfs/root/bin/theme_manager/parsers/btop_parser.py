from pathlib import Path
from typing import Dict, Any
import re
from parsers.base import ThemeParser


class BtopParser(ThemeParser):
    def parse(self, file_path: Path) -> Dict[str, str]:
        colors = {}
        with open(file_path, "r") as f:
            for line in f:
                line = line.strip()
                if line.startswith("theme[") and "=" in line:
                    match = re.match(
                        r'theme\[([^\]]+)\]\s*=\s*["\']?([^"\'\s]+)["\']?', line
                    )
                    if match:
                        key, value = match.groups()
                        colors[f"btop_{key}"] = value
        return colors

    def generate(self, colors: Dict[str, str], metadata: Dict[str, Any]) -> str:
        lines = []
        name = metadata.get("name", "custom")
        author = metadata.get("author", "Theme Manager")
        lines.append(f"# Theme: {name}")
        lines.append(f"# Author: {author}")
        lines.append("")

        for key, value in sorted(colors.items()):
            if key.startswith("btop_"):
                theme_key = key.replace("btop_", "")
                lines.append(f"theme[{theme_key}]={value}")

        return "\n".join(lines)

    def apply(self, theme_file: Path, target_config: Path):
        if not target_config.exists():
            return

        with open(target_config, "r") as f:
            lines = f.readlines()

        # Read new theme values into a dict
        new_theme = {}
        with open(theme_file, "r") as f:
            for line in f:
                match = re.match(r"theme\[([^\]]+)\]=(.+)", line.strip())
                if match:
                    new_theme[match.group(1)] = match.group(2).strip()

        # Rebuild the file, replacing values but keeping all # comment lines
        updated_lines = []
        for line in lines:
            stripped = line.strip()

            # Always keep comment lines untouched
            if stripped.startswith("#") or stripped == "":
                updated_lines.append(line)
                continue

            # Replace theme value if key exists in new theme
            match = re.match(r"theme\[([^\]]+)\]=", stripped)
            if match:
                key = match.group(1)
                if key in new_theme:
                    updated_lines.append(f"theme[{key}]={new_theme[key]}\n")
                else:
                    updated_lines.append(line)
            else:
                updated_lines.append(line)

        with open(target_config, "w") as f:
            f.writelines(updated_lines)
