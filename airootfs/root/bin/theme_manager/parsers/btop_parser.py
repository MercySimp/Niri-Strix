from pathlib import Path
from typing import Dict, Any
import re
from parsers.base import ThemeParser

class BtopParser(ThemeParser):
    def parse(self, file_path: Path) -> Dict[str, str]:
        colors = {}
        with open(file_path, 'r') as f:
            for line in f:
                line = line.strip()
                if line.startswith('theme[') and '=' in line:
                    match = re.match(r'theme\[([^\]]+)\]\s*=\s*["\']?([^"\'\s]+)["\']?', line)
                    if match:
                        key, value = match.groups()
                        colors[f"btop_{key}"] = value
        return colors

    def generate(self, colors: Dict[str, str], metadata: Dict[str, Any]) -> str:
        lines = []
        name = metadata.get('name', 'custom')
        author = metadata.get('author', 'Theme Manager')
        lines.append(f"# Theme: {name}")
        lines.append(f"# Author: {author}")
        lines.append("")

        for key, value in sorted(colors.items()):
            if key.startswith('btop_'):
                theme_key = key.replace('btop_', '')
                lines.append(f'theme[{theme_key}]={value}')

        return '\n'.join(lines)

    def apply(self, theme_file: Path, target_config: Path):
        if not target_config.exists():
            return

        with open(target_config, 'r') as f:
            lines = f.readlines()

        theme_name = theme_file.stem
        updated = False
        for i, line in enumerate(lines):
            if line.strip().startswith('color_theme'):
                lines[i] = f'color_theme = "{theme_name}"\n'
                updated = True
                break

        if not updated:
            lines.append(f'color_theme = "{theme_name}"\n')

        with open(target_config, 'w') as f:
            f.writelines(lines)
