import QtQuick

// Walnut veneer drawn once: warm base, wavy grain lines from a fixed seed
// (so the wood looks the same every time it opens) and a varnish sheen.
Canvas {
  id: wood
  property real radius: 0
  property real unit: 1
  property int seed: 7

  onWidthChanged: requestPaint()
  onHeightChanged: requestPaint()

  onPaint: {
    var ctx = getContext("2d")
    ctx.reset()
    var w = width, h = height
    if (w <= 0 || h <= 0) return
    var s = seed
    function rnd() { s = (s * 16807) % 2147483647; return s / 2147483647 }

    ctx.save()
    ctx.beginPath()
    ctx.roundedRect(0, 0, w, h, radius, radius)
    ctx.clip()

    var base = ctx.createLinearGradient(0, 0, 0, h)
    base.addColorStop(0, "#6e4529")
    base.addColorStop(0.55, "#5a361f")
    base.addColorStop(1, "#45291a")
    ctx.fillStyle = base
    ctx.fillRect(0, 0, w, h)

    for (var i = 0; i < 150; i++) {
      var y0 = rnd() * h
      var amp = (2 + rnd() * 7) * unit
      var f = (0.004 + rnd() * 0.012) / unit
      var ph = rnd() * 6.283
      var dark = rnd() < 0.72
      ctx.strokeStyle = dark
        ? "rgba(28,13,4," + (0.08 + rnd() * 0.2) + ")"
        : "rgba(255,214,170," + (0.03 + rnd() * 0.06) + ")"
      ctx.lineWidth = (0.5 + rnd() * 1.8) * unit
      ctx.beginPath()
      for (var x = 0; x <= w + 6; x += 6) {
        var y = y0 + Math.sin(x * f + ph) * amp + Math.sin(x * f * 3.1 + ph * 2) * amp * 0.3
        if (x === 0) ctx.moveTo(x, y)
        else ctx.lineTo(x, y)
      }
      ctx.stroke()
    }

    var sheen = ctx.createLinearGradient(0, 0, w, h)
    sheen.addColorStop(0, "rgba(255,255,255,0.10)")
    sheen.addColorStop(0.45, "rgba(255,255,255,0)")
    sheen.addColorStop(1, "rgba(0,0,0,0.18)")
    ctx.fillStyle = sheen
    ctx.fillRect(0, 0, w, h)
    ctx.restore()

    // Bevelled edge.
    ctx.lineWidth = 1.5 * unit
    ctx.strokeStyle = "rgba(255,225,190,0.18)"
    ctx.beginPath()
    ctx.roundedRect(0.75 * unit, 0.75 * unit, w - 1.5 * unit, h - 1.5 * unit, radius, radius)
    ctx.stroke()
  }
}
