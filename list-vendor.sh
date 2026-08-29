#!/bin/bash
find /home/steam/Desktop/SteamOS-Ubuntu/vendor -print 2>/dev/null | sort > /home/steam/Desktop/SteamOS-Ubuntu/vendor-list.txt
echo "EXISTS" >> /home/steam/Desktop/SteamOS-Ubuntu/vendor-list.txt
test -f /etc/systemd/system/plugin_loader.service && echo "PLUGIN_LOADER: /etc/systemd/system/plugin_loader.service" >> /home/steam/Desktop/SteamOS-Ubuntu/vendor-list.txt || echo "PLUGIN_LOADER: NOT_FOUND" >> /home/steam/Desktop/SteamOS-Ubuntu/vendor-list.txt
