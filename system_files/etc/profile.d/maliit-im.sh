# Maliit for non-Plasma sessions. Under Plasma Wayland, KWin's InputMethod
# (com.github.maliit.keyboard.desktop) owns the OSK via text-input-v3 — setting
# QT_IM_MODULE here would bypass that path and the keyboard never appears.
if [ "${XDG_SESSION_TYPE:-}" = "wayland" ] && {
  [ "${XDG_CURRENT_DESKTOP:-}" = "KDE" ] || [ "${XDG_SESSION_DESKTOP:-}" = "plasma" ]
}; then
  unset QT_IM_MODULE GTK_IM_MODULE 2>/dev/null || true
else
  export QT_IM_MODULE="${QT_IM_MODULE:-Maliit}"
  export GTK_IM_MODULE="${GTK_IM_MODULE:-Maliit}"
fi
