# Convert-ToHEVC (V7d)

Convertisseur video vers HEVC (x265) avec interface Windows (PowerShell / WinForms) base sur FFmpeg.

## Fonctions
- **V7d** : `logo.jpg` telecharge depuis GitHub s'il manque (premier lancement, installation, mise a jour) ; fenetre Parametres simplifiee
- **V7c** : verification des mises a jour au demarrage (application + FFmpeg, en arriere-plan, bandeau cliquable, option dans Parametres) ; FFmpeg absent -> telechargement automatique propose ; correctifs (voir ci-dessous)
- **V7b** : fenetre Parametres -> "Faire la mise a jour" (telecharge la nouvelle version depuis GitHub, verifie le SHA-256, redemarre) et mise a jour directe de FFmpeg (derniere version stable, retour arriere si echec)
- **V7a** : logo engrenage (en-tete) -> fenetre Parametres : lien du depot, verification de la nouvelle version (version.json), verification de la mise a jour FFmpeg
- Encodage NVIDIA NVENC, Intel Quick Sync ou x265 CPU (detection automatique)
- Cible de debit : debit d'origine / 1,8
- Upscaling 1080p optionnel (Lanczos), 2 passes optionnelles
- Conservation HDR10 et des etiquettes de couleur de la source
- Audio FR (ou piste unique) copie sans reencodage, sous-titres FR copies
- Suppression des metadonnees et chapitres, journal `log.txt`

## Contenu
- `powershell/Convert-ToHEVC_V7d.ps1` : source (version courante) ; V7c, V7b, V7a et V7 : versions precedentes
- `powershell/Convert-ToHEVC.cmd` : lanceur
- `release/Convert-ToHEVC_V7d.exe` : version compilee (courante) ; V7c, V7b, V7a et V7 : precedentes
- `version.json` : derniere version publiee (lue par la fenetre Parametres)
- `tools/build-exe/` : sources du lanceur .exe et script de build
- `release/logo.jpg` : logo (a cote du script / exe ; telecharge automatiquement s'il manque)

## Prerequis
`ffmpeg.exe` et `ffprobe.exe` dans le PATH ou dans le dossier de l'application. S'ils sont absents, l'application propose de les telecharger au demarrage (non inclus dans le depot).

## Correctifs V7c
- Corrige : apres ouverture des Parametres (V7a/V7b), le chronometre de conversion etait ecrase (variable `$script:sw`) et la conversion suivante echouait.
- Fermer la fenetre pendant une conversion supprime le fichier partiel `_X265.mkv` (il etait sinon pris pour un fichier deja converti).
- Alerte dans le journal et dans la liste si le fichier converti est plus gros que l'original.
- Le lanceur .exe affiche les erreurs de chargement PowerShell au lieu de s'arreter en silence.

## Points connus (V7)
- L'upscaling a qualite constante ou 2 passes (0,08 bpp) peut produire un fichier bien plus gros qu'une source deja tres compressee.
