#!/usr/bin/env bash
# Furface Linux Setup: Fedora 44 KDE / Surface Laptop 4 Intel.
# Interactive: bash "furface linux setup.sh"
# CLI: --fix mic | --fix gpu,touch,face | --all | --plan all
set -Eeuo pipefail
VERSION=2.0.0
usage() {
    cat <<'HELP'
Furface Linux Setup
Usage:
  bash "furface linux setup.sh"                  Interactive menu
  bash "furface linux setup.sh" --fix mic        One fix
  bash "furface linux setup.sh" --fix gpu,mic    Selected fixes
  bash "furface linux setup.sh" --all            All fixes
  bash "furface linux setup.sh" --plan all       Preview only; no sudo or changes
  bash "furface linux setup.sh" --help

Fix names: repos, gpu, mic, touch, face
Scope: Fedora 44 KDE, Intel Surface Laptop 4, x86_64 (not Atomic/Kinoite).
Face setup requires a local camera scan. Touch requires reboot/MOK enrollment.
HELP
}
validate() {
    local item
    [[ -n "$1" && "$1" != ,* && "$1" != *, && "$1" != *,,* ]] || return 1
    IFS=, read -ra REQUESTED <<< "$1"
    for item in "${REQUESTED[@]}"; do
        case "$item" in repos|gpu|mic|touch|face) ;; *) return 1 ;; esac
    done
}
ACTION=''; PLAN=0
case "${1:-}" in
    --help|-h) usage; exit 0 ;;
    --version) echo "$VERSION"; exit 0 ;;
    --all) [[ $# == 1 ]] || { usage; exit 2; }; ACTION=all ;;
    --fix|--plan)
        [[ $# == 2 ]] || { usage; exit 2; }
        ACTION=$2
        [[ $1 != --plan ]] || PLAN=1 ;;
    '')
        [[ -t 0 ]] || { usage; exit 2; }
        cat <<'MENU'
Furface Linux Setup
  1) Fix everything
  2) Repair Surface repository and refresh repositories
  3) Intel GPU / DaVinci Resolve OpenCL
  4) Microphone distortion (20% input)
  5) Surface touchscreen / kernel / Secure Boot
  6) Face unlock (Howdy, KDE login and lock screen)
  0) Exit
You may select multiple numbers, e.g. 3 4
MENU
        read -r -p 'Select: ' CHOICE
        ACTION=''
        for NUMBER in $CHOICE; do
            case "$NUMBER" in
                0) exit 0 ;; 1) ACTION=all; break ;;
                2) ITEM=repos ;; 3) ITEM=gpu ;; 4) ITEM=mic ;;
                5) ITEM=touch ;; 6) ITEM=face ;;
                *) echo 'Unknown choice.' >&2; exit 2 ;;
            esac
            ACTION="${ACTION:+$ACTION,}$ITEM"
        done ;;
    *) usage; exit 2 ;;
esac
[[ "$ACTION" != all ]] || ACTION=repos,gpu,mic,touch,face
validate "$ACTION" || { echo 'Invalid fix selection.' >&2; exit 2; }
# Normalize order, remove duplicates, and resolve touch's repository dependency.
SELECTED=()
for ITEM in repos gpu mic touch face; do
    if [[ ",$ACTION," == *",$ITEM,"* ]]; then SELECTED+=("$ITEM"); fi
done
if (( PLAN )); then
    printf 'Selected: %s\n' "${SELECTED[*]}"
    [[ ",$ACTION," != *,touch,* ]] || echo 'Touch also prepares the Surface repository.'
    echo 'Backups precede changes; failures stop the run. No automatic reboot.'
    exit 0
fi
[[ -t 0 ]] || { echo 'Run in a local terminal.' >&2; exit 1; }
if [[ $EUID -ne 0 ]]; then exec sudo -- bash "$0" --fix "$ACTION"; fi
TARGET_USER=${SUDO_USER:-}
if [[ -z "$TARGET_USER" || "$TARGET_USER" == root ]]; then
    read -r -p 'Your normal Fedora username: ' TARGET_USER
fi
id "$TARGET_USER" >/dev/null
[[ "$TARGET_USER" != root && "$TARGET_USER" =~ ^[a-zA-Z_][a-zA-Z0-9_.-]*\$?$ ]] || {
    echo 'A valid normal user is required.'; exit 1;
}
export TARGET_USER
source /etc/os-release
[[ "$ID" == fedora && "$VERSION_ID" == 44 && "$(uname -m)" == x86_64 ]] || {
    echo 'Supported target: Fedora 44 x86_64. Other releases need separate validation.'; exit 1;
}
[[ ! -e /run/ostree-booted ]] || { echo 'Atomic/Kinoite is not supported.'; exit 1; }
[[ $(cat /sys/class/dmi/id/product_name) == 'Surface Laptop 4' && $(cat /proc/cpuinfo) == *GenuineIntel* ]] || {
    echo 'Supported hardware: Intel Surface Laptop 4.'; exit 1;
}
exec 9>/run/lock/furface-linux-setup.lock
flock -n 9 || { echo "Another setup instance is running."; exit 1; }
BACKUP_DIR=$(mktemp -d /var/backups/furface-linux-XXXXXXXX)
chmod 700 "$BACKUP_DIR"
export BACKUP_DIR
cp -a /etc/yum.repos.d "$BACKUP_DIR/"
cp -a /etc/pam.d "$BACKUP_DIR/"
[[ ! -d /etc/howdy ]] || cp -a /etc/howdy "$BACKUP_DIR/"
exec > >(tee -a "$BACKUP_DIR/setup.log") 2>&1
trap 'rc=$?; echo "Stopped at line $LINENO (exit $rc). Earlier fixes may be applied. Backups/log: $BACKUP_DIR"; exit "$rc"' ERR
printf 'Selected: %s\nBackups: %s\n' "${SELECTED[*]}" "$BACKUP_DIR"
fedora_dnf() { dnf --disablerepo='*' --enablerepo=fedora --enablerepo=updates "$@"; }
probe() { curl --fail --silent --location --retry 2 --connect-timeout 10 --max-time 30 "$1" -o /dev/null; }
ensure_curl() { command -v curl >/dev/null || fedora_dnf install -y curl; }

prepare_surface_repo() {
ensure_curl
# Repair only the known Surface repository; unrelated repositories are retained.
SURFACE_RELEASE="$VERSION_ID"
if ! probe "https://pkg.surfacelinux.com/fedora/f${SURFACE_RELEASE}/repodata/repomd.xml"; then
    if [[ "$VERSION_ID" == 44 ]] && probe 'https://pkg.surfacelinux.com/fedora/f43/repodata/repomd.xml'; then
        SURFACE_RELEASE=43
        echo 'Fedora 44 Surface repository unavailable; using the Fedora 43 Surface packages tested on this laptop.'
    else
        echo 'No verified Surface repository for this release. Stopping without changing the boot setup.'
        exit 1
    fi
fi
cat > /etc/yum.repos.d/linux-surface.repo <<REPO
[linux-surface]
name=linux-surface
baseurl=https://pkg.surfacelinux.com/fedora/f${SURFACE_RELEASE}/
enabled=1
gpgcheck=1
gpgkey=https://raw.githubusercontent.com/linux-surface/linux-surface/master/pkg/keys/surface.asc
skip_if_unavailable=0
REPO


}

fix_repos() {
prepare_surface_repo
# DNF imports the signing keys declared by installed repository configurations.
# This also fixes the existing ChatGPT repository's unaccepted signing key.
# Signature checking stays enabled. No unrelated repositories are removed.
dnf -y makecache --refresh


}

fix_gpu() {
echo 'Installing Intel OpenCL and camera diagnostics...'
fedora_dnf install -y intel-compute-runtime clinfo v4l-utils
runuser -u "$TARGET_USER" -- clinfo -l
if ! runuser -u "$TARGET_USER" -- clinfo -l | grep -qi 'Iris.*Xe'; then
    echo 'Intel Iris Xe was not detected by OpenCL. Check the log before using Resolve.'
    exit 1
fi



}

fix_mic() {
# Surface ALC274 mic: 100% maps to +30 dB capture plus +30 dB boost.
# A 20% source level gave +18 dB capture and zero boost on this machine.
# WirePlumber persists this source level across session restarts.
echo 'Setting the built-in microphone to a conservative input level...'
fedora_dnf install -y pulseaudio-utils alsa-utils
MIC_SOURCE=alsa_input.pci-0000_00_1f.3.analog-stereo
TARGET_UID=$(id -u "$TARGET_USER")
user_audio() {
    runuser -u "$TARGET_USER" -- env \
        XDG_RUNTIME_DIR="/run/user/$TARGET_UID" \
        DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$TARGET_UID/bus" "$@"
}
if user_audio pactl get-source-volume "$MIC_SOURCE" >/dev/null 2>&1; then
    user_audio pactl list sources > "$BACKUP_DIR/microphone-sources-before.txt"
    user_audio pactl set-source-port "$MIC_SOURCE" analog-input-internal-mic
    user_audio pactl set-source-volume "$MIC_SOURCE" 20%
    user_audio pactl get-source-volume "$MIC_SOURCE"
    amixer -c PCH sget 'Internal Mic Boost'
    echo 'Microphone input is at 20%. Test speech before increasing it; 100% caused clipping.'
else
    echo 'Microphone fix NOT applied: no active desktop audio source. After login run:'
    echo "pactl set-source-volume $MIC_SOURCE 20%"
    return 1
fi


}

fix_touch() {
prepare_surface_repo
echo 'Installing the Surface kernel and touchscreen service...'
# No --allowerasing: incompatible package changes stop for review.
dnf --disablerepo='*' --enablerepo=fedora --enablerepo=updates --enablerepo=linux-surface install -y kernel-surface iptsd surface-secureboot kernel-surface-default-watchdog mokutil grubby
# A signed Surface kernel needs a one-time firmware enrollment under Secure Boot.
if mokutil --sb-state 2>/dev/null | grep -qi 'SecureBoot enabled'; then
    if ! mokutil --test-key /usr/share/surface-secureboot/surface.cer >/dev/null 2>&1; then
        HASH_PATH=$(mktemp)
        mokutil --generate-hash=surface > "$HASH_PATH"
        mokutil --hash-file "$HASH_PATH" --import /usr/share/surface-secureboot/surface.cer
        rm -f "$HASH_PATH"
        echo 'On reboot: Enroll MOK -> Continue -> Yes -> password: surface -> Reboot.'
    fi
fi
systemctl enable --now linux-surface-default-watchdog.path
/usr/bin/linux-surface-default-watchdog.py
grubby --default-kernel


}

fix_face() {
ensure_curl
fedora_dnf install -y v4l-utils python3
echo 'Installing Howdy face authentication from the starfish Fedora COPR...'
HOWDY_URL="https://download.copr.fedorainfracloud.org/results/starfish/howdy-beta/fedora-${VERSION_ID}-x86_64/"
if ! probe "${HOWDY_URL}repodata/repomd.xml"; then
    echo 'Howdy packages are unavailable for this release. Drivers are installed; face login was not changed.'
    exit 1
fi
cat > /etc/yum.repos.d/starfish-howdy-beta.repo <<REPO
[copr:copr.fedorainfracloud.org:starfish:howdy-beta]
name=Copr repo for howdy-beta owned by starfish
baseurl=${HOWDY_URL}
enabled=1
gpgcheck=1
gpgkey=https://download.copr.fedorainfracloud.org/results/starfish/howdy-beta/pubkey.gpg
skip_if_unavailable=0
REPO
dnf --disablerepo='*' --enablerepo=fedora --enablerepo=updates \
    --enablerepo=copr:copr.fedorainfracloud.org:starfish:howdy-beta \
    --setopt=install_weak_deps=False install -y howdy howdy-gtk

# Find the infrared capture interface; do not assume /dev/video2 stays fixed.
IR_DEVICE=''
for DEV in /dev/video*; do
    [[ -e "$DEV" ]] || continue
    NAME=$(cat "/sys/class/video4linux/${DEV##*/}/name")
    if [[ "$NAME" == *'Surface I'* ]] && v4l2-ctl -d "$DEV" --list-formats-ext 2>/dev/null | grep -q GREY; then
        IR_DEVICE="$DEV"
        for LINK in /dev/v4l/by-path/*video-index0; do
            [[ -L "$LINK" ]] || continue
            if [[ "$(readlink -f "$LINK")" == "$DEV" ]]; then
                IR_DEVICE="$LINK"
                break
            fi
        done
        break
    fi
done
[[ -n "$IR_DEVICE" ]] || {
    echo 'No Surface infrared camera detected. Howdy is installed; face login was not changed.'; exit 1;
}
export IR_DEVICE
python3 - <<'CONFIG'
import configparser, os
from pathlib import Path
p=Path('/etc/howdy/config.ini')
c=configparser.ConfigParser(); c.read(p)
for section in ('video','debug','core'):
    if not c.has_section(section): raise SystemExit('Unexpected Howdy configuration; stopping')
c['video']['device_path']=os.environ['IR_DEVICE']
c['video']['max_height']='480'
c['video']['timeout']='8'
c['debug']['end_report']='false'
c['core']['disabled']='false'
with p.open('w') as f: c.write(f)
CONFIG
python3 -c 'import cv2, dlib; print("Face recognition dependencies loaded.")'

echo 'Face enrollment stores a face model locally. Password login remains available.'
read -r -p 'Ready to look straight at the camera? [Y/n] ' ANSWER
if [[ "$ANSWER" =~ ^[Nn] ]]; then
    echo 'Face enrollment skipped. Rerun this script when ready.'
else
    if [[ -s "/etc/howdy/models/$TARGET_USER.dat" ]]; then
        howdy -U "$TARGET_USER" list
        read -r -p 'Add another face scan? [y/N] ' ANSWER
        if [[ "$ANSWER" =~ ^[Yy]$ ]]; then
            howdy -U "$TARGET_USER" -y add 'Surface setup'
        fi
    else
        howdy -U "$TARGET_USER" -y add 'Surface setup'
    fi
    echo 'Keep looking at the camera for the authentication test...'
    python3 - <<'PAM_SETUP'
import ctypes as C
from pathlib import Path
import shutil
import os
pam=C.CDLL('libpam.so.0'); libc=C.CDLL(None)
class Message(C.Structure): _fields_=[('style',C.c_int),('msg',C.c_char_p)]
class Response(C.Structure): _fields_=[('resp',C.c_char_p),('retcode',C.c_int)]
CB=C.CFUNCTYPE(C.c_int,C.c_int,C.POINTER(C.POINTER(Message)),C.POINTER(C.POINTER(Response)),C.c_void_p)
libc.calloc.argtypes=[C.c_size_t,C.c_size_t]; libc.calloc.restype=C.c_void_p
@CB
def converse(n,msg,out,data):
    for i in range(n):
        if msg[i].contents.style in (1,2): return 19
    out[0]=C.cast(libc.calloc(n,C.sizeof(Response)),C.POINTER(Response))
    return 0
class Conv(C.Structure): _fields_=[('conv',CB),('data',C.c_void_p)]
pam.pam_start.argtypes=[C.c_char_p,C.c_char_p,C.POINTER(Conv),C.POINTER(C.c_void_p)]
pam.pam_authenticate.argtypes=[C.c_void_p,C.c_int]
pam.pam_end.argtypes=[C.c_void_p,C.c_int]
for service in ('kde','plasmalogin'):
    target=Path('/etc/pam.d')/service
    source=target if target.exists() else Path('/usr/lib/pam.d')/service
    if not source.exists() or not any(line.split()[:3] == ['auth','substack','password-auth'] for line in source.read_text().splitlines()):
        raise SystemExit('Unsupported login configuration; no PAM changes made')
test=Path('/etc/pam.d/furface-howdy-test')
if test.exists(): raise SystemExit('Test service already exists; stopping')
try:
    test.write_text('auth required pam_howdy.so\naccount required pam_permit.so\n')
    handle=C.c_void_p(); conv=Conv(converse,None)
    rc=pam.pam_start(b'furface-howdy-test',os.environ['TARGET_USER'].encode(),C.byref(conv),C.byref(handle))
    if rc: raise SystemExit(f'PAM start failed: {rc}')
    rc=pam.pam_authenticate(handle,0)
    pam.pam_end(handle,rc)
    print(f'Face-only PAM authentication result: {rc}',flush=True)
    if rc: raise SystemExit('Face authentication failed; login configuration unchanged')
finally:
    test.unlink(missing_ok=True)
for service in ['kde','plasmalogin']:
    target=Path('/etc/pam.d')/service
    source=target if target.exists() else Path('/usr/lib/pam.d')/service
    s=source.read_text()
    if 'pam_howdy.so' in s: continue
    backup=Path('/etc/pam.d')/(service+'.before-howdy')
    if not backup.exists(): shutil.copy2(source,backup)
    lines=s.splitlines(keepends=True)
    index=next(i for i,line in enumerate(lines) if line.split()[:3]==['auth','substack','password-auth'])
    lines.insert(index,'auth        sufficient    pam_howdy.so\n')
    target.write_text(''.join(lines)); target.chmod(0o644)
    print(f'Enabled face authentication for {service}; password fallback retained',flush=True)

PAM_SETUP
    restorecon /etc/pam.d/kde /etc/pam.d/plasmalogin
fi

}

for ITEM in "${SELECTED[@]}"; do
    echo "--- Applying: $ITEM ---"
    "fix_$ITEM"
    echo "--- Finished: $ITEM ---"
done
echo "Selected fixes finished. Backups/log: $BACKUP_DIR"
if [[ ",$ACTION," == *,touch,* ]]; then
    echo 'Save work and reboot. If prompted: Enroll MOK -> Continue -> Yes -> surface -> Reboot.'
    echo 'After reboot, uname -r should contain surface; test the touchscreen.'
fi
if [[ ",$ACTION," == *,face,* ]]; then
    echo 'If enrollment was completed, test face unlock using Meta+L. Password fallback remains.'
fi
if [[ ",$ACTION," == *,gpu,* ]]; then
    echo 'OpenCL verified. DaVinci Resolve itself must be installed separately.'
fi
echo 'No automatic reboot was performed.'
