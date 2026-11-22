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
import QtQuick.Controls
import org.kde.plasma.plasmoid
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
    property bool showBusyIndicator: Plasmoid.configuration.showBusyIndicator
    
    // The states the button cycles through, from the 'states' config
    // entry (a JSON array). When that entry is empty, parseStates()
    // builds a two-entry list from the legacy on/off settings, so
    // existing configurations keep working unchanged.
    property var states: parseStates(Plasmoid.configuration.states)
    // Index of the state the button currently shows; set to the
    // default state on completion (a binding here would re-evaluate
    // whenever states changes and snap the display back to default)
    property int currentState: 0
    // True while the instance still runs on the shipped defaults:
    // no state list stored and the legacy scripts untouched (the
    // defaults from main.xml). Such an instance has nothing sensible
    // to show or run, so it renders a placeholder instead of an
    // empty label next to a lone status icon.
    property bool unconfigured: Plasmoid.configuration.states === ""
        && onScript === "sleep 2; exit 0"
        && offScript === "sleep 1; exit 0"
    //When script is running pause status check script
    property bool scriptRunning: false
    // Tooltip text set by scripts. A script prints
    // {PlasmoidTooltipHeadStart}...{PlasmoidTooltipHeadEnd} and/or
    // {PlasmoidTooltipBodyStart}...{PlasmoidTooltipBodyEnd} on stdout
    // (the Scriptinator tag names) and the hover popup shows them
    // until another script run replaces them. Empty means unset.
    property string tooltipHead: ""
    property string tooltipBody: ""

    // The toolTip* properties live on PlasmoidItem (this root), not
    // on the Plasmoid attached object: Plasma::Applet exposes none
    // of them (libplasma's applet.h carries a TODO to add them
    // there), so Plasmoid.toolTipSubText failed to load with
    // 'Cannot assign to non-existent property'.
    toolTipMainText: root.tooltipHead !== ""
        ? root.tooltipHead
        : (root.unconfigured || root.states[root.currentState].name === ""
            ? Plasmoid.title
            : root.states[root.currentState].name)
    toolTipSubText: root.tooltipBody

    onStatesChanged: {
        if (currentState >= states.length) {
            currentState = defaultStateIndex();
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
        currentState = defaultStateIndex();
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
            // Scripts can set the hover tooltip by printing tagged
            // segments on stdout (see extractTagged). The segments
            // are stripped before the status parsing below, so one
            // run can print a state name and a tooltip together.
            const rawOut = data['stdout'] || '';
            const head = extractTagged(rawOut, '{PlasmoidTooltipHeadStart}', '{PlasmoidTooltipHeadEnd}');
            if (head !== null) {
                tooltipHead = head;
            }
            let body = extractTagged(rawOut, '{PlasmoidTooltipBodyStart}', '{PlasmoidTooltipBodyEnd}');
            if (body === null) {
                body = extractTagged(rawOut, '{PlasmoidTooltipStart}', '{PlasmoidTooltipEnd}');
            }
            if (body !== null) {
                tooltipBody = body;
            }
            const out = stripTagged(rawOut).trim();

            if (!scriptRunning) {
                // Behaviour for the status script: its result selects
                // the desired state, resolved in a fixed order. A
                // state name printed on stdout wins, then an index
                // printed on stdout, then a state whose declared exit
                // code matches the run's exit code, and finally the
                // default state. The legacy contract is the special
                // case: On declares exit code 0 and Off is the
                // default, so exit 0 selects On and any other exit
                // code selects Off.
                let target = -1;
                if (out !== '') {
                    target = states.findIndex(state => state.name === out);
                    if (target < 0) {
                        const numbered = parseInt(out, 10);
                        if (!isNaN(numbered) && numbered >= 0 && numbered < states.length) {
                            target = numbered;
                        }
                    }
                }
                if (target < 0) {
                    const code = data['exit code'];
                    target = states.findIndex(state => state.exitCode !== null && state.exitCode === code);
                }
                currentState = target >= 0 ? target : defaultStateIndex();
            } else {
                // Behaviour for button-press scripts: a failed run
                // falls back to the default state. (With the legacy
                // pair the default is Off, which reproduces the
                // original behaviour exactly: a failed on-script
                // returns to Off, a failed off-script stays at Off.)
                if (data['exit code'] != 0) {
                    currentState = defaultStateIndex();
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
    
    // The value of the last startTag...endTag segment in text, or
    // null when there is none. The tag names follow Scriptinator's,
    // so scripts written for it work here unchanged.
    function extractTagged(text, startTag, endTag) {
        const pattern = new RegExp(escapeRegExp(startTag) + '([\\s\\S]*?)' + escapeRegExp(endTag), 'g');
        let match;
        let last = null;
        while ((match = pattern.exec(text)) !== null) {
            last = match[1];
        }
        return last;
    }

    // text with every tooltip segment removed, so what remains can
    // still be parsed as a state name or index.
    function stripTagged(text) {
        return text
            .replace(/\{PlasmoidTooltipHeadStart\}[\s\S]*?\{PlasmoidTooltipHeadEnd\}/g, '')
            .replace(/\{PlasmoidTooltipBodyStart\}[\s\S]*?\{PlasmoidTooltipBodyEnd\}/g, '')
            .replace(/\{PlasmoidTooltipStart\}[\s\S]*?\{PlasmoidTooltipEnd\}/g, '');
    }

    function escapeRegExp(text) {
        return text.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
    }

    function parseStates(raw) {
        if (raw) {
            try {
                const parsed = JSON.parse(raw);
                if (Array.isArray(parsed) && parsed.length > 0) {
                    // Normalise entries so exitCode and default are
                    // always present with the expected types, even
                    // for lists stored before they existed.
                    return parsed.map(state => ({
                        name: state.name || "",
                        script: state.script || "",
                        icon: state.icon || "dialog-ok",
                        enabled: state.enabled !== false,
                        exitCode: typeof state.exitCode === "number" ? state.exitCode : null,
                        default: state.default === true
                    }));
                }
            } catch (e) {
                console.log('Invalid states configuration, using on/off settings: ' + e);
            }
        }
        // The legacy pair: On answers to exit code 0, Off is the
        // default, which together reproduce the original status
        // contract (exit 0 shows On, anything else shows Off).
        return [
            { name: "Off", script: offScript, icon: Plasmoid.configuration.iconOff, enabled: offScriptEnabled, exitCode: null, default: true },
            { name: "On", script: onScript, icon: Plasmoid.configuration.iconOn, enabled: onScriptEnabled, exitCode: 0, default: false }
        ];
    }

    // Index of the state marked as default, or the first state when
    // none is marked.
    function defaultStateIndex() {
        const found = states.findIndex(state => state.default === true);
        return found >= 0 ? found : 0;
    }

    // Show a state and run its script. If the script fails, onNewData
    // falls back to the default state.
    function activateState(index) {
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
            Kirigami.Icon {
                id: icon
                anchors.fill: parent
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
                    visible: root.scriptRunning && root.showBusyIndicator
                }
            }
            // The whole widget is the button.
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
