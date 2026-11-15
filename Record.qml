import QtQuick
import QtQuick.Effects
import qs.Commons
import qs.Ui

// A 12" record from above. The vinyl and its label turn; the light glinting
// off the grooves does not, the way it looks on a real deck.
Item {
  id: rec
  property real size: 200
  property bool spinning: false
  property string artUrl: ""
  property color accent: "#888888"
  property color labelInk: "#101010"
  property alias angle: spinner.rotation
  // Only draw frames while someone can see the record.
  property bool live: true
  // 0 = stopped, 1 = 33⅓ rpm. Eased towards the target like a platter with
  // some mass: about half a second to spin up, a second to coast to a stop.
  property real speed: 0

  onLiveChanged: if (live) speed = (spinning && !Style.reduceMotion) ? 1 : 0

  FrameAnimation {
    running: rec.live && !Style.reduceMotion && (rec.spinning || rec.speed > 0)
    onTriggered: {
      var dt = Math.min(frameTime, 0.1)
      if (rec.spinning) rec.speed = Math.min(1, rec.speed + dt * 2.0)
      else rec.speed = Math.max(0, rec.speed - dt * 1.0)
      // 33⅓ rpm = 200°/s.
      spinner.rotation = (spinner.rotation + dt * 200 * rec.speed) % 360
    }
  }

  width: size
  height: size

  Item {
    id: spinner
    anchors.fill: parent

    Rectangle {
      anchors.fill: parent
      radius: width / 2
      color: "#121212"
    }

    // Grooves, with a few smoother bands between tracks.
    Canvas {
      anchors.fill: parent
      onWidthChanged: requestPaint()
      onPaint: {
        var ctx = getContext("2d")
        ctx.reset()
        var c = width / 2
        var s = 11
        function rnd() { s = (s * 16807) % 2147483647; return s / 2147483647 }
        var gaps = [0.52, 0.63, 0.74, 0.85]
        for (var r = c * 0.38; r < c * 0.975; r += 1.1) {
          var t = r / c
          var inGap = false
          for (var i = 0; i < gaps.length; i++) if (Math.abs(t - gaps[i]) < 0.008) inGap = true
          ctx.strokeStyle = inGap ? "rgba(0,0,0,0.55)" : "rgba(255,255,255," + (0.025 + rnd() * 0.045) + ")"
          ctx.lineWidth = inGap ? 1.6 : 0.7
          ctx.beginPath()
          ctx.arc(c, c, r, 0, Math.PI * 2)
          ctx.stroke()
        }
        // Raised rim.
        ctx.strokeStyle = "rgba(255,255,255,0.10)"
        ctx.lineWidth = 1.2
        ctx.beginPath()
        ctx.arc(c, c, c - 1, 0, Math.PI * 2)
        ctx.stroke()
      }
    }

    // Label: the theme accent, with the album art printed over it.
    Rectangle {
      id: label
      anchors.centerIn: parent
      width: rec.size * 0.36
      height: width
      radius: width / 2
      color: rec.accent

      // Without art, a printed band shows the turn.
      Rectangle {
        visible: !art.visible
        anchors.centerIn: parent
        width: parent.width
        height: parent.height * 0.16
        color: rec.labelInk
        opacity: 0.35
      }

      SizedImage {
        id: art
        anchors.fill: parent
        crop: true
        url: rec.artUrl
        visible: rec.artUrl !== ""
        layer.enabled: visible
        layer.effect: MultiEffect {
          maskEnabled: true
          maskSource: labelMask
          maskThresholdMin: 0.5
          maskSpreadAtMin: 1.0
        }
      }

      Rectangle {
        id: labelMask
        anchors.fill: parent
        radius: width / 2
        visible: false
        layer.enabled: true
      }

      // Thin accent ring where the label meets the run-out groove.
      Rectangle {
        anchors.fill: parent
        radius: width / 2
        color: "transparent"
        border.width: Math.max(1, rec.size * 0.006)
        border.color: rec.accent
      }
    }
  }

  // Fixed glint on the grooves.
  Canvas {
    anchors.fill: parent
    onWidthChanged: requestPaint()
    onPaint: {
      var ctx = getContext("2d")
      ctx.reset()
      var c = width / 2
      function wedge(a0, a1) {
        var g = ctx.createRadialGradient(c, c, c * 0.2, c, c, c)
        g.addColorStop(0, "rgba(255,255,255,0)")
        g.addColorStop(0.55, "rgba(255,255,255,0.10)")
        g.addColorStop(1, "rgba(255,255,255,0.03)")
        ctx.fillStyle = g
        ctx.beginPath()
        ctx.moveTo(c, c)
        ctx.arc(c, c, c * 0.97, a0, a1)
        ctx.closePath()
        ctx.fill()
      }
      wedge(-Math.PI * 0.40, -Math.PI * 0.26)
      wedge(Math.PI * 0.60, Math.PI * 0.74)
    }
  }

  // Spindle.
  Rectangle {
    anchors.centerIn: parent
    width: Math.max(3, rec.size * 0.025)
    height: width
    radius: width / 2
    gradient: Gradient {
      GradientStop { position: 0; color: "#f2f2f2" }
      GradientStop { position: 1; color: "#7a7a7a" }
    }
  }
}
