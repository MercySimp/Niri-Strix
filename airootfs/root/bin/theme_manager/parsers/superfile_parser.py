from pathlib import Path
from typing import Dict, Any
import re
from parsers.base import ThemeParser

class SuperfileParser(ThemeParser):
    def parse(self, file_path: Path) -> Dict[str, str]:
        """Parse superfile TOML theme file"""
        colors = {}
        with open(file_path, 'r') as f:
            for line in f:
                line = line.strip()
                if not line or line.startswith('#'):
                    continue
                
                # Parse key = "value"
                match = re.match(r'([a-zA-Z_]+)\s*=\s*"([^"]+)"', line)
                if match:
                    key, value = match.groups()
                    colors[f"superfile_{key}"] = value
                
                # Parse gradient array
                match = re.match(r'gradient_color\s*=\s*\[([^\]]+)\]', line)
                if match:
                    gradient_values = match.group(1)
                    color_matches = re.findall(r'"(#[a-fA-F0-9]{6})"', gradient_values)
                    for i, color in enumerate(color_matches):
                        colors[f"superfile_gradient_{i}"] = color
        
        return colors
    
    def generate(self, colors: Dict[str, str], metadata: Dict[str, Any]) -> str:
        """Generate superfile TOML theme file"""
        lines = [f'# Theme: {metadata.get("name", "custom")}\n']
        
        gradient_colors = []
        regular_colors = []
        
        for key, value in sorted(colors.items()):
            if key.startswith('superfile_'):
                config_key = key.replace('superfile_', '')
                if config_key.startswith('gradient_'):
                    gradient_colors.append(value)
                else:
                    regular_colors.append((config_key, value))
        
        if gradient_colors:
            gradient_str = ', '.join([f'"{c}"' for c in gradient_colors])
            lines.append(f'gradient_color = [{gradient_str}]\n')
        
        for key, value in regular_colors:
            lines.append(f'{key} = "{value}"')
        
        return '\n'.join(lines)
    
    def apply(self, theme_file: Path, target_config: Path):
        """Apply superfile theme"""
        if not target_config.exists():
            target_config.parent.mkdir(parents=True, exist_ok=True)
        
        with open(theme_file, 'r') as f:
            theme_content = f.read()
        
        with open(target_config, 'w') as f:
            f.write(theme_content)
