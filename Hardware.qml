import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

BarWidget {
  id: root
  moduleName: "hermes.hardware"
  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  function injectPanel() {
    if (!panelLoader.item) return
    panelLoader.item.bar = root.bar
    panelLoader.item.settings = root.settings
    panelLoader.item.anchorItem = button
    panelLoader.item.hostWidget = root
  }
  function togglePanel() { if (panelLoader.item) panelLoader.item.toggle() }

  Loader {
    id: panelLoader
    active: true
    source: Qt.resolvedUrl("Panel.qml")
    visible: false
    onLoaded: root.injectPanel()
  }
  onBarChanged: injectPanel()
  onSettingsChanged: injectPanel()

  // ── state (fed by Panel.qml's sampler) ──────────────────────
  readonly property var doc: panelLoader.item ? panelLoader.item.doc : ({})

  function pct(v) { return v === null || v === undefined ? "--" : Math.round(Number(v)) + "%" }
  function temp(v) { return v === null || v === undefined ? "--" : Math.round(Number(v)) + "°C" }

  function peakSensor() {
    if (!doc.sensors || doc.sensors.length === 0) return null
    var peak = doc.sensors[0]
    for (var i = 1; i < doc.sensors.length; i++)
      if (doc.sensors[i].celsius > peak.celsius) peak = doc.sensors[i]
    return peak
  }

  // Bar badge: "CPU  RAM  peak°C". Any series the machine cannot report is
  // skipped (never faked as 0); a machine with no counters shows only the icon.
  function badgeParts() {
    var parts = []
    if (doc.cpu && doc.cpu.meanPercent !== null && doc.cpu.meanPercent !== undefined)
      parts.push(root.pct(doc.cpu.meanPercent))
    if (doc.memory && doc.memory.percent !== null && doc.memory.percent !== undefined)
      parts.push(root.pct(doc.memory.percent))
    var p = root.peakSensor()
    if (p) parts.push(root.temp(p.celsius))
    return parts
  }

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    hasVisualContent: true
    horizontalMargin: 8
    verticalPadding: 8
    text: root.badgeParts().join("  ")
    tooltipText: {
      var parts = root.badgeParts()
      if (parts.length === 0) return "Hardware · waiting for first sample · click for details"
      var t = "CPU " + (doc.cpu ? root.pct(doc.cpu.meanPercent) : "--")
      if (doc.memory) t += " · RAM " + root.pct(doc.memory.percent)
      var p = root.peakSensor()
      if (p) t += " · " + p.label + " " + root.temp(p.celsius)
      if (doc.gpus) {
        var reporting = doc.gpus.filter(function(g) { return g.percent !== null })
        if (reporting.length > 0)
          t += " · GPU " + reporting.map(function(g) { return root.pct(g.percent) }).join(" / ")
      }
      return t + " · click for details"
    }
    onPressed: function(b) { if (b === Qt.LeftButton) root.togglePanel() }
  }
}