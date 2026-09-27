#!/bin/bash
# fa8ix theme installer for Debian/Ubuntu — GPL-3.0
set -euo pipefail
export PATH=/usr/sbin:/usr/bin:/sbin:/bin
base=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
if [[ ${EUID} -ne 0 ]]; then
    echo 'Run this installer with sudo.' >&2; exit 1
fi
exec 9>/run/lock/fa8ix-theme.lock
flock -n 9 || { echo 'Another installation is running.' >&2; exit 1; }
for tool in grub-mkconfig grub-script-check python3; do command -v "$tool" >/dev/null; done
if [[ ${1:-} == --restore ]]; then
    [[ $# == 2 ]] || { echo 'Usage: install.sh --restore /var/backups/fa8ix-theme/ID' >&2; exit 1; }
    saved=$(realpath -- "$2")
    [[ "$saved" == /var/backups/fa8ix-theme/* && -f "$saved/grub.default" && -f "$saved/grub.cfg" ]]
    grub-script-check "$saved/grub.cfg"
    cp -a -- "$saved/grub.default" /etc/default/grub
    if [[ -d "$saved/previous-theme" ]]; then
        # No directory deletion: restore over the current assets.
        cp -a -- "$saved/previous-theme/." /boot/grub/themes/fa8ix-theme/
    fi
    cp -a -- "$saved/grub.cfg" /boot/grub/grub.cfg
    echo "Configuration restored from $saved"
    exit 0
fi
preset=theme.txt
case ${1:-} in
    '') [[ $# == 0 ]] ;;
    --compact) [[ $# == 1 ]]; preset=theme-1920.txt ;;
    *) echo 'Usage: install.sh [--compact] | --restore DIRECTORY' >&2; exit 1 ;;
esac
[[ -f "$base/theme/$preset" && -f /etc/default/grub && -f /boot/grub/grub.cfg ]]
dest=/boot/grub/themes/fa8ix-theme
# Do not follow a pre-existing symlink when copying theme assets.
[[ ! -L "$dest" ]] || { echo "$dest is a symbolic link; installation stopped." >&2; exit 1; }
saved=/var/backups/fa8ix-theme/$(date +%Y%m%d-%H%M%S)-$$
install -d -m 700 "$saved"
cp -a /etc/default/grub "$saved/grub.default"
cp -a /boot/grub/grub.cfg "$saved/grub.cfg"
if [[ -d "$dest" ]]; then cp -a "$dest" "$saved/previous-theme"; fi
rollback() {
    local status=$?
    trap - ERR
    cp -a -- "$saved/grub.default" /etc/default/grub
    cp -a -- "$saved/grub.cfg" /boot/grub/grub.cfg
    if [[ -d "$saved/previous-theme" ]]; then cp -a -- "$saved/previous-theme/." "$dest/"; fi
    echo "Installation failed; previous configuration restored. Backup: $saved" >&2
    exit "$status"
}
trap rollback ERR
install -d -m 755 "$dest"
cp -r -- "$base/theme/." "$dest/"
chown -R root:root "$dest"
find "$dest" -type d -exec chmod 755 {} +
find "$dest" -type f -exec chmod 644 {} +
install -m 644 "$base/theme/$preset" "$dest/theme.txt"
python3 - <<'PY'
from pathlib import Path
import re
p=Path('/etc/default/grub')
s=p.read_text()
line='GRUB_THEME="/boot/grub/themes/fa8ix-theme/theme.txt"'
if re.search(r'^\s*GRUB_THEME=',s,re.M):
    s=re.sub(r'^\s*GRUB_THEME=.*$',line,s,flags=re.M)
else:
    s+='\n'+line+'\n'
p.write_text(s)
PY
# Public edition: retain the full GRUB menu and enable available test entries.
python3 - <<'PY'
from pathlib import Path
import re
p=Path('/etc/default/grub')
s=p.read_text()
settings={'GRUB_TIMEOUT_STYLE':'menu','GRUB_DISABLE_MEMTEST':'false','GRUB_DISABLE_RECOVERY':'false','GRUB_DISABLE_OS_PROBER':'false'}
for key,value in settings.items():
    line=f'{key}={value}'
    pattern=rf'^\s*{key}=.*$'
    if re.search(pattern,s,re.M): s=re.sub(pattern,line,s,flags=re.M)
    else: s+='\n'+line+'\n'
p.write_text(s)
PY
# Generate on the same filesystem, validate, then atomically activate.
candidate=$(mktemp /boot/grub/grub.cfg.fa8ix.XXXXXX)
grub-mkconfig -o "$candidate"
grub-script-check "$candidate"
# Catch a later configuration override of GRUB_THEME.
grep -Fq '/boot/grub/themes/fa8ix-theme/theme.txt' "$candidate"
chmod --reference=/boot/grub/grub.cfg "$candidate"
chown --reference=/boot/grub/grub.cfg "$candidate"
mv -f -- "$candidate" /boot/grub/grub.cfg
trap - ERR
printf 'fa8ix theme activated. Backup: %s\n' "$saved"
printf 'Restore: sudo %q --restore %q\n' "$base/install.sh" "$saved"
