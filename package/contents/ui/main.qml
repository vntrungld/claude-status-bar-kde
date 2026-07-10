import QtQuick
import org.kde.plasma.plasmoid
import org.kde.plasma.plasma5support as Plasma5Support

PlasmoidItem {
    id: root

    // The installer always writes scripts here (XDG_DATA_HOME rarely differs;
    // the shell wrapper below expands it at runtime).
    readonly property string binDir:
        "${XDG_DATA_HOME:-$HOME/.local/share}/claude-status-bar/bin"
    readonly property string aggCmd: "python3 " + binDir + "/claude-status-aggregate.py"
    readonly property string usageCmd: "python3 " + binDir + "/usage-fetch.py"

    property var agg: ({ state: "idle", tool: null, started_at: null,
                         active_count: 0, waiting_count: 0, sessions: [] })
    property var usage: ({ status: "loading", five_hour: {}, seven_day: {} })

    // Executable engine runs the command through /bin/sh, so the ${XDG...}
    // expansion in binDir is resolved by the shell — no manual env lookup.
    Plasma5Support.DataSource {
        id: aggSrc
        engine: "executable"
        connectedSources: []
        onNewData: (source, data) => {
            disconnectSource(source)  // allow the same command to re-run next tick
            try { root.agg = JSON.parse((data["stdout"] || "").trim()) }
            catch (e) { /* keep previous value */ }
        }
        function run(cmd) { connectSource(cmd) }
    }

    Timer {
        interval: 1000; repeat: true; running: true; triggeredOnStart: true
        onTriggered: aggSrc.run(root.aggCmd)
    }

    Plasma5Support.DataSource {
        id: usageSrc
        engine: "executable"
        connectedSources: []
        onNewData: (source, data) => {
            disconnectSource(source)
            try { root.usage = JSON.parse((data["stdout"] || "").trim()) }
            catch (e) { /* keep previous */ }
        }
        function run(cmd) { connectSource(cmd) }
    }

    Timer {
        id: usageTimer
        interval: 300000; repeat: true
        running: false   // enabled in Task 7 by the config toggle
        triggeredOnStart: true
        onTriggered: usageSrc.run(root.usageCmd)
    }

    compactRepresentation: CompactView { agg: root.agg; usage: root.usage }
    fullRepresentation: FullView { agg: root.agg; usage: root.usage }
}
