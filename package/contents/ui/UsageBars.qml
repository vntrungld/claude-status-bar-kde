import QtQuick
import QtQuick.Layouts
import org.kde.plasma.components as PlasmaComponents

ColumnLayout {
    Layout.fillWidth: true
    spacing: 4

    property var usage: ({ status: "loading", five_hour: {}, seven_day: {} })
    function pct(w) { return (w && w.utilization !== undefined) ? Math.round(w.utilization) : null }

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
        RowLayout {
            Layout.fillWidth: true
            visible: pct(modelData.w) !== null
            PlasmaComponents.Label { text: modelData.label; Layout.preferredWidth: 70 }
            PlasmaComponents.ProgressBar {
                Layout.fillWidth: true
                from: 0; to: 100; value: pct(modelData.w) || 0
            }
            PlasmaComponents.Label { text: (pct(modelData.w) || 0) + "%" }
        }
    }
}
