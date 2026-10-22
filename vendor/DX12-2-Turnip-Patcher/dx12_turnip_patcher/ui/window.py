"""Choose one Proton ARM build and patch its vkd3d-proton."""

from __future__ import annotations

import gi

gi.require_version("Gtk", "3.0")
from gi.repository import Gdk, GLib, Gtk, Pango  # noqa: E402

from .. import __app_name__, __version__
from ..discover import ProtonInstall, iter_protons, selectable_protons
from ..service import apply_patch, is_patched, restore_patch

CSS = b"""
window { background-color: #1a1d23; }
.sidebar { background-color: #12151a; }
.title { font-size: 20px; font-weight: 700; color: #e8eef7; }
.body { color: #c5d0dc; font-size: 13px; }
.muted { color: #8b98a8; font-size: 12px; }
.card {
  background-color: #222833;
  border-radius: 10px;
  padding: 8px;
}
row {
  padding: 4px 8px;
}
.badge-ok {
  background-color: #1f6f4a;
  color: #d8ffe9;
  border-radius: 6px;
  padding: 2px 8px;
  font-size: 11px;
  font-weight: 600;
}
.badge-no {
  background-color: #3a4250;
  color: #d5dde8;
  border-radius: 6px;
  padding: 2px 8px;
  font-size: 11px;
}
button.suggested-action {
  background-image: linear-gradient(to bottom, #3d8bfd, #2b6fd6);
  color: white;
  border-radius: 8px;
  padding: 8px 16px;
}
button.destructive-action {
  background-image: linear-gradient(to bottom, #d9534f, #b83b37);
  color: white;
  border-radius: 8px;
  padding: 8px 16px;
}
statusbar {
  background-color: #12151a;
  color: #a9b4c2;
  padding: 8px 12px;
}
"""

EXPLAIN = (
    "Turnip has no mesh shaders, and its compute subgroup size is 64. "
    "VKD3D_FEATURE_LEVEL=12_2 stays on: Rebirth will not start without it, and it needs "
    "MeshShaderTier 1 so its shader library loads. The game then calls "
    "vkCmdDrawMeshTasksIndirectEXT, which is NULL on Turnip, and it builds a compute "
    "shader that asks for wave size 32.\n\n"
    "The patch leaves that feature level and MeshShaderTier in place. On the ARM64 DLL, "
    "a NULL mesh call returns, and a wave-32 shader is accepted so it runs at wave 64.\n\n"
    "Choose the Proton to patch, then assign it in Steam only to these games. "
    "Every Proton in compatibilitytools.d is listed. Builds under steamapps/common are left unchanged."
)


class MainWindow(Gtk.Window):
    def __init__(self) -> None:
        super().__init__(title=__app_name__)
        self.set_default_size(860, 640)
        self._rows: list[tuple[ProtonInstall, Gtk.RadioButton]] = []
        self._busy = False

        provider = Gtk.CssProvider()
        provider.load_from_data(CSS)
        screen = Gdk.Screen.get_default()
        if screen is not None:
            Gtk.StyleContext.add_provider_for_screen(
                screen, provider, Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION
            )

        root = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=0)
        self.add(root)

        body = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=12)
        body.set_margin_start(20)
        body.set_margin_end(20)
        body.set_margin_top(18)
        body.set_margin_bottom(12)
        root.pack_start(body, True, True, 0)

        title = Gtk.Label(label=__app_name__, xalign=0)
        title.get_style_context().add_class("title")
        body.pack_start(title, False, False, 0)

        sub = Gtk.Label(label=f"vkd3d-proton · version {__version__}", xalign=0)
        sub.get_style_context().add_class("muted")
        body.pack_start(sub, False, False, 0)

        explain = Gtk.Label(label=EXPLAIN, xalign=0, yalign=0)
        explain.set_line_wrap(True)
        explain.set_max_width_chars(72)
        explain.get_style_context().add_class("body")
        body.pack_start(explain, False, False, 0)

        self.list_box = Gtk.ListBox()
        self.list_box.set_selection_mode(Gtk.SelectionMode.NONE)
        scroll = Gtk.ScrolledWindow()
        scroll.set_policy(Gtk.PolicyType.NEVER, Gtk.PolicyType.AUTOMATIC)
        scroll.set_vexpand(True)
        scroll.add(self.list_box)
        frame = Gtk.Frame()
        frame.get_style_context().add_class("card")
        frame.add(scroll)
        body.pack_start(frame, True, True, 0)

        self.empty = Gtk.Label(xalign=0, yalign=0)
        self.empty.set_line_wrap(True)
        self.empty.get_style_context().add_class("body")
        body.pack_start(self.empty, False, False, 0)

        self.prefixes = Gtk.CheckButton(label="Also update Steam prefixes that already use this Proton")
        self.prefixes.set_active(True)
        body.pack_start(self.prefixes, False, False, 0)

        buttons = Gtk.Box(spacing=8)
        self.refresh_btn = Gtk.Button(label="Refresh")
        self.refresh_btn.connect("clicked", lambda *_: self.reload())
        self.apply_btn = Gtk.Button(label="Apply patch")
        self.apply_btn.get_style_context().add_class("suggested-action")
        self.apply_btn.connect("clicked", lambda *_: self._confirm_apply())
        self.restore_btn = Gtk.Button(label="Restore original")
        self.restore_btn.get_style_context().add_class("destructive-action")
        self.restore_btn.connect("clicked", lambda *_: self._confirm_restore())
        buttons.pack_start(self.refresh_btn, False, False, 0)
        buttons.pack_end(self.apply_btn, False, False, 0)
        buttons.pack_end(self.restore_btn, False, False, 0)
        body.pack_start(buttons, False, False, 0)

        self.status = Gtk.Label(label="", xalign=0)
        self.status.set_line_wrap(True)
        self.status.get_style_context().add_class("muted")
        bar = Gtk.Box()
        bar.get_style_context().add_class("statusbar")
        bar.set_margin_top(0)
        bar.pack_start(self.status, True, True, 8)
        root.pack_start(bar, False, False, 0)

        self.reload()

    def reload(self) -> None:
        for child in self.list_box.get_children():
            self.list_box.remove(child)
        self._rows.clear()
        protons = selectable_protons()
        hidden = [item for item in iter_protons() if not item.selectable]
        group: Gtk.RadioButton | None = None
        for proton in protons:
            row = Gtk.ListBoxRow()
            box = Gtk.Box(spacing=12)
            box.set_margin_top(6)
            box.set_margin_bottom(6)
            if group is None:
                radio = Gtk.RadioButton.new_with_label(None, proton.display_name)
            else:
                radio = Gtk.RadioButton.new_with_label_from_widget(group, proton.display_name)
            group = radio
            child = radio.get_child()
            if child is not None:
                child.set_ellipsize(Pango.EllipsizeMode.END)
            text = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=2)
            path = Gtk.Label(label=str(proton.root), xalign=0)
            path.get_style_context().add_class("muted")
            path.set_ellipsize(Pango.EllipsizeMode.MIDDLE)
            path.set_margin_start(24)
            text.pack_start(radio, False, False, 0)
            text.pack_start(path, False, False, 0)
            box.connect("button-release-event", lambda *_args, button=radio: button.set_active(True))
            badge = Gtk.Label(label="Patched" if is_patched(proton.root) else "Not patched")
            badge.get_style_context().add_class("badge-ok" if is_patched(proton.root) else "badge-no")
            badge.set_valign(Gtk.Align.CENTER)
            box.pack_start(text, True, True, 0)
            box.pack_start(badge, False, False, 0)
            row.add(box)
            self.list_box.add(row)
            self._rows.append((proton, radio))
        self.list_box.show_all()
        if protons:
            self.empty.set_text("")
            self._set_status(f"{len(protons)} Proton(s) in compatibilitytools.d. Left out: {len(hidden)}.")
        else:
            self.empty.set_text(
                "No Proton with a vkd3d-proton DLL was found in compatibilitytools.d.\n"
                "Install one there (GE-Proton, CachyOS, and similar). "
                "Proton builds under steamapps/common are left unchanged."
            )
            self._set_status("No selectable Proton.")
        self._set_busy(False)

    def selected(self) -> ProtonInstall | None:
        for proton, radio in self._rows:
            if radio.get_active():
                return proton
        return None

    def _confirm_apply(self) -> None:
        proton = self.selected()
        if proton is None:
            self._set_status("Choose a Proton.")
            return
        if not self._ask(
            "Apply patch",
            f"vkd3d-proton inside {proton.display_name} will be modified. "
            "An original copy is saved next to each DLL.",
        ):
            return
        self._run(lambda: apply_patch(proton, update_prefixes=self.prefixes.get_active()))

    def _confirm_restore(self) -> None:
        proton = self.selected()
        if proton is None:
            self._set_status("Choose a Proton.")
            return
        if not self._ask("Restore", f"The original vkd3d of {proton.display_name} will be restored."):
            return
        self._run(lambda: restore_patch(proton))

    def _ask(self, title: str, text: str) -> bool:
        dialog = Gtk.MessageDialog(
            parent=self,
            flags=Gtk.DialogFlags.MODAL,
            type=Gtk.MessageType.QUESTION,
            buttons=Gtk.ButtonsType.OK_CANCEL,
            message_format=title,
        )
        dialog.format_secondary_text(text)
        try:
            return dialog.run() == Gtk.ResponseType.OK
        finally:
            dialog.destroy()

    def _run(self, work) -> None:
        self._set_busy(True)
        self._set_status("Working…")

        def background() -> None:
            outcome = work()
            GLib.idle_add(self._finish, outcome)

        import threading

        threading.Thread(target=background, daemon=True).start()

    def _finish(self, outcome) -> bool:
        self.reload()
        self._set_status(outcome.summary)
        if not outcome.ok:
            dialog = Gtk.MessageDialog(
                parent=self,
                flags=Gtk.DialogFlags.MODAL,
                type=Gtk.MessageType.WARNING,
                buttons=Gtk.ButtonsType.CLOSE,
                message_format="Could not finish",
            )
            dialog.format_secondary_text(outcome.summary)
            dialog.run()
            dialog.destroy()
        return False

    def _set_busy(self, busy: bool) -> None:
        self._busy = busy
        for button in (self.refresh_btn, self.apply_btn, self.restore_btn):
            button.set_sensitive(not busy)

    def _set_status(self, text: str) -> None:
        self.status.set_text(text)


def run() -> int:
    win = MainWindow()
    win.connect("destroy", Gtk.main_quit)
    win.show_all()
    Gtk.main()
    return 0
