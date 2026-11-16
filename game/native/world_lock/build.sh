#!/bin/sh
set -eu
cd "$(dirname "$0")"
output=../../addons/world_lock
cc -std=c11 -Wall -Wextra -Werror -Wno-cast-function-type -O2 -fPIC -fvisibility=hidden -shared world_lock.c -o "$output/libisland_world_lock.so"
x86_64-w64-mingw32-gcc -std=c11 -Wall -Wextra -Werror -Wno-cast-function-type -O2 -shared world_lock.c -o "$output/island_world_lock.dll"
