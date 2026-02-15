from pathlib import Path
from typing import Dict, Any
import re
from parsers.base import ThemeParser

class RofiParser(ThemeParser):
    def parse(self, file_path: Path) -> Dict[str, str]:
        """Parse rofi rasi theme file"""
        colors = {}
        with open(file_path, 'r') as f:
            content = f.read()
        
        # Parse color definitions inside * { }
        for match in re.finditer(r'(\w+):\s*(#[a-fA-F0-9]{6,8}|hsl\([^)]+\));', content):
            key, value = match.groups()
            colors[f"rofi_{key}"] = value
        
        return colors
    
    def generate(self, colors: Dict[str, str], metadata: Dict[str, Any]) -> str:
        """Generate rofi rasi theme file"""
        lines = [
            f'/* Theme: {metadata.get("name", "custom")} */',
            '',
            '* {'
        ]
        
        for key, value in sorted(colors.items()):
            if key.startswith('rofi_'):
                color_name = key.replace('rofi_', '')
                lines.append(f'    {color_name}: {value};')
        
        lines.append('}')
        return '\n'.join(lines)
    
    def apply(self, theme_file: Path, target_config: Path):
        """Apply rofi theme"""
        if not target_config.exists():
            target_config.parent.mkdir(parents=True, exist_ok=True)
        
        import shutil
        shutil.copy2(theme_file, target_config)
