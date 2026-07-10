import QtQuick
import QtQuick.Layouts
import org.kde.plasma.components as PlasmaComponents

ColumnLayout {
    Layout.minimumWidth: 260
    Layout.minimumHeight: 120
    property var agg: ({ active_count: 0, sessions: [] })
    PlasmaComponents.Label { text: "Claude sessions: " + agg.active_count }
    Repeater {
        model: agg.sessions
        PlasmaComponents.Label {
            text: modelData.session_id.substring(0, 8) + " — " + modelData.state
        }
    }
}
