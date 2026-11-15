import QtQuick

// Brushed aluminium: a cool grey gradient with fine horizontal hairlines.
// `round` draws it as a disc (knobs, pivots) with concentric brushing instead.
Canvas {
  id: metal
  property real radius: 0
  property real unit: 1
  property bool round: false
  property real shade: 1.0
  property int seed: 3

  onWidthChanged: requestPaint()
  onHeightChanged: requestPaint()
  onShadeChanged: requestPaint()

  function tone(v) {
    var c = Math.max(0, Math.min(255, Math.round(v * shade)))
    return "rgb(" + c + "," + Math.min(255, c + 3) + "," + Math.min(255, c + 8) + ")"
  }

  onPaint: {
    var ctx = getContext("2d")
    ctx.reset()
    var w = width, h = height
    if (w <= 0 || h <= 0) return
    var s = seed
    function rnd() { s = (s * 16807) % 2147483647; return s / 2147483647 }

    ctx.save()
    ctx.beginPath()
    if (round) ctx.ellipse(0, 0, w, h)
    else ctx.roundedRect(0, 0, w, h, radius, radius)
    ctx.clip()

    var g = round ? ctx.createLinearGradient(0, 0, w, h) : ctx.createLinearGradient(0, 0, 0, h)
    g.addColorStop(0, tone(214))
    g.addColorStop(0.5, tone(176))
    g.addColorStop(1, tone(132))
    ctx.fillStyle = g
    ctx.fillRect(0, 0, w, h)

    if (round) {
      var cx = w / 2, cy = h / 2
      for (var r = 1; r < w / 2; r += 0.8 * unit) {
        ctx.strokeStyle = rnd() < 0.5 ? "rgba(255,255,255," + (rnd() * 0.10) + ")" : "rgba(0,0,0," + (rnd() * 0.08) + ")"
        ctx.lineWidth = 0.6 * unit
        ctx.beginPath()
        ctx.arc(cx, cy, r, 0, Math.PI * 2)
        ctx.stroke()
      }
    } else {
      for (var y = 0; y < h; y += 0.9 * unit) {
        ctx.strokeStyle = rnd() < 0.5 ? "rgba(255,255,255," + (rnd() * 0.14) + ")" : "rgba(0,0,0," + (rnd() * 0.07) + ")"
        ctx.lineWidth = 0.6 * unit
        ctx.beginPath()
        ctx.moveTo(0, y)
        ctx.lineTo(w, y)
        ctx.stroke()
      }
    }
    ctx.restore()
  }
}
