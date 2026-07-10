import QtQuick
import QtQuick.Layouts
import org.kde.plasma.components as PlasmaComponents
import org.kde.kirigami as Kirigami

ColumnLayout {
    id: fullRoot

    Layout.minimumWidth: 300
    Layout.minimumHeight: 200
    spacing: Kirigami.Units.smallSpacing

    // Passed in from main.qml (Task 5/6); child files can't reach the applet root
    property var agg: ({ active_count: 0, sessions: [] })
    property var usage: ({ status: "loading", five_hour: {}, seven_day: {} })

    PlasmaComponents.Label {
        text: i18n("Claude Code — %1 active", agg.active_count)
        font.bold: true
    }
    Repeater {
        model: agg.sessions
        RowLayout {
            Layout.fillWidth: true
            PlasmaComponents.Label { text: (modelData.cwd || "").split("/").pop() || (modelData.session_id || "").substring(0,8) }
            Item { Layout.fillWidth: true }
            PlasmaComponents.Label {
                text: modelData.state + (modelData.tool ? " · " + modelData.tool : "")
                opacity: 0.8
            }
        }
    }
    Kirigami.Separator { Layout.fillWidth: true }
    PlasmaComponents.Label { text: i18n("Usage limits"); font.bold: true }
    UsageBars { usage: fullRoot.usage }
}
