from pathlib import Path
from typing import Dict, Any
from parsers.base import ThemeParser

class KittyParser(ThemeParser):
    def parse(self, file_path: Path) -> Dict[str, str]:
        colors = {}
        with open(file_path, 'r') as f:
            for line in f:
                line = line.strip()
                if line and not line.startswith('#'):
                    parts = line.split(None, 1)
                    if len(parts) == 2:
                        key, value = parts
                        colors[f"kitty_{key}"] = value.strip()
        return colors

    def generate(self, colors: Dict[str, str], metadata: Dict[str, Any]) -> str:
        lines = []
        name = metadata.get('name', 'custom')
        author = metadata.get('author', 'Theme Manager')
        variant = metadata.get('variant', 'dark')
        lines.append(f"## name: {name}")
        lines.append(f"## author: {author}")
        lines.append(f'## variant: "{variant}"')
        lines.append("")

        for key, value in sorted(colors.items()):
            if key.startswith('kitty_'):
                config_key = key.replace('kitty_', '')
                padding = ' ' * max(1, 24 - len(config_key))
                lines.append(f"{config_key}{padding}{value}")

        return '\n'.join(lines)

    def apply(self, theme_file: Path, target_config: Path):
        if not target_config.exists():
            target_config.parent.mkdir(parents=True, exist_ok=True)
            target_config.touch()

        with open(target_config, 'r') as f:
            lines = f.readlines()

        lines = [l for l in lines if not l.strip().startswith('include themes/')]
        lines.insert(0, f'include themes/{theme_file.name}\n')

        with open(target_config, 'w') as f:
            f.writelines(lines)
