import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kirigami as Kirigami

Kirigami.FormLayout {
    property alias cfg_showUsageOnPanel: usageCheck.checked

    QQC2.CheckBox {
        id: usageCheck
        Kirigami.FormData.label: i18n("Usage:")
        text: i18n("Show 5-hour and weekly usage % on the panel")
    }
}
