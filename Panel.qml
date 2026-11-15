import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Services.Mpris
import Quickshell.Services.Pipewire
import qs.Commons
import qs.Commons as Commons
import qs.Ui

Panel {
  id: root
  moduleName: "logan.vitrola"
  ipcTarget: "logan.vitrola"
  manageIpc: false

  Commons.Translations { id: strings; directory: Qt.resolvedUrl("i18n") }

  // ── Spotify via MPRIS ──────────────────────────────────────────────────

  readonly property var players: Mpris.players ? Mpris.players.values : []
  readonly property var player: findSpotify(players)
  readonly property bool hasTrack: !!player && !!(player.trackTitle || player.trackArtist)
  readonly property bool playing: !!player && !!player.isPlaying
  readonly property string title: player ? String(player.trackTitle || "") : ""
  readonly property string artist: player ? String(player.trackArtist || "") : ""
  readonly property string album: player ? String(player.trackAlbum || "") : ""
  readonly property string artUrl: player && player.trackArtUrl ? String(player.trackArtUrl) : ""

  function findSpotify(list) {
    for (var i = 0; i < list.length; i++) {
      var p = list[i]
      if (!p) continue
      var id = [p.identity, p.desktopEntry, p.dbusName].join(" ")
      if (/spotify/i.test(id)) return p
    }
    return null
  }

  // Volume goes through Spotify's own Pipewire streams: its MPRIS volume is
  // unreliable.
  readonly property var spotifyStreams: {
    var out = []
    var nodes = Pipewire.nodes ? Pipewire.nodes.values : []
    for (var i = 0; i < nodes.length; i++) {
      var n = nodes[i]
      if (!n || !n.isStream) continue
      var playback = n.isSink === true || String(n.type || "").indexOf("Output") !== -1
      if (playback && /spotify/i.test(String(n.name || ""))) out.push(n)
    }
    return out
  }
  PwObjectTracker { objects: root.spotifyStreams }

  readonly property var volumeNode: {
    for (var i = 0; i < spotifyStreams.length; i++)
      if (spotifyStreams[i].audio) return spotifyStreams[i]
    return null
  }
  readonly property real volume: volumeNode ? volumeNode.audio.volume
    : (player && player.volumeSupported ? player.volume : 1)
  readonly property bool muted: volumeNode ? !!volumeNode.audio.muted : false

  function setVolume(v) {
    v = Math.max(0, Math.min(1, v))
    var done = false
    for (var i = 0; i < spotifyStreams.length; i++) {
      var a = spotifyStreams[i].audio
      if (a) { a.volume = v; if (a.muted && v > 0) a.muted = false; done = true }
    }
    if (!done && player && player.volumeSupported && player.canControl) player.volume = v
  }

  function toggleMute() {
    var m = !muted
    for (var i = 0; i < spotifyStreams.length; i++)
      if (spotifyStreams[i].audio) spotifyStreams[i].audio.muted = m
  }

  function seek(seconds) {
    if (!player || !player.canSeek) return
    player.position = Math.max(0, seconds)
    player.positionChanged()
  }

  function playPause() { if (player && player.canTogglePlaying) player.togglePlaying() }
  function next() { if (player && player.canGoNext) player.next() }
  function previous() { if (player && player.canGoPrevious) player.previous() }

  // ── Look ───────────────────────────────────────────────────────────────

  readonly property color foreground: bar ? bar.foreground : Color.foreground
  readonly property color barForeground: bar ? bar.barForeground : Color.foreground
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family
  readonly property string helperPath: decodeURIComponent(Qt.resolvedUrl("spotify.py").toString().replace(/^file:\/\//, ""))
  readonly property real maxTitleWidth: Math.max(60, Number(setting("maxTitleWidth", 180)) || 180)

  // Spotify blanks its metadata for a moment between songs. Hold on for a
  // beat before deciding nothing is playing, so the bar and the open panel
  // do not blink away on every track change.
  property bool present: hasTrack
  Timer {
    id: goneTimer
    interval: 1500
    onTriggered: root.present = false
  }
  onHasTrackChanged: {
    if (hasTrack) { goneTimer.stop(); present = true }
    else goneTimer.restart()
  }
  onPresentChanged: if (!present && opened) close()

  visible: present
  implicitWidth: present ? barRow.implicitWidth + Style.space(14) : 0
  implicitHeight: bar ? bar.barSize : Style.bar.sizeHorizontal


  // ── Bar: mini record + title ───────────────────────────────────────────

  Row {
    id: barRow
    anchors.centerIn: parent
    spacing: Style.space(6)

    MiniRecord {
      id: miniRecord
      anchors.verticalCenter: parent.verticalCenter
      size: Math.round(Style.font.body * 1.25)
      spinning: root.playing && root.visible && !(root.bar && root.bar.barHidden)
      opacity: root.playing ? 1 : 0.55
      Behavior on opacity { NumberAnimation { duration: Style.duration(160); easing.type: Easing.OutCubic } }
    }

    Item {
      id: titleClip
      visible: !(root.bar && root.bar.vertical) && root.title !== ""
      anchors.verticalCenter: parent.verticalCenter
      width: Math.min(root.maxTitleWidth, titleText.implicitWidth)
      height: titleText.implicitHeight
      clip: true

      Text {
        id: titleText
        textFormat: Text.PlainText
        anchors.verticalCenter: parent.verticalCenter
        text: root.title + (root.artist ? "  ·  " + root.artist : "")
        color: root.barForeground
        opacity: root.playing ? 1 : 0.6
        font.family: root.fontFamily
        font.pixelSize: Style.font.body

        readonly property bool needsScroll: implicitWidth > titleClip.width

        // Scrolling redraws the bar every frame, so it only runs while the
        // track plays and nobody is looking at the open panel instead.
        NumberAnimation on x {
          running: titleText.needsScroll && root.playing && titleClip.visible && !root.opened
            && !(root.bar && root.bar.barHidden) && !Style.reduceMotion
          onRunningChanged: if (!running) titleText.x = 0
          loops: Animation.Infinite
          duration: Math.max(6000, titleText.implicitWidth * 25)
          from: titleClip.width
          to: -titleText.implicitWidth
          easing.type: Easing.Linear
        }
      }
    }
  }

  MouseArea {
    id: barMouse
    anchors.fill: parent
    hoverEnabled: true
    cursorShape: Qt.PointingHandCursor
    acceptedButtons: Qt.LeftButton | Qt.MiddleButton | Qt.RightButton
    onClicked: function(mouse) {
      if (mouse.button === Qt.MiddleButton) root.playPause()
      else if (root.detached) root.setDetached(false)
      else root.toggle()
    }
    onEntered: if (root.bar && !root.opened) root.bar.showTooltip(root, root.title + (root.artist ? " — " + root.artist : ""))
    onExited: if (root.bar) root.bar.hideTooltip(root)
  }

  // omarchy-shell logan.vitrola <fn> [arg] — also handy for key bindings.
  IpcHandler {
    target: root.ipcTarget
    function open(): void { root.open() }
    function close(): void { root.close() }
    function toggle(): void { root.toggle() }
    function playPause(): void { root.playPause() }
    function next(): void { root.next() }
    function previous(): void { root.previous() }
    function volumeUp(): void { root.setVolume(root.volume + 0.05); root.flashVolume() }
    function volumeDown(): void { root.setVolume(root.volume - 0.05); root.flashVolume() }
    function setVolume(percent: int): void { root.setVolume(percent / 100); root.flashVolume() }
    function detach(): void { root.setDetached(!root.detached) }
    function crate(): void { root.setCrateOpen(!root.crateOpen) }
    function seekPercent(percent: int): void {
      if (root.player && root.player.lengthSupported) root.seek(root.player.length * percent / 100)
    }
    function state(): string {
      return JSON.stringify({ title: root.title, artist: root.artist, playing: root.playing,
        position: root.player ? root.player.position : 0, length: root.player ? root.player.length : 0,
        volume: Math.round(root.volume * 100), muted: root.muted, streams: root.spotifyStreams.length })
    }
  }

  // ── Detached window ────────────────────────────────────────────────────

  property bool detached: false

  function setDetached(on) {
    if (on) close()
    detached = on
  }

  function flashVolume() {
    turntable.flashVolume()
    if (windowDeck) windowDeck.flashVolume()
  }

  property var windowDeck: null

  // ── Record crate open/closed (remembered across restarts) ──────────────

  property bool crateOpen: true

  FileView {
    id: crateState
    path: Quickshell.env("HOME") + "/.local/state/vitrola/crate"
    blockLoading: true
    printErrors: false
  }
  Component.onCompleted: crateOpen = String(crateState.text() || "").trim() !== "closed"

  function setCrateOpen(on) {
    crateOpen = on
    crateState.setText(on ? "open\n" : "closed\n")
    if (deckWindow.visible) resizeWindow()
  }

  // The detached window follows the crate: ask Hyprland for the new size.
  function resizeWindow() {
    var w = crateOpen ? 772 : 460
    resizeProc.command = ["hyprctl", "dispatch",
      "hl.dsp.window.resize({ x = " + w + ", y = 400, window = \"title:^(Vitrola)$\" })"]
    resizeProc.running = true
  }
  Process { id: resizeProc; running: false }

  FloatingWindow {
    id: deckWindow
    visible: root.detached && root.present
    title: "Vitrola"
    color: "transparent"
    implicitWidth: root.crateOpen ? 772 : 460
    implicitHeight: 400

    // Closing the window (Super+W) docks it back into the bar.
    onVisibleChanged: {
      if (!visible && root.present) root.detached = false
      else if (visible) resizeLater.restart()
    }
    Timer { id: resizeLater; interval: 150; onTriggered: root.resizeWindow() }

    // Grab the wood to move the window.
    MouseArea {
      anchors.fill: parent
      onPressed: function(mouse) {
        if (typeof deckWindow.startSystemMove === "function") deckWindow.startSystemMove()
        else mouse.accepted = false
      }
    }

    Row {
      anchors.left: parent.left
      anchors.verticalCenter: parent.verticalCenter
      Deck {
        id: floatingDeck
        width: deckWindow.height * 460 / 400
        live: deckWindow.visible
        Component.onCompleted: root.windowDeck = floatingDeck
      }
      CrateSlot {
        deck: floatingDeck
        live: deckWindow.visible
      }
    }
  }

  // ── Panel: the record player ───────────────────────────────────────────

  // MPRIS does not push position updates; poke it while someone is watching.
  Timer {
    interval: 500
    repeat: true
    running: (root.opened || deckWindow.visible) && root.playing
    triggeredOnStart: true
    onTriggered: if (root.player) root.player.positionChanged()
  }

  // No card behind the record player: it hangs under the bar on its own
  // transparent layer like an object, with just a soft shadow. The deck sits
  // still in the middle and the crate slides out from behind it to the
  // right, so nothing has to resize around them.
  PanelWindow {
    id: popup
    readonly property real deckWidth: Style.space(460)
    readonly property real unit: deckWidth / 460
    readonly property real slotFull: (12 + 300) * unit
    readonly property real pad: Style.space(28)

    screen: root.QsWindow.window ? root.QsWindow.window.screen : null
    visible: root.opened || stage.opacity > 0
    color: "transparent"
    // Covers the screen below the bar (the bar stays clickable); a click
    // anywhere that is not the deck or the crate puts the player away.
    exclusionMode: ExclusionMode.Normal
    exclusiveZone: 0
    anchors {
      top: true
      bottom: true
      left: true
      right: true
    }

    WlrLayershell.namespace: "vitrola"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: root.opened ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

    MouseArea {
      anchors.fill: parent
      enabled: root.opened
      acceptedButtons: Qt.AllButtons
      onPressed: root.close()
    }

    // Swallows clicks on the deck and the visible crate so they don't
    // reach the dismissal area behind them.
    MouseArea {
      x: stage.x + popup.slotFull
      y: stage.y
      width: popup.deckWidth + panelSlot.width
      height: turntable.height
      acceptedButtons: Qt.AllButtons
    }

    Item {
      id: stage
      x: Math.round((popup.width - width) / 2)
      y: Math.max(0, Style.gapsOut - popup.pad) + popup.pad
      width: popup.deckWidth + 2 * popup.slotFull
      height: turntable.height
      focus: true

      opacity: root.opened ? 1 : 0
      scale: root.opened ? 1 : 0.97
      transformOrigin: Item.Top
      Behavior on opacity {
        NumberAnimation { duration: Style.duration(root.opened ? 180 : 120); easing.type: Easing.OutCubic }
      }
      Behavior on scale {
        NumberAnimation { duration: Style.duration(root.opened ? 180 : 120); easing.type: Easing.Bezier; easing.bezierCurve: Style.easeOut }
      }

      Keys.onPressed: function(event) {
        if (event.key === Qt.Key_Escape) { root.close(); event.accepted = true }
        else if (event.key === Qt.Key_Space) { root.playPause(); event.accepted = true }
        else if (event.key === Qt.Key_N) { root.next(); event.accepted = true }
        else if (event.key === Qt.Key_P) { root.previous(); event.accepted = true }
      }

      // Soft shadows the deck and the crate cast on the desktop.
      SoftShadow {
        x: popup.slotFull
        width: popup.deckWidth
        height: parent.height
      }
      SoftShadow {
        x: popup.slotFull + popup.deckWidth + 12 * popup.unit
        width: Math.max(0, panelSlot.width - 12 * popup.unit)
        height: parent.height
        visible: width > 1
      }

      Row {
        x: popup.slotFull
        Deck {
          id: turntable
          width: popup.deckWidth
          live: root.opened
        }
        CrateSlot {
          id: panelSlot
          deck: turntable
          live: root.opened
        }
      }
    }
  }

  onOpenedChanged: if (opened) Qt.callLater(function() { stage.forceActiveFocus() })

  component SoftShadow: Item {
    Rectangle {
      id: shadowShape
      anchors.fill: parent
      anchors.topMargin: 10 * popup.unit
      radius: 14 * popup.unit
      color: "#000000"
      opacity: 0.55
      layer.enabled: true
      layer.effect: MultiEffect {
        blurEnabled: true
        blurMax: 48
        blur: 1.0
      }
    }
  }

  // The record player wired to Spotify; used in the bar panel and in the
  // detached window alike.
  component Deck: Turntable {
    detached: root.detached
    onDetachToggled: root.setDetached(!root.detached)
    crateOpen: root.crateOpen
    onCrateToggled: root.setCrateOpen(!root.crateOpen)
    hasTrack: root.hasTrack
    playing: root.playing
    spinning: root.playing
    trackKey: root.hasTrack ? [root.title, root.artist, root.album].join("\u0001") : ""
    title: root.title || strings.t("nothingPlaying")
    artist: root.artist
    artUrl: root.artUrl
    position: root.player && root.player.positionSupported ? root.player.position : 0
    length: root.player && root.player.lengthSupported ? root.player.length : 0
    volume: root.volume
    muted: root.muted
    canSeek: !!root.player && root.player.canSeek && root.player.lengthSupported
    canPrevious: !!root.player && root.player.canGoPrevious
    canNext: !!root.player && root.player.canGoNext
    canPlayPause: !!root.player && root.player.canTogglePlaying
    accent: Commons.Color.accent
    foreground: root.foreground
    background: Commons.Color.background
    fontFamily: root.fontFamily
    onSeekRequested: function(seconds) { root.seek(seconds) }
    onVolumeRequested: function(value) { root.setVolume(value) }
    onMuteToggleRequested: root.toggleMute()
    onPreviousRequested: root.previous()
    onPlayPauseRequested: root.playPause()
    onNextRequested: root.next()
  }

  // The crate tucks in behind the deck: the slot narrows to nothing while
  // the crate stays pinned to its right edge, so it slides out of sight.
  component CrateSlot: Item {
    id: slot
    property var deck: null
    property bool live: false
    readonly property real full: deck ? (12 + 300) * deck.s : 0
    width: root.crateOpen ? full : 0
    height: deck ? deck.height : 0
    clip: true
    Behavior on width {
      NumberAnimation {
        duration: Style.duration(root.crateOpen ? 260 : 200)
        easing.type: Easing.Bezier
        easing.bezierCurve: Style.easeOut
      }
    }
    Shelf {
      anchors.right: parent.right
      height: parent.height
      live: slot.live && root.crateOpen
      opacity: slot.width / Math.max(1, slot.full) * 0.6 + 0.4
    }
  }

  component Shelf: Crate {
    helperPath: root.helperPath
    accent: Commons.Color.accent
    foreground: root.foreground
    background: Commons.Color.background
    fontFamily: root.fontFamily
    tr: function(key) { return strings.t(key) }
  }

  // ── Components ─────────────────────────────────────────────────────────

  // A vinyl record seen from above: black disc, grooves, a theme-coloured
  // label (or the album art once it is large enough to read) and a glint
  // that makes the spin visible even on a tiny bar icon.
  component MiniRecord: Item {
    id: rec
    property real size: 16
    property bool spinning: false
    property string artUrl: ""
    readonly property bool showArt: artUrl !== "" && size >= 40

    width: size
    height: size

    Item {
      id: disc
      anchors.fill: parent

      // 33⅓ rpm: one turn every 1.8 s. Pausing freezes the angle, so the
      // record stops where it was instead of snapping back.
      NumberAnimation on rotation {
        from: 0
        to: 360
        duration: 1800
        loops: Animation.Infinite
        running: !Style.reduceMotion
        paused: !rec.spinning
      }

      Rectangle {
        anchors.fill: parent
        radius: width / 2
        color: "#141414"
        border.width: Math.max(1, rec.size / 40)
        border.color: Qt.rgba(1, 1, 1, 0.10)
      }

      Repeater {
        model: rec.size >= 40 ? 5 : 2
        Rectangle {
          required property int index
          readonly property real ring: rec.size >= 40 ? 0.88 - index * 0.08 : 0.78 - index * 0.18
          anchors.centerIn: parent
          width: rec.size * ring
          height: width
          radius: width / 2
          color: "transparent"
          border.width: 1
          border.color: Qt.rgba(1, 1, 1, 0.07)
        }
      }

      // Light catching the grooves on one side.
      Canvas {
        anchors.fill: parent
        onWidthChanged: requestPaint()
        onPaint: {
          var ctx = getContext("2d")
          ctx.reset()
          var c = width / 2
          ctx.fillStyle = Qt.rgba(1, 1, 1, 0.16)
          ctx.beginPath()
          ctx.moveTo(c, c)
          ctx.arc(c, c, c * 0.92, -Math.PI * 0.42, -Math.PI * 0.22)
          ctx.closePath()
          ctx.fill()
          ctx.beginPath()
          ctx.moveTo(c, c)
          ctx.arc(c, c, c * 0.92, Math.PI * 0.58, Math.PI * 0.78)
          ctx.closePath()
          ctx.fill()
        }
      }

      Rectangle {
        id: label
        anchors.centerIn: parent
        width: rec.size * (rec.showArt ? 0.46 : 0.40)
        height: width
        radius: width / 2
        color: Commons.Color.accent

        // Album art printed on the label, cut to a circle.
        SizedImage {
          anchors.fill: parent
          crop: true
          url: rec.showArt ? rec.artUrl : ""
          visible: rec.showArt
          layer.enabled: rec.showArt
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

        // A printed stripe on the label, so a plain colour still shows the turn.
        Rectangle {
          visible: !rec.showArt
          width: parent.width * 0.5
          height: Math.max(1, parent.height * 0.14)
          x: parent.width * 0.5
          y: (parent.height - height) / 2
          color: Commons.Color.background
          opacity: 0.55
        }
      }

      Rectangle {
        anchors.centerIn: parent
        width: Math.max(2, rec.size * 0.06)
        height: width
        radius: width / 2
        color: "#0a0a0a"
      }
    }
  }
}
