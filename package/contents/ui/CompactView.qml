import QtQuick
import QtQuick.Layouts
import org.kde.plasma.components as PlasmaComponents
import org.kde.plasma.plasmoid

MouseArea {
    id: compact
    Layout.minimumWidth: row.implicitWidth
    onClicked: plasmoid.expanded = !plasmoid.expanded

    property var agg: ({ state: "idle", tool: null, started_at: null, active_count: 0, waiting_count: 0, sessions: [] })
    property var usage: ({ status: "loading", five_hour: {}, seven_day: {} })

    function toolLabel(t) {
        switch (t) {
        case "Edit": case "Write": case "MultiEdit": return "Editing"
        case "Bash": return "Running"
        case "Read": return "Reading"
        case "Grep": case "Glob": return "Searching"
        case "WebFetch": case "WebSearch": return "Browsing"
        case "Task": return "Delegating"
        default: return t || ""
        }
    }

    property int elapsed: 0
    Timer {
        interval: 1000; repeat: true
        running: agg.started_at !== null
        triggeredOnStart: true
        onTriggered: elapsed = Math.max(0, Math.floor(Date.now()/1000) - agg.started_at)
    }
    function fmt(s) {
        var m = Math.floor(s/60); return m > 0 ? (m + "m " + (s%60) + "s") : (s + "s")
    }

    RowLayout {
        id: row
        anchors.fill: parent
        spacing: 4
        PlasmaComponents.Label {
            text: agg.state === "waiting" ? "●" : "◆"
            color: agg.state === "waiting" ? "#f5c451" : palette.text
        }
        PlasmaComponents.Label {
            visible: agg.state === "tool"
            text: toolLabel(agg.tool)
        }
        PlasmaComponents.Label {
            visible: agg.started_at !== null
            text: fmt(compact.elapsed)
        }
        Item { Layout.fillWidth: true }   // spacer pushes usage to the right
        PlasmaComponents.Label {
            id: usageLabel
            visible: plasmoid.configuration.showUsageOnPanel
            function pct(w) { return (w && w.utilization !== undefined) ? Math.round(w.utilization) : null }
            function part(prefix, w) { var v = pct(w); return prefix + (v === null ? "—" : v) + "%" }
            text: part("5h ", usage.five_hour) + " · " + part("7d ", usage.seven_day)
            opacity: usage.status === "ok" ? 1.0 : 0.5
            color: {
                var v = Math.max(pct(usage.five_hour) || 0, pct(usage.seven_day) || 0)
                return v > 90 ? "#e05252" : (v > 70 ? "#f5c451" : palette.text)
            }
        }
    }
}
