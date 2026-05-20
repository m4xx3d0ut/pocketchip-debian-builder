#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
print_defaults=0
use_local_env=1
for arg in "$@"; do
  case "$arg" in
    --print-defaults) print_defaults=1 ;;
    --no-local-env) use_local_env=0 ;;
    *)
      printf 'error: unknown argument: %s\n' "$arg" >&2
      exit 2
      ;;
  esac
done

local_env="${LOCAL_ENV:-$repo_root/configs/local.env}"
if [[ "$use_local_env" == 1 && -r "$local_env" ]]; then
  set -a
  # shellcheck source=/dev/null
  . "$local_env"
  set +a
fi

suite="${SUITE:-trixie}"
arch="${ARCH:-armhf}"
mirror="${MIRROR:-http://deb.debian.org/debian}"
security_mirror="${SECURITY_MIRROR:-http://security.debian.org/debian-security}"
build_dir="${BUILD_DIR:-$repo_root/build}"
rootfs="${ROOTFS:-$build_dir/rootfs-$suite-$arch}"
packages_file="${PACKAGES_FILE:-$repo_root/configs/debian-trixie-armhf.packages}"
install_oh_my_zsh="${INSTALL_OH_MY_ZSH:-1}"
debian_keyring="${DEBIAN_KEYRING:-$build_dir/keyrings/debian-trixie-archive-keyring.gpg}"
initramfs_modules_file="${INITRAMFS_MODULES_FILE:-$repo_root/configs/initramfs-modules}"
pocketchip_image_profile="${POCKETCHIP_IMAGE_PROFILE:-balanced}"
pocketchip_user="${POCKETCHIP_USER:-chip}"
pocketchip_root_auth="${POCKETCHIP_ROOT_AUTH:-locked}"
pocketchip_root_password="${POCKETCHIP_ROOT_PASSWORD:-}"
if [[ "${POCKETCHIP_USER_PASSWORD+x}" == x ]]; then
  pocketchip_user_password="$POCKETCHIP_USER_PASSWORD"
else
  pocketchip_user_password=""
fi
pocketchip_autologin_tty1="${POCKETCHIP_AUTOLOGIN_TTY1:-auto}"
pocketchip_wifi_ssid="${POCKETCHIP_WIFI_SSID:-}"
pocketchip_wifi_psk="${POCKETCHIP_WIFI_PSK:-}"
pocketchip_wifi_country="${POCKETCHIP_WIFI_COUNTRY:-}"
pocketchip_wifi_hidden="${POCKETCHIP_WIFI_HIDDEN:-0}"
pocketchip_touch_matrix="${POCKETCHIP_TOUCH_MATRIX:--1 0 1 0 -1.18 1.09 0 0 1}"
pocketchip_touch_output="${POCKETCHIP_TOUCH_OUTPUT:-}"
pocketchip_boot_to_i3="${POCKETCHIP_BOOT_TO_I3:-1}"
pocketchip_first_login_password_setup="${POCKETCHIP_FIRST_LOGIN_PASSWORD_SETUP:-auto}"
pocketchip_asset_dir="${POCKETCHIP_ASSET_DIR:-$repo_root/.local/chip-assets}"
pocketchip_bg_image="${POCKETCHIP_BG_IMAGE:-}"
pocketchip_bg_top_margin="${POCKETCHIP_BG_TOP_MARGIN:-0}"
pocketchip_boot_video="${POCKETCHIP_BOOT_VIDEO:-}"
pocketchip_boot_animation="${POCKETCHIP_BOOT_ANIMATION:-0}"
pocketchip_browser="${POCKETCHIP_BROWSER:-firefox-esr}"
pocketchip_gestures="${POCKETCHIP_GESTURES:-1}"
pocketchip_dark_mode="${POCKETCHIP_DARK_MODE:-1}"
pocketchip_timezone="${POCKETCHIP_TIMEZONE:-America/Los_Angeles}"
pocketchip_network_time="${POCKETCHIP_NETWORK_TIME:-1}"
pocketchip_firefox_scale="${POCKETCHIP_FIREFOX_SCALE:-1.15}"
pocketchip_firefox_default_zoom="${POCKETCHIP_FIREFOX_DEFAULT_ZOOM:-1.0}"
pocketchip_browser_fullscreen="${POCKETCHIP_BROWSER_FULLSCREEN:-1}"
pocketchip_browser_touch_mode="${POCKETCHIP_BROWSER_TOUCH_MODE:-gestures}"

die() {
  printf 'error: %s\n' "$*" >&2
  exit 1
}

validate_linux_user() {
  if [[ ! "$1" =~ ^[a-z_][a-z0-9_-]{0,31}$ ]]; then
    die "invalid POCKETCHIP_USER '$1'"
  fi
}

reject_chpasswd_secret() {
  local name="$1"
  local value="$2"
  if [[ "$value" == *$'\n'* || "$value" == *:* ]]; then
    die "$name may not contain newlines or ':'"
  fi
}

reject_newline() {
  local name="$1"
  local value="$2"
  if [[ "$value" == *$'\n'* ]]; then
    die "$name may not contain newlines"
  fi
}

validate_bool() {
  local name="$1"
  local value="$2"
  case "$value" in
    0|1) ;;
    *) die "$name must be 0 or 1" ;;
  esac
}

validate_command_name() {
  local name="$1"
  local value="$2"
  if [[ ! "$value" =~ ^[A-Za-z0-9._+-]+$ ]]; then
    die "$name must be a simple command name"
  fi
}

validate_nonnegative_int() {
  local name="$1"
  local value="$2"
  if [[ ! "$value" =~ ^[0-9]+$ ]]; then
    die "$name must be a non-negative integer"
  fi
}

validate_decimal() {
  local name="$1"
  local value="$2"
  if [[ ! "$value" =~ ^[0-9]+([.][0-9]+)?$ ]]; then
    die "$name must be a non-negative decimal"
  fi
}

write_shell_var() {
  local name="$1"
  local value="$2"
  printf '%s=%q\n' "$name" "$value"
}

resolve_asset() {
  local name="$1"
  local value="$2"
  local path
  if [[ "$value" == /* ]]; then
    path="$value"
  else
    path="$pocketchip_asset_dir/$value"
  fi
  [[ -r "$path" ]] || die "$name file not found: $path"
  printf '%s\n' "$path"
}

install_wallpaper() {
  local src="$1"
  local dst="$2"
  local top_margin="$3"
  if (( top_margin == 0 )); then
    install -m 0644 "$src" "$dst"
    return
  fi

  python3 - "$src" "$dst" "$top_margin" <<'PY'
import sys
from PIL import Image

src, dst, top_margin = sys.argv[1], sys.argv[2], int(sys.argv[3])
screen_w, screen_h = 480, 272
if top_margin >= screen_h:
    raise SystemExit("top margin is too large for 480x272")

image = Image.open(src).convert("RGBA")
resampling = getattr(Image, "Resampling", Image)
resized = image.resize((screen_w, screen_h - top_margin), resampling.LANCZOS)
canvas = Image.new("RGBA", (screen_w, screen_h), (0, 0, 0, 255))
canvas.alpha_composite(resized, (0, top_margin))
canvas.convert("RGB").save(dst, optimize=True)
PY
  chmod 0644 "$dst"
}

validate_linux_user "$pocketchip_user"
case "$pocketchip_image_profile" in
  balanced|minimal|full) ;;
  *) die "POCKETCHIP_IMAGE_PROFILE must be balanced, minimal, or full" ;;
esac
case "$pocketchip_root_auth" in
  locked) ;;
  password)
    [[ -n "$pocketchip_root_password" ]] || die "POCKETCHIP_ROOT_PASSWORD must be set explicitly when POCKETCHIP_ROOT_AUTH=password"
    ;;
  *) die "POCKETCHIP_ROOT_AUTH must be locked or password" ;;
esac
if [[ -n "$pocketchip_root_password" ]]; then
  reject_chpasswd_secret POCKETCHIP_ROOT_PASSWORD "$pocketchip_root_password"
fi
reject_chpasswd_secret POCKETCHIP_USER_PASSWORD "$pocketchip_user_password"
reject_newline POCKETCHIP_WIFI_SSID "$pocketchip_wifi_ssid"
reject_newline POCKETCHIP_WIFI_PSK "$pocketchip_wifi_psk"
validate_bool POCKETCHIP_WIFI_HIDDEN "$pocketchip_wifi_hidden"
reject_newline POCKETCHIP_TOUCH_MATRIX "$pocketchip_touch_matrix"
reject_newline POCKETCHIP_TOUCH_OUTPUT "$pocketchip_touch_output"
reject_newline POCKETCHIP_ASSET_DIR "$pocketchip_asset_dir"
reject_newline POCKETCHIP_BG_IMAGE "$pocketchip_bg_image"
validate_nonnegative_int POCKETCHIP_BG_TOP_MARGIN "$pocketchip_bg_top_margin"
reject_newline POCKETCHIP_BOOT_VIDEO "$pocketchip_boot_video"
reject_newline POCKETCHIP_BROWSER "$pocketchip_browser"
validate_bool POCKETCHIP_BOOT_TO_I3 "$pocketchip_boot_to_i3"
validate_bool POCKETCHIP_BOOT_ANIMATION "$pocketchip_boot_animation"
validate_bool POCKETCHIP_GESTURES "$pocketchip_gestures"
validate_bool POCKETCHIP_DARK_MODE "$pocketchip_dark_mode"
validate_bool POCKETCHIP_NETWORK_TIME "$pocketchip_network_time"
validate_bool POCKETCHIP_BROWSER_FULLSCREEN "$pocketchip_browser_fullscreen"
reject_newline POCKETCHIP_TIMEZONE "$pocketchip_timezone"
reject_newline POCKETCHIP_FIREFOX_SCALE "$pocketchip_firefox_scale"
reject_newline POCKETCHIP_FIREFOX_DEFAULT_ZOOM "$pocketchip_firefox_default_zoom"
reject_newline POCKETCHIP_BROWSER_TOUCH_MODE "$pocketchip_browser_touch_mode"
validate_decimal POCKETCHIP_FIREFOX_SCALE "$pocketchip_firefox_scale"
validate_decimal POCKETCHIP_FIREFOX_DEFAULT_ZOOM "$pocketchip_firefox_default_zoom"
validate_command_name POCKETCHIP_BROWSER "$pocketchip_browser"
case "$pocketchip_browser_touch_mode" in
  gestures|stylus|off) ;;
  *) die "POCKETCHIP_BROWSER_TOUCH_MODE must be gestures, stylus, or off" ;;
esac
case "$pocketchip_timezone" in
  /*|*..*|"") die "POCKETCHIP_TIMEZONE must be a relative zoneinfo name" ;;
esac

if [[ "$pocketchip_asset_dir" != /* ]]; then
  pocketchip_asset_dir="$repo_root/$pocketchip_asset_dir"
fi

if [[ "$pocketchip_autologin_tty1" == auto ]]; then
  if [[ -z "$pocketchip_user_password" ]]; then
    pocketchip_autologin_tty1=1
  else
    pocketchip_autologin_tty1=0
  fi
fi

case "$pocketchip_autologin_tty1" in
  0|1) ;;
  *) die "POCKETCHIP_AUTOLOGIN_TTY1 must be auto, 0, or 1" ;;
esac

case "$pocketchip_first_login_password_setup" in
  auto)
    if [[ "$pocketchip_boot_to_i3" == 1 && -z "$pocketchip_user_password" ]]; then
      pocketchip_first_login_password_setup=1
    else
      pocketchip_first_login_password_setup=0
    fi
    ;;
  0|1) ;;
  *) die "POCKETCHIP_FIRST_LOGIN_PASSWORD_SETUP must be auto, 0, or 1" ;;
esac

if [[ "$print_defaults" == 1 ]]; then
  printf 'SUITE=%s\n' "$suite"
  printf 'ARCH=%s\n' "$arch"
  printf 'POCKETCHIP_IMAGE_PROFILE=%s\n' "$pocketchip_image_profile"
  printf 'POCKETCHIP_ROOT_AUTH=%s\n' "$pocketchip_root_auth"
  printf 'POCKETCHIP_ROOT_PASSWORD_SET=%s\n' "$([[ -n "$pocketchip_root_password" ]] && printf yes || printf no)"
  printf 'POCKETCHIP_USER=%s\n' "$pocketchip_user"
  printf 'POCKETCHIP_USER_PASSWORD_SET=%s\n' "$([[ -n "$pocketchip_user_password" ]] && printf yes || printf no)"
  printf 'POCKETCHIP_AUTOLOGIN_TTY1=%s\n' "$pocketchip_autologin_tty1"
  printf 'POCKETCHIP_BOOT_TO_I3=%s\n' "$pocketchip_boot_to_i3"
  printf 'POCKETCHIP_FIRST_LOGIN_PASSWORD_SETUP=%s\n' "$pocketchip_first_login_password_setup"
  printf 'POCKETCHIP_WIFI_SSID_SET=%s\n' "$([[ -n "$pocketchip_wifi_ssid" ]] && printf yes || printf no)"
  printf 'POCKETCHIP_WIFI_PSK_SET=%s\n' "$([[ -n "$pocketchip_wifi_psk" ]] && printf yes || printf no)"
  printf 'POCKETCHIP_WIFI_HIDDEN=%s\n' "$pocketchip_wifi_hidden"
  printf 'POCKETCHIP_WIFI_COUNTRY=%s\n' "$pocketchip_wifi_country"
  printf 'POCKETCHIP_BG_IMAGE=%s\n' "$pocketchip_bg_image"
  printf 'POCKETCHIP_BOOT_VIDEO=%s\n' "$pocketchip_boot_video"
  printf 'POCKETCHIP_BOOT_ANIMATION=%s\n' "$pocketchip_boot_animation"
  printf 'POCKETCHIP_BROWSER=%s\n' "$pocketchip_browser"
  printf 'POCKETCHIP_GESTURES=%s\n' "$pocketchip_gestures"
  printf 'POCKETCHIP_DARK_MODE=%s\n' "$pocketchip_dark_mode"
  printf 'POCKETCHIP_TIMEZONE=%s\n' "$pocketchip_timezone"
  printf 'POCKETCHIP_NETWORK_TIME=%s\n' "$pocketchip_network_time"
  printf 'POCKETCHIP_FIREFOX_SCALE=%s\n' "$pocketchip_firefox_scale"
  printf 'POCKETCHIP_FIREFOX_DEFAULT_ZOOM=%s\n' "$pocketchip_firefox_default_zoom"
  printf 'POCKETCHIP_BROWSER_FULLSCREEN=%s\n' "$pocketchip_browser_fullscreen"
  printf 'POCKETCHIP_BROWSER_TOUCH_MODE=%s\n' "$pocketchip_browser_touch_mode"
  exit 0
fi

bg_asset_src=""
boot_video_asset_src=""
if [[ -n "$pocketchip_bg_image" ]]; then
  bg_asset_src="$(resolve_asset POCKETCHIP_BG_IMAGE "$pocketchip_bg_image")"
  if (( pocketchip_bg_top_margin > 0 )); then
    python3 - <<'PY' || die "POCKETCHIP_BG_TOP_MARGIN requires python3 Pillow; install python3-pil"
import PIL.Image
PY
  fi
fi
if [[ -n "$pocketchip_boot_video" ]]; then
  boot_video_asset_src="$(resolve_asset POCKETCHIP_BOOT_VIDEO "$pocketchip_boot_video")"
fi

if [[ -n "$pocketchip_wifi_ssid" || -n "$pocketchip_wifi_psk" ]]; then
  [[ -n "$pocketchip_wifi_ssid" ]] || die "POCKETCHIP_WIFI_PSK is set but POCKETCHIP_WIFI_SSID is empty"
  [[ -n "$pocketchip_wifi_psk" ]] || die "POCKETCHIP_WIFI_SSID is set but POCKETCHIP_WIFI_PSK is empty"
fi

if [[ -n "$pocketchip_wifi_country" && ! "$pocketchip_wifi_country" =~ ^[A-Z]{2}$ ]]; then
  die "POCKETCHIP_WIFI_COUNTRY must be a two-letter uppercase regulatory code, for example US"
fi

if [[ ${EUID:-$(id -u)} -ne 0 ]]; then
  printf 'error: build-rootfs.sh must run as root because it creates device nodes and chroots.\n' >&2
  exit 1
fi

for cmd in mmdebstrap chroot install lsinitramfs python3 rsync; do
  if ! command -v "$cmd" >/dev/null 2>&1; then
    printf 'error: %s is required.\n' "$cmd" >&2
    exit 1
  fi
done

host_arch="$(dpkg --print-architecture 2>/dev/null || uname -m)"
if [[ "$host_arch" != "$arch" && "$host_arch" != armhf && "$host_arch" != armv7l ]]; then
  if [[ ! -r /proc/sys/fs/binfmt_misc/qemu-arm ]] || ! grep -q enabled /proc/sys/fs/binfmt_misc/qemu-arm; then
    printf 'error: qemu-arm binfmt is required for foreign armhf chroot configuration.\n' >&2
    printf '       Install qemu-user-static and binfmt-support, then retry.\n' >&2
    exit 1
  fi
fi

if [[ -e "$rootfs" && "${FORCE:-0}" != 1 ]]; then
  printf 'error: %s already exists. Set FORCE=1 to replace it.\n' "$rootfs" >&2
  exit 1
fi

if [[ -e "$rootfs" ]]; then
  rm -rf "$rootfs"
fi

cleanup_failed_rootfs() {
  local rc=$?
  if (( rc != 0 )); then
    printf 'error: rootfs build failed; removing incomplete %s\n' "$rootfs" >&2
    rm -rf "$rootfs"
  fi
  exit "$rc"
}
trap cleanup_failed_rootfs EXIT

build_package_csv() {
  local pkg
  local packages=()
  local seen=" "
  local remove=()
  local append=()

  case "$pocketchip_image_profile" in
    minimal)
      remove=(
        bluez-tools btscanner firefox-esr gpiod iperf3 mesa-utils minicom mpv
        mtr-tiny nmap netsurf-gtk python3-libgpiod ser2net spi-tools tcpdump
        traceroute vim-tiny wavemon xdotool
      )
      ;;
    full)
      append=(btscanner minicom mpv mesa-utils netsurf-gtk ser2net vim-tiny)
      ;;
  esac

  if [[ "$pocketchip_browser_touch_mode" == gestures ]]; then
    append+=(xdotool)
  fi

  if [[ "$pocketchip_boot_animation" == 1 && -n "$pocketchip_boot_video" ]]; then
    append+=(mpv)
  fi

  if [[ "$pocketchip_network_time" == 1 ]]; then
    append+=(systemd-timesyncd)
  fi

  while read -r pkg; do
    [[ -n "$pkg" ]] || continue
    local skip=0
    local name
    for name in "${remove[@]}"; do
      if [[ "$pkg" == "$name" ]]; then
        skip=1
        break
      fi
    done
    (( skip == 0 )) || continue
    if [[ "$seen" != *" $pkg "* ]]; then
      packages+=("$pkg")
      seen+="$pkg "
    fi
  done < <(awk 'NF && $1 !~ /^#/ { print $1 }' "$packages_file")

  for pkg in "${append[@]}"; do
    if [[ "$seen" != *" $pkg "* ]]; then
      packages+=("$pkg")
      seen+="$pkg "
    fi
  done

  local IFS=,
  printf '%s' "${packages[*]}"
}

package_csv="$(build_package_csv)"

mkdir -p "$build_dir"

if [[ ! -f "$debian_keyring" ]]; then
  debian_keyring="$("$repo_root/scripts/prepare-debian-keyring.sh")"
fi

mmdebstrap \
  --architectures="$arch" \
  --components='main,contrib,non-free-firmware' \
  --variant=minbase \
  --keyring="$debian_keyring" \
  --include="$package_csv" \
  "$suite" "$rootfs" \
  "$mirror"

cat > "$rootfs/etc/apt/sources.list" <<EOF
deb $mirror $suite main contrib non-free-firmware
deb $mirror $suite-updates main contrib non-free-firmware
deb $security_mirror $suite-security main contrib non-free-firmware
EOF

printf 'pocketchip\n' > "$rootfs/etc/hostname"
cat > "$rootfs/etc/hosts" <<'EOF'
127.0.0.1 localhost
127.0.1.1 pocketchip

::1 localhost ip6-localhost ip6-loopback
ff02::1 ip6-allnodes
ff02::2 ip6-allrouters
EOF

if [[ ! -r "$rootfs/usr/share/zoneinfo/$pocketchip_timezone" ]]; then
  die "timezone not found in rootfs: $pocketchip_timezone"
fi
printf '%s\n' "$pocketchip_timezone" > "$rootfs/etc/timezone"
ln -sfn "../usr/share/zoneinfo/$pocketchip_timezone" "$rootfs/etc/localtime"

chroot "$rootfs" groupadd -r -f pocketchip-setup
chip_groups="adm,dialout,video,input,audio,pocketchip-setup"
if [[ -n "$pocketchip_user_password" ]]; then
  chip_groups="sudo,$chip_groups"
fi
for optional_group in netdev bluetooth; do
  if chroot "$rootfs" getent group "$optional_group" >/dev/null 2>&1; then
    chip_groups="$chip_groups,$optional_group"
  fi
done

chroot "$rootfs" useradd -m -s /usr/bin/zsh -G "$chip_groups" "$pocketchip_user"
case "$pocketchip_root_auth" in
  locked)
    chroot "$rootfs" passwd -l root >/dev/null
    ;;
  password)
    printf 'root:%s\n' "$pocketchip_root_password" | chroot "$rootfs" chpasswd
    ;;
esac
if [[ -n "$pocketchip_user_password" ]]; then
  printf '%s:%s\n' "$pocketchip_user" "$pocketchip_user_password" | chroot "$rootfs" chpasswd
else
  chroot "$rootfs" passwd -d "$pocketchip_user"
fi
install -m 0644 "$initramfs_modules_file" "$rootfs/etc/initramfs-tools/modules"
ln -sfn ../lib/systemd/systemd "$rootfs/usr/sbin/init"
chroot "$rootfs" update-initramfs -u -k all
chroot "$rootfs" apt-get clean

user_home="$rootfs/home/$pocketchip_user"
install -m 0644 "$repo_root/configs/zshrc" "$user_home/.zshrc"
install -m 0644 "$repo_root/configs/zprofile" "$user_home/.zprofile"
install -m 0644 "$repo_root/configs/xinitrc" "$user_home/.xinitrc"
install -m 0644 "$repo_root/configs/tmux.conf" "$user_home/.tmux.conf"
install -m 0644 "$repo_root/configs/Xresources" "$user_home/.Xresources"
install -m 0644 "$repo_root/configs/pocketchip.Xmodmap" "$user_home/.Xmodmap"
install -d -m 0755 "$user_home/.config/i3"
install -m 0644 "$repo_root/configs/i3-config" "$user_home/.config/i3/config"
install -d -m 0755 "$user_home/.config/nvim"
rsync -a --delete "$repo_root/configs/nvim/" "$user_home/.config/nvim/"

if [[ "$pocketchip_dark_mode" == 1 ]]; then
  install -d -m 0755 "$user_home/.config/gtk-3.0"
  cat > "$user_home/.config/gtk-3.0/settings.ini" <<'EOF'
[Settings]
gtk-application-prefer-dark-theme=1
gtk-theme-name=Adwaita
gtk-icon-theme-name=Adwaita
EOF
  cat > "$user_home/.gtkrc-2.0" <<'EOF'
gtk-application-prefer-dark-theme=1
gtk-theme-name="Adwaita"
gtk-icon-theme-name="Adwaita"
EOF
fi

firefox_profile_dir="$user_home/.mozilla/firefox/pocketchip.default"
install -d -m 0755 "$firefox_profile_dir/chrome"
cat > "$user_home/.mozilla/firefox/profiles.ini" <<'EOF'
[Profile0]
Name=pocketchip
IsRelative=1
Path=pocketchip.default
Default=1

[General]
StartWithLastProfile=1
Version=2
EOF
if [[ "$pocketchip_dark_mode" == 1 ]]; then
  firefox_system_dark=1
  firefox_theme=0
else
  firefox_system_dark=0
  firefox_theme=1
fi
cat > "$firefox_profile_dir/user.js" <<EOF
user_pref("browser.shell.checkDefaultBrowser", false);
user_pref("browser.startup.homepage", "about:blank");
user_pref("browser.startup.page", 0);
user_pref("browser.tabs.warnOnClose", false);
user_pref("browser.uidensity", 1);
user_pref("browser.zoom.defaultZoomValue", "$pocketchip_firefox_default_zoom");
user_pref("browser.zoom.siteSpecific", false);
user_pref("browser.theme.content-theme", $firefox_theme);
user_pref("browser.theme.toolbar-theme", $firefox_theme);
user_pref("datareporting.healthreport.uploadEnabled", false);
user_pref("datareporting.policy.dataSubmissionEnabled", false);
user_pref("dom.forms.autocomplete.formautofill", false);
user_pref("extensions.getAddons.showPane", false);
user_pref("layout.css.devPixelsPerPx", "$pocketchip_firefox_scale");
user_pref("layout.css.prefers-color-scheme.content-override", $firefox_theme);
user_pref("toolkit.legacyUserProfileCustomizations.stylesheets", true);
user_pref("ui.systemUsesDarkTheme", $firefox_system_dark);
EOF
cat > "$firefox_profile_dir/chrome/userChrome.css" <<'EOF'
@namespace url("http://www.mozilla.org/keymaster/gatekeeper/there.is.only.xul");

#TabsToolbar,
#PersonalToolbar {
  min-height: 22px !important;
}

#nav-bar {
  min-height: 28px !important;
}

toolbarbutton,
.toolbarbutton-1 {
  padding: 1px !important;
}
EOF

install -d -m 0755 "$rootfs/usr/local/bin"
install -m 0755 "$repo_root/configs/pocketchip-startx" "$rootfs/usr/local/bin/pocketchip-startx"
install -m 0755 "$repo_root/configs/pocketchip-status" "$rootfs/usr/local/bin/pocketchip-status"
install -m 0755 "$repo_root/configs/pocketchip-touch-calibrate" "$rootfs/usr/local/bin/pocketchip-touch-calibrate"
install -m 0755 "$repo_root/configs/pocketchip-connect" "$rootfs/usr/local/bin/pocketchip-connect"
install -m 0755 "$repo_root/configs/pocketchip-about" "$rootfs/usr/local/bin/pocketchip-about"
install -m 0755 "$repo_root/configs/pocketchip-browser" "$rootfs/usr/local/bin/pocketchip-browser"
install -m 0755 "$repo_root/configs/pocketchip-browser-action" "$rootfs/usr/local/bin/pocketchip-browser-action"
install -m 0755 "$repo_root/configs/pocketchip-menu" "$rootfs/usr/local/bin/pocketchip-menu"
install -m 0755 "$repo_root/configs/pocketchip-control" "$rootfs/usr/local/bin/pocketchip-control"
install -m 0755 "$repo_root/configs/pocketchip-power" "$rootfs/usr/local/bin/pocketchip-power"
install -m 0755 "$repo_root/configs/pocketchip-boot-animation" "$rootfs/usr/local/bin/pocketchip-boot-animation"
install -m 0755 "$repo_root/configs/pocketchip-gestures" "$rootfs/usr/local/bin/pocketchip-gestures"
install -m 0755 "$repo_root/configs/pocketchip-first-login-password" "$rootfs/usr/local/bin/pocketchip-first-login-password"
install -d -m 0755 "$rootfs/usr/local/sbin"
install -m 0755 "$repo_root/configs/pocketchip-disable-autologin" "$rootfs/usr/local/sbin/pocketchip-disable-autologin"
install -m 0755 "$repo_root/configs/pocketchip-power-root" "$rootfs/usr/local/sbin/pocketchip-power-root"

install -d -m 0755 "$rootfs/usr/share/pocketchip"
bg_image_path=""
boot_video_path=""
if [[ -n "$bg_asset_src" ]]; then
  bg_image_path=/usr/share/pocketchip/bg.png
  install_wallpaper "$bg_asset_src" "$rootfs$bg_image_path" "$pocketchip_bg_top_margin"
fi
if [[ "$pocketchip_boot_animation" == 1 && -n "$boot_video_asset_src" ]]; then
  boot_video_path=/usr/share/pocketchip/boot.mp4
  install -m 0644 "$boot_video_asset_src" "$rootfs$boot_video_path"
fi

install -d -m 0755 "$rootfs/usr/share/doc/pocketchip"
install -m 0644 "$repo_root/configs/i3-cheatsheet.md" "$rootfs/usr/share/doc/pocketchip/i3-cheatsheet.md"
install -d -m 0755 "$rootfs/usr/local/share/keymaps"
install -m 0644 "$repo_root/configs/pocketchip.kmap" "$rootfs/usr/local/share/keymaps/pocketchip.kmap"

install -d -m 0755 "$rootfs/etc/X11/xorg.conf.d"
install -m 0644 "$repo_root/configs/xorg-pocketchip-touch.conf" "$rootfs/etc/X11/xorg.conf.d/40-pocketchip-touch.conf"

install -d -m 0755 "$rootfs/etc/default"
{
  write_shell_var POCKETCHIP_USER "$pocketchip_user"
  write_shell_var POCKETCHIP_IMAGE_PROFILE "$pocketchip_image_profile"
  write_shell_var POCKETCHIP_ROOT_AUTH "$pocketchip_root_auth"
} > "$rootfs/etc/default/pocketchip-user"
{
  write_shell_var POCKETCHIP_TOUCH_DEVICE "1c25000.rtp"
  write_shell_var POCKETCHIP_TOUCH_MATRIX "$pocketchip_touch_matrix"
  write_shell_var POCKETCHIP_TOUCH_OUTPUT "$pocketchip_touch_output"
} > "$rootfs/etc/default/pocketchip-touch"
{
  write_shell_var POCKETCHIP_BOOT_TO_I3 "$pocketchip_boot_to_i3"
  write_shell_var POCKETCHIP_FIRST_LOGIN_PASSWORD_SETUP "$pocketchip_first_login_password_setup"
  write_shell_var POCKETCHIP_BG_IMAGE_PATH "$bg_image_path"
  write_shell_var POCKETCHIP_BG_TOP_MARGIN "$pocketchip_bg_top_margin"
  write_shell_var POCKETCHIP_BOOT_VIDEO_PATH "$boot_video_path"
  write_shell_var POCKETCHIP_BOOT_ANIMATION "$pocketchip_boot_animation"
  write_shell_var POCKETCHIP_BROWSER "$pocketchip_browser"
  write_shell_var POCKETCHIP_GESTURES "$pocketchip_gestures"
  write_shell_var POCKETCHIP_DARK_MODE "$pocketchip_dark_mode"
  write_shell_var POCKETCHIP_TIMEZONE "$pocketchip_timezone"
  write_shell_var POCKETCHIP_NETWORK_TIME "$pocketchip_network_time"
  write_shell_var POCKETCHIP_FIREFOX_SCALE "$pocketchip_firefox_scale"
  write_shell_var POCKETCHIP_FIREFOX_DEFAULT_ZOOM "$pocketchip_firefox_default_zoom"
  write_shell_var POCKETCHIP_BROWSER_FULLSCREEN "$pocketchip_browser_fullscreen"
  write_shell_var POCKETCHIP_BROWSER_TOUCH_MODE "$pocketchip_browser_touch_mode"
} > "$rootfs/etc/default/pocketchip-ui"

install -d -m 0755 "$rootfs/etc/systemd/logind.conf.d"
install -m 0644 "$repo_root/configs/logind-pocketchip.conf" "$rootfs/etc/systemd/logind.conf.d/pocketchip.conf"

install -d -m 0755 "$rootfs/etc/systemd/journald.conf.d"
cat > "$rootfs/etc/systemd/journald.conf.d/pocketchip.conf" <<'EOF'
[Journal]
Storage=persistent
SystemMaxUse=16M
RuntimeMaxUse=8M
MaxRetentionSec=14day
EOF

install -d -m 0755 "$rootfs/etc/sysctl.d"
cat > "$rootfs/etc/sysctl.d/90-pocketchip-performance.conf" <<'EOF'
# Favor compressed in-RAM swap over reclaiming useful file cache on a 512 MiB
# NAND-backed PocketCHIP. Keep dirty writeback caps low to avoid long stalls.
vm.swappiness=120
vm.page-cluster=0
vm.dirty_background_bytes=4194304
vm.dirty_bytes=16777216
EOF

cat > "$rootfs/etc/systemd/zram-generator.conf" <<'EOF'
[zram0]
zram-size = ram / 2
swap-priority = 100
EOF

install -d -m 0755 "$rootfs/etc/systemd/system"
if [[ "$pocketchip_network_time" == 1 ]]; then
  install -d -m 0755 "$rootfs/etc/systemd/system/sysinit.target.wants"
  if [[ -e "$rootfs/usr/lib/systemd/system/systemd-timesyncd.service" ]]; then
    ln -sfn /usr/lib/systemd/system/systemd-timesyncd.service \
      "$rootfs/etc/systemd/system/sysinit.target.wants/systemd-timesyncd.service"
  elif [[ -e "$rootfs/lib/systemd/system/systemd-timesyncd.service" ]]; then
    ln -sfn /lib/systemd/system/systemd-timesyncd.service \
      "$rootfs/etc/systemd/system/sysinit.target.wants/systemd-timesyncd.service"
  else
    die "POCKETCHIP_NETWORK_TIME=1 requires systemd-timesyncd, but its unit was not installed"
  fi
else
  ln -sfn /dev/null "$rootfs/etc/systemd/system/systemd-timesyncd.service"
fi

for masked_unit in \
  apt-daily.timer \
  apt-daily-upgrade.timer \
  dpkg-db-backup.timer \
  fstrim.timer \
  iperf3.service \
  systemd-networkd.service \
  systemd-networkd.socket \
  systemd-networkd-wait-online.service
do
  ln -sfn /dev/null "$rootfs/etc/systemd/system/$masked_unit"
done

install -d -m 0755 "$rootfs/etc/tmpfiles.d"
install -m 0644 "$repo_root/configs/tmpfiles-pocketchip-backlight.conf" "$rootfs/etc/tmpfiles.d/pocketchip-backlight.conf"

install -d -m 0755 "$rootfs/etc/ssh/sshd_config.d"
cat > "$rootfs/etc/ssh/sshd_config.d/50-pocketchip-root.conf" <<'EOF'
PermitRootLogin no
EOF

install -d -m 0755 "$rootfs/etc/polkit-1/rules.d"
install -m 0644 "$repo_root/configs/polkit-pocketchip-radios.rules" "$rootfs/etc/polkit-1/rules.d/50-pocketchip-radios.rules"

install -d -m 0750 "$rootfs/etc/sudoers.d"
install -m 0440 "$repo_root/configs/sudoers-pocketchip-startx" "$rootfs/etc/sudoers.d/pocketchip-startx"
install -m 0440 "$repo_root/configs/sudoers-pocketchip-first-login" "$rootfs/etc/sudoers.d/pocketchip-first-login"
install -m 0440 "$repo_root/configs/sudoers-pocketchip-power" "$rootfs/etc/sudoers.d/pocketchip-power"
chroot "$rootfs" visudo -cf /etc/sudoers.d/pocketchip-startx
chroot "$rootfs" visudo -cf /etc/sudoers.d/pocketchip-first-login
chroot "$rootfs" visudo -cf /etc/sudoers.d/pocketchip-power

install -m 0644 "$repo_root/configs/pocketchip-keymap.service" "$rootfs/etc/systemd/system/pocketchip-keymap.service"
install -d -m 0755 "$rootfs/etc/systemd/system/multi-user.target.wants"
ln -sfn ../pocketchip-keymap.service "$rootfs/etc/systemd/system/multi-user.target.wants/pocketchip-keymap.service"

if [[ "$pocketchip_autologin_tty1" == 1 ]]; then
  install -d -m 0755 "$rootfs/etc/systemd/system/getty@tty1.service.d"
  cat > "$rootfs/etc/systemd/system/getty@tty1.service.d/autologin.conf" <<EOF
[Service]
ExecStart=
ExecStart=-/sbin/agetty --autologin $pocketchip_user --noclear %I \$TERM
EOF
fi

if [[ -n "$pocketchip_wifi_country" ]]; then
  cat > "$rootfs/etc/systemd/system/pocketchip-wifi-regdom.service" <<EOF
[Unit]
Description=Set PocketCHIP Wi-Fi regulatory domain
Before=NetworkManager.service

[Service]
Type=oneshot
ExecStart=/usr/sbin/iw reg set $pocketchip_wifi_country

[Install]
WantedBy=multi-user.target
EOF
  install -d -m 0755 "$rootfs/etc/systemd/system/multi-user.target.wants"
  ln -sfn ../pocketchip-wifi-regdom.service "$rootfs/etc/systemd/system/multi-user.target.wants/pocketchip-wifi-regdom.service"
fi

if [[ -n "$pocketchip_wifi_ssid" ]]; then
  install -d -m 0700 "$rootfs/etc/NetworkManager/system-connections"
  wifi_hidden_setting=""
  if [[ "$pocketchip_wifi_hidden" == 1 ]]; then
    wifi_hidden_setting="hidden=true"
  fi
  cat > "$rootfs/etc/NetworkManager/system-connections/pocketchip-wifi.nmconnection" <<EOF
[connection]
id=pocketchip-wifi
type=wifi
autoconnect=true
interface-name=wlan0

[wifi]
mode=infrastructure
ssid=$pocketchip_wifi_ssid
$wifi_hidden_setting

[wifi-security]
key-mgmt=wpa-psk
psk=$pocketchip_wifi_psk

[ipv4]
method=auto

[ipv6]
method=auto
EOF
  chmod 0600 "$rootfs/etc/NetworkManager/system-connections/pocketchip-wifi.nmconnection"
fi

if [[ "$install_oh_my_zsh" == 1 ]]; then
  if command -v git >/dev/null 2>&1; then
    git clone --depth=1 https://github.com/ohmyzsh/ohmyzsh.git "$user_home/.oh-my-zsh"
  else
    printf 'warning: git missing on host; skipping Oh My Zsh clone.\n' >&2
  fi
fi

chip_uid="$(chroot "$rootfs" id -u "$pocketchip_user")"
chip_gid="$(chroot "$rootfs" id -g "$pocketchip_user")"
chown -R "$chip_uid:$chip_gid" "$user_home"

kernel="$(find "$rootfs/boot" -maxdepth 1 -type f -name 'vmlinuz-*armmp*' -printf '%f\n' | sort -V | tail -1)"
if [[ -z "$kernel" ]]; then
  printf 'error: rootfs is missing an armmp kernel in /boot.\n' >&2
  exit 1
fi

version="${kernel#vmlinuz-}"
if [[ ! -x "$rootfs/sbin/init" ]]; then
  printf 'error: rootfs is missing executable /sbin/init.\n' >&2
  exit 1
fi

if [[ ! -f "$rootfs/boot/initrd.img-$version" ]]; then
  printf 'error: rootfs is missing initrd.img-%s.\n' "$version" >&2
  exit 1
fi

required_initrd_modules=(
  i2c-mv64xxx.ko
  axp20x-regulator.ko
  axp20x_usb_power.ko
  axp20x_ac_power.ko
  axp20x_battery.ko
  axp20x_adc.ko
  pinctrl-axp209.ko
  phy-sun4i-usb.ko
  ehci-platform.ko
  ohci-platform.ko
  usb-storage.ko
  uas.ko
  scsi_common.ko
  scsi_mod.ko
  sd_mod.ko
  ext4.ko
)
initrd_listing="$(lsinitramfs "$rootfs/boot/initrd.img-$version")"
for module in "${required_initrd_modules[@]}"; do
  if ! grep -Fq "/$module" <<<"$initrd_listing"; then
    printf 'error: initrd.img-%s is missing %s for USB-root boot.\n' "$version" "$module" >&2
    exit 1
  fi
done

if ! find "$rootfs/usr/lib/linux-image-$version" -type f -name 'sun5i-r8-chip.dtb' -print -quit | grep -q .; then
  printf 'error: rootfs is missing sun5i-r8-chip.dtb for %s.\n' "$version" >&2
  exit 1
fi

trap - EXIT

printf '\nBuilt rootfs at %s\n' "$rootfs"
printf 'Image profile: %s\n' "$pocketchip_image_profile"
printf 'Root auth: %s\n' "$pocketchip_root_auth"
printf 'Root password set: %s\n' "$([[ -n "$pocketchip_root_password" ]] && printf yes || printf no)"
printf 'User: %s\n' "$pocketchip_user"
printf 'User password set: %s\n' "$([[ -n "$pocketchip_user_password" ]] && printf yes || printf no)"
printf 'TTY1 autologin: %s\n' "$pocketchip_autologin_tty1"
printf 'Boot to i3: %s\n' "$pocketchip_boot_to_i3"
printf 'First-login password setup: %s\n' "$pocketchip_first_login_password_setup"
printf 'Browser: %s\n' "$pocketchip_browser"
printf 'Browser fullscreen: %s\n' "$pocketchip_browser_fullscreen"
printf 'Dark mode: %s\n' "$pocketchip_dark_mode"
printf 'Gestures: %s\n' "$pocketchip_gestures"
printf 'Timezone: %s\n' "$pocketchip_timezone"
printf 'Network time: %s\n' "$pocketchip_network_time"
printf 'Wi-Fi hidden profile: %s\n' "$pocketchip_wifi_hidden"
printf 'Boot animation: %s\n' "$pocketchip_boot_animation"
