/*
 * SystemPage — what this machine is, as opposed to what it is doing.
 *
 * Everything here changes at most once per boot, which is exactly why it is
 * not on the Overview: that page has a five-second tick, and re-reading the
 * processor model two hundred times an hour is work nobody asked for. This
 * page asks once, when it opens.
 *
 * Facts, not controls. The one button copies the lot, because the reason a
 * person opens this page is almost always that somebody else asked them what
 * they are running.
 */
import QtQuick
import "../components"
import ".."

Item {
    id: page

    property var backend: null
    property var d: ({})

    readonly property var sys: page.d || ({})

    function txt(v) {
        return (v === undefined || v === null || v === "") ? "" : String(v);
    }

    Connections {
        target: page.backend
        ignoreUnknownSignals: true
        function onSectionReady(name, payload) {
            if (name !== "system")
                return;
            try {
                page.d = JSON.parse(payload);
            } catch (e) {}
        }
    }

    Component.onCompleted: if (page.backend) page.backend.ask("system")

    PageFrame {
        anchors.fill: parent
        index: "01"
        group: qsTr("Overview")
        title: qsTr("System")
        blurb: qsTr("The machine itself: what it runs on, what it runs, and when "
                    + "it was last brought up to date. Read once when this page "
                    + "opens — none of it changes while you are looking at it.")
        note: page.sys.name ? qsTr("%1 · %2").arg(page.sys.name).arg(page.txt(page.sys.build))
                            : qsTr("reading…")

        Panel {
            width: parent.width
            height: osGrid.implicitHeight + 36

            Grid {
                id: osGrid
                anchors { left: parent.left; right: parent.right; top: parent.top }
                anchors.margins: 18
                columns: Math.max(2, Math.floor(width / 220))
                columnSpacing: 18
                rowSpacing: 20

                readonly property real cell: (width - (columns - 1) * columnSpacing) / columns

                Fact {
                    width: osGrid.cell
                    label: qsTr("Distribution")
                    value: page.txt(page.sys.name)
                    sub: page.txt(page.sys.version)
                }
                Fact {
                    width: osGrid.cell
                    label: qsTr("Build")
                    value: page.txt(page.sys.build)
                }
                Fact {
                    width: osGrid.cell
                    label: qsTr("Kernel")
                    value: page.txt(page.sys.kernel)
                    sub: page.txt(page.sys.arch)
                }
                Fact {
                    width: osGrid.cell
                    label: qsTr("Session")
                    value: page.txt(page.sys.session)
                    sub: page.txt(page.sys.session_type)
                }
                Fact {
                    width: osGrid.cell
                    label: qsTr("Shell")
                    value: page.txt(page.sys.shell)
                }
                Fact {
                    width: osGrid.cell
                    label: qsTr("Packages")
                    value: page.sys.packages ? String(page.sys.packages) : ""
                    sub: qsTr("installed")
                }
            }
        }

        Panel {
            width: parent.width
            height: hwGrid.implicitHeight + 36

            Grid {
                id: hwGrid
                anchors { left: parent.left; right: parent.right; top: parent.top }
                anchors.margins: 18
                columns: Math.max(2, Math.floor(width / 260))
                columnSpacing: 18
                rowSpacing: 20

                readonly property real cell: (width - (columns - 1) * columnSpacing) / columns

                Fact {
                    width: hwGrid.cell
                    label: qsTr("Processor")
                    value: page.txt(page.sys.cpu)
                    sub: page.sys.cores ? qsTr("%1 threads").arg(page.sys.cores) : ""
                    wide: true
                }
                Fact {
                    width: hwGrid.cell
                    label: qsTr("Graphics")
                    // Every adapter, not the first: a laptop with switchable
                    // graphics has two, and which one is in use is the thing
                    // people are usually trying to find out.
                    value: (page.sys.gpus || []).length > 0
                           ? page.sys.gpus.join("\n") : ""
                    wide: true
                }
                Fact {
                    width: hwGrid.cell
                    label: qsTr("Memory")
                    value: page.sys.memory_total_mb
                           ? qsTr("%1 GB").arg((page.sys.memory_total_mb / 1024).toFixed(1))
                           : ""
                }
                Fact {
                    width: hwGrid.cell
                    label: qsTr("Machine")
                    value: page.txt(page.sys.host)
                    sub: page.txt(page.sys.vendor)
                    wide: true
                }
            }
        }

        Panel {
            width: parent.width
            height: timeGrid.implicitHeight + 36

            Grid {
                id: timeGrid
                anchors { left: parent.left; right: parent.right; top: parent.top }
                anchors.margins: 18
                columns: Math.max(2, Math.floor(width / 220))
                columnSpacing: 18
                rowSpacing: 20

                readonly property real cell: (width - (columns - 1) * columnSpacing) / columns

                Fact {
                    width: timeGrid.cell
                    label: qsTr("Up for")
                    value: page.sys.uptime ? page.txt(page.sys.uptime.text) : ""
                }
                Fact {
                    width: timeGrid.cell
                    label: qsTr("Booted")
                    value: page.txt(page.sys.boot)
                }
                Fact {
                    width: timeGrid.cell
                    label: qsTr("Last full upgrade")
                    // From pacman's own log, so it is when the system was
                    // actually upgraded rather than when the notifier last
                    // said something.
                    value: page.txt(page.sys.last_update)
                    sub: qsTr("from pacman.log")
                }
            }
        }
    }
}
