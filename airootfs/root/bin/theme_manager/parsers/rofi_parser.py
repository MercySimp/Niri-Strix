from pathlib import Path
from typing import Dict, Any
import re
from parsers.base import ThemeParser


class RofiParser(ThemeParser):
    @property
    def app_name(self):
        return "rofi"

    def parse(self, file_path: Path) -> Dict[str, str]:
        colors = {}
        self.store_source(file_path, colors)
        with open(file_path, "r") as f:
            content = f.read()
        for match in re.finditer(
            r"(\w[\w-]*)\s*:\s*(#[a-fA-F0-9]{6,8}|hsl\([^)]+\));", content
        ):
            key, value = match.groups()
            colors[f"rofi_{key}"] = value
        return colors

    def generate(self, colors: Dict[str, str], metadata: Dict[str, Any]) -> str:
        if self.source_key() in colors:
            content = colors[self.source_key()]
            for key, value in colors.items():
                if key.startswith("rofi_"):
                    color_name = key.replace("rofi_", "")
                    content = re.sub(
                        rf"({re.escape(color_name)}\s*:\s*)[^;]+;",
                        rf"\g<1>{value};",
                        content,
                    )
            return content

        lines = [f"/* Theme: {metadata.get('name', 'custom')} */\n", "* {"]
        for key, value in sorted(colors.items()):
            if key.startswith("rofi_"):
                lines.append(f"    {key.replace('rofi_', '')}: {value};")
        lines.append("}")
        return "\n".join(lines)

    def apply(self, theme_file: Path, target_config: Path):
        import shutil

        if not theme_file.exists() or theme_file.stat().st_size == 0:
            return
        if not target_config.exists():
            target_config.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(theme_file, target_config)
