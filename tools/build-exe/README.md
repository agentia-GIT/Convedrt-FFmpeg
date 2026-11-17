# Build du .exe

Le .exe est un lanceur Windows (C, x86-64) qui embarque le script .ps1 (ressource RCDATA 100),
l'ecrit dans %TEMP%, le lance avec Windows PowerShell (STA, sans console) puis le supprime.
Il pose la variable HEVC_APPDIR (dossier de l'exe : ffmpeg.exe, ffprobe.exe, logo.jpg).

    pip install ziglang
    sh build.sh <version, ex: 7a> <chemin/Convert-ToHEVC_V7a.ps1> <sortie.exe>

## Regle de publication (chaque build)
1. Mettre a jour `$script:appVersion` dans le .ps1 (ex. '7b').
2. Construire le .exe avec `build.sh`.
3. Deposer `powershell/Convert-ToHEVC_V<v>.ps1` et `release/Convert-ToHEVC_V<v>.exe`.
4. Mettre a jour `version.json` (version, chemins, notes, `sha256_exe`, `sha256_ps1` = `sha256sum` des deux fichiers) : c'est lui que lit l'application, qui verifie le SHA-256 avant d'installer.
5. Commit + push sur `main`.
