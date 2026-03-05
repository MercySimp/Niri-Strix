from pathlib import Path
from typing import Dict, Any
import re
from parsers.base import ThemeParser


class SuperfileParser(ThemeParser):
    @property
    def app_name(self):
        return "superfile"

    def parse(self, file_path: Path) -> Dict[str, str]:
        colors = {}
        self.store_source(file_path, colors)
        with open(file_path, "r") as f:
            for line in f:
                line = line.strip()
                if not line or line.startswith("#"):
                    continue
                match = re.match(r'([a-zA-Z_]+)\s*=\s*"([^"]+)"', line)
                if match:
                    key, value = match.groups()
                    colors[f"superfile_{key}"] = value
                match = re.match(r"gradient_color\s*=\s*\[([^\]]+)\]", line)
                if match:
                    for i, color in enumerate(
                        re.findall(r'"(#[a-fA-F0-9]{6})"', match.group(1))
                    ):
                        colors[f"superfile_gradient_{i}"] = color
        return colors

    def generate(self, colors: Dict[str, str], metadata: Dict[str, Any]) -> str:
        if self.source_key() in colors:
            content = colors[self.source_key()]
            for key, value in colors.items():
                if key.startswith("superfile_") and not key.startswith(
                    "superfile_gradient_"
                ):
                    config_key = key.replace("superfile_", "")
                    content = re.sub(
                        rf'^({re.escape(config_key)}\s*=\s*)"[^"]+"',
                        rf'\g<1>"{value}"',
                        content,
                        flags=re.MULTILINE,
                    )
            return content

        lines = [f"# Theme: {metadata.get('name', 'custom')}\n"]
        gradient_colors = [
            v for k, v in sorted(colors.items()) if k.startswith("superfile_gradient_")
        ]
        if gradient_colors:
            gradient_str = ", ".join(f'"{c}"' for c in gradient_colors)
            lines.append(f"gradient_color = [{gradient_str}]\n")
        for key, value in sorted(colors.items()):
            if key.startswith("superfile_") and not key.startswith(
                "superfile_gradient_"
            ):
                lines.append(f'{key.replace("superfile_", "")} = "{value}"')
        return "\n".join(lines)

    def apply(self, theme_file: Path, target_config: Path):
        import shutil

        if not theme_file.exists() or theme_file.stat().st_size == 0:
            return
        if not target_config.exists():
            target_config.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(theme_file, target_config)
