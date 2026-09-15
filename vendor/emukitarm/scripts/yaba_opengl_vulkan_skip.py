#!/usr/bin/env python3
"""Patch YabaSanshiro Qt sources for OpenGL-only Linux (no Vulkan runtime)."""
from __future__ import annotations

import shutil
import sys
from pathlib import Path


def patch_yabause_thread(path: Path) -> None:
    text = path.read_text(encoding="utf-8", errors="surrogateescape")
    if "MasiScript: OpenGL-only Vulkan skip" in text:
        return
    old_inc = '#include "../vulkan/Renderer.h"\nRenderer* _vulkanRenderer;\n'
    new_inc = """#ifdef HAVE_VULKAN
#include \"../vulkan/Renderer.h\"
Renderer* _vulkanRenderer;
#else
/* MasiScript: OpenGL-only Vulkan skip */
void* _vulkanRenderer = nullptr;
#endif
"""
    if old_inc not in text:
        raise SystemExit("YabauseThread.cpp: Renderer include block not found")
    text = text.replace(old_inc, new_inc, 1)

    old_ctor = "\t_vulkanRenderer = new Renderer();\n"
    new_ctor = """#ifdef HAVE_VULKAN
\t_vulkanRenderer = new Renderer();
#else
\t_vulkanRenderer = nullptr;
#endif
"""
    if old_ctor not in text:
        raise SystemExit("YabauseThread.cpp: Renderer ctor not found")
    text = text.replace(old_ctor, new_ctor, 1)

    old_dtor = """\tvkQueueWaitIdle(_vulkanRenderer->GetVulkanQueue());
\tvkDeviceWaitIdle(_vulkanRenderer->GetVulkanDevice());
\tdelete _vulkanRenderer;
"""
    new_dtor = """#ifdef HAVE_VULKAN
\tif (_vulkanRenderer) {
\t\tvkQueueWaitIdle(_vulkanRenderer->GetVulkanQueue());
\t\tvkDeviceWaitIdle(_vulkanRenderer->GetVulkanDevice());
\t\tdelete _vulkanRenderer;
\t}
#endif
"""
    if old_dtor not in text:
        raise SystemExit("YabauseThread.cpp: Renderer dtor not found")
    text = text.replace(old_dtor, new_dtor, 1)
    path.write_text(text, encoding="utf-8", errors="surrogateescape")
    print("YabauseThread.cpp patched")


def patch_qt_cmake(path: Path) -> None:
    text = path.read_text(encoding="utf-8", errors="surrogateescape")
    if "MasiScript: always build QYabVulkanWidget stub" in text:
        return
    old = """if (YAB_WANT_VULKAN)
#set( yabause_qt_SOURCES ${yabause_qt_SOURCES} ../vulkan/Window_glfw.cpp )
set( yabause_qt_SOURCES ${yabause_qt_SOURCES} QYabVulkanWidget.cpp QYabVulkanWidget.h )
endif()
"""
    new = """if (YAB_WANT_VULKAN)
#set( yabause_qt_SOURCES ${yabause_qt_SOURCES} ../vulkan/Window_glfw.cpp )
set( yabause_qt_SOURCES ${yabause_qt_SOURCES} QYabVulkanWidget.cpp QYabVulkanWidget.h )
else()
# MasiScript: always build QYabVulkanWidget stub (UI references it unconditionally)
set( yabause_qt_SOURCES ${yabause_qt_SOURCES} QYabVulkanWidget.cpp QYabVulkanWidget.h )
endif()
"""
    if old not in text:
        raise SystemExit("qt CMakeLists.txt: YAB_WANT_VULKAN widget block not found")
    path.write_text(text.replace(old, new, 1), encoding="utf-8", errors="surrogateescape")
    print("qt CMakeLists.txt patched")


def main() -> int:
    if len(sys.argv) != 3:
        print(f"usage: {sys.argv[0]} <qt_dir> <stub_cpp>", file=sys.stderr)
        return 2
    qt_dir = Path(sys.argv[1])
    stub_cpp = Path(sys.argv[2])
    shutil.copyfile(stub_cpp, qt_dir / "QYabVulkanWidget.cpp")
    print("installed QYabVulkanWidget stub")
    patch_yabause_thread(qt_dir / "YabauseThread.cpp")
    patch_qt_cmake(qt_dir / "CMakeLists.txt")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
