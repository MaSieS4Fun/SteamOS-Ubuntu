# AYN Odin 2: SDL2 gamecontroller mapping (rsinput), not mouse remapping.
# User-priority string: SDL's built-in DB ignores the file for this GUID.
export SDL_GAMECONTROLLERCONFIG="${SDL_GAMECONTROLLERCONFIG:-0300b605202000000130000001000000,AYN Odin2 Gamepad,platform:Linux,a:b0,b:b1,x:b3,y:b2,back:b6,start:b7,guide:b8,leftshoulder:b5,rightshoulder:b4,leftstick:b9,rightstick:b10,leftx:a0,lefty:a1,rightx:a3,righty:a4,lefttrigger:a2,righttrigger:a5,dpup:b11,dpleft:b13,dpdown:b12,dpright:b14,}"
export SDL_GAMECONTROLLERCONFIG_FILE="${SDL_GAMECONTROLLERCONFIG_FILE:-/etc/sdl2/qcom-gamecontrollerdb.txt}"
export SDL_VIDEO_X11_DGAMOUSE=0
