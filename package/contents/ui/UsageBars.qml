import QtQuick
import QtQuick.Layouts
import org.kde.plasma.components as PlasmaComponents
import org.kde.kirigami as Kirigami

ColumnLayout {
    id: bars
    Layout.fillWidth: true
    spacing: 4

    property var usage: ({ status: "loading", five_hour: {}, seven_day: {} })
    function pct(w) { return (w && w.utilization !== undefined) ? Math.round(w.utilization) : null }

    // Ticks so the "resets in …" countdown stays roughly current without a re-fetch.
    property int nowSec: Math.floor(Date.now() / 1000)
    Timer { interval: 30000; repeat: true; running: true; onTriggered: bars.nowSec = Math.floor(Date.now() / 1000) }

    // Relative time until the window's limit resets, from its ISO `resets_at`.
    function resetText(w) {
        if (!w || !w.resets_at) return ""
        var t = Date.parse(w.resets_at)
        if (isNaN(t)) return ""
        var d = Math.floor(t / 1000) - nowSec
        if (d <= 0) return i18n("resetting…")
        var days = Math.floor(d / 86400)
        var hours = Math.floor((d % 86400) / 3600)
        var mins = Math.floor((d % 3600) / 60)
        if (days > 0) return i18n("resets in %1d %2h", days, hours)
        if (hours > 0) return i18n("resets in %1h %2m", hours, mins)
        return i18n("resets in %1m", mins)
    }

    PlasmaComponents.Label {
        visible: usage.status !== "ok"
        text: usage.status === "reauth" ? i18n("Sign in to Claude to see usage")
            : usage.status === "rate_limited" ? i18n("Usage rate-limited — showing last known")
            : usage.status === "error" ? i18n("Usage unavailable")
            : i18n("Loading usage…")
        opacity: 0.7
    }
    Repeater {
        model: [{ label: i18n("5-hour"), w: usage.five_hour },
                { label: i18n("Weekly"), w: usage.seven_day }]
        ColumnLayout {
            Layout.fillWidth: true
            spacing: 0
            visible: pct(modelData.w) !== null
            RowLayout {
                Layout.fillWidth: true
                PlasmaComponents.Label { text: modelData.label; Layout.preferredWidth: 70 }
                PlasmaComponents.ProgressBar {
                    Layout.fillWidth: true
                    from: 0; to: 100; value: pct(modelData.w) || 0
                }
                PlasmaComponents.Label { text: (pct(modelData.w) || 0) + "%" }
            }
            PlasmaComponents.Label {
                text: resetText(modelData.w)
                visible: text !== ""
                opacity: 0.6
                font: Kirigami.Theme.smallFont
            }
        }
    }
}
