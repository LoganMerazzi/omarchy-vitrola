import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

// A wooden crate of records next to the turntable. The wheel flips through
// the sleeves; clicking the front one turns it over to its back cover with
// the track list. Data comes from spotify.py (the user's own Web API app).
Item {
  id: crate

  property string helperPath: ""
  property bool live: true
  property color accent: Color.accent
  property color foreground: Color.foreground
  property color background: Color.background
  property string fontFamily: Style.font.family
  property var tr: function(key) { return key }

  readonly property real s: height / 400
  width: 300 * s

  // ── Shelf state ────────────────────────────────────────────────────────

  readonly property var sections: ["foryou", "albums", "playlists", "search"]
  property string section: "foryou"
  property var cache: ({})
  property var items: []
  property int current: 0
  property real cursor: 0
  property bool loading: false
  property string error: ""
  property string query: ""
  property string pendingSection: ""

  Behavior on cursor {
    NumberAnimation { duration: Style.duration(240); easing.type: Easing.OutCubic }
  }

  readonly property var front: items.length > 0 ? items[Math.max(0, Math.min(items.length - 1, current))] : null

  // ── Back cover state ───────────────────────────────────────────────────

  property bool flipped: false
  property var detail: null
  property var detailStack: []
  property bool detailLoading: false
  property string message: ""

  function cacheFresh(name) {
    var c = cache[name]
    return c && (Date.now() - c.at) < 10 * 60 * 1000
  }

  function setItems(list) {
    items = list
    current = 0
    cursor = 0
  }

  function load(name, force) {
    section = name
    flipped = false
    error = ""
    if (name === "search" && query.trim() === "") { setItems([]); return }
    var key = name === "search" ? "search:" + query.trim().toLowerCase() : name
    if (!force && cacheFresh(key)) { setItems(cache[key].items); return }
    if (shelfProc.running) { pendingSection = name; return }
    loading = true
    setItems([])
    shelfProc.key = key
    shelfProc.command = name === "search"
      ? ["python3", "-I", helperPath, "shelf", "search", query.trim().slice(0, 100)]
      : ["python3", "-I", helperPath, "shelf", name]
    shelfProc.running = true
  }

  function step(delta) {
    if (items.length === 0 || flipped) return
    current = Math.max(0, Math.min(items.length - 1, current + delta))
    cursor = current
  }

  function openItem(item) {
    if (!item || !item.id) return
    detailStack = []
    flipped = true
    fetchDetail(item.type, item.id)
  }

  function fetchDetail(type, id) {
    if (detailProc.running) return
    detail = null
    detailLoading = true
    message = ""
    detailProc.command = ["python3", "-I", helperPath, "tracks", type, id]
    detailProc.running = true
  }

  function openAlbumFromDetail(row) {
    if (!row || !row.id) return
    detailStack = detailStack.concat([detail])
    fetchDetail("album", row.id)
  }

  function back() {
    if (detailStack.length > 0) {
      detail = detailStack[detailStack.length - 1]
      detailStack = detailStack.slice(0, -1)
      message = ""
    } else {
      flipped = false
    }
  }

  function play(contextUri, trackUri) {
    if (playProc.running) return
    message = tr("crate.starting")
    playProc.command = ["python3", "-I", helperPath, "play", contextUri || "", trackUri || ""]
    playProc.running = true
  }

  function errorText(raw) {
    var e = String(raw || "")
    if (e === "login" || e.indexOf("401") === 0) return tr("crate.needLogin")
    if (e === "no-device") return tr("crate.noDevice")
    if (e.indexOf("429") === 0) return tr("crate.rateLimited")
    if (e.indexOf("network") === 0) return tr("crate.offline")
    return e.slice(0, 120)
  }

  function parse(raw) {
    try { return JSON.parse(String(raw || "").trim()) } catch (e) { return { ok: false, error: "bad response" } }
  }

  function clock(sec) {
    sec = Math.max(0, Math.floor(sec || 0))
    var m = Math.floor(sec / 60), r = sec % 60
    return m + ":" + (r < 10 ? "0" : "") + r
  }

  onLiveChanged: if (live && items.length === 0 && !loading && section !== "search") load(section, false)

  Process {
    id: shelfProc
    property string key: ""
    running: false
    stdout: StdioCollector { id: shelfOut; waitForEnd: true }
    onExited: {
      crate.loading = false
      var d = crate.parse(shelfOut.text)
      if (d.ok && Array.isArray(d.items)) {
        var c = Object.assign({}, crate.cache)
        c[key] = { items: d.items, at: Date.now() }
        crate.cache = c
        var want = crate.section === "search" ? "search:" + crate.query.trim().toLowerCase() : crate.section
        if (want === key) crate.setItems(d.items)
      } else {
        crate.error = crate.errorText(d.error)
      }
      if (crate.pendingSection !== "") {
        var next = crate.pendingSection
        crate.pendingSection = ""
        crate.load(next, false)
      }
    }
  }

  Process {
    id: detailProc
    running: false
    stdout: StdioCollector { id: detailOut; waitForEnd: true }
    onExited: {
      crate.detailLoading = false
      var d = crate.parse(detailOut.text)
      if (d.ok) crate.detail = d
      else crate.message = crate.errorText(d.error)
    }
  }

  Process {
    id: playProc
    running: false
    stdout: StdioCollector { id: playOut; waitForEnd: true }
    onExited: {
      var d = crate.parse(playOut.text)
      if (d.ok) {
        crate.message = ""
        crate.flipped = false
      } else {
        crate.message = crate.errorText(d.error)
      }
    }
  }

  // ── The crate ──────────────────────────────────────────────────────────

  // Back wall and floor, darker inside.
  Wood {
    x: 0
    y: 52 * crate.s
    width: parent.width
    height: 260 * crate.s
    radius: 10 * crate.s
    unit: crate.s
    seed: 41
  }
  Rectangle {
    x: 12 * crate.s
    y: 64 * crate.s
    width: parent.width - 24 * crate.s
    height: 240 * crate.s
    radius: 6 * crate.s
    gradient: Gradient {
      GradientStop { position: 0; color: "#1c120b" }
      GradientStop { position: 1; color: "#0d0805" }
    }
  }

  // Search tape across the top, only on the search tab.
  Rectangle {
    id: searchTape
    visible: crate.section === "search" && !crate.flipped
    x: 20 * crate.s
    y: 12 * crate.s
    width: parent.width - 40 * crate.s
    height: 30 * crate.s
    radius: 4 * crate.s
    color: crate.background
    border.width: Math.max(1, 1.2 * crate.s)
    border.color: Qt.rgba(crate.accent.r, crate.accent.g, crate.accent.b, searchInput.activeFocus ? 0.9 : 0.4)
    z: 50

    Text {
      textFormat: Text.PlainText
      anchors.left: parent.left
      anchors.leftMargin: 9 * crate.s
      anchors.verticalCenter: parent.verticalCenter
      text: "󰍉"
      color: crate.accent
      font.family: crate.fontFamily
      font.pixelSize: 12 * crate.s
    }

    TextInput {
      id: searchInput
      anchors.left: parent.left
      anchors.leftMargin: 28 * crate.s
      anchors.right: parent.right
      anchors.rightMargin: 9 * crate.s
      anchors.verticalCenter: parent.verticalCenter
      color: crate.foreground
      selectionColor: crate.accent
      font.family: crate.fontFamily
      font.pixelSize: 11 * crate.s
      clip: true
      maximumLength: 100
      onAccepted: { crate.query = text; crate.load("search", false) }
      Keys.onEscapePressed: function(event) { if (text !== "") { text = ""; event.accepted = true } else event.accepted = false }

      Text {
        textFormat: Text.PlainText
        visible: searchInput.text === "" && !searchInput.activeFocus
        anchors.verticalCenter: parent.verticalCenter
        text: crate.tr("crate.searchHint")
        color: Qt.darker(crate.foreground, 1.8)
        font: searchInput.font
      }
    }
  }

  // Records standing in the crate. The front sleeve is `current`; the ones
  // behind peek out above it, the ones already flipped fall forward out of
  // sight.
  Item {
    id: records
    anchors.fill: parent
    visible: !crate.flipped || backCover.angle > 0

    Repeater {
      model: crate.items

      Item {
        id: sleeve
        required property var modelData
        required property int index
        readonly property real k: index - crate.cursor
        readonly property bool shown: k > -1 && k < 7

        visible: shown
        z: 100 - k
        width: 210 * crate.s
        height: width
        x: (crate.width - width) / 2
        y: k >= 0 ? (98 - k * 14) * crate.s : (98 - k * 70) * crate.s
        scale: k >= 0 ? 1 - k * 0.035 : 1
        opacity: k >= 0 ? 1 : 1 + k
        transformOrigin: Item.Bottom

        Rectangle {
          x: 3 * crate.s
          y: -2 * crate.s
          width: parent.width
          height: parent.height
          radius: 2 * crate.s
          color: "#000000"
          opacity: 0.45
        }

        Rectangle {
          anchors.fill: parent
          radius: 2 * crate.s
          color: "#2a2a2a"
          clip: true

          SizedImage {
            anchors.fill: parent
            crop: true
            url: sleeve.shown ? (sleeve.modelData.image || "") : ""
          }

          // Placeholder sleeve when there is no art.
          Text {
            textFormat: Text.PlainText
            visible: !sleeve.modelData.image
            anchors.centerIn: parent
            text: "󰝚"
            color: crate.accent
            font.family: crate.fontFamily
            font.pixelSize: 48 * crate.s
          }

          // Records further back sit in the crate's shadow.
          Rectangle {
            anchors.fill: parent
            color: "#000000"
            opacity: Math.max(0, Math.min(0.6, sleeve.k * 0.12))
          }

          // Cardboard edge.
          Rectangle {
            anchors.fill: parent
            color: "transparent"
            radius: 2 * crate.s
            border.width: Math.max(1, crate.s)
            border.color: Qt.rgba(1, 1, 1, 0.12)
          }
        }

        MouseArea {
          anchors.fill: parent
          enabled: sleeve.shown && !crate.flipped
          cursorShape: Qt.PointingHandCursor
          onClicked: {
            if (sleeve.index === crate.current) crate.openItem(sleeve.modelData)
            else { crate.current = sleeve.index; crate.cursor = sleeve.index }
          }
        }
      }
    }

    // Status inside the empty crate.
    Text {
      textFormat: Text.PlainText
      visible: crate.items.length === 0
      anchors.horizontalCenter: parent.horizontalCenter
      y: 160 * crate.s
      width: parent.width - 60 * crate.s
      horizontalAlignment: Text.AlignHCenter
      wrapMode: Text.WordWrap
      text: crate.loading ? crate.tr("crate.loading")
        : (crate.error !== "" ? crate.error
        : (crate.section === "search" ? crate.tr("crate.searchEmpty") : crate.tr("crate.empty")))
      color: crate.error !== "" ? Color.urgent : Qt.rgba(1, 0.9, 0.78, 0.55)
      font.family: crate.fontFamily
      font.pixelSize: 11 * crate.s
    }

    WheelHandler {
      acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
      enabled: !crate.flipped
      property real rest: 0
      onWheel: function(event) {
        rest += event.angleDelta.y / 120
        var n = rest > 0 ? Math.floor(rest) : Math.ceil(rest)
        if (n === 0) return
        rest -= n
        crate.step(-n)
      }
    }
  }

  // ── Back cover ─────────────────────────────────────────────────────────

  Rectangle {
    id: backCover
    property real angle: crate.flipped ? 0 : 90
    Behavior on angle { NumberAnimation { duration: Style.duration(220); easing.type: Easing.OutCubic } }

    visible: angle < 89.5
    z: 200
    x: 12 * crate.s
    y: 8 * crate.s
    width: parent.width - 24 * crate.s
    height: 296 * crate.s
    radius: 3 * crate.s
    color: Qt.lighter(crate.background, 1.25)
    border.width: Math.max(1, crate.s)
    border.color: Qt.rgba(crate.foreground.r, crate.foreground.g, crate.foreground.b, 0.15)
    transform: Rotation {
      origin.x: backCover.width / 2
      origin.y: backCover.height / 2
      axis { x: 0; y: 1; z: 0 }
      angle: backCover.angle
    }

    // Header: small cover, title, subtitle.
    Row {
      id: header
      x: 10 * crate.s
      y: 10 * crate.s
      width: parent.width - 20 * crate.s
      spacing: 9 * crate.s

      Rectangle {
        width: 46 * crate.s
        height: width
        radius: 2 * crate.s
        color: "#222"
        clip: true
        SizedImage {
          anchors.fill: parent
          crop: true
          url: crate.detail ? (crate.detail.image || "") : ""
        }
      }

      Column {
        width: parent.width - 55 * crate.s
        anchors.verticalCenter: parent.verticalCenter
        spacing: 2 * crate.s
        Text {
          textFormat: Text.PlainText
          width: parent.width
          text: crate.detail ? crate.detail.name : (crate.detailLoading ? crate.tr("crate.loading") : "")
          color: crate.foreground
          font.family: crate.fontFamily
          font.pixelSize: 12 * crate.s
          font.bold: true
          elide: Text.ElideRight
        }
        Text {
          textFormat: Text.PlainText
          width: parent.width
          text: crate.detail ? crate.detail.subtitle : ""
          color: Qt.darker(crate.foreground, 1.5)
          font.family: crate.fontFamily
          font.pixelSize: 9.5 * crate.s
          elide: Text.ElideRight
        }
      }
    }

    // Actions.
    Row {
      id: actions
      x: 10 * crate.s
      y: 64 * crate.s
      spacing: 6 * crate.s

      SleeveButton {
        label: "󰐊  " + crate.tr("crate.playAll")
        primary: true
        enabled: !!crate.detail && !!crate.detail.uri
        onClicked: crate.play(crate.detail.uri, "")
      }
      SleeveButton {
        label: crate.detailStack.length > 0 ? "󰁍  " + crate.tr("crate.back") : "󰁍  " + crate.tr("crate.crate")
        onClicked: crate.back()
      }
    }

    Text {
      id: messageLine
      textFormat: Text.PlainText
      visible: text !== ""
      x: 10 * crate.s
      y: 92 * crate.s
      width: parent.width - 20 * crate.s
      text: crate.message !== "" ? crate.message
        : (crate.detail && crate.detail.locked ? crate.tr("crate.locked") : "")
      color: crate.message !== "" && crate.message !== crate.tr("crate.starting") ? Color.urgent : Qt.darker(crate.foreground, 1.4)
      font.family: crate.fontFamily
      font.pixelSize: 9 * crate.s
      wrapMode: Text.WordWrap
      maximumLineCount: 3
      elide: Text.ElideRight
    }

    ListView {
      id: trackList
      x: 4 * crate.s
      y: (messageLine.visible ? messageLine.y + messageLine.height + 6 * crate.s : 94 * crate.s)
      width: parent.width - 8 * crate.s
      height: parent.height - y - 6 * crate.s
      clip: true
      boundsBehavior: Flickable.StopAtBounds
      model: crate.detail ? crate.detail.tracks : []
      spacing: 0

      delegate: Rectangle {
        id: row
        required property var modelData
        required property int index
        readonly property bool isAlbum: modelData.type === "album"
        width: trackList.width
        height: (isAlbum ? 34 : 24) * crate.s
        radius: 3 * crate.s
        color: rowMouse.containsMouse ? Qt.rgba(crate.accent.r, crate.accent.g, crate.accent.b, 0.18) : "transparent"

        Text {
          id: num
          textFormat: Text.PlainText
          visible: !row.isAlbum
          x: 6 * crate.s
          width: 18 * crate.s
          anchors.verticalCenter: parent.verticalCenter
          horizontalAlignment: Text.AlignRight
          text: row.modelData.number > 0 ? row.modelData.number : ""
          color: crate.accent
          font.family: crate.fontFamily
          font.pixelSize: 9 * crate.s
        }

        Rectangle {
          id: thumb
          visible: row.isAlbum
          x: 6 * crate.s
          anchors.verticalCenter: parent.verticalCenter
          width: 26 * crate.s
          height: width
          color: "#222"
          clip: true
          SizedImage {
            anchors.fill: parent
            crop: true
            url: row.isAlbum ? (row.modelData.image || "") : ""
          }
        }

        Column {
          x: (row.isAlbum ? 40 : 30) * crate.s
          width: parent.width - x - dur.width - 14 * crate.s
          anchors.verticalCenter: parent.verticalCenter
          Text {
            textFormat: Text.PlainText
            width: parent.width
            text: row.modelData.name
            color: crate.foreground
            font.family: crate.fontFamily
            font.pixelSize: 10 * crate.s
            elide: Text.ElideRight
          }
          Text {
            textFormat: Text.PlainText
            visible: row.isAlbum
            width: parent.width
            text: row.modelData.artists
            color: Qt.darker(crate.foreground, 1.6)
            font.family: crate.fontFamily
            font.pixelSize: 8.5 * crate.s
            elide: Text.ElideRight
          }
        }

        Text {
          id: dur
          textFormat: Text.PlainText
          anchors.right: parent.right
          anchors.rightMargin: 8 * crate.s
          anchors.verticalCenter: parent.verticalCenter
          text: row.isAlbum ? "󰅂" : crate.clock(row.modelData.duration)
          color: Qt.darker(crate.foreground, 1.6)
          font.family: crate.fontFamily
          font.pixelSize: 9 * crate.s
        }

        MouseArea {
          id: rowMouse
          anchors.fill: parent
          hoverEnabled: true
          cursorShape: Qt.PointingHandCursor
          onClicked: {
            if (row.isAlbum) crate.openAlbumFromDetail(row.modelData)
            else crate.play(crate.detail.uri, row.modelData.uri)
          }
        }
      }
    }
  }

  // ── Front board: label and dividers ────────────────────────────────────

  Wood {
    id: board
    z: 150
    x: 0
    y: 290 * crate.s
    width: parent.width
    height: 110 * crate.s
    radius: 10 * crate.s
    unit: crate.s
    seed: 23
  }

  // Sleeve sticker: what is in front, and where you are in the crate.
  Rectangle {
    z: 151
    x: 14 * crate.s
    y: 300 * crate.s
    width: parent.width - 28 * crate.s
    height: 44 * crate.s
    radius: 4 * crate.s
    color: crate.background
    border.width: Math.max(1, 1.2 * crate.s)
    border.color: Qt.rgba(0, 0, 0, 0.55)

    Text {
      id: frontName
      textFormat: Text.PlainText
      x: 9 * crate.s
      y: 6 * crate.s
      width: parent.width - counter.width - 24 * crate.s
      text: crate.front ? crate.front.name : crate.tr("crate.title")
      color: crate.foreground
      font.family: crate.fontFamily
      font.pixelSize: 11 * crate.s
      font.bold: true
      elide: Text.ElideRight
    }
    Text {
      textFormat: Text.PlainText
      x: 9 * crate.s
      anchors.top: frontName.bottom
      anchors.topMargin: 1 * crate.s
      width: parent.width - 18 * crate.s
      text: {
        if (!crate.front) return ""
        var g = crate.front.group ? crate.tr("crate.group." + crate.front.group) : ""
        return [g, crate.front.subtitle].filter(function(x) { return x }).join(" · ")
      }
      color: Qt.darker(crate.foreground, 1.45)
      font.family: crate.fontFamily
      font.pixelSize: 9 * crate.s
      elide: Text.ElideRight
    }
    Text {
      id: counter
      textFormat: Text.PlainText
      anchors.right: parent.right
      anchors.rightMargin: 9 * crate.s
      y: 7 * crate.s
      visible: crate.items.length > 0
      text: (crate.current + 1) + "/" + crate.items.length
      color: crate.accent
      font.family: crate.fontFamily
      font.pixelSize: 9 * crate.s
    }
  }

  // Divider tabs.
  Row {
    z: 151
    x: 14 * crate.s
    y: 352 * crate.s
    spacing: 5 * crate.s

    Repeater {
      model: crate.sections
      Item {
        id: tab
        required property string modelData
        readonly property bool active: crate.section === modelData
        width: (modelData === "search" ? 34 : 70) * crate.s
        height: 32 * crate.s

        Rectangle {
          anchors.fill: parent
          anchors.topMargin: 3 * crate.s
          radius: 4 * crate.s
          color: "#140a04"
          opacity: 0.65
        }
        Item {
          width: parent.width
          height: parent.height - 3 * crate.s
          y: tabMouse.pressed || tab.active ? 2 * crate.s : 0
          Brushed {
            anchors.fill: parent
            radius: 4 * crate.s
            unit: crate.s
            seed: 51
            shade: tab.active ? 0.9 : (tabMouse.containsMouse ? 1.06 : 1)
          }
          Rectangle {
            visible: tab.active
            x: 7 * crate.s
            y: 3 * crate.s
            width: parent.width - 14 * crate.s
            height: 2 * crate.s
            radius: height / 2
            color: crate.accent
          }
          Text {
            textFormat: Text.PlainText
            anchors.centerIn: parent
            anchors.verticalCenterOffset: 1 * crate.s
            text: tab.modelData === "search" ? "󰍉" : crate.tr("crate.section." + tab.modelData)
            color: "#2a2b2e"
            font.family: crate.fontFamily
            font.pixelSize: (tab.modelData === "search" ? 12 : 9) * crate.s
            font.bold: tab.active
          }
        }
        MouseArea {
          id: tabMouse
          anchors.fill: parent
          hoverEnabled: true
          cursorShape: Qt.PointingHandCursor
          onClicked: {
            if (tab.active && tab.modelData !== "search") crate.load(tab.modelData, true)
            else crate.load(tab.modelData, false)
            if (tab.modelData === "search") searchInput.forceActiveFocus()
          }
        }
      }
    }
  }

  // ── Components ─────────────────────────────────────────────────────────

  component SleeveButton: Rectangle {
    id: btn
    property string label: ""
    property bool primary: false
    signal clicked()

    width: btnText.implicitWidth + 18 * crate.s
    height: 22 * crate.s
    radius: 4 * crate.s
    opacity: enabled ? 1 : 0.45
    color: primary ? (btnMouse.containsMouse ? Qt.lighter(crate.accent, 1.1) : crate.accent)
      : (btnMouse.containsMouse ? Qt.rgba(crate.foreground.r, crate.foreground.g, crate.foreground.b, 0.15) : "transparent")
    border.width: primary ? 0 : Math.max(1, crate.s)
    border.color: Qt.rgba(crate.foreground.r, crate.foreground.g, crate.foreground.b, 0.3)

    Text {
      id: btnText
      textFormat: Text.PlainText
      anchors.centerIn: parent
      text: btn.label
      color: btn.primary ? crate.background : crate.foreground
      font.family: crate.fontFamily
      font.pixelSize: 9.5 * crate.s
      font.bold: btn.primary
    }
    MouseArea {
      id: btnMouse
      anchors.fill: parent
      hoverEnabled: true
      enabled: btn.enabled
      cursorShape: Qt.PointingHandCursor
      onClicked: btn.clicked()
    }
  }
}
