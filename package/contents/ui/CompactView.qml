import QtQuick
import QtQuick.Layouts
import org.kde.plasma.components as PlasmaComponents
import org.kde.plasma.plasmoid

MouseArea {
    id: compact
    Layout.minimumWidth: row.implicitWidth
    onClicked: plasmoid.expanded = !plasmoid.expanded

    readonly property var agg: root.agg

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
    }
}
