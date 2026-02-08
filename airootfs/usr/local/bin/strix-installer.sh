#!/usr/bin/env bash
# Custom Arch Installer TUI using gum
# Front-end for archinstall (linux-zen + Limine + Btrfs + optional LUKS)

set -eEo pipefail

# -----------------------------
# State
# -----------------------------
DISK=""
HOSTNAME=""
USERNAME=""
FULLNAME=""
EMAIL=""
TIMEZONE=""
KEYMAP=""
ENCRYPT=""   # "Yes"/"No"
USERPASS=""
ROOTPASS=""
NIRI_STRIX_REPO="MercySimp/Niri-Strix"
PARU_REPO="Morganamilo/Paru"
PARU_DIR="${HOME}/.local/share/paru"
NIRI_STRIX_DIR="${HOME}/.local/share/niri-strix"
PACKAGES_FILE="${NIRI_STRIX_DIR}/base-packages.txt"
PACKAGES_AUR="${NIRI_STRIX_DIR}/aur-packages.txt"

# -----------------------------
# Helpers
# -----------------------------
pause() { gum confirm "Continue?" >/dev/null || exit 1; }

banner() {
  gum style --border normal --margin "1 2" --padding "1 2" \
    --border-foreground 212 "$(cat <<'EOF'
   ▄████████     ███        ▄████████  ▄█  ▀████    ▐████▀ 
  ███    ███ ▀█████████▄   ███    ███ ███    ███▌   ████▀  
  ███    █▀     ▀███▀▀██   ███    ███ ███▌    ███  ▐███    
  ███            ███   ▀  ▄███▄▄▄▄██▀ ███▌    ▀███▄███▀    
▀███████████     ███     ▀▀███▀▀▀▀▀   ███▌    ████▀██▄     
         ███     ███     ▀███████████ ███    ▐███  ▀███    
   ▄█    ███     ███       ███    ███ ███   ▄███     ███▄  
 ▄████████▀     ▄████▀     ███    ███ █▀   ████       ███▄ 
                           ███    ███                      
EOF
)"
}

summary() {
  gum style --margin "1 2" --padding "0 2" --border normal --border-foreground 240 \
"Disk:       ${DISK:-<not set>}
Hostname:   ${HOSTNAME:-<not set>}
Username:   ${USERNAME:-<not set>}
Full name:  ${FULLNAME:-<not set>}
Email:      ${EMAIL:-<not set>}
Timezone:   ${TIMEZONE:-<not set>}
Keymap:     ${KEYMAP:-<not set>}
Encryption: ${ENCRYPT:-<not set>}"
}

# -----------------------------
# Input sections
# -----------------------------
pick_disk() {
  echo "Scanning disks..."

  # Always get full /dev paths (-p / --paths behavior) so later lsblk calls work
  mapfile -t disk_lines < <(lsblk -dpno NAME,SIZE,MODEL | grep -E '^/dev/(nvme|sd|vd)')

  ((${#disk_lines[@]})) || { gum style --foreground 196 "No disks found."; return 1; }

  local choices=()
  for line in "${disk_lines[@]}"; do
    local disk size model
    disk=$(awk '{print $1}' <<<"$line")
    size=$(awk '{print $2}' <<<"$line")
    model=$(cut -d' ' -f3- <<<"$line")

    # Build an OS hint based on partition FS types
    local os_hint="Empty"
    while read -r p fstype _; do
      case "$fstype" in
        ntfs) os_hint="Windows" ;;
        vfat) [[ "$os_hint" == "Empty" ]] && os_hint="EFI/Boot" ;;
        ext4|ext3|btrfs|xfs|f2fs) [[ "$os_hint" != "Windows" ]] && os_hint="Linux" ;;
      esac
    done < <(lsblk -pnro NAME,FSTYPE "$disk" | tail -n +2)

    local part_count
    part_count=$(lsblk -pnro NAME "$disk" | tail -n +2 | wc -l)

    choices+=("$disk  ($size)  $model  |  $part_count partitions  |  $os_hint")
  done

  local sel
  sel=$(printf '%s\n' "${choices[@]}" | gum choose --height 12 --header "Select installation disk (will be wiped)")
  DISK=$(awk '{print $1}' <<<"$sel")

  # Show a detailed preview for confirmation
  local detail
  detail=$(lsblk -p -o NAME,SIZE,FSTYPE,LABEL,MOUNTPOINT,PARTTYPE "$DISK")
  gum style --border normal --padding "1 2" "$detail"

  gum confirm "ERASE ALL DATA ON $DISK and continue?" --default=false || { DISK=""; return 1; }
}

pick_timezone() {
  mapfile -t choices <<EOF
America/New_York  [Eastern US]
America/Chicago   [Central US]
America/Denver    [Mountain US]
America/Los_Angeles [Pacific US]
America/Anchorage [Alaska]
Pacific/Honolulu  [Hawaii]
Europe/London     [UK]
Europe/Paris      [Central Europe]
Europe/Berlin     [Germany]
Asia/Tokyo        [Japan]
Asia/Shanghai     [China]
Australia/Sydney  [Australia East]
UTC               [UTC]
EOF

  sel=$(printf '%s\n' "${choices[@]}" | gum choose --height 12 --header "Select timezone")
  TIMEZONE=${sel%% *}
}

pick_keymap() {
  mapfile -t choices <<EOF
us       [US English]
uk       [UK English]
de       [German]
fr       [French]
es       [Spanish]
it       [Italian]
pt       [Portuguese]
ru       [Russian]
jp106    [Japanese]
dvorak   [Dvorak]
colemak  [Colemak]
EOF

  sel=$(printf '%s\n' "${choices[@]}" | gum choose --height 12 --header "Select keyboard layout")
  KEYMAP=${sel%% *}
}

pick_encryption() {
  ENCRYPT=$(printf '%s\n' "Yes" "No" | gum choose --header "Enable LUKS encryption for root?")
}

enter_strings() {
  HOSTNAME=$(gum input --placeholder "Hostname" --value "${HOSTNAME:-}" --header "Enter hostname")
  USERNAME=$(gum input --placeholder "Username" --value "${USERNAME:-}" --header "Enter username")
  FULLNAME=$(gum input --placeholder "Full name (for git)" --value "${FULLNAME:-}" --header "Enter full name")
  EMAIL=$(gum input --placeholder "Email (for git)" --value "${EMAIL:-}" --header "Enter email")
}

enter_password() {
  while true; do
    p1=$(gum input --password --header "Enter password for $USERNAME")
    p2=$(gum input --password --header "Confirm password")
    [[ "$p1" == "$p2" ]] && { USERPASS="$p1"; break; }
    gum style --foreground 196 "Passwords do not match, try again."
  done

    # Root password (optional)
  if gum confirm "Set a root password? (recommended: No)" --default=false; then
    while true; do
      local r1 r2
      r1=$(gum input --password --header "Enter root password")
      r2=$(gum input --password --header "Confirm root password")
      [[ "$r1" == "$r2" ]] && { ROOTPASS="$r1"; break; }
      gum style --foreground 196 "Root passwords do not match, try again."
    done
  else
    ROOTPASS=$USERPASS
  fi
}

test_packages() {
  local packages_json
  packages_json=$(read_packages_file)

  gum style --border normal --padding "1 2" \
    "PACKAGES_FILE: ${PACKAGES_FILE:-unset}

Raw packages_json:
[${packages_json}]"

  pause
}
disk_bytes() {
  lsblk -dbno SIZE "$1" | head -n1
}

sector_bytes() {
  local base
  base="$(basename "$1")"
  cat "/sys/class/block/${base}/queue/logical_block_size"
}

align_down() { # align_down VALUE ALIGN
  echo $(( ($1 / $2) * $2 ))
}

generate_partition_geometry() {
  local disk="$1"

  local mib=$((1024*1024))
  local gib=$((1024*1024*1024))

  local dbytes sbytes
  dbytes="$(disk_bytes "$disk")"
  sbytes="$(sector_bytes "$disk")"

  local gpt_tail=$((34 * sbytes))

  # ESP: 1MiB start, 1GiB size (matches your template)
  local esp_start=$mib
  local esp_size=$gib

  # Root starts right after ESP
  local root_start=$((esp_start + esp_size))

  # root_size = align_down(disk_bytes - 34*sector_bytes, 1MiB) - root_start - 1MiB
  local last_aligned
  last_aligned="$(align_down $((dbytes - gpt_tail)) $mib)"

  local root_size=$((last_aligned - root_start - mib))

  # Basic sanity
  if (( root_size <= 0 )); then
    echo "0 0"
    return 1
  fi

  echo "${root_start} ${root_size}"
}

new_uuid() {
  if command -v uuidgen >/dev/null 2>&1; then
    uuidgen
  else
    cat /proc/sys/kernel/random/uuid
  fi
}

# -----------------------------
# Config + install
# -----------------------------

generate_config() {
  # Archinstall main config JSON
  local packages_json
  packages_json=$(read_packages_file)
  read -r ROOT_START ROOT_SIZE < <(generate_partition_geometry "$DISK")

  local ESP_OBJ_ID ROOT_OBJ_ID
  ESP_OBJ_ID="$(new_uuid)"
  ROOT_OBJ_ID="$(new_uuid)"

  cat > /tmp/archinstall.json <<EOF
{
  "app_config": {
    "audio_config": { "audio": "pipewire" },
    "bluetooth_config": { "enabled": true },
    "power_management_config": { "power_management": "tuned" },
    "print_service_config": { "enabled": true }
  },
  "archinstall-language": "English",
  "auth_config": {},
  "bootloader_config": {
    "bootloader": "Limine",
    "removable": true,
    "uki": false
  },
  "custom_commands": [],
  "disk_config": {
    "btrfs_options": {
      "snapshot_config": {
        "type": "Snapper"
      }
    },
    "config_type": "default_layout",
    "device_modifications": [
      {
        "device": "${DISK}",
        "partitions": [
          {
            "btrfs": [],
            "dev_path": null,
            "flags": [
              "boot",
              "esp"
            ],
            "fs_type": "fat32",
            "mount_options": [],
            "mountpoint": "/boot",
            "obj_id": "${ESP_OBJ_ID}",
            "size": {
              "sector_size": { "unit": "B", "value": 512 },
              "unit": "GiB",
              "value": 1
            },
            "start": {
              "sector_size": { "unit": "B", "value": 512 },
              "unit": "MiB",
              "value": 1
            },
            "status": "create",
            "type": "primary"
          },
          {
            "btrfs": [
              { "mountpoint": "/", "name": "@" },
              { "mountpoint": "/home", "name": "@home" },
              { "mountpoint": "/var/log", "name": "@log" },
              { "mountpoint": "/var/cache/pacman/pkg", "name": "@pkg" }
            ],
            "dev_path": null,
            "flags": [],
            "fs_type": "btrfs",
            "mount_options": [ "compress=zstd" ],
            "mountpoint": null,
            "obj_id": "${ROOT_OBJ_ID}",
            "size": {
              "sector_size": { "unit": "B", "value": 512 },
              "unit": "B",
              "value": ${ROOT_SIZE}
            },
            "start": {
              "sector_size": { "unit": "B", "value": 512 },
              "unit": "B",
              "value": 1074790400
            },
            "status": "create",
            "type": "primary"
          }
        ],
        "wipe": true
      }
    ]
  },
  "hostname": "${HOSTNAME}",
  "kernels": [
    "linux-zen"
  ],
  "locale_config": {
    "kb_layout": "${KEYMAP}",
    "sys_enc": "UTF-8",
    "sys_lang": "en_US.UTF-8"
  },
  "network_config": {
    "type": "iso"
  },
  "ntp": true,
  "packages": [ ${packages_json} ],
  "parallel_downloads": 0,
  "profile_config": {
    "gfx_driver": "All open-source",
    "greeter": "sddm",
    "profile": {
    	"custom_settings": {},
	"details": [],
	"main": "Minimal"
    }
  },
  "script": null,
  "services": [],
  "swap": {
    "algorithm": "zstd",
    "enabled": true
  },
  "timezone": "${TIMEZONE}",
  "version": "3.0.15"
}
EOF

  # Credentials JSON (root + one user)
  cat > /tmp/creds.json <<EOF
{
	"root_enc_password": "${ROOTPASS}"
	"users": [
	    {
		"enc_password": "${USERPASS}",
		"groups":[],
		"sudo": true,
		"username": "${USERNAME}"
	    }
	]
}
EOF
}



post_install() {
	local aur_list_src ="${PACKAGES_AUR}"
	local aur_list_dst ="/mnt/tmp/aur-packages.txt"
  # crude but works for your layout: root partition = second partition or cryptroot
  if [[ "$ENCRYPT" == "Yes" ]]; then
    ROOT_DEV="/dev/mapper/cryptroot"
  else
    ROOT_DEV="${DISK}p2"
    [[ "$DISK" =~ ^/dev/sd ]] && ROOT_DEV="${DISK}2"
  fi

  mount "$ROOT_DEV" /mnt 2>/dev/null || true
  arch-chroot /mnt /bin/bash <<CHROOT
  su - "$USERNAME" -c "git config --global user.name \"$FULLNAME\""
  su - "$USERNAME" -c "git config --global user.email \"$EMAIL\""
  echo "KEYMAP=$KEYMAP" > /etc/vconsole.conf

  # Build+install paru as the user (NOT root)
  su - "${USERNAME}" -c '
  set -eEuo pipefail
  cd /tmp
  rm -rf paru
  git clone https://aur.archlinux.org/paru.git
  cd paru
  makepkg -si --noconfirm
  '

  # Install AUR packages from list (skip blanks/comments)
  if [[ -s /tmp/aur-packages.txt ]]; then
    su - "${USERNAME}" -c '
    set -eEuo pipefail
    mapfile -t pkgs < <(grep -vE \"^\\s*(#|$)\" /tmp/aur-packages.txt)
    if (( \${#pkgs[@]} )); then
      paru -S --noconfirm --needed \"\${pkgs[@]}\"
    fi
  '
  fi

CHROOT
  umount /mnt 2>/dev/null || true
}

ensure_repo() {
  sudo pacman -Syu --noconfirm --needed git

  echo -e "\nCloning Niri-Strix from: https://github.com/${NIRI_STRIX_REPO}.git"
  rm -rf "${NIRI_STRIX_DIR}"
  git clone "https://github.com/${NIRI_STRIX_REPO}.git" "${NIRI_STRIX_DIR}" >/dev/null
  
}

run_install() {
  # validate
  missing=()
  [[ -z "$DISK" ]]      && missing+=("disk")
  [[ -z "$HOSTNAME" ]]  && missing+=("hostname")
  [[ -z "$USERNAME" ]]  && missing+=("username")
  [[ -z "$FULLNAME" ]]  && missing+=("full name")
  [[ -z "$EMAIL" ]]     && missing+=("email")
  [[ -z "$USERPASS" ]]  && missing+=("password")
  [[ -z "$TIMEZONE" ]]  && missing+=("timezone")
  [[ -z "$KEYMAP" ]]    && missing+=("keymap")
  [[ -z "$ENCRYPT" ]]   && missing+=("encryption choice")

  if (( ${#missing[@]} )); then
    gum style --foreground 196 "Missing: ${missing[*]}"
    pause
    return
  fi

  clear
  banner
  summary
  echo
  gum confirm "Proceed with installation and ERASE $DISK ?" || return

  loadkeys "$KEYMAP" 2>/dev/null || true

  spin_fn "Generating config..." generate_config
  gum spin --title "Running archinstall..." -- archinstall --config /tmp/archinstall.json --creds /tmp/creds.json
  gum spin --title "Post-install configuration..." -- post_install

  clear
  banner
  gum style --foreground 46 "Installation complete. Reboot into your new system."
}

spin_fn() {
  local title="$1"
  local fn="$2"
  export DISK HOSTNAME USERNAME FULLNAME EMAIL TIMEZONE KEYMAP ENCRYPT USERPASS ROOTPASS
  export NIRI_STRIX_REPO NIRI_STRIX_DIR PACKAGES_FILE
  export -f "$fn"
  export -f read_packages_file
  export -f generate_partition_geometry
  export -f disk_bytes sector_bytes align_down
  export -f new_uuid
  gum spin --title "$title" -- bash -c "$fn"
}


view_archinstall_json() {
  spin_fn "Generating config..." generate_config

  [[ -s /tmp/archinstall.json ]] || {
    gum style --foreground 196 "Missing /tmp/archinstall.json (generate_config didn't create it)."
    pause
    return 1
  }

  gum style --border normal --padding "0 1" "archinstall config: /tmp/archinstall.json"

  if command -v jq >/dev/null 2>&1; then
    jq . /tmp/archinstall.json > /tmp/archinstall.pretty.json
    gum pager < /tmp/archinstall.pretty.json
  else
    gum pager < /tmp/archinstall.json
  fi

  pause
}

view_creds_json() {
  spin_fn "Generating config..." generate_config

  [[ -s /tmp/creds.json ]] || {
    gum style --foreground 196 "Missing /tmp/creds.json (generate_config didn't create it)."
    pause
    return 1
  }

  gum style --border normal --padding "0 1" "archinstall config: /tmp/creds.json"

  if command -v jq >/dev/null 2>&1; then
    jq . /tmp/creds.json > /tmp/creds.pretty.json
    gum pager < /tmp/creds.pretty.json
  else
    gum pager < /tmp/creds.json
  fi

  pause
}

read_packages_file() {
  local pkgs=()
  if [[ -f "$PACKAGES_FILE" ]]; then
    while IFS= read -r line; do
      [[ -z "$line" ]] && continue      # empty
      [[ "$line" =~ ^# ]] && continue   # comment
      pkgs+=("$line")
    done < "$PACKAGES_FILE"
  fi

  local out=()
  for p in "${pkgs[@]}"; do
    out+=("\"$p\"")
  done
  printf '%s\n' "$(IFS=,; echo "${out[*]}")"
}

# -----------------------------
# Main wizard
# -----------------------------
main_menu() {
#  ensure_repo
   local last_choice="Password"
  while true; do
    clear
    banner
    summary
    echo

choice=$(printf '%s\n' \
  "Disk" "Hostname/User/Git" "Timezone" "Keyboard" "Encryption" "Password" \
  "View archinstall JSON" "View creds JSON"\
  "Install" "Quit" \
| gum choose --header "Select an item to edit:" --selected "${last_choice}")

  last_choice="$choice"

case "$choice" in
  "Disk") pick_disk ;;
  "Hostname/User/Git") enter_strings ;;
  "Timezone") pick_timezone ;;
  "Keyboard") pick_keymap ;;
  "Encryption") pick_encryption ;;
  "Password") enter_password ;;
  "View archinstall JSON") view_archinstall_json ;;
  "View creds JSON") view_creds_json ;;
  "Install") run_install ;;
  "Quit") exit 0 ;;
esac
  done
}

# -----------------------------
# Entry
# -----------------------------
clear
banner
gum style "This wizard will install Arch Linux with:" \
  "\n- linux-zen kernel" \
  "\n- Limine bootloader" \
  "\n- Btrfs (via archinstall default layout)" \
  "\n- Optional LUKS encryption"
pause

main_menu

