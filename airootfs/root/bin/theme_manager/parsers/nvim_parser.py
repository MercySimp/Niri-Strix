from pathlib import Path
from typing import Dict, Any
import re
from parsers.base import ThemeParser

class NvimParser(ThemeParser):
    def parse(self, file_path: Path) -> Dict[str, str]:
        colors = {}
        with open(file_path, 'r') as f:
            content = f.read()

        for match in re.finditer(r'hex_([a-fA-F0-9]+)\s*=\s*"(#[a-fA-F0-9]{6})"', content):
            hex_name, color_value = match.groups()
            colors[f"nvim_hex_{hex_name}"] = color_value

        return colors

    def generate(self, colors: Dict[str, str], metadata: Dict[str, Any]) -> str:
        lines = ['-- Color palette']
        lines.append('local colors = {')

        for key, value in sorted(colors.items()):
            if key.startswith('nvim_hex_'):
                hex_name = key.replace('nvim_hex_', '')
                lines.append(f'  hex_{hex_name} = "{value}",')

        lines.append('}')
        lines.append('')
        lines.append('-- Apply your full highlight configuration here')
        lines.append('return colors')

        return '\n'.join(lines)

    def apply(self, theme_file: Path, target_config: Path):
        import shutil
        if not target_config.exists():
            target_config.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(theme_file, target_config)
