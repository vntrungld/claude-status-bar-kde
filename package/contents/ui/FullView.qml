import QtQuick
import QtQuick.Layouts
import org.kde.plasma.components as PlasmaComponents

ColumnLayout {
    Layout.minimumWidth: 260
    Layout.minimumHeight: 120
    PlasmaComponents.Label { text: "Claude sessions: " + root.agg.active_count }
    Repeater {
        model: root.agg.sessions
        PlasmaComponents.Label {
            text: modelData.session_id.substring(0, 8) + " — " + modelData.state
        }
    }
}
