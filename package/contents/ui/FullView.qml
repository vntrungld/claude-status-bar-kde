import QtQuick
import QtQuick.Controls as QQC2
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
    property bool usageFetching: false

    // Ask the applet root to re-fetch usage now (wired in main.qml).
    signal refreshRequested()

    // "last updated" hint; nowSec ticks so it stays roughly current.
    property int nowSec: Math.floor(Date.now() / 1000)
    Timer { interval: 30000; repeat: true; running: true; onTriggered: fullRoot.nowSec = Math.floor(Date.now() / 1000) }
    function updatedText(fetchedAt) {
        if (!fetchedAt) return ""
        var d = Math.max(0, fullRoot.nowSec - fetchedAt)
        if (d < 60) return i18n("updated just now")
        if (d < 3600) return i18n("updated %1m ago", Math.floor(d / 60))
        return i18n("updated %1h ago", Math.floor(d / 3600))
    }

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
        RowLayout {
            Layout.fillWidth: true
            spacing: Kirigami.Units.smallSpacing
            PlasmaComponents.Label { text: i18n("Usage limits"); font.bold: true }
            PlasmaComponents.Label {
                text: fullRoot.updatedText(fullRoot.usage.fetched_at)
                visible: text !== ""
                opacity: 0.6
                font: Kirigami.Theme.smallFont
            }
            Item { Layout.fillWidth: true }
            // Refresh button, swapped for a spinner while a fetch is in flight.
            Item {
                Layout.preferredWidth: Kirigami.Units.iconSizes.smallMedium
                Layout.preferredHeight: Kirigami.Units.iconSizes.smallMedium
                PlasmaComponents.ToolButton {
                    anchors.fill: parent
                    visible: !fullRoot.usageFetching
                    icon.name: "view-refresh"
                    display: QQC2.AbstractButton.IconOnly
                    text: i18n("Refresh usage now")
                    onClicked: fullRoot.refreshRequested()
                    QQC2.ToolTip.visible: hovered
                    QQC2.ToolTip.text: text
                }
                PlasmaComponents.BusyIndicator {
                    anchors.fill: parent
                    visible: fullRoot.usageFetching
                    running: visible
                }
            }
        }
        UsageBars { usage: fullRoot.usage; Layout.fillWidth: true }
    }
}
