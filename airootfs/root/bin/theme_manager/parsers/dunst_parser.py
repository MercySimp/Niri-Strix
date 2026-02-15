from pathlib import Path
from typing import Dict, Any
import re
from parsers.base import ThemeParser

class DunstParser(ThemeParser):
    def parse(self, file_path: Path) -> Dict[str, str]:
        """Parse dunst theme file (INI format)"""
        colors = {}
        with open(file_path, 'r') as f:
            current_section = None
            for line in f:
                line = line.strip()
                
                # Track sections
                if line.startswith('[') and line.endswith(']'):
                    current_section = line[1:-1]
                    continue
                
                # Parse key = value in urgency sections
                if current_section and 'urgency' in current_section:
                    match = re.match(r'(background|foreground|frame_color)\s*=\s*"([^"]+)"', line)
                    if match:
                        key, value = match.groups()
                        colors[f"dunst_{current_section}_{key}"] = value
                
                # Parse frame_color in global section
                if not current_section or current_section == 'global':
                    match = re.match(r'frame_color\s*=\s*"([^"]+)"', line)
                    if match:
                        colors["dunst_frame_color"] = match.group(1)
        
        return colors
    
    def generate(self, colors: Dict[str, str], metadata: Dict[str, Any]) -> str:
        """Generate dunst theme file"""
        lines = [f'# Theme: {metadata.get("name", "custom")}\n']
        
        # Global frame color
        if 'dunst_frame_color' in colors:
            lines.append('[global]')
            lines.append(f'frame_color = "{colors["dunst_frame_color"]}"')
            lines.append('')
        
        # Urgency levels
        for urgency in ['low', 'normal', 'critical']:
            section_colors = {k: v for k, v in colors.items() if f'urgency_{urgency}' in k}
            if section_colors:
                lines.append(f'[urgency_{urgency}]')
                for key, value in sorted(section_colors.items()):
                    color_key = key.split('_')[-1]
                    lines.append(f'{color_key} = "{value}"')
                lines.append('')
        
        return '\n'.join(lines)
    
    def apply(self, theme_file: Path, target_config: Path):
        """Apply dunst theme"""
        if not target_config.exists():
            return
        
        with open(theme_file, 'r') as f:
            theme_content = f.read()
        
        with open(target_config, 'r') as f:
            content = f.read()
        
        # Replace urgency sections
        for urgency in ['low', 'normal', 'critical']:
            pattern = rf'\[urgency_{urgency}\].*?(?=\[|$)'
            content = re.sub(pattern, '', content, flags=re.DOTALL)
        
        content += '\n\n' + theme_content
        
        with open(target_config, 'w') as f:
            f.write(content)
