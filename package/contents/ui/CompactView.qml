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
        Item {
            id: iconBox
            Layout.alignment: Qt.AlignVCenter
            // Square, sized to panel thickness (compact.height is set by the
            // panel, so this does not feed back into the row's implicit width).
            Layout.preferredHeight: Math.max(16, compact.height)
            Layout.preferredWidth: Layout.preferredHeight

            readonly property bool working: agg.state === "thinking" || agg.state === "tool"
            property int frame: 0

            // Cycle the two leg frames only while working -> "walking" legs.
            Timer {
                interval: 170; repeat: true; running: iconBox.working
                onTriggered: iconBox.frame = (iconBox.frame + 1) % 2
            }

            Image {
                id: crab
                anchors.fill: parent
                fillMode: Image.PreserveAspectFit
                smooth: true
                sourceSize.width: 96
                sourceSize.height: 96
                // Idle rests on frame A; working alternates A/B.
                source: Qt.resolvedUrl(
                    (iconBox.working && iconBox.frame === 1) ? "../icons/crab-b.svg"
                                                             : "../icons/crab-a.svg")
                opacity: iconBox.working ? 1.0 : 0.6
                transform: Translate { id: sway }

                // Sideways scuttle while working.
                SequentialAnimation {
                    running: iconBox.working
                    loops: Animation.Infinite
                    alwaysRunToEnd: true
                    NumberAnimation { target: sway; property: "x"; to: 2.5; duration: 330; easing.type: Easing.InOutSine }
                    NumberAnimation { target: sway; property: "x"; to: -2.5; duration: 330; easing.type: Easing.InOutSine }
                    onStopped: sway.x = 0
                }
            }

            // Yellow "awaiting permission" dot.
            Rectangle {
                visible: agg.state === "waiting"
                width: Math.round(parent.width * 0.34)
                height: width
                radius: width / 2
                color: "#f5c451"
                border.color: "#40000000"
                border.width: 1
                anchors.right: parent.right
                anchors.bottom: parent.bottom
            }
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
