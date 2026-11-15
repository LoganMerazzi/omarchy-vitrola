import QtQuick
import QtQuick.Effects
import qs.Commons

// The record player itself, drawn top-down on a 460×400 design grid and
// scaled to whatever width the panel gives it. Wood and metal stay wood and
// metal; the theme shows up in the label, the power light, the display and
// the knob's pointer.
Item {
  id: tt

  // Track state, fed by Panel.qml.
  property bool hasTrack: false
  property bool playing: false
  property string title: ""
  property string artist: ""
  property string artUrl: ""
  property real position: 0      // seconds
  property real length: 0        // seconds
  property real volume: 1        // 0..1
  property bool canPrevious: false
  property bool canNext: false
  property bool canPlayPause: false
  property bool spinning: false
  property bool live: true            // panel is open
  property string trackKey: ""        // changes when the song changes

  // Theme.
  property color accent: Color.accent
  property color foreground: Color.foreground
  property color background: Color.background
  property string fontFamily: Style.font.family

  property bool canSeek: false
  property bool detached: false
  signal detachToggled()
  property bool crateOpen: true
  signal crateToggled()
  property bool muted: false

  signal seekRequested(real seconds)
  signal volumeRequested(real value)
  signal muteToggleRequested()
  signal previousRequested()
  signal playPauseRequested()
  signal nextRequested()

  readonly property real s: width / 460
  implicitWidth: 460
  height: width * 400 / 460

  // ── Geometry (design units) ────────────────────────────────────────────

  readonly property point platterCenter: Qt.point(160, 155)
  readonly property real recordRadius: 118
  readonly property point pivot: Qt.point(400, 52)
  readonly property real armLength: 236

  readonly property real progress: length > 0 ? Math.max(0, Math.min(1, position / length)) : 0

  // Angle (degrees, clockwise from straight down) that puts the stylus at
  // distance `r` from the spindle. The distance shrinks monotonically as the
  // arm swings in, so a bisection is enough.
  function armAngleFor(r) {
    var dx = platterCenter.x - pivot.x, dy = platterCenter.y - pivot.y
    var maxA = Math.atan2(-dx, dy)
    var lo = 0, hi = maxA
    for (var i = 0; i < 30; i++) {
      var mid = (lo + hi) / 2
      var nx = pivot.x - armLength * Math.sin(mid), ny = pivot.y + armLength * Math.cos(mid)
      var d = Math.hypot(nx - platterCenter.x, ny - platterCenter.y)
      if (d > r) lo = mid
      else hi = mid
    }
    return (lo + hi) / 2 * 180 / Math.PI
  }

  readonly property real outerGroove: recordRadius * 0.95
  readonly property real runOut: recordRadius * 0.41
  // While swapping records the arm goes home; paused, it hovers in place.
  property bool parked: false
  readonly property bool lifted: parked || !hasTrack || !playing || dragging

  // Dragging the arm: while held it follows the hand; after letting go it
  // stays where it was dropped until Spotify reports the new position.
  property bool dragging: false
  property real dragAngle: 0
  property real heldProgress: -1
  readonly property real shownProgress: dragging ? progressForAngle(dragAngle)
    : (heldProgress >= 0 ? heldProgress : progress)
  readonly property real shownPosition: (dragging || heldProgress >= 0) ? shownProgress * length : position

  Timer {
    id: holdTimer
    interval: 1200
    onTriggered: tt.heldProgress = -1
  }

  function needleAt(deg) {
    var a = deg * Math.PI / 180
    return Qt.point(pivot.x - armLength * Math.sin(a), pivot.y + armLength * Math.cos(a))
  }

  function progressForAngle(deg) {
    var n = needleAt(deg)
    var r = Math.hypot(n.x - platterCenter.x, n.y - platterCenter.y)
    return Math.max(0, Math.min(1, (outerGroove - r) / (outerGroove - runOut)))
  }

  readonly property real outerAngle: armAngleFor(outerGroove)
  readonly property real innerAngle: armAngleFor(runOut)

  // Volume readout that briefly replaces the artist line.
  property bool showVolume: false
  Timer {
    id: volumeFlash
    interval: 1400
    onTriggered: tt.showVolume = false
  }
  function flashVolume() { showVolume = true; volumeFlash.restart() }
  property string shownArt: artUrl
  property string shownKey: ""

  readonly property real armAngle: dragging ? dragAngle
    : (hasTrack && !parked ? armAngleFor(outerGroove + (runOut - outerGroove) * shownProgress) : 0)

  function clock(sec) {
    if (!(sec >= 0) || !isFinite(sec)) return "0:00"
    var t = Math.floor(sec)
    var m = Math.floor(t / 60), ss = t % 60
    return m + ":" + (ss < 10 ? "0" : "") + ss
  }

  // ── Changing records ───────────────────────────────────────────────────

  onTrackKeyChanged: {
    // The blank gap between songs is not a song; wait for the next one.
    if (trackKey === "") return
    var first = shownKey === ""
    shownKey = trackKey
    if (first || !live || Style.reduceMotion) {
      swap.stop()
      parked = false
      record.opacity = 1
      record.scale = 1
      shownArt = artUrl
      return
    }
    swap.restart()
  }
  // Art can arrive a moment after the title; take it unless mid-swap.
  onArtUrlChanged: if (!swap.running) shownArt = artUrl
  onLiveChanged: if (!live && swap.running) {
    swap.stop()
    parked = false
    record.opacity = 1
    record.scale = 1
    shownArt = artUrl
  }

  SequentialAnimation {
    id: swap
    // Arm swings home.
    ScriptAction { script: tt.parked = true }
    PauseAnimation { duration: Style.duration(260) }
    // Old record lifts off towards you and fades.
    ParallelAnimation {
      NumberAnimation { target: record; property: "scale"; to: 1.07; duration: Style.duration(160); easing.type: Easing.OutCubic }
      NumberAnimation { target: record; property: "opacity"; to: 0; duration: Style.duration(160); easing.type: Easing.OutCubic }
    }
    ScriptAction { script: tt.shownArt = tt.artUrl }
    // New one settles onto the platter.
    ParallelAnimation {
      NumberAnimation { target: record; property: "scale"; from: 1.07; to: 1; duration: Style.duration(220); easing.type: Easing.Bezier; easing.bezierCurve: Style.easeOut }
      NumberAnimation { target: record; property: "opacity"; from: 0; to: 1; duration: Style.duration(220); easing.type: Easing.OutCubic }
    }
    // Cue the stylus at the lead-in.
    ScriptAction { script: tt.parked = false }
  }

  // ── Plinth ─────────────────────────────────────────────────────────────

  Wood {
    anchors.fill: parent
    radius: 14 * tt.s
    unit: tt.s
  }

  Text {
    textFormat: Text.PlainText
    x: 22 * tt.s
    y: 16 * tt.s
    text: "VITROLA"
    color: Qt.rgba(1, 0.9, 0.78, 0.45)
    font.family: tt.fontFamily
    font.pixelSize: 10 * tt.s
    font.bold: true
    font.letterSpacing: 3 * tt.s
  }

  Text {
    textFormat: Text.PlainText
    x: 22 * tt.s
    y: 30 * tt.s
    text: "STEREO · 33⅓"
    color: Qt.rgba(1, 0.9, 0.78, 0.25)
    font.family: tt.fontFamily
    font.pixelSize: 7 * tt.s
    font.letterSpacing: 1.5 * tt.s
  }

  // ── Platter + record ───────────────────────────────────────────────────

  Item {
    id: platter
    readonly property real r: 127
    x: (tt.platterCenter.x - r) * tt.s
    y: (tt.platterCenter.y - r) * tt.s
    width: r * 2 * tt.s
    height: width

    // Shadow the platter casts on the wood.
    Rectangle {
      x: 3 * tt.s
      y: 6 * tt.s
      width: parent.width
      height: parent.height
      radius: width / 2
      color: "#000000"
      opacity: 0.35
    }

    Brushed {
      anchors.fill: parent
      round: true
      unit: tt.s
      seed: 5
    }

    // Strobe dots on the rim, turning with the record.
    Item {
      anchors.fill: parent
      rotation: record.angle
      Repeater {
        model: 72
        Rectangle {
          required property int index
          readonly property real a: index / 72 * Math.PI * 2
          readonly property real rr: (platter.r - 4) * tt.s
          width: 2.2 * tt.s
          height: width
          radius: width / 2
          color: "#3a3d42"
          x: platter.width / 2 + Math.cos(a) * rr - width / 2
          y: platter.height / 2 + Math.sin(a) * rr - height / 2
        }
      }
    }

    // Rubber mat, seen while a record is being changed.
    Rectangle {
      anchors.centerIn: parent
      width: (tt.recordRadius + 2) * 2 * tt.s
      height: width
      radius: width / 2
      color: "#242427"
      Repeater {
        model: 6
        Rectangle {
          required property int index
          anchors.centerIn: parent
          width: parent.width * (0.92 - index * 0.12)
          height: width
          radius: width / 2
          color: "transparent"
          border.width: Math.max(1, 1.2 * tt.s)
          border.color: "#1a1a1c"
        }
      }
    }

    Record {
      id: record
      anchors.centerIn: parent
      size: tt.recordRadius * 2 * tt.s
      spinning: tt.spinning
      live: tt.live
      artUrl: tt.shownArt
      accent: tt.accent
      labelInk: tt.background
    }
  }

  // ── Tonearm ────────────────────────────────────────────────────────────

  // Base plate and rest post sit under the arm.
  Brushed {
    x: (tt.pivot.x - 27) * tt.s
    y: (tt.pivot.y - 27) * tt.s
    width: 54 * tt.s
    height: width
    round: true
    unit: tt.s
    seed: 9
    shade: 0.92
  }

  Rectangle {
    x: (tt.pivot.x - 8) * tt.s
    y: (tt.pivot.y + tt.armLength * 0.74) * tt.s
    width: 16 * tt.s
    height: 11 * tt.s
    radius: 3 * tt.s
    color: "#1b1b1d"
    border.width: Math.max(1, tt.s)
    border.color: "#3b3b3f"
  }

  // The shadow lives on a full-size wrapper: a layer on the zero-size
  // rotating arm would have nothing to render into.
  Item {
    anchors.fill: parent
    layer.enabled: true
    layer.effect: MultiEffect {
      shadowEnabled: true
      shadowColor: "#000000"
      shadowOpacity: tt.lifted ? 0.4 : 0.55
      shadowBlur: tt.lifted ? 0.6 : 0.35
      shadowHorizontalOffset: (tt.lifted ? 10 : 4) * tt.s
      shadowVerticalOffset: (tt.lifted ? 14 : 6) * tt.s
      Behavior on shadowOpacity { NumberAnimation { duration: Style.duration(200); easing.type: Easing.OutCubic } }
      Behavior on shadowBlur { NumberAnimation { duration: Style.duration(200); easing.type: Easing.OutCubic } }
      Behavior on shadowHorizontalOffset { NumberAnimation { duration: Style.duration(200); easing.type: Easing.OutCubic } }
      Behavior on shadowVerticalOffset { NumberAnimation { duration: Style.duration(200); easing.type: Easing.OutCubic } }
    }

  Item {
    id: arm
    x: tt.pivot.x * tt.s
    y: tt.pivot.y * tt.s
    width: 0
    height: 0
    rotation: tt.armAngle
    // Raised arm reads a touch bigger: it is closer to you.
    scale: tt.lifted ? 1.035 : 1

    Behavior on scale {
      NumberAnimation { duration: Style.duration(200); easing.type: Easing.OutCubic }
    }
    Behavior on rotation {
      enabled: !tt.dragging
      NumberAnimation { duration: Style.duration(280); easing.type: Easing.OutCubic }
    }

    // Counterweight.
    Rectangle {
      x: -12 * tt.s
      y: -50 * tt.s
      width: 24 * tt.s
      height: 26 * tt.s
      radius: 4 * tt.s
      gradient: Gradient {
        orientation: Gradient.Horizontal
        GradientStop { position: 0; color: "#2a2b2e" }
        GradientStop { position: 0.45; color: "#6c6f75" }
        GradientStop { position: 1; color: "#1f2023" }
      }
    }

    // Arm tube.
    Rectangle {
      x: -2.5 * tt.s
      y: -26 * tt.s
      width: 5 * tt.s
      height: (tt.armLength - 4) * tt.s
      radius: width / 2
      gradient: Gradient {
        orientation: Gradient.Horizontal
        GradientStop { position: 0; color: "#7d8187" }
        GradientStop { position: 0.4; color: "#f1f2f4" }
        GradientStop { position: 1; color: "#8a8e94" }
      }
    }

    // Headshell, angled in like the real thing, with an accent finger lift.
    Item {
      x: 0
      y: (tt.armLength - 30) * tt.s
      rotation: 24

      Rectangle {
        x: -7 * tt.s
        y: 0
        width: 14 * tt.s
        height: 32 * tt.s
        radius: 3 * tt.s
        gradient: Gradient {
          orientation: Gradient.Horizontal
          GradientStop { position: 0; color: "#2c2d30" }
          GradientStop { position: 0.5; color: "#55585e" }
          GradientStop { position: 1; color: "#232427" }
        }
      }
      Rectangle {
        x: 6 * tt.s
        y: 4 * tt.s
        width: 10 * tt.s
        height: 3 * tt.s
        radius: height / 2
        color: tt.accent
      }
      // Cartridge.
      Rectangle {
        x: -5 * tt.s
        y: 18 * tt.s
        width: 10 * tt.s
        height: 12 * tt.s
        radius: 1.5 * tt.s
        color: tt.accent
        border.width: Math.max(1, 0.8 * tt.s)
        border.color: Qt.darker(tt.accent, 1.6)
      }
    }
  }
  }

  // Grab the arm anywhere along its length and drop it where you want to
  // listen from. Presses that miss the arm fall through.
  MouseArea {
    id: armMouse
    x: 0
    y: 0
    width: parent.width
    height: 284 * tt.s
    hoverEnabled: true
    property bool overArm: false
    cursorShape: tt.dragging ? Qt.ClosedHandCursor
      : (overArm && tt.hasTrack && tt.canSeek ? Qt.OpenHandCursor : Qt.ArrowCursor)

    function design(m) { return Qt.point(m.x / tt.s, m.y / tt.s) }

    function nearArm(p) {
      var e = tt.needleAt(arm.rotation)
      var vx = e.x - tt.pivot.x, vy = e.y - tt.pivot.y
      var t = Math.max(0, Math.min(1, ((p.x - tt.pivot.x) * vx + (p.y - tt.pivot.y) * vy) / (vx * vx + vy * vy)))
      var d = Math.hypot(p.x - (tt.pivot.x + t * vx), p.y - (tt.pivot.y + t * vy))
      return d < 12 && t > 0.15
    }

    function angleAt(p) {
      var a = Math.atan2(-(p.x - tt.pivot.x), p.y - tt.pivot.y) * 180 / Math.PI
      return Math.max(tt.outerAngle, Math.min(tt.innerAngle, a))
    }

    onPressed: function(mouse) {
      var p = design(mouse)
      if (!tt.hasTrack || !tt.canSeek || tt.parked || !nearArm(p)) { mouse.accepted = false; return }
      holdTimer.stop()
      tt.dragAngle = angleAt(p)
      tt.dragging = true
    }
    onPositionChanged: function(mouse) {
      var p = design(mouse)
      if (tt.dragging) tt.dragAngle = angleAt(p)
      else overArm = nearArm(p)
    }
    onReleased: {
      if (!tt.dragging) return
      var target = tt.progressForAngle(tt.dragAngle)
      tt.heldProgress = target
      tt.dragging = false
      holdTimer.restart()
      tt.seekRequested(target * tt.length)
    }
    onCanceled: tt.dragging = false
    onExited: overArm = false
  }

  // Pivot cap over the arm.
  Brushed {
    x: (tt.pivot.x - 11) * tt.s
    y: (tt.pivot.y - 11) * tt.s
    width: 22 * tt.s
    height: width
    round: true
    unit: tt.s
    seed: 13
    shade: 1.05
  }

  // Pop out into its own window / dock back into the bar.
  Item {
    x: 418 * tt.s
    y: 112 * tt.s
    width: 26 * tt.s
    height: 26 * tt.s

    Rectangle {
      anchors.fill: parent
      anchors.topMargin: 2 * tt.s
      radius: 5 * tt.s
      color: "#140a04"
      opacity: 0.6
    }
    Brushed {
      width: parent.width
      height: parent.height - 2 * tt.s
      y: detachMouse.pressed ? 2 * tt.s : 0
      radius: 5 * tt.s
      unit: tt.s
      seed: 31
      shade: detachMouse.containsMouse ? 1.06 : 0.95
    }
    Text {
      textFormat: Text.PlainText
      anchors.centerIn: parent
      anchors.verticalCenterOffset: detachMouse.pressed ? 1 * tt.s : -1 * tt.s
      text: tt.detached ? "󰅖" : "󰏌"
      color: "#2a2b2e"
      font.family: tt.fontFamily
      font.pixelSize: 12 * tt.s
    }
    MouseArea {
      id: detachMouse
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onClicked: tt.detachToggled()
    }
  }

  // ── Deck controls ──────────────────────────────────────────────────────

  Row {
    x: 22 * tt.s
    y: 288 * tt.s
    spacing: 8 * tt.s
    LayoutMirroring.enabled: false
    LayoutMirroring.childrenInherit: true

    Key {
      glyph: "󰒮"
      enabledKey: tt.canPrevious
      onClicked: tt.previousRequested()
    }
    Key {
      glyph: tt.playing ? "󰏤" : "󰐊"
      lit: tt.playing
      wide: true
      enabledKey: tt.canPlayPause
      onClicked: tt.playPauseRequested()
    }
    Key {
      glyph: "󰒭"
      enabledKey: tt.canNext
      onClicked: tt.nextRequested()
    }
  }

  // Opens and closes the record crate beside the deck.
  Key {
    x: 312 * tt.s
    y: 288 * tt.s
    glyph: "󰀥"
    lit: tt.crateOpen
    onClicked: tt.crateToggled()
  }

  // Power light.
  Rectangle {
    id: led
    x: 214 * tt.s
    y: 297 * tt.s
    width: 9 * tt.s
    height: width
    radius: width / 2
    color: tt.playing ? tt.accent : Qt.darker(tt.accent, 2.6)
    border.width: Math.max(1, 0.8 * tt.s)
    border.color: "#1a1a1a"
    layer.enabled: tt.playing
    layer.effect: MultiEffect {
      shadowEnabled: true
      shadowColor: tt.accent
      shadowBlur: 0.8
      shadowOpacity: 0.9
      shadowHorizontalOffset: 0
      shadowVerticalOffset: 0
    }
  }

  Text {
    textFormat: Text.PlainText
    anchors.left: led.right
    anchors.leftMargin: 6 * tt.s
    anchors.verticalCenter: led.verticalCenter
    text: "33⅓   45"
    color: Qt.rgba(1, 0.9, 0.78, 0.4)
    font.family: tt.fontFamily
    font.pixelSize: 8 * tt.s
    font.letterSpacing: 1 * tt.s
  }

  // ── Front faceplate: display + volume knob ─────────────────────────────

  Brushed {
    id: faceplate
    x: 12 * tt.s
    y: 326 * tt.s
    width: 436 * tt.s
    height: 62 * tt.s
    radius: 8 * tt.s
    unit: tt.s
    seed: 21
  }

  Rectangle {
    id: display
    x: 24 * tt.s
    y: 334 * tt.s
    width: 334 * tt.s
    height: 46 * tt.s
    radius: 5 * tt.s
    color: tt.background
    border.width: Math.max(1, 1.2 * tt.s)
    border.color: Qt.rgba(0, 0, 0, 0.55)

    // Glass sheen.
    Rectangle {
      anchors.fill: parent
      anchors.margins: parent.border.width
      radius: parent.radius
      gradient: Gradient {
        GradientStop { position: 0; color: Qt.rgba(1, 1, 1, 0.06) }
        GradientStop { position: 0.5; color: Qt.rgba(1, 1, 1, 0) }
      }
    }

    Text {
      id: titleLine
      textFormat: Text.PlainText
      x: 10 * tt.s
      y: 6 * tt.s
      width: parent.width - 20 * tt.s
      text: tt.title
      color: tt.foreground
      font.family: tt.fontFamily
      font.pixelSize: 12 * tt.s
      font.bold: true
      elide: Text.ElideRight
    }

    Text {
      textFormat: Text.PlainText
      x: 10 * tt.s
      anchors.top: titleLine.bottom
      anchors.topMargin: 1 * tt.s
      width: parent.width - timeText.width - 30 * tt.s
      visible: !tt.showVolume
      text: tt.artist
      color: Qt.darker(tt.foreground, 1.4)
      font.family: tt.fontFamily
      font.pixelSize: 9.5 * tt.s
      elide: Text.ElideRight
    }

    Row {
      visible: tt.showVolume
      x: 10 * tt.s
      anchors.top: titleLine.bottom
      anchors.topMargin: 3 * tt.s
      spacing: 6 * tt.s

      Text {
        textFormat: Text.PlainText
        anchors.verticalCenter: parent.verticalCenter
        text: tt.muted ? "MUTE" : "VOL"
        color: Qt.darker(tt.foreground, 1.4)
        font.family: tt.fontFamily
        font.pixelSize: 8.5 * tt.s
        font.bold: true
      }
      Row {
        anchors.verticalCenter: parent.verticalCenter
        spacing: 2 * tt.s
        Repeater {
          model: 20
          Rectangle {
            required property int index
            width: 4 * tt.s
            height: 7 * tt.s
            radius: 1 * tt.s
            color: !tt.muted && index < Math.round(tt.volume * 20) ? tt.accent
              : Qt.rgba(tt.foreground.r, tt.foreground.g, tt.foreground.b, 0.15)
          }
        }
      }
      Text {
        textFormat: Text.PlainText
        anchors.verticalCenter: parent.verticalCenter
        text: Math.round(tt.volume * 100) + "%"
        color: tt.foreground
        font.family: tt.fontFamily
        font.pixelSize: 8.5 * tt.s
      }
    }

    Text {
      id: timeText
      textFormat: Text.PlainText
      anchors.right: parent.right
      anchors.rightMargin: 10 * tt.s
      anchors.top: titleLine.bottom
      anchors.topMargin: 1 * tt.s
      text: tt.clock(tt.shownPosition) + " / " + tt.clock(tt.length)
      color: tt.accent
      font.family: tt.fontFamily
      font.pixelSize: 9.5 * tt.s
    }

    // Progress hairline along the bottom of the glass.
    Rectangle {
      x: 10 * tt.s
      y: parent.height - 6 * tt.s
      width: parent.width - 20 * tt.s
      height: Math.max(1, 1.5 * tt.s)
      radius: height / 2
      color: Qt.rgba(tt.foreground.r, tt.foreground.g, tt.foreground.b, 0.15)
      Rectangle {
        width: parent.width * tt.shownProgress
        height: parent.height
        radius: height / 2
        color: tt.accent
      }
    }
  }

  // Volume knob (turns with the wheel in a later step).
  Item {
    id: knob
    x: (406 - 22) * tt.s
    y: (357 - 22) * tt.s
    width: 44 * tt.s
    height: width

    Rectangle {
      anchors.fill: parent
      anchors.margins: -2 * tt.s
      radius: width / 2
      color: "#000000"
      opacity: 0.35
    }
    Brushed {
      anchors.fill: parent
      round: true
      unit: tt.s
      seed: 17
      shade: 0.95
    }
    Item {
      anchors.fill: parent
      rotation: -135 + 270 * Math.max(0, Math.min(1, tt.volume))
      Behavior on rotation { NumberAnimation { duration: Style.duration(120); easing.type: Easing.OutCubic } }
      Rectangle {
        anchors.horizontalCenter: parent.horizontalCenter
        y: 4 * tt.s
        width: 3 * tt.s
        height: 11 * tt.s
        radius: width / 2
        color: tt.muted ? Qt.darker(tt.accent, 2.4) : tt.accent
      }
    }

    // Wheel turns it (5% a notch), a click mutes.
    MouseArea {
      anchors.fill: parent
      anchors.margins: -4 * tt.s
      cursorShape: Qt.PointingHandCursor
      property real wheelRest: 0
      onWheel: function(wheel) {
        wheelRest += wheel.angleDelta.y / 120
        var steps = wheelRest > 0 ? Math.floor(wheelRest) : Math.ceil(wheelRest)
        if (steps === 0) { tt.flashVolume(); return }
        wheelRest -= steps
        var v = Math.round((tt.volume + steps * 0.05) * 100) / 100
        tt.volumeRequested(Math.max(0, Math.min(1, v)))
        tt.flashVolume()
      }
      onClicked: { tt.muteToggleRequested(); tt.flashVolume() }
    }
  }

  // ── Components ─────────────────────────────────────────────────────────

  component Key: Item {
    id: key
    property string glyph: ""
    property bool lit: false
    property bool wide: false
    property bool enabledKey: true
    signal clicked()

    width: (wide ? 52 : 42) * tt.s
    height: 28 * tt.s
    opacity: enabledKey ? 1 : 0.55

    Rectangle {
      anchors.fill: parent
      anchors.topMargin: 3 * tt.s
      radius: 4 * tt.s
      color: "#140a04"
      opacity: 0.7
    }

    Item {
      id: cap
      width: parent.width
      height: parent.height - 3 * tt.s
      y: keyMouse.pressed ? 2 * tt.s : 0

      Brushed {
        anchors.fill: parent
        radius: 4 * tt.s
        unit: tt.s
        shade: keyMouse.pressed ? 0.82 : (keyMouse.containsMouse ? 1.06 : 1)
      }

      Rectangle {
        visible: key.lit
        x: 7 * tt.s
        y: 3 * tt.s
        width: parent.width - 14 * tt.s
        height: 2 * tt.s
        radius: height / 2
        color: tt.accent
      }

      Text {
        textFormat: Text.PlainText
        anchors.centerIn: parent
        anchors.verticalCenterOffset: 1 * tt.s
        text: key.glyph
        color: "#2a2b2e"
        font.family: tt.fontFamily
        font.pixelSize: 13 * tt.s
      }
    }

    MouseArea {
      id: keyMouse
      anchors.fill: parent
      hoverEnabled: true
      enabled: key.enabledKey
      cursorShape: Qt.PointingHandCursor
      onClicked: key.clicked()
    }
  }
}
