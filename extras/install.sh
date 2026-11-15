#!/bin/bash
# Instala as peças do Vitrola que ficam fora da pasta do plugin:
# o atalho Super+Shift+M, as regras de janela e o autostart do Spotify.
# Pode rodar mais de uma vez: só acrescenta o que ainda não estiver lá.
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
hypr="$HOME/.config/hypr"

install -Dm755 "$here/vitrola-spotify-toggle" "$HOME/.local/bin/vitrola-spotify-toggle"

append() {  # append <snippet> <target> <marker>
  if grep -qF "$3" "$2" 2>/dev/null; then
    echo "já configurado: $2"
  else
    { echo; cat "$1"; } >> "$2"
    echo "adicionado: $2"
  fi
}
append "$here/hyprland.lua"  "$hypr/hyprland.lua"  'title = "^Vitrola$"'
append "$here/bindings.lua"  "$hypr/bindings.lua"  'vitrola-spotify-toggle'
append "$here/autostart.lua" "$hypr/autostart.lua" 'launch_on_start("spotify")'

echo
echo "Pronto. Falta só o login no Spotify (uma vez por máquina):"
echo "  python3 $(dirname "$here")/spotify.py login <client_id>"
