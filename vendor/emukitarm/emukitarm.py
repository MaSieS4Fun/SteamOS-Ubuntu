#!/usr/bin/env python3
"""EmuKitARM — graphical emulator installer for sm8550 / Ubuntu 26.04."""

from __future__ import annotations

import os
import signal
import stat
import subprocess
import sys
import threading
from pathlib import Path

import gi

gi.require_version("Gtk", "3.0")
from gi.repository import GLib, Gtk, Pango  # noqa: E402

ROOT = Path(__file__).resolve().parent
SCRIPTS = ROOT / "scripts"
ASKPASS = ROOT / "lib" / "askpass"
RUNTIME_DIR = Path(os.environ.get("XDG_RUNTIME_DIR", "/tmp")) / "emukitarm"
PASS_FILE = RUNTIME_DIR / "sudo_pass"

APPS = [
    {
        "id": "duckstation",
        "name": "DuckStation",
        "summary": "PlayStation 1 emulator (official AppImage)",
        "script": "duckstation.sh",
        "ready": True,
    },
    {
        "id": "melonds",
        "name": "melonDS",
        "summary": "Nintendo DS emulator (compile + cmake --install)",
        "script": "melonds.sh",
        "ready": True,
    },
    {
        "id": "dolphin",
        "name": "Dolphin",
        "summary": "GameCube / Wii emulator (compile + cmake --install)",
        "script": "dolphin.sh",
        "ready": True,
    },
    {
        "id": "azahar",
        "name": "Azahar",
        "summary": "Nintendo 3DS emulator (compile + cmake --install)",
        "script": "azahar.sh",
        "ready": True,
    },
    {
        "id": "cemu",
        "name": "Cemu",
        "summary": "Wii U emulator (compile from source)",
        "script": "cemu.sh",
        "ready": True,
    },
    {
        "id": "armsx2",
        "name": "ARMSX2",
        "summary": "PlayStation 2 emulator (official AppImage)",
        "script": "armsx2.sh",
        "ready": True,
    },
    {
        "id": "rpcs3",
        "name": "RPCS3",
        "summary": "PlayStation 3 emulator (official aarch64 AppImage)",
        "script": "rpcs3.sh",
        "ready": True,
    },
    {
        "id": "armsx3",
        "name": "ARMSX3",
        "summary": "PS3 fork of RPCS3 (compile Linux desktop; no AppImage)",
        "script": "armsx3.sh",
        "ready": True,
    },
    {
        "id": "megic",
        "name": "Eden",
        "summary": "Nintendo Switch emulator (compile; clang + optimized)",
        "script": "megic.sh",
        "ready": True,
    },
    {
        "id": "vita3k",
        "name": "Vita3K",
        "summary": "PlayStation Vita emulator (compile + cmake --install)",
        "script": "vita3k.sh",
        "ready": True,
    },
    {
        "id": "xenia-canary",
        "name": "Xenia Canary",
        "summary": "Xbox 360 emulator (./xb build + system install)",
        "script": "xenia-canary.sh",
        "ready": True,
    },
    {
        "id": "xenia-edge",
        "name": "Xenia Edge",
        "summary": "Xbox 360 emulator fork (./xb build + system install)",
        "script": "xenia-edge.sh",
        "ready": True,
    },
    {
        "id": "shadps4-qtlauncher",
        "name": "shadPS4 QtLauncher",
        "summary": "PS4 GUI launcher (compile; needs ShadPS4 ARM64 core)",
        "script": "shadps4-qtlauncher.sh",
        "ready": True,
    },
    {
        "id": "shadps4",
        "name": "ShadPS4 (ARM64)",
        "summary": "PS4 core (zenithblue + FEX → ~/shadps4/<ver>/; needs QtLauncher)",
        "script": "shadps4.sh",
        "ready": True,
    },
    {
        "id": "retropie",
        "name": "RetroPie",
        "summary": "RetroPie basic (core+main) + EmulationStation frontend",
        "script": "retropie.sh",
        "ready": True,
        "keep_tree": True,
    },
    {
        "id": "pi-apps",
        "name": "Pi-Apps",
        "summary": "Pi-Apps store (SteamOS-Ubuntu + classic sources.list fix)",
        "script": "pi-apps.sh",
        "ready": True,
        "keep_tree": True,
    },
    {
        "id": "yabasanshiro",
        "name": "YabaSanshiro",
        "summary": "SEGA Saturn emulator (official GPL tarball / Qt)",
        "script": "yabasanshiro.sh",
        "ready": True,
    },
    {
        "id": "flycast",
        "name": "Flycast",
        "summary": "Dreamcast / Naomi emulator (compile from source)",
        "script": "flycast.sh",
        "ready": True,
    },
    {
        "id": "xemu",
        "name": "xemu",
        "summary": "Original Xbox emulator (./build.sh + install)",
        "script": "xemu.sh",
        "ready": True,
    },
]


class EmuKitArmApp(Gtk.Window):
    def __init__(self) -> None:
        super().__init__(title="EmuKitARM")
        self.set_default_size(1040, 620)
        self.set_size_request(720, 420)
        self.set_border_width(0)
        self.set_position(Gtk.WindowPosition.CENTER)
        self.connect("destroy", self._on_destroy)

        self._proc: subprocess.Popen[str] | None = None
        self._busy = False
        self._checks: dict[str, Gtk.CheckButton] = {}
        self._sudo_ready = False

        css = b"""
        window { background-color: #12151c; }
        .hero {
            background-color: #1a2030;
            padding: 18px 24px 14px 24px;
        }
        .brand {
            color: #f2f5fb;
            font-size: 26px;
            font-weight: 700;
            letter-spacing: 0.5px;
        }
        .tagline {
            color: #9aa7bd;
            font-size: 13px;
            margin-top: 4px;
        }
        .section-title {
            color: #d7deea;
            font-size: 13px;
            font-weight: 600;
            padding: 10px 12px 6px 12px;
        }
        .panel {
            background-color: #151a24;
            border-radius: 10px;
        }
        .card {
            background-color: #1b2230;
            border-radius: 8px;
            padding: 8px 12px;
            margin: 3px 8px;
        }
        .app-name { color: #eef2f8; font-weight: 600; }
        .app-summary { color: #8b97ab; font-size: 12px; }
        .soon { color: #6f7c90; font-style: italic; font-size: 11px; }
        .log {
            background-color: #0d1016;
            color: #c6d0e0;
            font-family: monospace;
            font-size: 12px;
            padding: 8px;
        }
        .footer { padding: 10px 16px 14px 16px; }
        button.suggested-action {
            background-image: linear-gradient(to bottom, #3d8bfd, #2f6fd6);
            color: white; border: none; padding: 8px 18px;
            border-radius: 8px; font-weight: 600;
        }
        button.destructive-action {
            background-image: linear-gradient(to bottom, #c44, #a33);
            color: white; border: none; padding: 8px 18px;
            border-radius: 8px;
        }
        """
        provider = Gtk.CssProvider()
        provider.load_from_data(css)
        Gtk.StyleContext.add_provider_for_screen(
            self.get_screen(), provider, Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION
        )

        root = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=0)
        self.add(root)

        hero = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=2)
        hero.get_style_context().add_class("hero")
        brand = Gtk.Label(label="EmuKitARM", xalign=0)
        brand.get_style_context().add_class("brand")
        tag = Gtk.Label(
            label="Installer for Snapdragon 8 Gen 2 · Ubuntu 26.04 Resolute",
            xalign=0,
        )
        tag.get_style_context().add_class("tagline")
        hero.pack_start(brand, False, False, 0)
        hero.pack_start(tag, False, False, 0)
        root.pack_start(hero, False, False, 0)

        # Main area: scrollable app list (left) + fixed log panel (right).
        panes = Gtk.Paned(orientation=Gtk.Orientation.HORIZONTAL)
        panes.set_wide_handle(True)
        panes.set_margin_start(12)
        panes.set_margin_end(12)
        panes.set_margin_top(6)
        panes.set_margin_bottom(4)
        panes.set_hexpand(True)
        panes.set_vexpand(True)

        left = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=0)
        left.get_style_context().add_class("panel")
        left.set_size_request(300, -1)
        apps_title = Gtk.Label(label="Applications", xalign=0)
        apps_title.get_style_context().add_class("section-title")
        left.pack_start(apps_title, False, False, 0)

        list_scroll = Gtk.ScrolledWindow()
        list_scroll.set_policy(Gtk.PolicyType.NEVER, Gtk.PolicyType.AUTOMATIC)
        list_scroll.set_hexpand(True)
        list_scroll.set_vexpand(True)
        list_scroll.set_shadow_type(Gtk.ShadowType.NONE)
        list_box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=0)
        list_box.set_margin_bottom(8)
        for app in APPS:
            list_box.pack_start(self._make_app_row(app), False, False, 0)
        list_scroll.add(list_box)
        left.pack_start(list_scroll, True, True, 0)
        panes.pack1(left, resize=False, shrink=False)

        right = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=0)
        right.get_style_context().add_class("panel")
        log_title = Gtk.Label(label="Log", xalign=0)
        log_title.get_style_context().add_class("section-title")
        right.pack_start(log_title, False, False, 0)

        log_scroll = Gtk.ScrolledWindow()
        log_scroll.set_policy(Gtk.PolicyType.AUTOMATIC, Gtk.PolicyType.AUTOMATIC)
        log_scroll.set_hexpand(True)
        log_scroll.set_vexpand(True)
        log_scroll.set_shadow_type(Gtk.ShadowType.NONE)
        log_scroll.set_margin_start(8)
        log_scroll.set_margin_end(8)
        log_scroll.set_margin_bottom(8)

        self.log_view = Gtk.TextView()
        self.log_view.set_editable(False)
        self.log_view.set_cursor_visible(False)
        self.log_view.set_wrap_mode(Gtk.WrapMode.WORD_CHAR)
        self.log_view.get_style_context().add_class("log")
        self.log_view.override_font(Pango.FontDescription("Monospace 11"))
        self.log_buffer = self.log_view.get_buffer()
        log_scroll.add(self.log_view)
        right.pack_start(log_scroll, True, True, 0)
        panes.pack2(right, resize=True, shrink=False)

        # Prefer ~38% width for the app list on first show.
        def _set_pane_pos(_widget: Gtk.Widget) -> bool:
            alloc = panes.get_allocated_width()
            if alloc > 1:
                panes.set_position(max(280, int(alloc * 0.38)))
            return False

        panes.connect("map", lambda w: GLib.idle_add(_set_pane_pos, w))
        root.pack_start(panes, True, True, 0)

        footer = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=10)
        footer.get_style_context().add_class("footer")
        self.status = Gtk.Label(label="Select an application.", xalign=0)
        self.status.set_hexpand(True)
        self.status.set_ellipsize(Pango.EllipsizeMode.END)
        footer.pack_start(self.status, True, True, 0)

        self.cancel_btn = Gtk.Button(label="Cancel")
        self.cancel_btn.get_style_context().add_class("destructive-action")
        self.cancel_btn.set_sensitive(False)
        self.cancel_btn.connect("clicked", self._on_cancel)
        footer.pack_end(self.cancel_btn, False, False, 0)

        self.uninstall_btn = Gtk.Button(label="Uninstall / remove")
        self.uninstall_btn.get_style_context().add_class("destructive-action")
        self.uninstall_btn.connect("clicked", self._on_uninstall)
        footer.pack_end(self.uninstall_btn, False, False, 0)

        self.install_btn = Gtk.Button(label="Install or update selected")
        self.install_btn.get_style_context().add_class("suggested-action")
        self.install_btn.connect("clicked", self._on_install)
        footer.pack_end(self.install_btn, False, False, 0)

        root.pack_start(footer, False, False, 0)
        self._append_log(
            "Ready. Download/build leftovers are removed after install.\n"
            "Compiled apps install to /usr/local; AppImages to ~/Applications.\n"
            "Admin password is asked once per EmuKitARM session.\n"
            "AppImage tip (Steam Gaming Mode): APPIMAGE_EXTRACT_AND_RUN=1 %command%\n"
        )

    def _on_destroy(self, *_args) -> None:
        self._clear_sudo_session()
        Gtk.main_quit()

    def _clear_sudo_session(self) -> None:
        try:
            if PASS_FILE.exists():
                PASS_FILE.write_text("")
                PASS_FILE.unlink(missing_ok=True)
        except OSError:
            pass
        self._sudo_ready = False

    def _make_app_row(self, app: dict) -> Gtk.Widget:
        frame = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=12)
        frame.get_style_context().add_class("card")

        check = Gtk.CheckButton()
        check.set_sensitive(bool(app["ready"]))
        check.set_active(False)
        self._checks[app["id"]] = check
        frame.pack_start(check, False, False, 0)

        text = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=2)
        name = Gtk.Label(label=app["name"], xalign=0)
        name.get_style_context().add_class("app-name")
        summary = Gtk.Label(label=app["summary"], xalign=0)
        summary.get_style_context().add_class("app-summary")
        summary.set_line_wrap(True)
        summary.set_max_width_chars(36)
        text.pack_start(name, False, False, 0)
        text.pack_start(summary, False, False, 0)
        if not app["ready"]:
            soon = Gtk.Label(label="Not available yet", xalign=0)
            soon.get_style_context().add_class("soon")
            text.pack_start(soon, False, False, 0)
        frame.pack_start(text, True, True, 0)
        return frame

    def _append_log(self, text: str) -> None:
        end = self.log_buffer.get_end_iter()
        self.log_buffer.insert(end, text)
        mark = self.log_buffer.create_mark(None, self.log_buffer.get_end_iter(), False)
        self.log_view.scroll_to_mark(mark, 0.0, True, 0.0, 1.0)

    def _set_busy(self, busy: bool) -> None:
        self._busy = busy
        self.install_btn.set_sensitive(not busy)
        self.uninstall_btn.set_sensitive(not busy)
        self.cancel_btn.set_sensitive(busy)
        for app in APPS:
            self._checks[app["id"]].set_sensitive(bool(app["ready"]) and not busy)

    def _selected_apps(self) -> list[dict]:
        selected = []
        for app in APPS:
            if app["ready"] and self._checks[app["id"]].get_active():
                selected.append(app)
        return selected

    def _prompt_sudo_password(self) -> bool:
        """Ask once and cache in $XDG_RUNTIME_DIR for this GUI session."""
        if self._sudo_ready and PASS_FILE.exists():
            # Still valid?
            if self._sudo_validate():
                return True

        dialog = Gtk.Dialog(title="Administrator password", parent=self, modal=True)
        dialog.add_button("Cancel", Gtk.ResponseType.CANCEL)
        dialog.add_button("OK", Gtk.ResponseType.OK)
        dialog.set_default_response(Gtk.ResponseType.OK)
        box = dialog.get_content_area()
        box.set_spacing(8)
        box.set_border_width(12)
        box.add(Gtk.Label(label="Enter your password once for this EmuKitARM session:", xalign=0))
        entry = Gtk.Entry()
        entry.set_visibility(False)
        entry.set_input_purpose(Gtk.InputPurpose.PASSWORD)
        entry.set_activates_default(True)
        box.add(entry)
        dialog.show_all()
        response = dialog.run()
        password = entry.get_text()
        dialog.destroy()
        if response != Gtk.ResponseType.OK or not password:
            return False

        RUNTIME_DIR.mkdir(parents=True, exist_ok=True)
        RUNTIME_DIR.chmod(stat.S_IRWXU)
        PASS_FILE.write_text(password)
        PASS_FILE.chmod(stat.S_IRUSR | stat.S_IWUSR)
        # Drop local copy ASAP.
        password = ""
        if not self._sudo_validate():
            self._clear_sudo_session()
            self._append_log("[EmuKitARM] Incorrect password or sudo failed.\n")
            return False
        self._sudo_ready = True
        self._append_log("[EmuKitARM] Administrator password cached for this session.\n")
        return True

    def _sudo_validate(self) -> bool:
        env = os.environ.copy()
        env["SUDO_ASKPASS"] = str(ASKPASS)
        env["MASI_SUDO_PASS_FILE"] = str(PASS_FILE)
        try:
            r = subprocess.run(
                ["sudo", "-A", "-v"],
                env=env,
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
                check=False,
            )
            return r.returncode == 0
        except OSError:
            return False

    def _on_install(self, _btn: Gtk.Button) -> None:
        apps = self._selected_apps()
        if not apps:
            self.status.set_text("No applications selected.")
            return
        if not self._prompt_sudo_password():
            self.status.set_text("Administrator password required.")
            return
        self._set_busy(True)
        self.status.set_text("Installing / updating…")
        threading.Thread(target=self._run_batch, args=(apps, False), daemon=True).start()

    def _on_uninstall(self, _btn: Gtk.Button) -> None:
        apps = self._selected_apps()
        if not apps:
            self.status.set_text("No applications selected.")
            return
        names = ", ".join(a["name"] for a in apps)
        dialog = Gtk.MessageDialog(
            parent=self,
            flags=0,
            message_type=Gtk.MessageType.WARNING,
            buttons=Gtk.ButtonsType.OK_CANCEL,
            text=f"Uninstall {names}?",
        )
        dialog.format_secondary_text("This removes the selected applications from the system.")
        response = dialog.run()
        dialog.destroy()
        if response != Gtk.ResponseType.OK:
            return
        if not self._prompt_sudo_password():
            self.status.set_text("Administrator password required.")
            return
        self._set_busy(True)
        self.status.set_text("Uninstalling…")
        threading.Thread(target=self._run_batch, args=(apps, True), daemon=True).start()

    def _on_cancel(self, _btn: Gtk.Button) -> None:
        if self._proc and self._proc.poll() is None:
            self._append_log("\n[EmuKitARM] Cancelling…\n")
            try:
                os.killpg(self._proc.pid, signal.SIGTERM)
            except ProcessLookupError:
                pass

    def _run_batch(self, apps: list[dict], uninstall: bool) -> None:
        ok = True
        action = "Uninstalling" if uninstall else "Installing"
        for app in apps:
            script = SCRIPTS / str(app["script"])
            GLib.idle_add(self._append_log, f"\n>>> {action} {app['name']}…\n")
            if not script.is_file():
                GLib.idle_add(self._append_log, f"Script not found: {script}\n")
                ok = False
                continue
            args = ["--uninstall"] if uninstall else []
            code = self._run_script(script, args)
            if code != 0:
                GLib.idle_add(
                    self._append_log,
                    f"\n[EmuKitARM] {app['name']} failed (exit code {code})\n",
                )
                ok = False
                break
            if uninstall:
                done = "removed"
            elif app.get("keep_tree"):
                done = "ready (setup tree kept)."
            else:
                done = "ready. Leftovers removed."
            GLib.idle_add(self._append_log, f"\n[EmuKitARM] {app['name']} {done}\n")

        def finish() -> None:
            self._set_busy(False)
            if uninstall:
                self.status.set_text(
                    "Uninstall complete." if ok else "Uninstall incomplete. Check the log."
                )
            else:
                self.status.set_text(
                    "Install / update complete." if ok else "Install incomplete. Check the log."
                )

        GLib.idle_add(finish)

    def _run_script(self, script: Path, args: list[str] | None = None) -> int:
        env = os.environ.copy()
        env["PYTHONUNBUFFERED"] = "1"
        env["SUDO_ASKPASS"] = str(ASKPASS)
        env["MASI_SUDO_PASS_FILE"] = str(PASS_FILE)
        cmd = ["bash", str(script), *(args or [])]
        self._proc = subprocess.Popen(
            cmd,
            cwd=str(ROOT),
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
            bufsize=1,
            env=env,
            start_new_session=True,
        )
        assert self._proc.stdout is not None

        def _pump() -> None:
            assert self._proc is not None and self._proc.stdout is not None
            try:
                for line in self._proc.stdout:
                    GLib.idle_add(self._append_log, line)
            except ValueError:
                # stdout closed from the waiter side
                pass

        reader = threading.Thread(target=_pump, daemon=True)
        reader.start()
        code = self._proc.wait()

        # RetroPie (and similar) may leave helpers like joy2key attached to our
        # session/pipe; without this the GUI stays busy forever after success.
        try:
            os.killpg(self._proc.pid, signal.SIGTERM)
        except ProcessLookupError:
            pass
        try:
            self._proc.stdout.close()
        except OSError:
            pass
        reader.join(timeout=2.0)
        try:
            os.killpg(self._proc.pid, signal.SIGKILL)
        except ProcessLookupError:
            pass
        self._proc = None
        return code


def main() -> int:
    if not (SCRIPTS / "duckstation.sh").exists():
        print("scripts/duckstation.sh not found", file=sys.stderr)
        return 1
    ASKPASS.chmod(ASKPASS.stat().st_mode | stat.S_IXUSR | stat.S_IXGRP | stat.S_IXOTH)
    win = EmuKitArmApp()
    win.show_all()
    Gtk.main()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
