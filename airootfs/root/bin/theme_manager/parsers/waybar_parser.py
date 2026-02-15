from pathlib import Path
from typing import Dict, Any
import re
from parsers.base import ThemeParser

class WaybarParser(ThemeParser):
    def parse(self, file_path: Path) -> Dict[str, str]:
        """Parse waybar CSS theme file"""
        colors = {}
        with open(file_path, 'r') as f:
            content = f.read()
        
        # Parse @define-color lines
        for match in re.finditer(r'@define-color\s+(\S+)\s+(#[a-fA-F0-9]{6}|hsl\([^)]+\));', content):
            color_name, color_value = match.groups()
            
            # Special: display green #BE3F50 as "border" to user
            if color_name == 'green' and '#BE3F50' in color_value.upper():
                colors[f"waybar_border"] = color_value
            else:
                colors[f"waybar_{color_name}"] = color_value
        
        return colors
    
    def generate(self, colors: Dict[str, str], metadata: Dict[str, Any]) -> str:
        """Generate waybar CSS theme file"""
        lines = [f'/* {metadata.get("name", "custom")} */\n']
        
        for key, value in sorted(colors.items()):
            if key.startswith('waybar_'):
                color_name = key.replace('waybar_', '')
                
                # Write border as green with comment
                if color_name == 'border':
                    lines.append(f'@define-color green           {value}; /* border */')
                else:
                    lines.append(f'@define-color {color_name:20} {value};')
        
        return '\n'.join(lines)
    
    def apply(self, theme_file: Path, target_config: Path):
        """Apply waybar theme by replacing color definitions"""
        if not target_config.exists():
            target_config.parent.mkdir(parents=True, exist_ok=True)
            target_config.touch()
        
        with open(target_config, 'r') as f:
            content = f.read()
        
        with open(theme_file, 'r') as f:
            theme_content = f.read()
        
        # Remove old @define-color lines
        content = re.sub(r'@define-color[^;]+;[^\n]*\n?', '', content)
        # Prepend new colors
        content = theme_content + '\n\n' + content
        
        with open(target_config, 'w') as f:
            f.write(content)
