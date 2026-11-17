#!/bin/sh
# usage: build.sh <tag ex: 7a> <script.ps1> <sortie.exe>
set -e
TAG="$1"; PS1="$2"; OUT="$3"
cp "$PS1" script.ps1
MAJ=$(echo "$TAG" | sed 's/[^0-9].*//'); LET=$(echo "$TAG" | sed 's/^[0-9]*//')
cat > app.rc <<RC
#include <windows.h>
1 ICON "app.ico"
1 RT_MANIFEST "manifest.xml"
100 RCDATA "script.ps1"
1 VERSIONINFO
 FILEVERSION $MAJ,0,0,0
 PRODUCTVERSION $MAJ,0,0,0
 FILEOS VOS_NT_WINDOWS32
 FILETYPE VFT_APP
BEGIN
  BLOCK "StringFileInfo"
  BEGIN
    BLOCK "040C04B0"
    BEGIN
      VALUE "FileDescription", "Conversion video H.265 / MKV (ffmpeg) - V$TAG"
      VALUE "ProductName", "Convert-ToHEVC V$TAG"
      VALUE "FileVersion", "$MAJ.0.0.0 ($TAG)"
      VALUE "OriginalFilename", "Convert-ToHEVC_V$TAG.exe"
    END
  END
  BLOCK "VarFileInfo"
  BEGIN
    VALUE "Translation", 0x040C, 1200
  END
END
RC
python3 -m ziglang cc -target x86_64-windows-gnu -O2 -s -Wl,--subsystem,windows -municode -DAPP_TAG="L\"V$TAG\"" launcher.c app.rc -o "$OUT"
