"""Patch vkd3d-proton inside a chosen Proton build.

Turnip has no mesh shaders and a wave size of 64. The patch keeps feature
level 12_2 and MeshShaderTier, turns a NULL mesh call into a return, and
accepts shaders that ask for wave size 32.
"""

__version__ = "1.1.0"
__app_name__ = "DX12 Turnip Patcher"
