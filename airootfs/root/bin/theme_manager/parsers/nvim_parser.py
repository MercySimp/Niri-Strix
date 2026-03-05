from pathlib import Path
from typing import Dict, Any
import re
from parsers.base import ThemeParser


class NvimParser(ThemeParser):
    @property
    def app_name(self):
        return "nvim"

    def parse(self, file_path: Path) -> Dict[str, str]:
        colors = {}
        with open(file_path, "r") as f:
            content = f.read()

        # Store full original file so generate() can rebuild it intact
        colors["nvim__source"] = content

        for match in re.finditer(
            r'hex_([a-fA-F0-9]+)\s*=\s*"(#[a-fA-F0-9]{6})"', content
        ):
            hex_name, color_value = match.groups()
            colors[f"nvim_hex_{hex_name}"] = color_value

        return colors

    def generate(self, colors: Dict[str, str], metadata: Dict[str, Any]) -> str:
        # Rebuild from original source, only swapping hex values
        if "nvim__source" in colors:
            content = colors["nvim__source"]
            for key, value in colors.items():
                if key.startswith("nvim_hex_"):
                    hex_name = key.replace("nvim_hex_", "")
                    content = re.sub(
                        rf'(hex_{re.escape(hex_name)}\s*=\s*)"#[a-fA-F0-9]{{6}}"',
                        rf'\1"{value}"',
                        content,
                    )
            return content

        # No source file stored — skip generating anything
        if not any(k.startswith("nvim_hex_") for k in colors):
            return ""

        # Fallback minimal palette (only used if source was never stored)
        lines = ["-- Color palette", "local colors = {"]
        for key, value in sorted(colors.items()):
            if key.startswith("nvim_hex_"):
                hex_name = key.replace("nvim_hex_", "")
                lines.append(f'  hex_{hex_name} = "{value}",')
        lines.append("}")
        lines.append("")
        lines.append("-- Apply your full highlight configuration here")
        lines.append("return colors")
        return "\n".join(lines)

    def apply(self, theme_file: Path, target_config: Path):
        import shutil

        if not theme_file.exists() or theme_file.stat().st_size == 0:
            return
        if not target_config.exists():
            target_config.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(theme_file, target_config)
