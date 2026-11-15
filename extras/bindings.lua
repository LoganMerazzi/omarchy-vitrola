-- Vitrola: Spotify lives hidden on special:spotify. Super+Shift+M shows or
-- hides it, starting Spotify first if it is not running.
hl.unbind("SUPER + SHIFT + M")
o.bind("SUPER + SHIFT + M", "Music", "vitrola-spotify-toggle")
