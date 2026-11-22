/*
 * Copyright (C) 2019 by Piotr Markiewicz p.marki@wp.pl
 *
 * This program is free software; you can redistribute it and/or
 * modify it under the terms of the GNU General Public License as
 * published by the Free Software Foundation;
 *
 * This program is distributed in the hope that it will be useful, but
 * WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU
 * General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program. If not, see <http://www.gnu.org/licenses/>
 */
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls

import org.kde.kcmutils as KCM
import org.kde.kirigami as Kirigami
import org.kde.plasma.plasmoid

KCM.SimpleKCM {
    id: configPage

    property string cfg_states: ""
    property alias cfg_statusScriptEnabled: statusScriptEnabledBox.checked
    property alias cfg_statusScript: checkStatusScriptText.text
    property alias cfg_runStatusOnStart: runStatusScriptBox.checked
    property alias cfg_updateInterval: updateIntervalSpinBox.value
    property alias cfg_updateIntervalUnit: updateIntervalUnitSpinBox.value
    property string cfg_iconOn: plasmoid.configuration.iconOn
    property string cfg_iconOff: plasmoid.configuration.iconOff
    property alias cfg_commandName: commandNameText.text

    ListModel {
        id: statesModel
    }

    function statesToJson() {
        const arr = [];
        for (let i = 0; i < statesModel.count; ++i) {
            const state = statesModel.get(i);
            arr.push({ name: state.name, script: state.script, icon: state.icon, enabled: state.enabled });
        }
        return JSON.stringify(arr);
    }

    function serializeStates() {
        cfg_states = statesToJson();
    }

    function loadStates() {
        let parsed = null;
        if (cfg_states) {
            try {
                parsed = JSON.parse(cfg_states);
            } catch (e) {
                parsed = null;
            }
        }
        statesModel.clear();
        if (Array.isArray(parsed) && parsed.length > 0) {
            for (const state of parsed) {
                statesModel.append({
                    name: state.name || "",
                    script: state.script || "",
                    icon: state.icon || "dialog-ok",
                    enabled: state.enabled !== false
                });
            }
        } else {
            // No state list stored yet: seed it from the legacy
            // two-state on/off settings.
            statesModel.append({
                name: "Off",
                script: plasmoid.configuration.offScript,
                icon: cfg_iconOff,
                enabled: plasmoid.configuration.offScriptEnabled
            });
            statesModel.append({
                name: "On",
                script: plasmoid.configuration.onScript,
                icon: cfg_iconOn,
                enabled: plasmoid.configuration.onScriptEnabled
            });
        }
    }

    // cfg_states is delivered by the KCM framework; reload the model
    // when it changes to something the model does not already say
    // (our own serializeStates() writes are already in sync).
    onCfg_statesChanged: {
        if (cfg_states !== statesToJson()) {
            loadStates();
        }
    }

    Component.onCompleted: loadStates()

    function setInterval() {
        if (updateIntervalUnitSpinBox.value == 1) {
            plasmoid.configuration.interval = updateIntervalSpinBox.value * 60;
        } else if (updateIntervalUnitSpinBox.value == 2) {
            plasmoid.configuration.interval = updateIntervalSpinBox.value * 60 * 60;
        } else {
            plasmoid.configuration.interval = updateIntervalSpinBox.value;
        }
    }

    Kirigami.FormLayout {
        GridLayout {
            columns: 2
            Label {
                Layout.row: 0
                Layout.column: 0
                text: i18n("Plasmoid label")
            }
            TextField {
                Layout.row: 0
                Layout.column: 1
                id: commandNameText
                Layout.minimumWidth: 300
            }

            Label {
                Layout.row: 1
                Layout.column: 0
                text: i18n("States")
                font.weight: Font.Bold
            }
            ColumnLayout {
                Layout.row: 1
                Layout.column: 1
                Label {
                    text: i18n("Clicking the button cycles to the next state and runs its script. The status script can print a state name or index to select a state directly.")
                    wrapMode: Text.Wrap
                    Layout.maximumWidth: 520
                }
                Repeater {
                    model: statesModel
                    delegate: RowLayout {
                        Layout.fillWidth: true
                        TextField {
                            text: model.name
                            placeholderText: i18n("Name")
                            Layout.preferredWidth: 110
                            onTextEdited: {
                                statesModel.setProperty(index, "name", text);
                                configPage.serializeStates();
                            }
                        }
                        TextField {
                            text: model.script
                            placeholderText: i18n("Script")
                            Layout.minimumWidth: 220
                            Layout.fillWidth: true
                            enabled: model.enabled
                            onTextEdited: {
                                statesModel.setProperty(index, "script", text);
                                configPage.serializeStates();
                            }
                        }
                        IconPicker {
                            currentIcon: model.icon
                            defaultIcon: "dialog-ok"
                            onIconSelected: function(iconName) {
                                statesModel.setProperty(index, "icon", iconName);
                                configPage.serializeStates();
                            }
                        }
                        CheckBox {
                            checked: model.enabled
                            text: i18n("Run when clicked")
                            onToggled: {
                                statesModel.setProperty(index, "enabled", checked);
                                configPage.serializeStates();
                            }
                        }
                        Button {
                            icon.name: "list-remove"
                            enabled: statesModel.count > 1
                            onClicked: {
                                statesModel.remove(index);
                                configPage.serializeStates();
                            }
                        }
                    }
                }
                Button {
                    icon.name: "list-add"
                    text: i18n("Add state")
                    onClicked: {
                        statesModel.append({ name: "", script: "", icon: "dialog-ok", enabled: true });
                        configPage.serializeStates();
                    }
                }
            }

            Label {
                Layout.row: 2
                Layout.column: 0
                text: i18n("Status script")
                font.weight: Font.Bold
            }
            CheckBox {
                Layout.row: 2
                Layout.column: 1
                id: statusScriptEnabledBox
                checked: checkStatusScriptText.activeFocus || checkStatusScriptText.length
                text: i18n("Run periodically")

                onClicked: if (checked) checkStatusScriptText.forceActiveFocus();
            }

            Label {
                Layout.row: 3
                Layout.column: 0
                text: i18n("Script")
            }
            TextField {
                Layout.row: 3
                Layout.column: 1
                id: checkStatusScriptText
                Layout.minimumWidth: 300
                enabled: (statusScriptEnabledBox.checked || runStatusScriptBox.checked)
            }

            Label {
                Layout.row: 4
                Layout.column: 0
                text: i18n("Run every")
            }
            GridLayout {
                columns: 2
                Layout.row: 4
                Layout.column: 1
                SpinBox {
                    Layout.row: 0
                    Layout.column: 0
                    id: updateIntervalSpinBox
                    enabled: statusScriptEnabledBox.checked
                    stepSize: 1
                    from: 1
                    onValueModified: setInterval()
                }
                SpinBox {
                    Layout.row: 0
                    Layout.column: 1
                    id: updateIntervalUnitSpinBox
                    enabled: statusScriptEnabledBox.checked
                    from: 0
                    to: items.length - 1
                    onValueModified: setInterval()

                    property var items: ["s", "min", "h"]

                    validator: RegularExpressionValidator {
                        regularExpression: /(s|min|h)/i
                    }

                    textFromValue: function(value) {
                        return items[value];
                    }

                    valueFromText: function(text) {
                        for (var i = 0; i < items.length; ++i) {
                            if (items[i].toLowerCase().indexOf(text.toLowerCase()) === 0)
                                return i
                        }
                        return sb.value
                    }
                }
            }
            CheckBox {
                Layout.row: 5
                Layout.column: 1
                id: runStatusScriptBox
                text: i18n("Check status on startup")
            }

        }
    }
}
