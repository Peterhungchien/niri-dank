# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is a **BlueBuild-based OCI container image** for a custom Fedora Atomic desktop featuring the Niri scrollable-tiling Wayland compositor. Built on Universal Blue's `base-main:43`, it produces an immutable, atomically-updated desktop OS image published to GitHub Container Registry.

## Common Commands

### Building and Testing

**Build the image locally:**
```bash
# Using BlueBuild CLI (if installed)
bluebuild build recipes/recipe.yml

# Using podman/docker directly
podman build -f Containerfile -t niri-dank .
```

**Validate recipe files:**
```bash
# Check YAML syntax
yamllint recipes/*.yml recipes/common/*.yml

# Validate BlueBuild recipe structure
bluebuild validate recipes/recipe.yml
```

**Check GitHub Actions workflow:**
```bash
# View recent builds
gh run list --workflow=build.yml

# Watch current build
gh run watch
```

**Test changes locally before pushing:**
```bash
# Rebase to local build (for testing)
rpm-ostree rebase ostree-unverified-registry:localhost/niri-dank:latest
systemctl reboot
```

### Repository Management

**Update base image version:**
- Edit `base-image` in `recipes/recipe.yml`
- Update Fedora version references (e.g., `:43` → `:44`)
- Update NVIDIA akmods image version in `recipes/common/nvidia-lts-modules.yml`

**Add/remove packages:**
- Common utilities: `recipes/common/common-modules.yml` (dnf install section)
- NVIDIA drivers: `recipes/common/nvidia-lts-modules.yml`
- Niri/Wayland: `recipes/common/niri-modules.yml`

**Clean up build artifacts:**
```bash
# Remove unused containers
podman system prune -a

# Clean rpm-ostree cache
rpm-ostree cleanup -pr
```

## Architecture

### Build System Architecture

```
GitHub Actions → BlueBuild → OCI Image → GHCR → User Systems (rpm-ostree)
```

**Build Flow:**
1. GitHub Actions triggers on schedule (daily 06:00 UTC), push, or PR
2. BlueBuild processes `recipe.yml` and loads modules sequentially
3. Each module type executes specific actions:
   - `files`: Copy from `/files/system` to image
   - `dnf`: Install packages via DNF
   - `script`: Execute bash scripts from `/files/scripts`
   - `systemd`: Enable/disable services
   - `signing`: Configure cosign verification
4. Image is signed with cosign and pushed to `ghcr.io/peterhungchien/niri-dank`
5. Users rebase with `rpm-ostree rebase` for atomic updates

### Module Loading Order (Critical)

Modules in `recipe.yml` are processed **sequentially** in this order:

1. **Files Module**: Copy system configs (SDDM, modprobe.d)
2. **DNF Module**: Install micro, starship (COPR packages)
3. **Flatpak Module**: Install Firefox, Loupe (removal of RPM Firefox)
4. **common-modules.yml**: 65+ Wayland packages, audio, networking, UBlue infrastructure
5. **nvidia-lts-modules.yml**: NVIDIA drivers, nouveau blacklist, DRM setup
6. **sddm-modules.yml**: SDDM packages, Qt5 dependencies, theme configuration
7. **niri-modules.yml**: Niri compositor from COPR (yalter/niri)
8. **proprietary-media-modules.yml**: Codec cleanup (base already has ffmpeg)
9. **final-modules.yml**: Repository cleanup, initramfs regeneration
10. **Signing Module**: Image signing setup

**Why order matters:**
- NVIDIA drivers must load before initramfs regeneration
- System files must exist before scripts reference them
- SDDM theme must be copied before theme configuration script runs
- Repository cleanup must be last to avoid missing dependencies

### Key Configuration Files

**recipes/recipe.yml** (main orchestrator):
- `base-image`: Base container to build from (`ghcr.io/ublue-os/base-main:43`)
- `modules`: List of module files and inline module definitions
- Order of modules determines build sequence
- Each module can be a separate file (via `from-file`) or inline YAML

**Module Files** (`recipes/common/*.yml`):
- Each contains a BlueBuild `modules` array with typed entries
- Module types: `containerfile`, `files`, `dnf`, `script`, `systemd`, `signing`
- Modules can include another module file, creating a chain

**System Files** (`/files/system`):
- Copied directly to image filesystem via `files` module
- Structure mirrors target paths (e.g., `/files/system/etc/sddm.conf` → `/etc/sddm.conf`)
- Contains SDDM theme (30MB, `/usr/share/sddm/themes/sequoia_2/`)

**Scripts** (`/files/scripts/*.sh`):
- 13 bash scripts executed during build via `script` modules
- Notable scripts:
  - `installsignedkernel.sh`: Ensures kernel matches akmods version
  - `setdrmvariables.sh`: Sets `nvidia-drm modeset=1 fbdev=1` in grub
  - `regenerateinitramfs.sh`: Rebuilds initramfs with NVIDIA modules
  - `setsddmtheming.sh`: Validates and applies Sequoia 2 theme
  - `removeunusedrepos.sh`: Cleans 14+ temporary .repo files

### NVIDIA Driver Stack

The NVIDIA configuration is split across multiple layers:

1. **Driver Installation** (`nvidia-lts-modules.yml`):
   - Uses `containerfile` module to copy from `ghcr.io/ublue-os/akmods-nvidia-lts:main-43`
   - Copies: kmod-nvidia, nvidia-driver-libs, nvidia-settings, CUDA libraries
   - Version must match kernel version (managed by `installsignedkernel.sh`)

2. **Driver Configuration** (scripts):
   - `setdrmvariables.sh`: Adds kernel cmdline parameters for DRM modesetting
   - `setearlyloading.sh`: Configures dracut to force-load drivers at early boot
   - `files/system/usr/lib/modprobe.d/nouveau-blacklist.conf`: Prevents nouveau from loading

3. **Initramfs Integration** (`final-modules.yml`):
   - `regenerateinitramfs.sh`: Rebuilds initramfs to include NVIDIA modules
   - Must run **after** all driver configuration is complete

**Critical**: When updating NVIDIA drivers, ensure:
- Base image version matches akmods image version (both `:43`)
- Kernel version in base matches akmods kernel version
- Scripts run in correct order (DRM setup → early loading → initramfs regen)

### SDDM Theming System

Theme is applied through multi-stage process:

1. **Theme Files** (`/files/system/usr/share/sddm/themes/sequoia_2/`):
   - Complete theme with QML UI components (11 .qml files)
   - `theme.conf`: Theme metadata (AccentColor=#568b22, background image)
   - Assets: backgrounds/, icons/ directories

2. **SDDM Config** (`/files/system/etc/sddm.conf` + `/etc/sddm.conf.d/theme.conf`):
   - Main config sets display server, user shell, session paths
   - Theme config sets `[Theme] Current=sequoia_2`

3. **Theme Validation** (`setsddmtheming.sh`):
   - Verifies theme directory exists at `/usr/share/sddm/themes/sequoia_2`
   - Checks `theme.conf` is readable
   - Validates QML components are present
   - Sets proper permissions

**Modifying theme**: Edit files in `/files/system/usr/share/sddm/themes/sequoia_2/`, especially `theme.conf` for colors/layout.

### Wayland Stack Components

**Session Flow**: SDDM → Niri → Wayland clients

1. **Display Manager** (SDDM):
   - Provides graphical login
   - Sources session files from `/usr/share/wayland-sessions/niri.desktop`
   - Launches Niri compositor on login

2. **Compositor** (Niri):
   - Installed from COPR (yalter/niri)
   - Config at `~/.config/niri/config.kdl` (user-created, not in image)
   - Manages window layout, keybindings, outputs

3. **Supporting Utilities**:
   - **xdg-desktop-portal-gnome**: File picker, screen sharing
   - **Waybar**: Status bar (user-configured)
   - **Rofi/Wofi**: Application launchers
   - **Kitty**: Default terminal emulator

**Package groups** (defined in `common-modules.yml`):
- Audio: pipewire, wireplumber, pavucontrol, easyeffects
- Networking: NetworkManager-wifi, network-manager-applet, blueman
- File management: thunar + plugins (archive, media-tags, volman), gvfs, pcmanfm-qt
- Display utilities: wlr-randr, kanshi, brightnessctl, wlsunset
- Screenshots: grim, slurp, swappy
- Security/Authentication: gnome-keyring, libsecret, polkit, xfce-polkit
- Qt theming: qt5ct, qt6ct, kvantum
- GTK theming: lxappearance, gnome-themes-extra, papirus/breeze/paper icons
- Wayland utilities (COPR): cliphist (clipboard history), nwg-look (GTK theme switcher)

## Development Workflow

### Making Changes

**When modifying build configuration:**

1. **Recipe Changes** (`recipes/*.yml`):
   - Test YAML validity before committing
   - Consider module execution order
   - Avoid changing module order unless necessary (can break build)

2. **Adding Packages**:
   - System packages: Add to appropriate module's `dnf` section
   - User applications: Prefer Flatpak (add to `flatpaks` module in `recipe.yml`)
   - COPR packages: Add repo first, then package

3. **System Files**:
   - Place in `/files/system` mirroring target path
   - Add `files` module entry in recipe if not already covered
   - Verify permissions (scripts must be executable)

4. **Scripts**:
   - Place in `/files/scripts/`
   - Make executable: `chmod +x files/scripts/yourscript.sh`
   - Add `script` module entry in appropriate module file
   - Scripts run as root during build, not at user runtime

5. **Testing Changes**:
   - Push to branch, let GitHub Actions build
   - Download artifact or rebase to `ghcr.io/peterhungchien/niri-dank:<branch>`
   - Test on VM before rebasing production system

### Common Modifications

**Update Fedora version:**
```yaml
# recipes/recipe.yml
base-image: ghcr.io/ublue-os/base-main:44  # Change :43 to :44

# recipes/common/nvidia-lts-modules.yml
- type: containerfile
  containerfiles:
    - from: ghcr.io/ublue-os/akmods-nvidia-lts:main-44  # Match version
```

**Add a new utility package:**
```yaml
# recipes/common/common-modules.yml - find the dnf module, add to install list
- type: dnf
  install:
    - micro
    - starship
    - your-new-package  # Add here
```

**Change SDDM theme colors:**
```conf
# files/system/usr/share/sddm/themes/sequoia_2/theme.conf
[General]
AccentColor="#568b22"  # Change hex color
Background="backgrounds/background.png"
```

**Add kernel boot parameter:**
```bash
# Create new script in files/scripts/setyourparameter.sh
#!/usr/bin/env bash
sed -i 's/^\(GRUB_CMDLINE_LINUX=".*\)"/\1 your.parameter=value"/' /etc/default/grub

# Add script module to appropriate module file
- type: script
  scripts:
    - setyourparameter.sh
```

### Debugging Build Failures

**GitHub Actions build fails:**
1. Check `.github/workflows/build.yml` for syntax errors
2. View build logs: `gh run view <run-id>`
3. Common issues:
   - Package not found: Check repo is enabled, package name is correct
   - Script fails: Test script locally with `bash -n script.sh`
   - Out of space: BlueBuild uses `maximize_build_space: true`, but very large layers can still fail

**Local build fails:**
1. Validate recipe: `bluebuild validate recipes/recipe.yml`
2. Check script syntax: `shellcheck files/scripts/*.sh`
3. Verify file paths in `files` modules match actual files

**Runtime issues after rebasing:**
1. NVIDIA not loading: Check `journalctl -b | grep -i nvidia`, verify nouveau is blacklisted
2. SDDM not starting: Check `systemctl status sddm`, verify theme files exist
3. Niri not in session list: Check `/usr/share/wayland-sessions/niri.desktop` exists

## Important Notes

- **Immutability**: Base system is read-only. User modifications go in `/etc` (persistent) or `/var` (persistent).
- **Atomic Updates**: Changes are applied as complete image replacements, not individual package updates.
- **Rollback**: Previous deployments kept for rollback: `rpm-ostree rollback && systemctl reboot`
- **Signing**: Images are cosign-signed. Rebasing to `ostree-image-signed:` verifies signatures.
- **Daily Builds**: Scheduled at 06:00 UTC. Push/PR also trigger builds. `latest` tag always points to newest Fedora 43 build.
- **COPR Dependencies**: Niri from `yalter/niri`, cliphist from `sdegler/hyprland`, nwg-look from `tofik/nwg-shell`, starship from Fedora COPR. These can break if COPR repos change or are discontinued.
