#!/bin/sh
# Runs every headless test from the repo root: sh tests/kos/run.sh   (needs texlua, python3, gcc for the link test)
cd "$(dirname "$0")/../.."
[ -x /tmp/kosLinkTest ] || gcc -std=c99 -o /tmp/kosLinkTest embedded/kosLink/kosLink.c embedded/kosLink/test.c
fail=0
for t in tests/kos/*.lua; do printf "%s: " "$(basename $t)"; timeout 120 texlua $t 2>&1 | tail -1 | cut -c1-70; [ "${PIPESTATUS:-0}" ] ; done
python3 tests/kos/regtest.py 2>&1 | tail -1
texlua tools/kosSim/sim.lua | tail -1
