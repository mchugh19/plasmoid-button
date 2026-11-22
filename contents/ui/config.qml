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

    // Explanatory help for the state columns, shown as tooltips on
    // both the column headers and the row controls so every column
    // has it in whichever place the user hovers.
    property string nameHelp: i18n("Name of the state. The status script can select this state by printing its name.")
    property string scriptHelp: i18n("Command run when the button cycles to this state. It can set the hover tooltip by printing {PlasmoidTooltipHeadStart}...{PlasmoidTooltipHeadEnd} or {PlasmoidTooltipBodyStart}...{PlasmoidTooltipBodyEnd}.")
    property string exitCodeHelp: i18n("A status run ending with this code selects the state.")
    property string iconHelp: i18n("Icon shown for this state. Click to choose a different one.")
    property string runHelp: i18n("Cycle to this state when the button is clicked and run its script. When unchecked, only the status script can select the state.")
    property string defaultHelp: i18n("Shown at startup, selected when a status run matches nothing, restored when a state's script fails.")

    // Width of the remove-button column, set explicitly on the row
    // buttons and reserved as an empty cell in the header row. The
    // header has no remove button, so without the reserved cell its
    // Script column stretches by that width and every header from
    // Exit code on sits to the right of its column.
    property int removeColumnWidth: Kirigami.Units.gridUnit * 2

    ListModel {
        id: statesModel
    }

    // One shared group for the per-row default radio buttons, so
    // checking one unchecks the others at the control level too
    // (a click breaks the checked binding on that row's button).
    ButtonGroup {
        id: defaultStateGroup
    }

    // Serialise on row add/remove from here, in the page's context.
    // The remove button cannot do it itself: removing its row
    // destroys its own delegate, and the rest of its click handler
    // then runs in that dead context (it threw
    // 'ReferenceError: configPage is not defined'), so the new list
    // was never written and the deleted state came back on the
    // next load.
    Connections {
        target: statesModel
        function onCountChanged() {
            configPage.normalizeDefault();
            configPage.serializeStates();
        }
    }

    // Keep exactly one default state: the first one marked wins,
    // and when none is marked (the marked row was removed, or a
    // stored list predates the flag) the first row becomes it.
    function normalizeDefault() {
        let seen = false;
        for (let i = 0; i < statesModel.count; ++i) {
            if (statesModel.get(i).isDefault === true) {
                if (seen) {
                    statesModel.setProperty(i, "isDefault", false);
                } else {
                    seen = true;
                }
            }
        }
        if (!seen && statesModel.count > 0) {
            statesModel.setProperty(0, "isDefault", true);
        }
    }

    function setDefaultState(row) {
        for (let i = 0; i < statesModel.count; ++i) {
            statesModel.setProperty(i, "isDefault", i === row);
        }
        serializeStates();
    }

    function statesToJson() {
        const arr = [];
        for (let i = 0; i < statesModel.count; ++i) {
            const state = statesModel.get(i);
            const code = parseInt(state.exitCode, 10);
            arr.push({
                name: state.name,
                script: state.script,
                icon: state.icon,
                enabled: state.enabled,
                exitCode: isNaN(code) ? null : code,
                default: state.isDefault === true
            });
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
                    enabled: state.enabled !== false,
                    exitCode: typeof state.exitCode === "number" ? String(state.exitCode) : "",
                    isDefault: state.default === true
                });
            }
        } else {
            // No state list stored yet: seed it from the legacy
            // two-state on/off settings. On answers to exit code 0
            // and Off is the default, matching the original status
            // contract.
            statesModel.append({
                name: "Off",
                script: plasmoid.configuration.offScript,
                icon: cfg_iconOff,
                enabled: plasmoid.configuration.offScriptEnabled,
                exitCode: "",
                isDefault: true
            });
            statesModel.append({
                name: "On",
                script: plasmoid.configuration.onScript,
                icon: cfg_iconOn,
                enabled: plasmoid.configuration.onScriptEnabled,
                exitCode: "0",
                isDefault: false
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
                text: i18n("States")
                font.weight: Font.Bold
            }
            ColumnLayout {
                Layout.row: 0
                Layout.column: 1
                Label {
                    text: i18n("Clicking the button cycles to the next state and runs its script.")
                    wrapMode: Text.Wrap
                    Layout.maximumWidth: 520
                }
                // Column headers for the state rows; the longer
                // explanations live in their tooltips. Labels wrap
                // within their column and bottom-align, so a narrow
                // column costs header height instead of width.
                RowLayout {
                    Layout.fillWidth: true
                    Label {
                        text: i18n("Name")
                        font: Kirigami.Theme.smallFont
                        Layout.preferredWidth: 110
                        Layout.fillHeight: false
                        Layout.alignment: Qt.AlignBottom
                        wrapMode: Text.Wrap
                        ToolTip.text: configPage.nameHelp
                        ToolTip.visible: hovered
                    }
                    Label {
                        text: i18n("Script")
                        font: Kirigami.Theme.smallFont
                        Layout.minimumWidth: 220
                        Layout.fillWidth: true
                        Layout.fillHeight: false
                        Layout.alignment: Qt.AlignBottom
                        wrapMode: Text.Wrap
                        ToolTip.text: configPage.scriptHelp
                        ToolTip.visible: hovered
                    }
                    Label {
                        text: i18n("Exit code")
                        font: Kirigami.Theme.smallFont
                        Layout.preferredWidth: 64
                        Layout.fillHeight: false
                        Layout.alignment: Qt.AlignBottom
                        wrapMode: Text.Wrap
                        ToolTip.text: configPage.exitCodeHelp
                        ToolTip.visible: hovered
                    }
                    Label {
                        text: i18n("Icon")
                        font: Kirigami.Theme.smallFont
                        Layout.preferredWidth: Kirigami.Units.iconSizes.medium + Kirigami.Units.smallSpacing * 4
                        Layout.fillHeight: false
                        Layout.alignment: Qt.AlignBottom
                        wrapMode: Text.Wrap
                        ToolTip.text: configPage.iconHelp
                        ToolTip.visible: hovered
                    }
                    Label {
                        text: i18n("Run when clicked")
                        font: Kirigami.Theme.smallFont
                        Layout.preferredWidth: 60
                        Layout.fillHeight: false
                        Layout.alignment: Qt.AlignBottom
                        wrapMode: Text.Wrap
                        ToolTip.text: configPage.runHelp
                        ToolTip.visible: hovered
                    }
                    Label {
                        text: i18n("Default")
                        font: Kirigami.Theme.smallFont
                        Layout.preferredWidth: 52
                        Layout.fillHeight: false
                        Layout.alignment: Qt.AlignBottom
                        wrapMode: Text.Wrap
                        ToolTip.text: configPage.defaultHelp
                        ToolTip.visible: hovered
                    }
                    Item {
                        Layout.preferredWidth: configPage.removeColumnWidth
                    }
                }
                Repeater {
                    model: statesModel
                    delegate: RowLayout {
                        Layout.fillWidth: true
                        TextField {
                            text: model.name
                            placeholderText: i18n("Name")
                            Layout.preferredWidth: 110
                            ToolTip.text: configPage.nameHelp
                            ToolTip.visible: hovered
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
                            ToolTip.text: configPage.scriptHelp
                            ToolTip.visible: hovered
                            onTextEdited: {
                                statesModel.setProperty(index, "script", text);
                                configPage.serializeStates();
                            }
                        }
                        TextField {
                            text: model.exitCode
                            placeholderText: i18n("Code")
                            Layout.preferredWidth: 64
                            inputMethodHints: Qt.ImhDigitsOnly
                            ToolTip.text: configPage.exitCodeHelp
                            ToolTip.visible: hovered
                            onTextEdited: {
                                statesModel.setProperty(index, "exitCode", text);
                                configPage.serializeStates();
                            }
                        }
                        IconPicker {
                            currentIcon: model.icon
                            defaultIcon: "dialog-ok"
                            ToolTip.text: configPage.iconHelp
                            ToolTip.visible: hovered
                            onIconSelected: function(iconName) {
                                statesModel.setProperty(index, "icon", iconName);
                                configPage.serializeStates();
                            }
                        }
                        CheckBox {
                            checked: model.enabled
                            Layout.preferredWidth: 60
                            ToolTip.text: configPage.runHelp
                            ToolTip.visible: hovered
                            onToggled: {
                                statesModel.setProperty(index, "enabled", checked);
                                configPage.serializeStates();
                            }
                        }
                        RadioButton {
                            checked: model.isDefault
                            ButtonGroup.group: defaultStateGroup
                            Layout.preferredWidth: 52
                            ToolTip.text: configPage.defaultHelp
                            ToolTip.visible: hovered
                            onToggled: {
                                if (checked) {
                                    configPage.setDefaultState(index);
                                }
                            }
                        }
                        Button {
                            icon.name: "list-remove"
                            enabled: statesModel.count > 1
                            Layout.preferredWidth: configPage.removeColumnWidth
                            ToolTip.text: i18n("Remove this state")
                            ToolTip.visible: hovered
                            // Serialising is left to the page-level
                            // count handler: this delegate is destroyed
                            // by the removal.
                            onClicked: statesModel.remove(index)
                        }
                    }
                }
                Button {
                    icon.name: "list-add"
                    text: i18n("Add state")
                    onClicked: {
                        statesModel.append({ name: "", script: "", icon: "dialog-ok", enabled: true, exitCode: "", isDefault: false });
                        configPage.serializeStates();
                    }
                }
            }

            Label {
                Layout.row: 1
                Layout.column: 0
                text: i18n("Status script")
                font.weight: Font.Bold
            }
            CheckBox {
                Layout.row: 1
                Layout.column: 1
                id: statusScriptEnabledBox
                checked: checkStatusScriptText.activeFocus || checkStatusScriptText.length
                text: i18n("Run periodically")

                onClicked: if (checked) checkStatusScriptText.forceActiveFocus();
            }

            Label {
                Layout.row: 2
                Layout.column: 0
                text: i18n("Script")
            }
            TextField {
                Layout.row: 2
                Layout.column: 1
                id: checkStatusScriptText
                Layout.minimumWidth: 300
                enabled: (statusScriptEnabledBox.checked || runStatusScriptBox.checked)
                ToolTip.text: i18n("Selects a state by printing its name or index, or by exiting with a state's exit code; a run that matches nothing selects the default state. Any script can also set the hover tooltip by printing {PlasmoidTooltipHeadStart}...{PlasmoidTooltipHeadEnd} or {PlasmoidTooltipBodyStart}...{PlasmoidTooltipBodyEnd}")
                ToolTip.visible: hovered
            }

            Label {
                Layout.row: 3
                Layout.column: 0
                text: i18n("Run every")
            }
            GridLayout {
                columns: 2
                Layout.row: 3
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
                Layout.row: 4
                Layout.column: 1
                id: runStatusScriptBox
                text: i18n("Check status on startup")
            }

        }
    }
}
