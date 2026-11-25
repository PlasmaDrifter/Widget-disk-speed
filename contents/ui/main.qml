import QtQuick
import QtQuick.Layouts
import QtQuick.Window
import org.kde.plasma.plasmoid
import org.kde.plasma.core as PlasmaCore
import org.kde.plasma.components as PlasmaComponents3
import org.kde.ksysguard.sensors as Sensors
import org.kde.kirigami as Kirigami

PlasmoidItem {
    id: root

    readonly property color trackColor: plasmoid.configuration.trackColor
    readonly property real smoothingAlpha: Math.max(0.05, Math.min(1, (plasmoid.configuration.smoothingPercent || 30) / 100))
    readonly property int updateMs: Math.max(500, (plasmoid.configuration.updateInterval || 5) * 1000)
    // Match the bar's glide time to the poll interval so it animates smoothly between samples
    readonly property int animDuration: updateMs
    readonly property real fallAlpha: 0.75

    toolTipMainText: ""
    toolTipSubText: ""

    function formatRate(mibps) {
        if (mibps >= 1024) return (mibps / 1024).toFixed(2) + " GiB/s"
        return mibps.toFixed(1) + " MiB/s"
    }

    function parentDiskFor(devName) {
        if (!devName) return ""
        return devName.replace(/p\d+$/, "").replace(/\d+$/, "")
    }

    component DriveSlot: Item {
        id: slot
        property string configuredDevice: ""
        property string label: ""
        property real maxRate: 100
        property color readColor: "#2ecc71"
        property color writeColor: "#e74c3c"

        property real readRate: 0
        property real writeRate: 0
        property bool primed: false
        property bool fallbackToParent: false

        readonly property string cleanDev: (configuredDevice || "").trim()
        readonly property string parentDisk: root.parentDiskFor(cleanDev)
        readonly property string effectiveDisk: (fallbackToParent && parentDisk.length > 0) ? parentDisk : cleanDev

        onConfiguredDeviceChanged: {
            fallbackToParent = false
            primed = false
            readRate = 0
            writeRate = 0
        }

        Sensors.Sensor {
            id: readSensor
            sensorId: slot.effectiveDisk.length > 0 ? ("disk/" + slot.effectiveDisk + "/read") : ""
            updateRateLimit: root.updateMs
            enabled: slot.effectiveDisk.length > 0
            onStatusChanged: {
                if (status === Sensors.Sensor.Error && !slot.fallbackToParent && slot.parentDisk !== slot.cleanDev && slot.parentDisk.length > 0) {
                    slot.fallbackToParent = true
                }
            }
        }

        Sensors.Sensor {
            id: writeSensor
            sensorId: slot.effectiveDisk.length > 0 ? ("disk/" + slot.effectiveDisk + "/write") : ""
            updateRateLimit: root.updateMs
            enabled: slot.effectiveDisk.length > 0
        }

        function sampleAndSmooth() {
            if (slot.effectiveDisk.length === 0) {
                readRate = 0
                writeRate = 0
                return
            }
            var instRead = Math.max(0, Number(readSensor.value || 0) / 1048576)
            var instWrite = Math.max(0, Number(writeSensor.value || 0) / 1048576)
            if (isNaN(instRead)) instRead = 0
            if (isNaN(instWrite)) instWrite = 0

            if (!primed && (readSensor.status === Sensors.Sensor.Ready || writeSensor.status === Sensors.Sensor.Ready)) {
                primed = true
                readRate = instRead
                writeRate = instWrite
                return
            }
            if (!primed) return

            var rAlpha = instRead < readRate ? root.fallAlpha : root.smoothingAlpha
            var wAlpha = instWrite < writeRate ? root.fallAlpha : root.smoothingAlpha
            var nextRead = rAlpha * instRead + (1 - rAlpha) * readRate
            var nextWrite = wAlpha * instWrite + (1 - wAlpha) * writeRate
            readRate = nextRead < 0.005 ? 0 : nextRead
            writeRate = nextWrite < 0.005 ? 0 : nextWrite
        }
    }

    property var slotList: [slot0, slot1, slot2, slot3, slot4]

    DriveSlot {
        id: slot0
        label: plasmoid.configuration.drive1Label
        configuredDevice: plasmoid.configuration.drive1Device
        maxRate: plasmoid.configuration.drive1MaxMiB
        readColor: plasmoid.configuration.drive1ReadColor
        writeColor: plasmoid.configuration.drive1WriteColor
    }
    DriveSlot {
        id: slot1
        label: plasmoid.configuration.drive2Label
        configuredDevice: plasmoid.configuration.drive2Device
        maxRate: plasmoid.configuration.drive2MaxMiB
        readColor: plasmoid.configuration.drive2ReadColor
        writeColor: plasmoid.configuration.drive2WriteColor
    }
    DriveSlot {
        id: slot2
        label: plasmoid.configuration.drive3Label
        configuredDevice: plasmoid.configuration.drive3Device
        maxRate: plasmoid.configuration.drive3MaxMiB
        readColor: plasmoid.configuration.drive3ReadColor
        writeColor: plasmoid.configuration.drive3WriteColor
    }
    DriveSlot {
        id: slot3
        label: plasmoid.configuration.drive4Label
        configuredDevice: plasmoid.configuration.drive4Device
        maxRate: plasmoid.configuration.drive4MaxMiB
        readColor: plasmoid.configuration.drive4ReadColor
        writeColor: plasmoid.configuration.drive4WriteColor
    }
    DriveSlot {
        id: slot4
        label: plasmoid.configuration.drive5Label
        configuredDevice: plasmoid.configuration.drive5Device
        maxRate: plasmoid.configuration.drive5MaxMiB
        readColor: plasmoid.configuration.drive5ReadColor
        writeColor: plasmoid.configuration.drive5WriteColor
    }

    Timer {
        interval: root.updateMs
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: {
            for (var i = 0; i < root.slotList.length; i++) {
                root.slotList[i].sampleAndSmooth()
            }
        }
    }

    // A single labeled vertical bar: name on top, stacked read+write segments
    // filling bottom-up (read on the bottom, write on top), rate text below.
    // A single labeled horizontal bar: name on left, rate text on right,
    // progress bar below with stacked read+write segments.
    component HorizontalBar: ColumnLayout {
        id: barRoot
        property string label: ""
        property real readRate: 0
        property real writeRate: 0
        property real maxRate: 100
        property color readColor: "#2ecc71"
        property color writeColor: "#e74c3c"

        readonly property real total: maxRate > 0 ? (readRate + writeRate) / maxRate : 0
        readonly property real scaleFactor: total > 1 ? 1 / total : 1

        Layout.fillWidth: true
        spacing: Kirigami.Units.smallSpacing / 2

        RowLayout {
            Layout.fillWidth: true
            PlasmaComponents3.Label {
                text: barRoot.label
                Layout.fillWidth: true
                elide: Text.ElideRight
            }
            PlasmaComponents3.Label {
                text: root.formatRate(barRoot.readRate + barRoot.writeRate)
                font.bold: true
            }
        }

        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: Kirigami.Units.gridUnit * 0.55
            radius: height / 2
            color: root.trackColor
            clip: true

            Rectangle {
                id: readSegV
                anchors.left: parent.left
                anchors.top: parent.top
                anchors.bottom: parent.bottom
                radius: parent.radius
                color: barRoot.readColor
                width: barRoot.maxRate > 0
                    ? Math.min(1, (barRoot.readRate / barRoot.maxRate) * barRoot.scaleFactor) * parent.width
                    : 0
                Behavior on width { NumberAnimation { duration: root.animDuration; easing.type: Easing.Linear } }
            }
            Rectangle {
                anchors.left: readSegV.right
                anchors.top: parent.top
                anchors.bottom: parent.bottom
                color: barRoot.writeColor
                width: barRoot.maxRate > 0
                    ? Math.min(1, (barRoot.writeRate / barRoot.maxRate) * barRoot.scaleFactor) * parent.width
                    : 0
                Behavior on width { NumberAnimation { duration: root.animDuration; easing.type: Easing.Linear } }
            }
        }
    }

    fullRepresentation: ColumnLayout {
        id: fullRepItem

        Layout.minimumWidth: Kirigami.Units.gridUnit * 12
        Layout.minimumHeight: Kirigami.Units.gridUnit * 10
        Layout.preferredWidth: plasmoid.configuration.popupWidth
        Layout.preferredHeight: plasmoid.configuration.popupHeight
        Layout.margins: Kirigami.Units.smallSpacing
        spacing: Kirigami.Units.smallSpacing * 2

        onWidthChanged: resizeSaveTimer.restart()
        onHeightChanged: resizeSaveTimer.restart()

        Timer {
            id: resizeSaveTimer
            interval: 250
            repeat: false
            onTriggered: {
                if (plasmoid.expanded && fullRepItem.Window.window && fullRepItem.Window.window.visible) {
                    if (fullRepItem.width >= fullRepItem.Layout.minimumWidth && fullRepItem.width !== plasmoid.configuration.popupWidth) {
                        plasmoid.configuration.popupWidth = fullRepItem.width;
                    }
                    if (fullRepItem.height >= fullRepItem.Layout.minimumHeight && fullRepItem.height !== plasmoid.configuration.popupHeight) {
                        plasmoid.configuration.popupHeight = fullRepItem.height;
                    }
                }
            }
        }

        Repeater {
            model: 5
            delegate: HorizontalBar {
                required property int index
                readonly property var slotObj: root.slotList[index]
                label: slotObj.label
                readRate: slotObj.readRate
                writeRate: slotObj.writeRate
                maxRate: slotObj.maxRate
                readColor: slotObj.readColor
                writeColor: slotObj.writeColor
            }
        }
    }

    // Small no-label bars for the panel, sized to fit the panel's thickness.
    compactRepresentation: Item {
        id: compact

        readonly property bool vertical: Plasmoid.formFactor === PlasmaCore.Types.Vertical
        readonly property int barThickness: plasmoid.configuration.barThickness
        readonly property int barGap: 4
        readonly property int margin: 4

        Layout.fillHeight: !compact.vertical
        Layout.fillWidth: compact.vertical
        Layout.preferredWidth: compact.vertical ? -1 : (compact.barThickness * 5 + compact.barGap * 4 + compact.margin * 2)
        Layout.preferredHeight: compact.vertical ? (compact.barThickness * 5 + compact.barGap * 4 + compact.margin * 2) : -1
        Layout.minimumWidth: Layout.preferredWidth
        Layout.minimumHeight: Layout.preferredHeight

        MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: root.expanded = !root.expanded
        }

        component CompactBar: Rectangle {
            id: barItem
            property real readRate: 0
            property real writeRate: 0
            property real maxRate: 100
            property color readColor: "#2ecc71"
            property color writeColor: "#e74c3c"
            property bool horizontalFill: false

            readonly property real total: maxRate > 0 ? (readRate + writeRate) / maxRate : 0
            readonly property real scaleFactor: total > 1 ? 1 / total : 1
            readonly property real readFrac: maxRate > 0 ? Math.min(1, (readRate / maxRate) * scaleFactor) : 0
            readonly property real writeFrac: maxRate > 0 ? Math.min(1, (writeRate / maxRate) * scaleFactor) : 0

            Layout.fillHeight: !horizontalFill
            Layout.fillWidth: horizontalFill
            Layout.preferredWidth: horizontalFill ? -1 : compact.barThickness
            Layout.preferredHeight: horizontalFill ? compact.barThickness : -1
            radius: (horizontalFill ? height : width) / 2
            color: root.trackColor
            clip: true

            Rectangle {
                id: readSeg
                anchors.left: parent.left
                anchors.bottom: parent.bottom
                anchors.top: barItem.horizontalFill ? parent.top : undefined
                anchors.right: barItem.horizontalFill ? undefined : parent.right
                radius: parent.radius
                color: barItem.readColor
                width: barItem.horizontalFill ? barItem.readFrac * parent.width : parent.width
                height: barItem.horizontalFill ? parent.height : barItem.readFrac * parent.height
                Behavior on width { enabled: barItem.horizontalFill; NumberAnimation { duration: root.animDuration; easing.type: Easing.Linear } }
                Behavior on height { enabled: !barItem.horizontalFill; NumberAnimation { duration: root.animDuration; easing.type: Easing.Linear } }
            }
            Rectangle {
                anchors.left: barItem.horizontalFill ? readSeg.right : parent.left
                anchors.bottom: barItem.horizontalFill ? parent.bottom : readSeg.top
                anchors.top: barItem.horizontalFill ? parent.top : undefined
                anchors.right: barItem.horizontalFill ? undefined : parent.right
                color: barItem.writeColor
                width: barItem.horizontalFill ? barItem.writeFrac * parent.width : parent.width
                height: barItem.horizontalFill ? parent.height : barItem.writeFrac * parent.height
                Behavior on width { enabled: barItem.horizontalFill; NumberAnimation { duration: root.animDuration; easing.type: Easing.Linear } }
                Behavior on height { enabled: !barItem.horizontalFill; NumberAnimation { duration: root.animDuration; easing.type: Easing.Linear } }
            }
        }

        RowLayout {
            anchors.fill: parent
            anchors.margins: compact.margin
            spacing: compact.barGap
            visible: !compact.vertical

            Repeater {
                model: 5
                delegate: CompactBar {
                    required property int index
                    readonly property var slotObj: root.slotList[index]
                    horizontalFill: false
                    readRate: slotObj.readRate
                    writeRate: slotObj.writeRate
                    maxRate: slotObj.maxRate
                    readColor: slotObj.readColor
                    writeColor: slotObj.writeColor
                }
            }
        }

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: compact.margin
            spacing: compact.barGap
            visible: compact.vertical

            Repeater {
                model: 5
                delegate: CompactBar {
                    required property int index
                    readonly property var slotObj: root.slotList[index]
                    horizontalFill: true
                    readRate: slotObj.readRate
                    writeRate: slotObj.writeRate
                    maxRate: slotObj.maxRate
                    readColor: slotObj.readColor
                    writeColor: slotObj.writeColor
                }
            }
        }
    }
}
