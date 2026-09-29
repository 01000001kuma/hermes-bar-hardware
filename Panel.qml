import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

Panel {
  id: panelRoot
  moduleName: "hermes.hardware"
  ipcTarget: "hermes.hardware"
  manageIpc: false

  // ── formatting helpers (used by the delegates below) ──────
  function pct(v) { return v === null || v === undefined ? "--" : Math.round(Number(v)) + "%" }
  function temp(v) { return v === null || v === undefined ? "--" : Math.round(Number(v)) + "°C" }
  property var anchorItem: null
  property var hostWidget: null
  readonly property var barIdentity: hostWidget || root
  property var doc: ({})
  // 60 s of samples for the sparklines. Keyed by series name so new cores /
  // GPUs appearing at runtime simply add buckets.
  property var history: ({})

  function open() { controller.show(); refresh() }
  function close() { controller.hide() }
  function toggle() { if (opened) close(); else open() }
  function refresh() { if (!statsProc.running) statsProc.running = true }

  function pushHistory() {
    var h = history
    function add(series, value) {
      if (value === null || value === undefined) return
      if (!h[series]) h[series] = []
      h[series].push(Number(value))
      if (h[series].length > 60) h[series].shift()
    }
    if (doc.cpu) {
      add("cpu", doc.cpu.meanPercent)
      var cores = doc.cpu.coresPercent || []
      for (var c = 0; c < cores.length; c++) add("core" + c, cores[c])
    }
    if (doc.memory && doc.memory.percent !== null) add("ram", doc.memory.percent)
    history = h
  }

  readonly property int intervalMs: Math.max(2000, Number(setting("intervalSec", 3)) * 1000)
  readonly property real diskWarn: Number(setting("diskWarnPercent", 80))
  readonly property real diskCrit: Number(setting("diskCritPercent", 90))
  readonly property real tempWarn: Number(setting("tempWarnC", 80))

  Timer { interval: panelRoot.intervalMs; running: true; repeat: true; triggeredOnStart: true; onTriggered: panelRoot.refresh() }

  Process {
    id: statsProc
    command: [Qt.resolvedUrl("bin/hardware-stats").toString().replace("file://", "")]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        try {
          panelRoot.doc = JSON.parse(String(text || "{}"))
          panelRoot.pushHistory()
        } catch (e) {
          console.warn("hardware", "bad sample:", e)
        }
      }
    }
  }

  KeyboardPanel {
    id: popup
    anchorItem: panelRoot.anchorItem
    owner: panelRoot.barIdentity
    bar: panelRoot.bar
    open: panelRoot.opened
    contentWidth: fittedContentWidth(Style.space(400))
    contentHeight: fittedContentHeight(body.implicitHeight)

    Column {
      id: body
      anchors.fill: parent
      spacing: Style.space(10)

      Text { text: "Hardware"; color: Color.foreground; font.family: Style.font.family; font.pixelSize: 16; font.bold: true }

      // ── CPU ──────────────────────────────────────────────
      Column {
        width: parent.width
        spacing: Style.space(4)
        Text {
          text: "CPU · " + (doc.cpu ? (doc.cpu.coresPercent ? doc.cpu.coresPercent.length : "?") + " cores" : "…") +
                " · mean " + (doc.cpu ? panelRoot.pct(doc.cpu.meanPercent) : "--")
          color: Color.muted; font.family: Style.font.family; font.pixelSize: 11
        }
        Flow {
          width: parent.width
          spacing: Style.space(8)
          Repeater {
            model: doc.cpu && doc.cpu.coresPercent ? doc.cpu.coresPercent.length : 0
            delegate: Column {
              required property int index
              width: 84
              spacing: 1
              Spark {
                values: panelRoot.series("core" + index)
                warnAt: panelRoot.tempWarn
              }
              Text { text: "c" + index + " " + panelRoot.pct(doc.cpu.coresPercent[index]); color: Color.muted; font.pixelSize: 9; anchors.horizontalCenter: parent.horizontalCenter }
            }
          }
        }
        Row {
          spacing: Style.space(8)
          Meter { label: "RAM"; frac: doc.memory ? doc.memory.percent / 100 : 0; text: doc.memory ? doc.memory.usedGiB + " / " + doc.memory.totalGiB + " GiB" : "--" }
          Meter {
            label: "swap"
            frac: (doc.memory && doc.memory.swapPercent !== null && doc.memory.swapPercent !== undefined) ? doc.memory.swapPercent / 100 : 0
            text: doc.memory && doc.memory.swapTotalGiB > 0 ? doc.memory.swapUsedGiB + " / " + doc.memory.swapTotalGiB + " GiB" : "none"
          }
        }
      }

      // ── sensors ─────────────────────────────────────────
      Column {
        width: parent.width
        spacing: Style.space(3)
        Text { text: "Temperature sensors"; color: Color.muted; font.family: Style.font.family; font.pixelSize: 11 }
        Repeater {
          model: doc.sensors || []
          delegate: Row {
            required property var modelData
            width: parent.width
            Text { text: modelData.label; color: Color.muted; font.family: Style.font.family; font.pixelSize: 11 }
            Item { width: 8; height: 1 }
            Text {
              text: panelRoot.temp(modelData.celsius)
              color: modelData.celsius >= panelRoot.tempWarn ? Color.urgent : Color.foreground
              font.family: Style.font.family; font.pixelSize: 11; font.bold: modelData.celsius >= panelRoot.tempWarn
            }
          }
        }
        Text {
          visible: !doc.sensors || doc.sensors.length === 0
          text: "no temperature sensors found (install lm-sensors and run sensors-detect)"
          color: Color.muted; font.family: Style.font.family; font.pixelSize: 11; font.italic: true
        }
      }

      // ── GPUs ────────────────────────────────────────────
      Column {
        width: parent.width
        spacing: Style.space(3)
        Text { text: "GPUs"; color: Color.muted; font.family: Style.font.family; font.pixelSize: 11 }
        Repeater {
          model: doc.gpus || []
          delegate: Column {
            required property var modelData
            width: parent.width
            spacing: 1
            Spark { values: panelRoot.series("gpu-" + modelData.type); warnAt: panelRoot.tempWarn }
            Text {
              text: (modelData.name || modelData.type.toUpperCase()) +
                    (modelData.percent !== null ? " · " + panelRoot.pct(modelData.percent) : " · no counter") +
                    (modelData.vramUsedMiB !== null ? " · VRAM " + modelData.vramUsedMiB + " / " + modelData.vramTotalMiB + " MiB" : "") +
                    (modelData.tempC !== null ? " · " + panelRoot.temp(modelData.tempC) : "")
              color: Color.foreground; font.family: Style.font.family; font.pixelSize: 10
              elide: Text.ElideRight; width: parent.width
            }
          }
        }
        Text {
          visible: !doc.gpus || doc.gpus.length === 0
          text: "no discrete GPUs discovered"
          color: Color.muted; font.family: Style.font.family; font.pixelSize: 11; font.italic: true
        }
      }

      // ── disks ───────────────────────────────────────────
      Column {
        width: parent.width
        spacing: Style.space(3)
        Text { text: "Disks"; color: Color.muted; font.family: Style.font.family; font.pixelSize: 11 }
        Repeater {
          model: doc.disks || []
          delegate: Meter {
            required property var modelData
            label: modelData.mount
            frac: modelData.percent / 100
            text: modelData.usedGiB + " / " + modelData.totalGiB + " GiB"
            warnAt: panelRoot.diskWarn / 100
            critAt: panelRoot.diskCrit / 100
          }
        }
        Text {
          visible: !doc.disks || doc.disks.length === 0
          text: "no mounts ≥ " + panelRoot.minDiskGiB() + " GiB"
          color: Color.muted; font.family: Style.font.family; font.pixelSize: 11; font.italic: true
        }
      }

      Row {
        spacing: Style.space(12)
        Text { text: "load " + (doc.load || []).join(" · "); color: Color.muted; font.family: Style.font.family; font.pixelSize: 10 }
        Text { text: "uptime " + panelRoot.uptime(doc.uptimeSeconds); color: Color.muted; font.family: Style.font.family; font.pixelSize: 10 }
      }
    }
  }

  function series(name) { return history[name] || [] }
  function minDiskGiB() { return Number(setting("minDiskGiB", 1)) }
  function uptime(seconds) {
    var h = Math.floor(Number(seconds || 0) / 3600)
    var d = Math.floor(h / 24)
    return (d ? d + "d " : "") + (h % 24) + "h"
  }

  component Spark: Canvas {
    id: spark
    property var values: []
    property real warnAt: 90
    width: parent ? parent.width : 84
    height: 22
    antialiasing: true
    onValuesChanged: requestPaint()
    onPaint: {
      var ctx = getContext("2d")
      ctx.clearRect(0, 0, width, height)
      if (values.length < 2) return
      var n = values.length
      var max = 100
      ctx.beginPath()
      for (var i = 0; i < n; i++) {
        var x = width * i / (n - 1)
        var y = height - (height * Math.min(max, values[i]) / max)
        if (i === 0) ctx.moveTo(x, y); else ctx.lineTo(x, y)
      }
      ctx.strokeStyle = Color.foreground
      ctx.lineWidth = 1.2
      ctx.stroke()
    }
  }

  component Meter: Row {
    id: meter
    property string label: ""
    property real frac: 0
    property string text: ""
    property real warnAt: 999
    property real critAt: 999
    spacing: Style.space(6)
    Text { text: meter.label; color: Color.muted; font.family: Style.font.family; font.pixelSize: 10 }
    Rectangle {
      width: 90
      height: 7
      radius: 4
      color: Style.selectedFillFor(Color.foreground, Color.accent)
      Rectangle {
        anchors.left: parent.left
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        width: Math.max(0, Math.min(1, meter.frac)) * parent.width
        radius: 4
        color: meter.frac >= meter.critAt ? Color.urgent : meter.frac >= meter.warnAt ? "#d97706" : Color.accent
      }
    }
    Text { text: meter.text; color: Color.foreground; font.family: Style.font.family; font.pixelSize: 10 }
  }

  IpcHandler {
    target: "hermes.hardware"
    function open(): void { panelRoot.open() }
    function close(): void { panelRoot.close() }
    function toggle(): void { panelRoot.toggle() }
    function refresh(): void { panelRoot.refresh() }
  }
}