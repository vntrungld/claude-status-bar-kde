import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kirigami as Kirigami

ColumnLayout {
    id: cfgRoot
    property alias cfg_showUsageOnPanel: usageCheck.checked
    property bool cfg_showUsageOnPanelDefault: true

    // Breathing room so the controls don't sit against the top edge.
    Item { Layout.preferredHeight: Kirigami.Units.gridUnit }

    Kirigami.FormLayout {
        Layout.fillWidth: true

        QQC2.CheckBox {
            id: usageCheck
            Kirigami.FormData.label: i18n("Usage:")
            text: i18n("Show 5-hour and weekly usage % on the panel")
        }
    }

    Item { Layout.fillHeight: true }
}
