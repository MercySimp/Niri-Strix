from pathlib import Path
import json
from typing import Dict, List, Any, Optional

from config import THEME_MANAGER_DIR, THEMES_FILE, STATE_FILE, APP_CONFIGS, ACTIVE_CONFIGS, WALLS_DIR
from parsers.btop_parser import BtopParser
from parsers.dunst_parser import DunstParser
from parsers.kitty_parser import KittyParser
from parsers.niri_parser import NiriParser
from parsers.nvim_parser import NvimParser
from parsers.rofi_parser import RofiParser
from parsers.superfile_parser import SuperfileParser
from parsers.waybar_parser import WaybarParser
from wallpaper_manager import WallpaperManager

class ThemeManager:
    def __init__(self):
        self.parsers = {
            'btop': BtopParser(),
            'kitty': KittyParser(),
            'niri': NiriParser(),
            'nvim': NvimParser(),
            'waybar': WaybarParser(),      
            'superfile': SuperfileParser(), 
            'rofi': RofiParser(),          
            'dunst': DunstParser(),        
        }
        self.wallpaper_manager = WallpaperManager(WALLS_DIR)
        self.ensure_dirs()

    def ensure_dirs(self):
        THEME_MANAGER_DIR.mkdir(exist_ok=True, parents=True)
        for app_dir in APP_CONFIGS.values():
            app_dir.mkdir(parents=True, exist_ok=True)

    def list_themes(self) -> List[Dict[str, Any]]:
        if not THEMES_FILE.exists():
            return []
        try:
            with open(THEMES_FILE, 'r') as f:
                data = json.load(f)
            return data.get('themes', [])
        except:
            return []

    def get_theme(self, name: str) -> Optional[Dict[str, Any]]:
        themes = self.list_themes()
        for theme in themes:
            if theme['name'] == name:
                return theme
        return None

    def save_theme(self, theme: Dict[str, Any]) -> bool:
        try:
            themes = self.list_themes()
            existing = None
            for i, t in enumerate(themes):
                if t['name'] == theme['name']:
                    existing = i
                    break

            if existing is not None:
                themes[existing] = theme
            else:
                themes.append(theme)

            with open(THEMES_FILE, 'w') as f:
                json.dump({'themes': themes}, f, indent=2)

            self.generate_theme_files(theme)
            return True
        except Exception as e:
            print(f"Error saving theme: {e}")
            return False

    def delete_theme(self, name: str) -> bool:
        try:
            themes = self.list_themes()
            themes = [t for t in themes if t['name'] != name]

            with open(THEMES_FILE, 'w') as f:
                json.dump({'themes': themes}, f, indent=2)

            for app, theme_dir in APP_CONFIGS.items():
                theme_file = theme_dir / f"{name}.{self.get_extension(app)}"
                if theme_file.exists():
                    theme_file.unlink()

            return True
        except Exception as e:
            print(f"Error deleting theme: {e}")
            return False

    def generate_theme_files(self, theme: Dict[str, Any]):
        for app, parser in self.parsers.items():
            try:
                content = parser.generate(theme['colors'], {
                    'name': theme['name'],
                    'author': theme.get('author', 'Theme Manager'),
                    'variant': theme.get('variant', 'dark')
                })

                theme_dir = APP_CONFIGS[app]
                theme_file = theme_dir / f"{theme['name']}.{self.get_extension(app)}"

                with open(theme_file, 'w') as f:
                    f.write(content)
            except Exception as e:
                print(f"Error generating {app} theme: {e}")
    
    
    def apply_theme(self, name: str, apps: List[str], apply_wallpaper: bool = False, transition: str = "fade") -> bool:
        theme = self.get_theme(name)
        if not theme:
            return False

        try:
            # Apply colors to apps
            for app in apps:
                if app not in self.parsers:
                    continue

                theme_dir = APP_CONFIGS[app]
                theme_file = theme_dir / f"{name}.{self.get_extension(app)}"

                if theme_file.exists() and app in ACTIVE_CONFIGS:
                    parser = self.parsers[app]
                    parser.apply(theme_file, ACTIVE_CONFIGS[app])

            # Apply wallpaper BEFORE return
            if apply_wallpaper:
                self.wallpaper_manager.set_random_wallpaper(name, transition)

            # Save state with wallpaper info
            self.save_state({
                'current_theme': name, 
                'apps': apps,
                'wallpaper_enabled': apply_wallpaper,
                'wallpaper_transition': transition
            })
        
            return True
        except Exception as e:
            print(f"Error applying theme: {e}")
            return False

   
    def save_state(self, state: Dict[str, Any]):
        try:
            with open(STATE_FILE, 'w') as f:
                json.dump(state, f, indent=2)
        except:
            pass

    def get_extension(self, app: str) -> str:
        extensions = {
            'btop': 'theme',
            'kitty': 'conf',
            'niri': 'kdl',
            'nvim': 'lua',
            'waybar': 'css',
            'superfile': 'toml',
            'rofi': 'rasi',
            'dunst': 'conf',
        }
        return extensions.get(app, 'conf')

    def get_theme_wallpaper_info(self, theme_name: str) -> dict:
        """Get wallpaper information for a theme"""
        wallpapers = self.wallpaper_manager.get_theme_wallpapers(theme_name)
        return {
            'count': len(wallpapers),
            'wallpapers': wallpapers,
            'directory': self.wallpaper_manager.walls_dir / theme_name
        }

    def import_from_existing(self, name: str, author: str = "Imported"):
        colors = {}

        for app, parser in self.parsers.items():
            theme_dir = APP_CONFIGS[app]
            for theme_file in theme_dir.glob(f"*{name}*"):
                try:
                    app_colors = parser.parse(theme_file)
                    colors.update(app_colors)
                    break
                except Exception as e:
                    print(f"Error parsing {app}: {e}")

        if colors:
            theme = {
                'name': name,
                'author': author,
                'variant': 'dark',
                'colors': colors
            }
            return self.save_theme(theme)
        return False
