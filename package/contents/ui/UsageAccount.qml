import QtQuick
import QtQuick.Layouts
import org.kde.plasma.components as PlasmaComponents
import org.kde.kirigami as Kirigami

// One managed account: a header (name · email, active chip, freshness) above
// the reused UsageBars. Rendered per-account by FullView in cux mode.
ColumnLayout {
    id: acct
    property var account: ({})
    Layout.fillWidth: true
    spacing: 2

    // Display name: alias if set, else the email's local-part.
    function displayName() {
        if (account.alias) return account.alias
        var e = account.email || ""
        var at = e.indexOf("@")
        return at >= 0 ? e.substring(0, at) : e
    }

    // Per-account "updated Xm ago" from polled_at (epoch seconds).
    property int nowSec: Math.floor(Date.now() / 1000)
    Timer { interval: 30000; repeat: true; running: true
            onTriggered: acct.nowSec = Math.floor(Date.now() / 1000) }
    function updatedText(t) {
        if (!t) return ""
        var d = Math.max(0, acct.nowSec - t)
        if (d < 60) return i18n("updated just now")
        if (d < 3600) return i18n("updated %1m ago", Math.floor(d / 60))
        return i18n("updated %1h ago", Math.floor(d / 3600))
    }

    RowLayout {
        Layout.fillWidth: true
        spacing: Kirigami.Units.smallSpacing
        PlasmaComponents.Label { text: acct.displayName(); font.bold: true }
        PlasmaComponents.Label {
            // Only show the full email when a distinct alias is already shown.
            visible: !!acct.account.alias && !!acct.account.email
            text: "· " + (acct.account.email || "")
            opacity: 0.6
            elide: Text.ElideRight
            Layout.fillWidth: true
        }
        Item { Layout.fillWidth: true; visible: !(!!acct.account.alias && !!acct.account.email) }
        PlasmaComponents.Label {
            visible: acct.account.active === true
            text: i18n("active")
            color: Kirigami.Theme.highlightColor
            font: Kirigami.Theme.smallFont
        }
        PlasmaComponents.Label {
            text: acct.updatedText(acct.account.polled_at)
            visible: text !== ""
            opacity: 0.6
            font: Kirigami.Theme.smallFont
        }
    }

    UsageBars {
        Layout.fillWidth: true
        visible: acct.account.has_data !== false
        usage: acct.account
    }
    PlasmaComponents.Label {
        visible: acct.account.has_data === false
        text: i18n("no usage data yet")
        opacity: 0.6
        font: Kirigami.Theme.smallFont
    }
}
