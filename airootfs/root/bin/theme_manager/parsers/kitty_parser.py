import re
from pathlib import Path
from typing import Dict, Any
from parsers.base import ThemeParser


class KittyParser(ThemeParser):
    @property
    def app_name(self):
        return "kitty"

    def parse(self, file_path: Path) -> Dict[str, str]:
        colors = {}
        self.store_source(file_path, colors)
        with open(file_path, "r") as f:
            for line in f:
                line = line.strip()
                if line and not line.startswith("#"):
                    parts = line.split(None, 1)
                    if len(parts) == 2:
                        key, value = parts
                        colors[f"kitty_{key}"] = value.strip()
        return colors

    def generate(self, colors: Dict[str, str], metadata: Dict[str, Any]) -> str:
        if self.source_key() in colors:
            content = colors[self.source_key()]
            for key, value in colors.items():
                if key.startswith("kitty_"):
                    config_key = key.replace("kitty_", "")
                    content = re.sub(
                        rf"^({re.escape(config_key)}\s+)\S+",
                        rf"\g<1>{value}",
                        content,
                        flags=re.MULTILINE,
                    )
            return content

        lines = []
        name = metadata.get("name", "custom")
        author = metadata.get("author", "Theme Manager")
        lines.append(f"## name: {name}")
        lines.append(f"## author: {author}")
        lines.append("")
        for key, value in sorted(colors.items()):
            if key.startswith("kitty_"):
                config_key = key.replace("kitty_", "")
                padding = " " * max(1, 24 - len(config_key))
                lines.append(f"{config_key}{padding}{value}")
        return "\n".join(lines)

    def apply(self, theme_file: Path, target_config: Path):
        import shutil

        if not theme_file.exists() or theme_file.stat().st_size == 0:
            return
        if not target_config.exists():
            target_config.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(theme_file, target_config)
