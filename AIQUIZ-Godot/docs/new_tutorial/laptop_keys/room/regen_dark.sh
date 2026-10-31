#!/usr/bin/env bash
# v0.5：暗い控え室・普通の拡大で R1〜R8 を作り直す。R1 を先に作り、それを参照にして残りを 3 本に分けて作る。
HERE="$(cd "$(dirname "$0")" && pwd)"
bash "$HERE/gen.sh" r1 &
bash "$HERE/gen.sh" r8 &
wait
bash "$HERE/gen.sh" r2 r3 r4 &
bash "$HERE/gen.sh" r5 r6 &
bash "$HERE/gen.sh" r7 &
wait
