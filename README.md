# Niri-Strix

A preconfigured, gaming-focused Arch Linux build running the [Niri](https://github.com/YaLTeR/niri) Wayland compositor. Inspired by [omarchy](https://github.com/basecamp/omarchy), but built around gaming rather than development tooling — think Steam, Lutris, Wine, and RetroArch instead of IDEs and compilers.

---

## What's Inside

- **Kernel:** linux-zen
- **Bootloader:** Limine
- **Filesystem:** btrfs
- **Compositor:** Niri (Wayland)
- **Bar:** Waybar
- **Launcher:** Rofi
- **AUR Helper:** Paru
- **Package selection:** Random Mess of things

Full package lists are available in [`base-packages.txt`](./base-packages.txt) and [`aur-packages.txt`](./aur-packages.txt).

---

## Requirements

- A UEFI-capable machine (x86_64)
- At least **20 GB** of free disk space recommended
- An internet connection during install
- The Niri-Strix ISO (see [Building the ISO](#building-the-iso) below)

---

## Building the ISO

The ISO is built using `archiso`. From an existing Arch Linux environment:

```bash
# Install archiso if not already present
sudo pacman -S archiso

# Clone the repo
git clone https://github.com/MercySimp/Niri-Strix.git
cd Niri-Strix

# Build the ISO (requires root)
sudo mkarchiso -v -w /tmp/niri-strix-work -o /tmp/niri-strix-out .
```

The finished `.iso` file will be written to `/tmp/niri-strix-out/`.

---

## Flashing the ISO

Use any tool you prefer to write the ISO to a USB drive. With `dd`:

```bash
# Replace /dev/sdX with your USB device — double-check with lsblk
sudo dd if=/tmp/niri-strix-out/niri-strix-*.iso of=/dev/sdX bs=4M status=progress oflag=sync
```

---

## Build from Git

If you don't want to build it from a USB you don't have to, if you are already running arch and have 2 hard drives. Just run the installer from your desktop.

```bash
git clone https://github.com/MercySimp/Niri-Strix.git
cd Niri-Strix
sudo airootfs/usr/local/bin/strix-installer.sh
```

---

## Installing

1. Boot your machine from the USB drive.
2. At the live environment prompt, the installer launches automatically. If it does not, run:

```bash
install-strix
```

3. The installer will:
   - Detect your GPU and suggest appropriate graphics drivers.
   - Ask for your target disk and partition preferences.
   - Ask you to set a root/user.
   - Install the base system via `archinstall` using the bundled JSON config.
   - Run a post-install script that:
     - Builds and installs `paru`
     - Installs all AUR packages from `aur-packages.txt`
     - Applies Niri configs and dotfiles
     - Removes the `xdg-desktop-portal-gnome` dependency (replaced with `xdg-desktop-portal-luminous`)

4. When the installer finishes, reboot and remove the USB drive.

## Theming

Niri-Strix includes a theme manager that applies consistent color schemes across the desktop. They are just some themes I found on Github or on the Rice Reddit. Supported targets currently include Niri, Btop, Kitty, Nvim, Waybar, Superfile, Rofi, and Dunst.

---

## Known Issues

- Some fonts missings from the installer.

---

## In Development

> These features are being actively tested and are **not yet part of a stable release**.

- **Quickshell bar:** Evaluating [Quickshell](https://quickshell.outfoxxed.me/) as a replacement for Waybar. Quickshell offers a more flexible, QML-based configuration model and is being tested as the primary status bar going forward. Waybar remains the default until this is considered stable.
- **Drive encryption:** Integrating LUKS encryption via archinstall's native encryption support.
