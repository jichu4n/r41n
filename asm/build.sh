#!/bin/bash

set -e

cd "$(dirname "$0")"
(set -x; \
    fasm r41n-8086.asm r41n-8086.exe; \
    fasm r41n-80186.asm r41n-80186.exe; \
)
