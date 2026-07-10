import QtQuick
import QtQuick.Layouts
import org.kde.plasma.components as PlasmaComponents
import org.kde.plasma.plasmoid

MouseArea {
    id: compact
    Layout.minimumWidth: row.implicitWidth
    // The click is wired from main.qml (onClicked: root.expanded = ...), where
    // the PlasmoidItem is in scope. In Plasma 6 `expanded` lives on the
    // PlasmoidItem, not on the `plasmoid` context property.

    property var agg: ({ state: "idle", tool: null, started_at: null, active_count: 0, waiting_count: 0, sessions: [] })
    property var usage: ({ status: "loading", five_hour: {}, seven_day: {} })

    function toolLabel(t) {
        switch (t) {
        case "Edit": case "Write": case "MultiEdit": return "Editing"
        case "Bash": return "Running"
        case "Read": return "Reading"
        case "Grep": case "Glob": return "Searching"
        case "WebFetch": case "WebSearch": return "Browsing"
        case "Task": return "Delegating"
        default: return t || ""
        }
    }

    // Map activity state + current tool to a Clawd animation file (assets from
    // clawd-tank, MIT-licensed — see icons/clawd/LICENSE.clawd-tank).
    function clawdAnim(state, tool) {
        if (state === "waiting") return "notification"
        if (state === "thinking") return "thinking"
        if (state === "tool") {
            switch (tool) {
            case "Edit": case "Write": case "MultiEdit": return "typing"
            case "Bash": return "building"
            case "Grep": case "Glob": return "debugger"
            case "Read": return "carrying"
            default: return "typing"
            }
        }
        return "idle"
    }

    // Playful "thinking" verbs (my own list). A fresh word is chosen each time a
    // session enters the thinking state and held for that phase, avoiding an
    // immediate repeat — Claude-Code-CLI style.
    readonly property var thinkingWords: [
        "Brewing", "Pondering", "Percolating", "Noodling", "Tinkering",
        "Simmering", "Conjuring", "Wrangling", "Untangling", "Musing",
        "Scheming", "Crunching", "Distilling", "Puzzling", "Weaving",
        "Sculpting", "Forging", "Ruminating", "Marinating", "Incubating",
        "Synthesizing", "Orchestrating", "Calibrating", "Whittling",
        "Germinating", "Concocting", "Cogitating", "Finagling"
    ]
    property string thinkingWord: thinkingWords[0]
    property string prevState: ""
    function pickThinkingWord() {
        if (thinkingWords.length < 2)
            return thinkingWords[0]
        var w = thinkingWord
        while (w === thinkingWord)
            w = thinkingWords[Math.floor(Math.random() * thinkingWords.length)]
        return w
    }
    onAggChanged: {
        var s = agg.state
        if (s === "thinking" && prevState !== "thinking")
            thinkingWord = pickThinkingWord()
        prevState = s
    }

    property int elapsed: 0
    Timer {
        interval: 1000; repeat: true
        running: agg.started_at !== null
        triggeredOnStart: true
        onTriggered: elapsed = Math.max(0, Math.floor(Date.now()/1000) - agg.started_at)
    }
    function fmt(s) {
        var m = Math.floor(s/60); return m > 0 ? (m + "m " + (s%60) + "s") : (s + "s")
    }

    // Usage readout helpers: a coloured dot per window (green <50, yellow
    // 50–80, red >=80) plus the percentage.
    property int dotSize: Math.max(6, Math.round(compact.height * 0.26))
    function usagePct(w) { return (w && w.utilization !== undefined) ? Math.round(w.utilization) : null }
    function usagePctText(w) { var v = usagePct(w); return (v === null ? "—" : v) + "%" }
    function usageDotColor(w) {
        var v = usagePct(w)
        if (v === null) return "#888888"
        if (v >= 80) return "#e05252"   // red
        if (v >= 50) return "#f5c451"   // yellow
        return "#3fb950"                // green
    }

    RowLayout {
        id: row
        anchors.fill: parent
        spacing: 4
        AnimatedImage {
            id: clawd
            Layout.alignment: Qt.AlignVCenter
            // Square, sized to panel thickness (compact.height is set by the
            // panel, so this does not feed back into the row's implicit width).
            Layout.preferredHeight: Math.max(16, compact.height)
            Layout.preferredWidth: Layout.preferredHeight
            fillMode: Image.PreserveAspectFit
            smooth: true
            cache: false
            playing: true
            // Animated Clawd (WebP) chosen by activity state / current tool.
            source: Qt.resolvedUrl("../icons/clawd/" + clawdAnim(agg.state, agg.tool) + ".webp")

            // Yellow "awaiting permission" dot on top of the notification anim.
            Rectangle {
                visible: agg.state === "waiting"
                width: Math.round(parent.height * 0.3)
                height: width
                radius: width / 2
                color: "#f5c451"
                border.color: "#40000000"
                border.width: 1
                anchors.right: parent.right
                anchors.bottom: parent.bottom
            }
        }
        // Text next to Clawd, shown only while thinking/using a tool, with a
        // per-character wiggle (each letter bobs at a staggered phase).
        Row {
            id: animText
            Layout.alignment: Qt.AlignVCenter
            visible: agg.state === "thinking" || agg.state === "tool"
            readonly property string content: agg.state === "tool" ? toolLabel(agg.tool)
                                                                    : (thinkingWord + "…")
            readonly property int n: content.length
            property real head: 0   // highlight position: high->low = right->left
            NumberAnimation on head {
                running: animText.visible && animText.n > 0
                from: animText.n + 2; to: -2
                duration: Math.max(700, animText.n * 130); loops: Animation.Infinite
            }
            Repeater {
                model: animText.n
                PlasmaComponents.Label {
                    text: { var c = animText.content.charAt(index); return c === " " ? " " : c }
                    // Dim base, brightening to full at the sweeping highlight.
                    opacity: 0.4 + 0.6 * Math.max(0, 1 - Math.abs(index - animText.head) / 2.4)
                }
            }
        }
        PlasmaComponents.Label {
            visible: agg.started_at !== null
            text: fmt(compact.elapsed)
        }
        Item { Layout.fillWidth: true }   // spacer pushes usage to the right
        RowLayout {
            id: usageBox
            visible: plasmoid.configuration.showUsageOnPanel
            opacity: usage.status === "ok" ? 1.0 : 0.5
            spacing: 3

            // 5-hour window
            Rectangle {
                Layout.alignment: Qt.AlignVCenter
                width: compact.dotSize; height: compact.dotSize; radius: width / 2
                color: usageDotColor(usage.five_hour)
            }
            PlasmaComponents.Label { text: usagePctText(usage.five_hour) }

            // Weekly (~72h) window
            Rectangle {
                Layout.alignment: Qt.AlignVCenter
                Layout.leftMargin: 4
                width: compact.dotSize; height: compact.dotSize; radius: width / 2
                color: usageDotColor(usage.seven_day)
            }
            PlasmaComponents.Label { text: usagePctText(usage.seven_day) }
        }
    }
}
