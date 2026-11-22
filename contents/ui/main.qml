/*
 * Copyright (C) 2019 by Piotr Markiewicz p.marki@wp.pl>
 * 
 * Credits to Norbert Eicker <norbert.eicker@gmx.de>
 * https://github.com/neicker/on-off-switch
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
import org.kde.plasma.plasmoid
import org.kde.plasma.core as PlasmaCore
import org.kde.plasma.components as PlasmaComponents
import org.kde.plasma.plasma5support as Plasma5Support
import org.kde.kirigami as Kirigami

PlasmoidItem {
    id: root
    property bool onScriptEnabled: Plasmoid.configuration.onScriptEnabled
    property string onScript: Plasmoid.configuration.onScript
    property bool offScriptEnabled: Plasmoid.configuration.offScriptEnabled
    property string offScript: Plasmoid.configuration.offScript
    property bool statusScriptEnabled: Plasmoid.configuration.statusScriptEnabled
    property string checkStatusScript: Plasmoid.configuration.statusScript
    property bool runStatusScriptOnStart: Plasmoid.configuration.runStatusOnStart
    property int statusInterval: Plasmoid.configuration.interval
    property string commandName: Plasmoid.configuration.commandName
    
    // The states the button cycles through, from the 'states' config
    // entry (a JSON array). When that entry is empty, parseStates()
    // builds a two-entry list from the legacy on/off settings, so
    // existing configurations keep working unchanged.
    property var states: parseStates(Plasmoid.configuration.states)
    // Index of the state the button currently shows
    property int currentState: 0
    // True while the instance still runs on the shipped defaults:
    // no state list stored and the legacy scripts untouched (the
    // defaults from main.xml). Such an instance has nothing sensible
    // to show or run, so it renders a placeholder instead of an
    // empty label next to a lone status icon.
    property bool unconfigured: Plasmoid.configuration.states === ""
        && onScript === "sleep 2; exit 0"
        && offScript === "sleep 1; exit 0"
    // State shown before a button-press script started, restored
    // when that script fails
    property int stateBeforeScript: 0
    //When script is running pause status check script
    property bool scriptRunning: false

    onStatesChanged: {
        if (currentState >= states.length) {
            currentState = 0;
        }
    }
    
    preferredRepresentation: compactRepresentation

    // A global shortcut assigned to the widget activates it:
    // treat activation as a click and cycle to the next state.
    // (Feature from sh033's fork, adapted to the state list.)
    Plasmoid.onActivated: activateNext()
    
    onStatusIntervalChanged: {
        console.log('* Interval changed: ' + statusInterval);
        checkStatusTimer.interval = statusInterval * 1000;
    }
    
    onStatusScriptEnabledChanged: {
        if (statusScriptEnabled) {
            checkStatusTimer.start(); 
        } else {
            checkStatusTimer.stop();
        }
    }
    
    Component.onCompleted: {
        if (runStatusScriptOnStart) {
            checkStatus()
            if (statusScriptEnabled) {
                checkStatusTimer.start(); 
            }
        }
    }
 
    Plasma5Support.DataSource {
        id: executable
        engine: "executable"
        connectedSources: []
        onNewData: function(sourceName, data) {
            if (!scriptRunning) {
                // Behaviour for the status script: printing a state
                // name or index on stdout selects that state. With no
                // usable output, fall back to the legacy contract:
                // exit code 0 selects the second state (on), any
                // other exit code the first (off).
                const out = (data['stdout'] || '').trim();
                const named = states.findIndex(state => state.name === out);
                const numbered = parseInt(out, 10);
                if (named >= 0) {
                    currentState = named;
                } else if (out !== '' && !isNaN(numbered) && numbered >= 0 && numbered < states.length) {
                    currentState = numbered;
                } else {
                    currentState = data['exit code'] == 0 && states.length > 1 ? 1 : 0;
                }
            } else {
                // Behaviour for button-press scripts: a failed run
                // restores the state shown before it. (The two-state
                // code only reverted a failed on-script; reverting any
                // failed run is the consistent generalisation.)
                if (data['exit code'] != 0) {
                    currentState = stateBeforeScript;
                }
                scriptRunning = false;

                if (statusScriptEnabled) {
                    checkStatusTimer.restart();
                }
            }

            disconnectSource(sourceName)
        }
        
        function exec(cmd) {
            connectSource(cmd)
        }
    }
    
    function parseStates(raw) {
        if (raw) {
            try {
                const parsed = JSON.parse(raw);
                if (Array.isArray(parsed) && parsed.length > 0) {
                    return parsed;
                }
            } catch (e) {
                console.log('Invalid states configuration, using on/off settings: ' + e);
            }
        }
        return [
            { name: "Off", script: offScript, icon: Plasmoid.configuration.iconOff, enabled: offScriptEnabled },
            { name: "On", script: onScript, icon: Plasmoid.configuration.iconOn, enabled: onScriptEnabled }
        ];
    }

    // Show a state and run its script. If the script fails, onNewData
    // restores the state shown before.
    function activateState(index) {
        stateBeforeScript = currentState;
        currentState = index;
        checkStatusTimer.stop();
        scriptRunning = true;
        executable.exec(states[index].script);
    }

    // Advance to the next state whose script is enabled, wrapping
    // around. Does nothing when no other state is enabled.
    function activateNext() {
        for (let step = 1; step < states.length; ++step) {
            const next = (currentState + step) % states.length;
            if (states[next].enabled) {
                activateState(next);
                return;
            }
        }
    }
    
    function checkStatus() {
        executable.exec(checkStatusScript);
    }
    
    Component {
        id: buttonComponent

        Item {
            RowLayout {
                anchors.fill: parent
                spacing: 0
                PlasmaComponents.Label {
                    id: commandNameLabel
                    // No label, no label item: with an empty label
                    // the widget is the icon alone.
                    visible: root.unconfigured || root.commandName !== ""
                    text: root.unconfigured ? i18n("Configure") : root.commandName
                }
                Kirigami.Icon {
                    id: icon
                    Layout.fillHeight: true
                    // Square, sized by the row height but capped:
                    // in a panel the height is the panel thickness,
                    // but a desktop tile can be hundreds of pixels
                    // tall, and an icon that wide makes the content
                    // broader than the tile so the layout overflows
                    // past its edge.
                    Layout.preferredWidth: Math.min(height, Kirigami.Units.iconSizes.huge)
                    Layout.minimumWidth: Math.min(height, Kirigami.Units.iconSizes.huge)
                    // Qualify with root.: the bare name 'states' inside
                    // a child item resolves to QQuickItem's built-in
                    // 'states' property (the item's QML state list,
                    // normally empty), not to the root's state list,
                    // so states[currentState] was undefined and the
                    // binding failed with the source never set.
                    source: root.unconfigured ? "configure" : root.states[root.currentState].icon
                    BusyIndicator {
                        id: busy
                        anchors.fill: parent
                        visible: root.scriptRunning
                    }
                }
            }
            // The whole widget is the button, not just the icon:
            // the mouse area covers the label as well.
            MouseArea {
                id: mouseArea
                anchors.fill: parent
                hoverEnabled: true
                onClicked: {
                    if (root.unconfigured) {
                        Plasmoid.internalAction("configure").trigger();
                    } else {
                        root.activateNext();
                    }
                }
            }
        }
    }

    compactRepresentation: buttonComponent
    fullRepresentation: buttonComponent

    Timer {
        id: checkStatusTimer
        interval: statusInterval
        running: false
        repeat: true
        triggeredOnStart: false
        onTriggered: {
            checkStatus();
        }
    }
}
