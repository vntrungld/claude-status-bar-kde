import QtQuick
import QtQuick.Layouts
import org.kde.plasma.components as PlasmaComponents
import org.kde.kirigami as Kirigami

// Root is an Item with explicit preferred size — Plasma sizes the popup from
// these hints. A bare Layout root without preferredWidth/Height collapses the
// popup to nothing.
Item {
    id: fullRoot

    Layout.minimumWidth: Kirigami.Units.gridUnit * 14
    Layout.minimumHeight: Kirigami.Units.gridUnit * 11
    Layout.preferredWidth: Kirigami.Units.gridUnit * 18
    Layout.preferredHeight: Kirigami.Units.gridUnit * 15

    // Passed in from main.qml (Task 5/6); child files can't reach the applet root
    property var agg: ({ active_count: 0, sessions: [] })
    property var usage: ({ status: "loading", five_hour: {}, seven_day: {} })

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: Kirigami.Units.smallSpacing
        spacing: Kirigami.Units.smallSpacing

        PlasmaComponents.Label {
            text: i18n("Claude Code — %1 active", fullRoot.agg.active_count)
            font.bold: true
        }

        Repeater {
            model: fullRoot.agg.sessions
            RowLayout {
                Layout.fillWidth: true
                PlasmaComponents.Label {
                    text: (modelData.cwd || "").split("/").pop() || (modelData.session_id || "").substring(0, 8)
                }
                Item { Layout.fillWidth: true }
                PlasmaComponents.Label {
                    text: modelData.state + (modelData.tool ? " · " + modelData.tool : "")
                          + (modelData.state === "idle" ? "" : "…")
                    opacity: 0.8
                }
            }
        }

        PlasmaComponents.Label {
            visible: fullRoot.agg.active_count === 0
            text: i18n("No active sessions")
            opacity: 0.6
        }

        Item { Layout.fillHeight: true }   // push the usage section to the bottom

        Kirigami.Separator { Layout.fillWidth: true }
        PlasmaComponents.Label { text: i18n("Usage limits"); font.bold: true }
        UsageBars { usage: fullRoot.usage; Layout.fillWidth: true }
    }
}
