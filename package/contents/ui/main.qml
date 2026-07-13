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
    readonly property string usageCmd: "python3 " + binDir + "/cux-usage-fetch.py"

    property var agg: ({ state: "idle", tool: null, started_at: null,
                         active_count: 0, waiting_count: 0, sessions: [] })
    property var usage: ({ status: "loading", five_hour: {}, seven_day: {} })

    // True while a usage fetch is in flight (drives the popup refresh button's
    // busy state). Counts fast-retry attempts so boot retries stay bounded.
    property bool usageFetching: false
    property int usageRetryCount: 0

    // User- or schedule-initiated fetch: fresh retry budget.
    function refreshUsage() {
        root.usageRetryCount = 0
        root.usageFetching = true
        usageSrc.run(root.usageCmd)
    }

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
            root.usageFetching = false
            try { root.usage = JSON.parse((data["stdout"] || "").trim()) }
            catch (e) { /* keep previous */ }
        }
        function run(cmd) { connectSource(cmd) }
    }

    // Usage is always fetched (the popup shows it regardless of the panel
    // setting); showUsageOnPanel only controls the compact-view readout.
    // triggeredOnStart makes login/boot fetch immediately.
    Timer {
        id: usageTimer
        interval: 300000; repeat: true; running: true
        triggeredOnStart: true
        onTriggered: root.refreshUsage()
    }

    // Boot resilience: if the first fetch fails (e.g. no network yet right after
    // login), retry quickly until usage lands, then this timer idles. Bounded so
    // a persistent failure doesn't spin — the 5-minute timer takes over after.
    // Skips reauth/rate_limited, where a fast retry can't help or must back off.
    Timer {
        id: usageRetryTimer
        interval: 10000; repeat: true
        running: (root.usage.status === "loading" || root.usage.status === "error")
                 && root.usageRetryCount < 18
        onTriggered: {
            root.usageRetryCount += 1
            root.usageFetching = true
            usageSrc.run(root.usageCmd)
        }
    }

    compactRepresentation: CompactView {
        agg: root.agg
        usage: root.usage
        onClicked: root.expanded = !root.expanded   // toggle popup (PlasmoidItem.expanded)
    }
    fullRepresentation: FullView {
        agg: root.agg
        usage: root.usage
        usageFetching: root.usageFetching
        onRefreshRequested: root.refreshUsage()
    }
}
