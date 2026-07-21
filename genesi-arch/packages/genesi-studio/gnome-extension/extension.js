/*
 * Genesi Studio Mode — GNOME Shell extension (45+ / ESM).
 *
 * GNOME is the one desktop Genesi ships where the session daemon cannot see the
 * window list: on Wayland, Mutter exposes nothing to third-party processes, so
 * genesi-studiod falls back to a /proc scan that lists applications and cannot
 * report focus. An extension runs INSIDE the shell, so it can do what the daemon
 * cannot — read the real focused window and hand its PID to the CLI.
 *
 * That is this extension's real job. The panel button is the visible part; the
 * important part is `focusedPid()`, which turns GNOME from the weakest Studio
 * Mode desktop into a first-class one.
 *
 * Everything else goes through the same `genesi-studio` CLI as the plasmoid and
 * the tray, and the same state.json, so all three stay in agreement.
 */

import GLib from 'gi://GLib';
import Gio from 'gi://Gio';
import GObject from 'gi://GObject';
import Meta from 'gi://Meta';
import St from 'gi://St';

import * as Main from 'resource:///org/gnome/shell/ui/main.js';
import * as PanelMenu from 'resource:///org/gnome/shell/ui/panelMenu.js';
import * as PopupMenu from 'resource:///org/gnome/shell/ui/popupMenu.js';
import {Extension} from 'resource:///org/gnome/shell/extensions/extension.js';

const REFRESH_SECONDS = 3;
const MAX_LISTED = 12;

const StudioIndicator = GObject.registerClass(
class StudioIndicator extends PanelMenu.Button {
    _init() {
        super._init(0.0, 'Genesi Studio Mode');

        this._icon = new St.Icon({
            icon_name: 'genesi-studio-symbolic',
            style_class: 'system-status-icon',
        });
        this.add_child(this._icon);

        this._state = {};
        this._buildMenu();
        this._refresh();
        this._timer = GLib.timeout_add_seconds(
            GLib.PRIORITY_DEFAULT, REFRESH_SECONDS, () => {
                this._refresh();
                return GLib.SOURCE_CONTINUE;
            });
    }

    destroy() {
        if (this._timer) {
            GLib.Source.remove(this._timer);
            this._timer = null;
        }
        super.destroy();
    }

    // ── the bit only an extension can do ─────────────────────────────────────
    _focusedPid() {
        // Mutter knows the focused window's PID; nothing outside the shell does.
        // Returning null (rather than guessing) makes the menu fall back to the
        // explicit app list, which is always correct if less convenient.
        try {
            const win = global.display.focus_window;
            if (!win)
                return null;
            const pid = win.get_pid();
            return pid > 0 ? pid : null;
        } catch (_e) {
            return null;
        }
    }

    _focusedApps() {
        // Every normal window with a resolvable pid, newest first — the same
        // shape the CLI's `list --json` returns on other desktops.
        const out = [];
        const seen = new Set();
        try {
            for (const actor of global.get_window_actors()) {
                const win = actor.meta_window;
                if (!win || win.get_window_type() !== Meta.WindowType.NORMAL)
                    continue;
                const pid = win.get_pid();
                if (pid <= 0 || seen.has(pid))
                    continue;
                seen.add(pid);
                out.push({pid, name: win.get_wm_class() || win.get_title() || String(pid)});
            }
        } catch (_e) {
            // Shell API drift — degrade to an empty list rather than break the menu
        }
        return out;
    }

    // ── daemon I/O ───────────────────────────────────────────────────────────
    _statePath() {
        const runtime = GLib.get_user_runtime_dir();
        return GLib.build_filenamev([runtime, 'genesi-studio', 'state.json']);
    }

    _readState() {
        try {
            const [ok, bytes] = GLib.file_get_contents(this._statePath());
            if (!ok)
                return {};
            return JSON.parse(new TextDecoder().decode(bytes));
        } catch (_e) {
            return {};
        }
    }

    _cli(args) {
        try {
            const proc = Gio.Subprocess.new(
                ['genesi-studio', ...args],
                Gio.SubprocessFlags.STDOUT_SILENCE | Gio.SubprocessFlags.STDERR_SILENCE);
            proc.wait_async(null, () => this._refresh());
        } catch (e) {
            Main.notifyError('Genesi Studio Mode', e.message);
        }
    }

    // ── menu ─────────────────────────────────────────────────────────────────
    _buildMenu() {
        this._statusItem = new PopupMenu.PopupMenuItem('Studio Mode', {
            reactive: false,
        });
        this.menu.addMenuItem(this._statusItem);

        this._detailItem = new PopupMenu.PopupMenuItem('', {reactive: false});
        this.menu.addMenuItem(this._detailItem);

        this.menu.addMenuItem(new PopupMenu.PopupSeparatorMenuItem());

        this._actionItem = new PopupMenu.PopupMenuItem('Focus the active window');
        this._actionItem.connect('activate', () => this._primaryAction());
        this.menu.addMenuItem(this._actionItem);

        this._pickerSection = new PopupMenu.PopupMenuSection();
        this.menu.addMenuItem(this._pickerSection);
    }

    _primaryAction() {
        if (this._state.active) {
            this._cli(['off']);
            return;
        }
        const pid = this._focusedPid();
        // Hand the CLI a concrete pid: the daemon's own focus detection does not
        // work on GNOME Wayland, so "on" with no argument would fail here.
        this._cli(pid ? ['on', String(pid)] : ['on']);
    }

    _refresh() {
        this._state = this._readState();
        const active = !!this._state.active;
        const targets = this._state.targets || [];
        const frozen = this._state.frozen || [];

        this._icon.style_class = active
            ? 'system-status-icon genesi-studio-active'
            : 'system-status-icon';

        if (!Object.keys(this._state).length) {
            this._statusItem.label.text = 'Studio Mode — daemon offline';
            this._detailItem.label.text = 'systemctl --user start genesi-studiod';
            this._actionItem.label.text = 'Focus the active window';
            this._actionItem.setSensitive(false);
            this._pickerSection.removeAll();
            return;
        }

        this._actionItem.setSensitive(true);
        this._statusItem.label.text = `Studio Mode: ${active ? 'ON' : 'OFF'}`;

        if (active) {
            const names = targets
                .map(t => t.app_id || String(t.pid))
                .join(', ') || '—';
            this._detailItem.label.text =
                `${names} · ${frozen.length} app(s) frozen`;
            this._actionItem.label.text = 'Turn Studio Mode off';
            this._pickerSection.removeAll();
        } else {
            this._detailItem.label.text = 'Ready — pick what gets the machine';
            this._actionItem.label.text = 'Focus the active window';
            this._rebuildPicker();
        }
    }

    _rebuildPicker() {
        this._pickerSection.removeAll();
        const apps = this._focusedApps().slice(0, MAX_LISTED);
        if (!apps.length)
            return;
        this._pickerSection.addMenuItem(new PopupMenu.PopupSeparatorMenuItem());
        for (const app of apps) {
            const item = new PopupMenu.PopupMenuItem(`${app.name}  (${app.pid})`);
            item.connect('activate', () => this._cli(['on', String(app.pid)]));
            this._pickerSection.addMenuItem(item);
        }
    }
});

export default class GenesiStudioExtension extends Extension {
    enable() {
        this._indicator = new StudioIndicator();
        Main.panel.addToStatusArea('genesi-studio', this._indicator);
    }

    disable() {
        // Studio Mode itself is NOT turned off here: disabling the extension
        // (or a shell restart on X11) must not silently thaw a session the user
        // deliberately started. The daemon owns that lifecycle.
        this._indicator?.destroy();
        this._indicator = null;
    }
}
