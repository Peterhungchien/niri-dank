# niri-dank &nbsp; [![bluebuild build badge](https://github.com/peterhungchien/niri-dank/actions/workflows/build.yml/badge.svg)](https://github.com/peterhungchien/niri-dank/actions/workflows/build.yml)

A custom Fedora Atomic desktop image featuring the Niri scrollable-tiling Wayland compositor with NVIDIA support, custom SDDM theming, and a curated selection of utilities from the Universal Blue ecosystem.

## What is this?

This is a custom OCI image built on top of [ublue-os/base-main](https://github.com/ublue-os/main) using [BlueBuild](https://blue-build.org/). It provides a minimal yet fully-featured desktop environment centered around the Niri window manager.

## Features

### 🪟 Desktop Environment
- **[Niri](https://github.com/YaLTeR/niri)**: Scrollable-tiling Wayland compositor with dynamic workspaces
- **SDDM**: Display manager with custom Sequoia 2 theme
- **Kitty**: GPU-accelerated terminal emulator
- **Waybar**: Highly customizable status bar

### 🎮 Hardware Support
- **NVIDIA Proprietary Drivers (LTS)**: Full GPU support with DRM modesetting
- **Nouveau blacklisted**: Ensures proper NVIDIA driver loading
- **Intel/AMD support**: Via base-main Mesa drivers

### 🎨 Utilities & Tools
Based on [wayblue](https://github.com/wayblueorg/wayblue) configurations:
- **Launchers**: rofi-wayland, wofi
- **File Manager**: Thunar with plugins, GVFS support
- **Audio**: PipeWire, WirePlumber, pavucontrol
- **Networking**: NetworkManager, Blueman, firewall-config
- **Screenshots**: grim, slurp
- **Display**: wlr-randr, wlsunset, brightnessctl, kanshi
- **Notifications**: dunst
- **Themes**: Papirus, Breeze, Paper icons

### 📦 Media & Codecs
- **Proprietary codecs**: Full ffmpeg, libfdk-aac (from base-main)
- **Additional codecs**: libopenjph, rar, gstreamer-ugly
- **Hardware acceleration**: VA-API, VDPAU support

### 🛠️ Development Tools
- **micro**: Modern terminal text editor
- **starship**: Customizable shell prompt
- **distrobox**: Container-based development environments
- Plus all standard tools from base-main (vim, just, fzf, tmux, htop)

## Base Image

Built on **ghcr.io/ublue-os/base-main:latest** (Fedora 43) which provides:
- Minimal Fedora Atomic base (no desktop environment)
- Pre-configured proprietary media codecs
- RPM Fusion repositories enabled
- Universal Blue infrastructure (updates, signing, udev rules)

## Customizations

### Module Structure
The image is built using a modular approach with the following components:
- **common-modules.yml**: Wayland utilities, audio, networking, file management (65 packages)
- **nvidia-lts-modules.yml**: NVIDIA proprietary drivers with kernel parameters
- **sddm-modules.yml**: Display manager with Sequoia 2 theme
- **niri-modules.yml**: Niri compositor, xdg-desktop-portal-gnome, kitty terminal
- **proprietary-media-modules.yml**: Additional codecs (libopenjph, rar)
- **final-modules.yml**: Cleanup and initramfs regeneration

### NVIDIA Configuration
- Proprietary LTS drivers from ublue-os/akmods-nvidia-lts
- Kernel parameters: `nvidia-drm.modeset=1`, `nvidia-drm.fbdev=1`
- Nouveau driver blacklisted at boot
- Early driver loading configured via dracut

### SDDM Theme
Custom Sequoia 2 theme with:
- Green accent color (#568b22)
- Dark background
- Clock and date display
- Custom wallpaper

## Installation

> [!WARNING]  
> [This is an experimental feature](https://www.fedoraproject.org/wiki/Changes/OstreeNativeContainerStable), try at your own discretion.

To rebase an existing atomic Fedora installation to the latest build:

- First rebase to the unsigned image, to get the proper signing keys and policies installed:
  ```
  rpm-ostree rebase ostree-unverified-registry:ghcr.io/peterhungchien/niri-dank:latest
  ```
- Reboot to complete the rebase:
  ```
  systemctl reboot
  ```
- Then rebase to the signed image, like so:
  ```
  rpm-ostree rebase ostree-image-signed:docker://ghcr.io/peterhungchien/niri-dank:latest
  ```
- Reboot again to complete the installation
  ```
  systemctl reboot
  ```

The `latest` tag will automatically point to the latest build. That build will still always use the Fedora version specified in `recipe.yml`, so you won't get accidentally updated to the next major version.

## Post-Installation

After rebasing to the image:

1. **Select Niri session**: At the SDDM login screen, select "Niri" from the session dropdown
2. **Verify NVIDIA**: Run `nvidia-smi` to confirm GPU detection
3. **Check Wayland**: Run `echo $XDG_SESSION_TYPE` (should output "wayland")
4. **Configure Niri**: Edit `~/.config/niri/config.kdl` for custom keybindings and layout

### First Steps
- Launch terminal: `Mod+T` (default, check your config)
- Launch rofi: `Mod+D` (default application launcher)
- Access waybar settings: Right-click the status bar

## ISO

If build on Fedora Atomic, you can generate an offline ISO with the instructions available [here](https://blue-build.org/learn/universal-blue/#fresh-install-from-an-iso). These ISOs cannot unfortunately be distributed on GitHub for free due to large sizes, so for public projects something else has to be used for hosting.

## Verification

These images are signed with [Sigstore](https://www.sigstore.dev/)'s [cosign](https://github.com/sigstore/cosign). You can verify the signature by downloading the `cosign.pub` file from this repo and running the following command:

```bash
cosign verify --key cosign.pub ghcr.io/peterhungchien/niri-dank
```
