# Convert-ToHEVC (V7a)

Convertisseur video vers HEVC (x265) avec interface Windows (PowerShell / WinForms) base sur FFmpeg.

## Fonctions
- **V7a** : logo engrenage (en-tete) -> fenetre Parametres : lien du depot, verification de la nouvelle version (version.json), verification de la mise a jour FFmpeg
- Encodage NVIDIA NVENC, Intel Quick Sync ou x265 CPU (detection automatique)
- Cible de debit : debit d'origine / 1,8
- Upscaling 1080p optionnel (Lanczos), 2 passes optionnelles
- Conservation HDR10 et des etiquettes de couleur de la source
- Audio FR (ou piste unique) copie sans reencodage, sous-titres FR copies
- Suppression des metadonnees et chapitres, journal `log.txt`

## Contenu
- `powershell/Convert-ToHEVC_V7a.ps1` : source (version courante) ; `Convert-ToHEVC_V7.ps1` : version precedente
- `powershell/Convert-ToHEVC.cmd` : lanceur
- `release/Convert-ToHEVC_V7a.exe` : version compilee (courante) ; `Convert-ToHEVC_V7.exe` : precedente
- `version.json` : derniere version publiee (lue par la fenetre Parametres)
- `tools/build-exe/` : sources du lanceur .exe et script de build
- `assets/logo.jpg` : logo (a placer a cote du script / exe)

## Prerequis
`ffmpeg.exe` et `ffprobe.exe` dans le PATH ou dans le dossier du script (non inclus dans le depot).

## Points connus (V7)
- L'upscaling a qualite constante ou 2 passes (0,08 bpp) peut produire un fichier bien plus gros qu'une source deja tres compressee.
