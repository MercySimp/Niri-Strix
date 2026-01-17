#!/usr/bin/env bash

# Import Current Theme (as you already do)
source "$HOME"/.config/rofi/applets/shared/theme.bash
theme="$type/$style"

# Set to true when going directly to a submenu, so we can exit directly
BACK_TO_EXIT=false

back_to() {
  local parent_menu="$1"

  if [[ "$BACK_TO_EXIT" == "true" ]]; then
    exit 0
  elif [[ -n "$parent_menu" ]]; then
    "$parent_menu"
  else
    show_main_menu
  fi
}

menu() {
  local prompt="$1"
  local options="$2"
  local extra="$3"
  local preselect="$4"
  list_col='1'
  list_row='10'

  # Convert the old "extra" into an array, but we will ignore width/height flags
  # because rofi styling is handled by your theme.
  read -r -a args <<<"$extra"

  # Preselect: walker used a 1-based index; rofi wants either -a or -selected-row.
  # We'll compute the index the same way and use -a (accept entry).
  if [[ -n "$preselect" ]]; then
    local index
    index=$(echo -e "$options" | grep -nxF "$preselect" | cut -d: -f1)
    if [[ -n "$index" ]]; then
      # Convert to 0-based for rofi
      index=$((index - 1))
      args+=("-a" "$index")
    fi
  fi

  # Call rofi in dmenu mode with your theme.
  # The old script used --dmenu and printed options line-by-line; rofi does the same.
  echo -e "$options" | rofi -theme-str "listview {columns: $list_col; lines: $list_row;}" -dmenu -theme "$theme" -p "$prompt…" "${args[@]}"
}

terminal() {
  xdg-terminal-exec --app-id="floating" "$@"
}

open_in_editor() {
  notify-send "Editing config file" "$1"
  strix-launch-editor "$1"
}

install() {
  terminal sh -c "echo 'Installing $1...'; sudo pacman -S --noconfirm $2"
}

install_and_launch() {
  terminal sh -c "echo 'Installing $1...'; sudo pacman -S --noconfirm $2 && setsid gtk-launch $3"
}

install_font() {
  terminal sh -c "echo 'Installing $1...'; sudo pacman -S --noconfirm --needed $2 && sleep 2 && omarchy-font-set '$3'"
}

install_terminal() {
  terminal strix-install-terminal "$1"
}

aur_install() {
  terminal sh -c "echo 'Installing $1 from AUR...'; yay -S --noconfirm $2"
}

aur_install_and_launch() {
  terminal sh -c "echo 'Installing $1 from AUR...'; yay -S --noconfirm $2 && setsid gtk-launch $3"
}

show_style_menu() {
  case $(menu "Style" "󰸌  Theme\n  Font\n  Background\n  Niri\n󱄄  Screensaver") in
    *Theme*) show_theme_menu ;;
    *Font*) show_font_menu ;;
    *Background*) terminal "bash" "-c" "$HOME/.config/walls/toggle-walls.sh" ;; # Move to Bin
    *Niri*) open_in_editor "$HOME/.config/niri/config.kdl" ;;
    *Screensaver*) open_in_editor ~/.config/omarchy/branding/screensaver.txt ;;
    *) show_main_menu ;;
  esac
}

show_theme_menu() {
  # Old: omarchy-launch-walker -m menus:omarchythemes --width 800 --minheight 400
  # For rofi, you likely have/need a separate script or mode; here we just call rofi app launcher
  # or you can replace this line with your own rofi-based theme selector.
  rofi -show drun -theme "$theme"
}

#Set up Font Selection File
show_font_menu() {
  theme=$(menu "Font" "$(fc-list :spacing=100 -f "%{family[0]}\n" | grep -v -i -E 'emoji|signwriting|omarchy' | sort -u)" "--width 350" "$(grep -oP 'font-family:\s*["'\'']?\K[^;"'\'']+' ~/.config/waybar/style.css | head -n1)")
  if [[ "$theme" == "CNCLD" || -z "$theme" ]]; then
    back_to show_style_menu
  else
    omarchy-font-set "$theme"
  fi
}

#done
show_setup_menu() {
  local options="  Audio\n  Wifi\n󰂯  Bluetooth\n󱐋  Power Profile\n󰍹  Monitors"
  [ -f $HOME/.config/niri/binds.kdl ] && options="$options\n  Keybindings"
  [ -f $HOME/.config/niri/input.kdl ] && options="$options\n  Input"
  options="$options\n  Defaults\n󰱔  DNS\n  Config"

  case $(menu "Setup" "$options") in
    *Audio*) "/home/tonys/.config/rofi/applets/bin/volume.sh" ;;
    *Wifi*) terminal "impala" ;;
    *Bluetooth*) terminal 'bluetui' ;;
    *Power*) show_setup_power_menu ;;
    *Monitors*) open_in_editor $HOME/.config/niri/outputs.kdl ;;
    *Keybindings*) open_in_editor $HOME/.config/niri/binds.kdl ;;
    *Input*) open_in_editor $HOME/.config/niri/input.kdl ;;
    *Defaults*) open_in_editor $HOME/.config/mimeapps.list ;;
    *DNS*) terminal strix-setup-dns ;;
    *Config*) show_setup_config_menu ;;
    *) show_main_menu ;;
  esac
}

#done
show_setup_power_menu() {
  profile=$(menu "Power Profile" "$(powerprofilesctl list | awk '/^\s*[* ]\s*[a-zA-Z0-9\-]+:$/ { gsub(/^[*[:space:]]+|:$/,""); print }' | tac)" "" "$(powerprofilesctl get)")

  if [[ "$profile" == "CNCLD" || -z "$profile" ]]; then
    back_to show_setup_menu
  else
    powerprofilesctl set "$profile"
  fi
}

show_setup_config_menu() {
  case $(menu "Setup" "  Niri\n  Swayidle\n  Swaylock\n  Hyprsunset\n  Swayosd\n󰌧  Rofi\n󰍜  Waybar") in
    *Niri*) open_in_editor $HOME/.config/niri/config.kdl ;;
    *Swayidle*) open_in_editor $HOME/.config/sway/idle && omarchy-restart-hypridle ;;
    *Swaylock*) open_in_editor $HOME/.config/sway/lock ;;
    *Hyprsunset*) open_in_editor ~/.config/hypr/hyprsunset.conf && omarchy-restart-hyprsunset ;;
    *Swayosd*) open_in_editor ~/.config/swayosd/config.toml && omarchy-restart-swayosd ;;
    *Rofi*) open_in_editor ~/.config/rofi/config.toml && omarchy-restart-walker ;;
    *Waybar*) open_in_editor ~/.config/waybar/config.jsonc && omarchy-restart-waybar ;;
    *) show_main_menu ;;
  esac
}

#done
show_install_menu() {
  case $(menu "Install" "󰣇  Package\n󰣇  AUR\n  Web App\n  TUI\n  Service\n󰵮  Development\n  Editor\n  Terminal\n󰍲  Windows\n  Gaming") in
    *Package*) terminal strix-install-pacman ;;
    *AUR*) terminal strix-install-aur ;;
    *Web*) terminal install-webapp.sh ;;
    *TUI*) terminal strix-install-tui ;;
    *Development*) show_install_development_menu ;;
    *Editor*) show_install_editor_menu ;;
    *Terminal*) show_install_terminal_menu ;;
    *Windows*) terminal "strix-windows-vm" "install" ;;
    *Gaming*) show_install_gaming_menu ;;
    *) show_main_menu ;;
  esac
}

#done
show_install_editor_menu() {
  case $(menu "Install" "  VSCode\n  Cursor\n  Zed\n  Sublime Text\n  Helix\n  Emacs") in
    *VSCode*) terminal "strix-install-vscode" ;;
    *Cursor*) install_and_launch "Cursor" "cursor-bin" "cursor" ;;
    *Zed*) terminal "echo 'Installing Zed...'; sudo pacman -S zed && setsid gtk-launch dev.zed.Zed" ;;
    *Sublime*) install_and_launch "Sublime Text" "sublime-text-4" "sublime_text" ;;
    *Helix*) install "Helix" "helix" ;;
    *Emacs*) install "Emacs" "emacs-wayland" && systemctl --user enable --now emacs.service ;;
    *) show_install_menu ;;
  esac
}

#done
show_install_terminal_menu() {
  case $(menu "Install" "  Alacritty\n  Ghostty\n  Kitty") in
    *Alacritty*) install_terminal "alacritty" ;;
    *Ghostty*) install_terminal "ghostty" ;;
    *Kitty*) install_terminal "kitty" ;;
    *) show_install_menu ;;
  esac
}

#done
show_install_gaming_menu() {
  case $(menu "Install" "  Steam\n  RetroArch [AUR]\n  Lutris [AUR]") in
    *Steam*) install_and_launch "steam" "steam" "steam";;
    *RetroArch*) aur_install_and_launch "RetroArch" "retroarch retroarch-assets libretro libretro-fbneo" "com.libretro.RetroArch.desktop" ;;
    *Lutris*) aur_install_and_launch "Lutris" "lutris-git" "lutris.desktop" ;;
    *) show_install_menu ;;
  esac
}
#done
show_install_development_menu() {
  case $(menu "Install" "󰫏  Ruby on Rails\n  Docker DB\n  JavaScript\n  Go\n  PHP\n  Python\n  Elixir\n  Zig\n  Rust\n  Java\n  .NET\n  OCaml\n  Clojure") in
    *Rails*) terminal "strix-dev-install" "ruby" ;;
    *Docker*) terminal "strix-dev-install" "docker" ;;
    *JavaScript*) show_install_javascript_menu ;;
    *Go*) terminal "strix-dev-install" "go" ;;
    *PHP*) show_install_php_menu ;;
    *Python*) terminal "strix-dev-install" "python" ;;
    *Elixir*) show_install_elixir_menu ;;
    *Zig*) terminal "strix-dev-install" "zig" ;;
    *Rust*) terminal "strix-dev-install" "rust" ;;
    *Java*) terminal "strix-dev-install" "java" ;;
    *NET*) terminal "strix-dev-install" "dotnet" ;;
    *OCaml*) terminal "strix-dev-install" "ocaml" ;;
    *Clojure*) terminal "strix-dev-install" "clojure" ;;
    *) show_install_menu ;;
  esac
}
#done
show_install_javascript_menu() {
  case $(menu "Install" "  Node.js\n  Bun\n  Deno") in
    *Node*) terminal "strix-dev-install" " node" ;;
    *Bun*) terminal "strix-dev-install" " bun" ;;
    *Deno*) terminal "strix-dev-install" " deno" ;;
    *) show_install_development_menu ;;
  esac
}
#done
show_install_php_menu() {
  case $(menu "Install" "  PHP\n  Laravel\n  Symfony") in
    *PHP*) terminal "strix-dev-install" "php" ;;
    *Laravel*) terminal "strix-dev-install" "laravel" ;;
    *Symfony*) terminal "strix-dev-install" "symfony" ;;
    *) show_install_development_menu ;;
  esac
}

#done
show_install_elixir_menu() {
  case $(menu "Install" "  Elixir\n  Phoenix") in
    *Elixir*) terminal "strix-dev-install" "elixir" ;;
    *Phoenix*) terminal "strix-dev-install" "phoenix" ;;
    *) show_install_development_menu ;;
  esac
}

show_remove_menu() {
  case $(menu "Remove" "󰣇  Package\n  Web App\n  TUI\n󰸌  Theme\n󰍲  Windows") in
    *Package*) terminal omarchy-pkg-remove ;;
    *Web*) terminal omarchy-webapp-remove ;;
    *TUI*) terminal omarchy-tui-remove ;;
    *Theme*) terminal omarchy-theme-remove ;;
    *Windows*) terminal "strix-windows-vm" "remove" ;;
    *) show_main_menu ;;
  esac
}

show_update_menu() {
  case $(menu "Update" " Arch\n  Config\n󰸌  Extra Themes\n󰇅  Hardware\n  Password\n  Timezone\n  Time") in
    *Arch*) terminal strix-update-arch ;;
    *Config*) show_update_config_menu ;;
    *Themes*) terminal omarchy-theme-update ;; # Seperate Script
    *Hardware*) show_update_hardware_menu ;;
    *Timezone*) terminal strix-tz-select ;;
    *Time*) terminal echo "Updating time..." && sudo systemctl restart systemd-timesyncd ;;
    *Password*) show_update_password_menu ;;
    *) show_main_menu ;;
  esac
}

# This Menu Board overwrites the current configs with the original configs
show_update_config_menu() {
  case $(menu "Use default config" "  Hyprland\n  Hypridle\n  Hyprlock\n  Hyprsunset\n󱣴  Plymouth\n  Swayosd\n󰌧  Walker\n󰍜  Waybar") in
    *Hyprland*) terminal omarchy-refresh-hyprland ;;
    *Hypridle*) terminal omarchy-refresh-hypridle ;;
    *Hyprlock*) terminal omarchy-refresh-hyprlock ;;
    *Hyprsunset*) terminal omarchy-refresh-hyprsunset ;;
    *Plymouth*) terminal omarchy-refresh-plymouth ;;
    *Swayosd*) terminal omarchy-refresh-swayosd ;;
    *Walker*) terminal omarchy-refresh-walker ;;
    *Waybar*) terminal omarchy-refresh-waybar ;;
    *) show_update_menu ;;
  esac
}

#done
show_update_hardware_menu() {
  case $(menu "Restart" "  Audio\n󱚾  Wi-Fi\n󰂯  Bluetooth") in
    *Audio*) terminal echo -e "Restarting pipewire audio service...\n" && systemctl --user restart pipewire.service ;;
    *Wi-Fi*) terminal echo -e "Unblocking wifi...\n" && rfkill unblock wifi && rfkill list wifi ;;
    *Bluetooth*) terminal echo -e "Unblocking bluetooth...\n" && rfkill unblock bluetooth && rfkill list bluetooth ;;
    *) show_update_menu ;;
  esac
}

#done
show_update_password_menu() {
  case $(menu "Update Password" "  Drive Encryption\n  User") in
    *Drive*) terminal strix-encrypt-drive ;;
    *User*) terminal passwd ;;
    *) show_update_menu ;;
  esac
}

#done
show_system_menu() {
  "/home/tonys/.config/rofi/powermenu/type-1/powermenu.sh"
}

show_main_menu() {
  go_to_menu "$(menu "Go" "󰀻  Apps\n  Style\n  Setup\n󰉉  Install\n󰭌  Remove\n  Update\n  About\n  System")"
}

go_to_menu() {
  case "${1,,}" in
    *apps*) "bash" "-c" "tofi-drun --drun-launch=true || pkill tofi-drun" ;;  # was: walker -p "Launch…"
    *share*) show_share_menu ;;
    *style*) show_style_menu ;;
    *theme*) show_theme_menu ;;
    *screenshot*) show_screenshot_menu ;;
    *screenrecord*) show_screenrecord_menu ;;
    *setup*) show_setup_menu ;;
    *power*) show_setup_power_menu ;;
    *install*) show_install_menu ;;
    *remove*) show_remove_menu ;;
    *update*) show_update_menu ;;
    *about*) omarchy-launch-about ;;
    *system*) show_system_menu ;;
  esac
}

if [[ -n "$1" ]]; then
  BACK_TO_EXIT=true
  go_to_menu "$1"
else
  show_main_menu
fi
