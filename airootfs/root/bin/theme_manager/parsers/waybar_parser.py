from pathlib import Path
from typing import Dict, Any
import re
from parsers.base import ThemeParser


class WaybarParser(ThemeParser):
    @property
    def app_name(self):
        return "waybar"

    def parse(self, file_path: Path) -> Dict[str, str]:
        colors = {}
        self.store_source(file_path, colors)
        with open(file_path, "r") as f:
            content = f.read()
        for match in re.finditer(
            r"@define-color\s+(\S+)\s+(#[a-fA-F0-9]{6,8}|hsl\([^)]+\)|@[\w-]+);",
            content,
        ):
            color_name, color_value = match.groups()
            if color_name == "green" and "#BE3F50" in color_value.upper():
                colors["waybar_border"] = color_value
            else:
                colors[f"waybar_{color_name}"] = color_value
        return colors

    def generate(self, colors: Dict[str, str], metadata: Dict[str, Any]) -> str:
        if self.source_key() in colors:
            content = colors[self.source_key()]
            for key, value in colors.items():
                if key.startswith("waybar_"):
                    color_name = (
                        "green"
                        if key == "waybar_border"
                        else key.replace("waybar_", "")
                    )
                    content = re.sub(
                        rf"(@define-color\s+{re.escape(color_name)}\s+)[^;]+;",
                        rf"\g<1>{value};",
                        content,
                    )
            return content

        lines = [f"/* {metadata.get('name', 'custom')} */\n"]
        for key, value in sorted(colors.items()):
            if key.startswith("waybar_"):
                color_name = key.replace("waybar_", "")
                if color_name == "border":
                    lines.append(f"@define-color green           {value}; /* border */")
                else:
                    lines.append(f"@define-color {color_name:20} {value};")
        return "\n".join(lines)

    def apply(self, theme_file: Path, target_config: Path):
        if not target_config.exists():
            target_config.parent.mkdir(parents=True, exist_ok=True)
            target_config.touch()
        with open(target_config, "r") as f:
            content = f.read()
        with open(theme_file, "r") as f:
            theme_content = f.read()
        content = re.sub(r"@define-color[^;]+;\s*\n?", "", content)
        content = re.sub(r"/\*.*?\*/", "", content, flags=re.DOTALL)
        content = re.sub(r"\n{3,}", "\n\n", content).strip()
        content = theme_content + "\n\n" + content
        with open(target_config, "w") as f:
            f.write(content)
