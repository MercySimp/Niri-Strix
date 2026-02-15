from pathlib import Path
from typing import Dict, Any
import re
from parsers.base import ThemeParser

class NiriParser(ThemeParser):
    def parse(self, file_path: Path) -> Dict[str, str]:
        colors = {}
        with open(file_path, 'r') as f:
            content = f.read()

        for match in re.finditer(r'(active-color|inactive-color|urgent-color)\s+"([^"]+)"', content):
            key, value = match.groups()
            colors[f"niri_{key}"] = value

        width_match = re.search(r'width\s+([\d.]+)', content)
        if width_match:
            colors['niri_border_width'] = width_match.group(1)

        return colors

    def generate(self, colors: Dict[str, str], metadata: Dict[str, Any]) -> str:
        width = colors.get('niri_border_width', '2.2')
        active = colors.get('niri_active-color', '#BE3F50')
        inactive = colors.get('niri_inactive-color', '#0e091d')
        urgent = colors.get('niri_urgent-color', '#14B9B5')

        lines = [
            'layout {',
            '    border {',
            f'        width {width}',
            f'        active-color "{active}"',
            f'        inactive-color "{inactive}"',
            f'        urgent-color "{urgent}"',
            '    }',
            '}',
        ]
        return '\n'.join(lines)

    def apply(self, theme_file: Path, target_config: Path):
        if not target_config.exists():
            return

        with open(target_config, 'r') as f:
            content = f.read()

        with open(theme_file, 'r') as f:
            theme_content = f.read()

        if 'layout {' in content:
            pattern = r'layout\s*{[^}]*border\s*{[^}]*}[^}]*}'
            content = re.sub(pattern, theme_content.strip(), content, flags=re.DOTALL)
        else:
            content += '\n\n' + theme_content

        with open(target_config, 'w') as f:
            f.write(content)
