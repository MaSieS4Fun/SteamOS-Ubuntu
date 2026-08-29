// Led Colors — menu: On/Off + gamepad colors
// SPDX-License-Identifier: GPL-2.0-or-later

import QtQuick
import QtQuick.Layouts
import org.kde.plasma.plasmoid
import org.kde.plasma.components as PlasmaComponents3
import org.kde.plasma.extras as PlasmaExtras
import org.kde.kirigami as Kirigami
import org.kde.plasma.plasma5support as Plasma5Support

PlasmoidItem {
    id: root

    readonly property string ctl: "/usr/libexec/masi/colorines-ctl"
    property bool ledsOn: false
    property bool ok: false
    property string hex: "#ff0000"
    property string preset: ""
    property var presets: []

    switchWidth: Kirigami.Units.gridUnit * 5
    switchHeight: Kirigami.Units.gridUnit * 5
    Plasmoid.icon: "color-management"
    toolTipMainText: i18n("Led Colors")
    toolTipSubText: ok ? (ledsOn ? (preset || hex) : i18n("Off")) : i18n("Unavailable")

    preferredRepresentation: compactRepresentation

    Component.onCompleted: refresh()

    function refresh() {
        exec.run(ctl + " get")
    }

    function turnOn() {
        exec.run(ctl + " on")
    }

    function turnOff() {
        exec.run(ctl + " off")
    }

    function applyPreset(name) {
        exec.run(ctl + " preset " + name)
    }

    function parseStdout(out) {
        try {
            const data = JSON.parse(out)
            root.ok = !!data.available
            root.ledsOn = !!data.on
            if (data.hex) root.hex = data.hex
            root.preset = data.preset_label || data.preset || ""
            if (data.presets && data.presets.length)
                root.presets = data.presets
        } catch (e) {
            root.ok = false
        }
    }

    Plasma5Support.DataSource {
        id: exec
        engine: "executable"
        onNewData: function(sourceName, data) {
            disconnectSource(sourceName)
            const exitCode = data["exit code"] ?? data.exitcode ?? 0
            const out = (data.stdout ?? data["stdout"] ?? "").trim()
            const err = (data.stderr ?? data["stderr"] ?? "").trim()
            if (exitCode !== 0) {
                root.ok = false
                console.warn("led-colors:", err || out || exitCode)
                return
            }
            if (out.length > 0)
                root.parseStdout(out)
        }
        function run(command) {
            disconnectSource(command)
            connectSource(command)
        }
    }

    compactRepresentation: MouseArea {
        id: compact
        anchors.fill: parent
        hoverEnabled: true
        activeFocusOnTab: true
        Accessible.role: Accessible.Button
        Accessible.name: i18n("Led Colors")

        property bool wasExpanded: false
        onPressed: wasExpanded = root.expanded
        onClicked: root.expanded = !wasExpanded

        Rectangle {
            anchors.centerIn: parent
            width: Math.min(parent.width, parent.height) * 0.55
            height: width
            radius: width / 2
            color: root.ledsOn ? root.hex : Kirigami.Theme.disabledTextColor
            border.color: Kirigami.Theme.textColor
            border.width: 1
            opacity: compact.containsMouse ? 0.85 : 1.0
        }
    }

    fullRepresentation: PlasmaExtras.Representation {
        id: dialog
        Layout.minimumWidth: Kirigami.Units.gridUnit * 14
        Layout.preferredWidth: Kirigami.Units.gridUnit * 16
        Layout.minimumHeight: Kirigami.Units.gridUnit * 12
        collapseMarginsHint: true
        focus: true

        contentItem: ColumnLayout {
            spacing: Kirigami.Units.smallSpacing
            width: dialog.width

            PlasmaExtras.Heading {
                level: 2
                text: i18n("Led Colors")
            }

            RowLayout {
                Layout.fillWidth: true
                PlasmaComponents3.Label {
                    text: root.ledsOn ? (root.preset || i18n("On")) : i18n("Off")
                    Layout.fillWidth: true
                }
                PlasmaComponents3.Switch {
                    checked: root.ledsOn
                    enabled: root.ok
                    text: checked ? i18n("On") : i18n("Off")
                    onToggled: {
                        if (checked)
                            root.turnOn()
                        else
                            root.turnOff()
                    }
                }
            }

            PlasmaExtras.Heading {
                level: 3
                text: i18n("Colors")
                visible: root.presets.length > 0
            }

            Flow {
                Layout.fillWidth: true
                spacing: Kirigami.Units.smallSpacing
                Repeater {
                    model: root.presets
                    delegate: PlasmaComponents3.Button {
                        implicitWidth: Kirigami.Units.gridUnit * 3.5
                        implicitHeight: Kirigami.Units.gridUnit * 3.5
                        text: modelData.label
                        checkable: true
                        checked: root.ledsOn && root.hex === modelData.hex
                        onClicked: root.applyPreset(modelData.id)

                        contentItem: ColumnLayout {
                            spacing: 2
                            Rectangle {
                                Layout.alignment: Qt.AlignHCenter
                                width: Kirigami.Units.gridUnit * 1.4
                                height: width
                                radius: width / 2
                                color: modelData.hex
                                border.color: Kirigami.Theme.textColor
                                border.width: 1
                            }
                            PlasmaComponents3.Label {
                                Layout.alignment: Qt.AlignHCenter
                                text: modelData.label
                                font.pointSize: Kirigami.Theme.smallFont.pointSize
                            }
                        }
                    }
                }
            }

            PlasmaComponents3.Label {
                visible: !root.ok
                text: i18n("LEDs unavailable")
                color: Kirigami.Theme.negativeTextColor
                wrapMode: Text.WordWrap
                Layout.fillWidth: true
            }
        }

        Connections {
            target: root
            function onExpandedChanged(expanded) {
                if (expanded)
                    root.refresh()
            }
        }
    }
}
