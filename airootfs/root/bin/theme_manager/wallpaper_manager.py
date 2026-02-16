from pathlib import Path
import subprocess
import random
from typing import Optional, List

class WallpaperManager:
    """Manage wallpapers using swww"""

    def __init__(self, walls_dir: Path):
        self.walls_dir = walls_dir
        self.walls_dir.mkdir(parents=True, exist_ok=True)

    def get_theme_wallpapers(self, theme_name: str) -> List[Path]:
        """Get all wallpaper images for a theme"""
        theme_dir = self.walls_dir / theme_name
        if not theme_dir.exists():
            return []

        # Supported image formats
        extensions = ['*.jpg', '*.jpeg', '*.png', '*.gif', '*.bmp', '*.webp']
        wallpapers = []

        for ext in extensions:
            wallpapers.extend(theme_dir.glob(ext))
            # Also check uppercase
            wallpapers.extend(theme_dir.glob(ext.upper()))

        return sorted(wallpapers)

    def set_wallpaper(self, image_path: Path, transition: str = "fade") -> bool:
        """Set wallpaper using swww"""
        if not image_path.exists():
            print(f"Wallpaper not found: {image_path}")
            return False

        try:
            # Check if swww daemon is running
            result = subprocess.run(
                ['pgrep', '-x', 'swww-daemon'],
                capture_output=True
            )

            # Start daemon if not running
            if result.returncode != 0:
                print("Starting swww daemon...")
                subprocess.Popen(
                    ['swww-daemon'],
                    stdout=subprocess.DEVNULL,
                    stderr=subprocess.DEVNULL
                )
                # Give it a moment to start
                import time
                time.sleep(0.5)

            # Set the wallpaper with transition
            cmd = ['swww', 'img', str(image_path), '--transition-type', transition]
            result = subprocess.run(cmd, capture_output=True, text=True)

            if result.returncode == 0:
                print(f"Wallpaper set: {image_path.name}")
                return True
            else:
                print(f"Error setting wallpaper: {result.stderr}")
                return False

        except FileNotFoundError:
            print("swww not found. Install it with: paru -S swww")
            return False
        except Exception as e:
            print(f"Error setting wallpaper: {e}")
            return False

    def set_random_wallpaper(self, theme_name: str, transition: str = "fade") -> bool:
        """Set a random wallpaper from theme directory"""
        wallpapers = self.get_theme_wallpapers(theme_name)

        if not wallpapers:
            print(f"No wallpapers found for theme: {theme_name}")
            return False

        wallpaper = random.choice(wallpapers)
        return self.set_wallpaper(wallpaper, transition)

    def create_theme_wallpaper_dir(self, theme_name: str) -> Path:
        """Create wallpaper directory for a theme"""
        theme_dir = self.walls_dir / theme_name
        theme_dir.mkdir(parents=True, exist_ok=True)
        return theme_dir

    def get_available_transitions(self) -> List[str]:
        """Get list of available swww transitions"""
        return [
            "fade",
            "left",
            "right",
            "top",
            "bottom",
            "wipe",
            "wave",
            "grow",
            "center",
            "any",
            "outer",
            "random"
        ]
