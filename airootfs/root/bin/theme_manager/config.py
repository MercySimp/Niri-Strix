from pathlib import Path

HOME = Path.home()
CONF_DIR = HOME / ".config"

APP_CONFIGS = {
    "niri": CONF_DIR / "niri/themes",
    "btop": CONF_DIR / "btop/themes",
    "dunst": CONF_DIR / "dunst/themes",
    "kitty": CONF_DIR / "kitty/themes",
    "superfile": CONF_DIR / "superfile/theme",
    "waybar": CONF_DIR / "waybar/themes/css",
    "nvim": CONF_DIR / "nvim/themes",
    "rofi": CONF_DIR / "rofi/colors",
}

ACTIVE_CONFIGS = {
    "niri": CONF_DIR / "niri/themes/current.kdl",
    "btop": CONF_DIR / "btop/themes/current.theme",
    "kitty": CONF_DIR / "kitty/themes/current.conf",
    "nvim": CONF_DIR / "nvim/lua/plugins/colorscheme.lua",
    "dunst": CONF_DIR / "dunst/dunstrc",
    "waybar": CONF_DIR / "waybar/theme.css",
    "superfile": CONF_DIR / "superfile/theme/current.toml",
    "rofi": CONF_DIR / "rofi/colors/current.rasi",
}

THEME_MANAGER_DIR = CONF_DIR / "theme-manager"
THEMES_FILE = THEME_MANAGER_DIR / "themes.json"
STATE_FILE = THEME_MANAGER_DIR / "state.json"
WALLS_DIR = CONF_DIR / "walls"

THEME_MANAGER_DIR.mkdir(parents=True, exist_ok=True)
for app_dir in APP_CONFIGS.values():
    app_dir.mkdir(parents=True, exist_ok=True)
