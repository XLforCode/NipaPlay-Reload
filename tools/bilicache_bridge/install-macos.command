#!/bin/bash
set -euo pipefail
cd -- "$(dirname -- "$0")"
read -r -p 'Chrome extension ID (shown in extension playback settings): ' extension_id
cache_root=$(/usr/bin/osascript -e 'POSIX path of (choose folder with prompt "Select the same BiliCache root as Chrome")')
player=$(/usr/bin/osascript -e 'POSIX path of (choose file with prompt "Select your NipaPlay application" of type {"com.apple.application-bundle"})')
./bilicache_setup install --extension-id "$extension_id" --cache-root "$cache_root" --player "${player%/}"
read -r -p 'Press Return to close.'
