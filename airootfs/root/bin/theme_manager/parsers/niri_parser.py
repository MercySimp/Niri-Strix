from pathlib import Path
from typing import Dict, Any
import re
from parsers.base import ThemeParser


class NiriParser(ThemeParser):
    @property
    def app_name(self):
        return "niri"

    def parse(self, file_path: Path) -> Dict[str, str]:
        colors = {}
        self.store_source(file_path, colors)
        with open(file_path, "r") as f:
            content = f.read()
        for match in re.finditer(
            r'(active-color|inactive-color|urgent-color)\s+"([^"]+)"', content
        ):
            key, value = match.groups()
            colors[f"niri_{key}"] = value
        width_match = re.search(r"width\s+([\d.]+)", content)
        if width_match:
            colors["niri_border_width"] = width_match.group(1)
        return colors

    def generate(self, colors: Dict[str, str], metadata: Dict[str, Any]) -> str:
        if self.source_key() in colors:
            content = colors[self.source_key()]
            for key, value in colors.items():
                if key.startswith("niri_") and key != "niri_border_width":
                    config_key = key.replace("niri_", "")
                    content = re.sub(
                        rf'({re.escape(config_key)}\s+)"[^"]+"',
                        rf'\g<1>"{value}"',
                        content,
                    )
            if "niri_border_width" in colors:
                content = re.sub(
                    r"(width\s+)[\d.]+", rf"\g<1>{colors['niri_border_width']}", content
                )
            return content

        width = colors.get("niri_border_width", "2.2")
        active = colors.get("niri_active-color", "#BE3F50")
        inactive = colors.get("niri_inactive-color", "#0e091d")
        urgent = colors.get("niri_urgent-color", "#14B9B5")
        return "\n".join(
            [
                "layout {",
                "    border {",
                f"        width {width}",
                f'        active-color "{active}"',
                f'        inactive-color "{inactive}"',
                f'        urgent-color "{urgent}"',
                "    }",
                "}",
            ]
        )

    def apply(self, theme_file: Path, target_config: Path):
        import shutil

        if not theme_file.exists() or theme_file.stat().st_size == 0:
            return
        if not target_config.exists():
            target_config.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(theme_file, target_config)
