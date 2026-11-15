-- Vitrola (logan.vitrola shell plugin): the detached record player floats
-- like an object on the desk, without border, shadow or blur behind its
-- rounded wooden corners.
o.window({ class = "^org\\.quickshell$", title = "^Vitrola$" }, {
  float = true,
  center = true,
  border_size = 0,
  no_shadow = true,
  no_blur = true,
})

-- Vitrola: the Spotify app only provides the sound; keep its window out of
-- sight on a special workspace (Super+Shift+M peeks at it).
o.window("^Spotify$", { workspace = "special:spotify silent" })
