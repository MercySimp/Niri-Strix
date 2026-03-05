from pathlib import Path
from typing import Dict, Any
import re
from parsers.base import ThemeParser


class BtopParser(ThemeParser):
    @property
    def app_name(self):
        return "btop"

    def parse(self, file_path: Path) -> Dict[str, str]:
        colors = {}
        self.store_source(file_path, colors)
        with open(file_path, "r") as f:
            for line in f:
                line = line.strip()
                if line.startswith("theme[") and "=" in line:
                    match = re.match(
                        r'theme\[([^\]]+)\]\s*=\s*["\']?([^"\']+?)["\']?\s*$', line
                    )
                    if match:
                        key, value = match.groups()
                        colors[f"btop_{key}"] = value.strip()
        return colors

    def generate(self, colors: Dict[str, str], metadata: Dict[str, Any]) -> str:
        if self.source_key() in colors:
            content = colors[self.source_key()]
            for key, value in colors.items():
                if key.startswith("btop_"):
                    theme_key = key.replace("btop_", "")
                    content = re.sub(
                        rf"(theme\[{re.escape(theme_key)}\]\s*=\s*)[^\n]+",
                        rf"\g<1>{value}",
                        content,
                    )
            return content

        lines = []
        name = metadata.get("name", "custom")
        lines.append(f"# Theme: {name}")
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
        new_theme = {}
        with open(theme_file, "r") as f:
            for line in f:
                match = re.match(r"theme\[([^\]]+)\]=(.+)", line.strip())
                if match:
                    new_theme[match.group(1)] = match.group(2).strip()
        updated_lines = []
        for line in lines:
            stripped = line.strip()
            if stripped.startswith("#") or stripped == "":
                updated_lines.append(line)
                continue
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
