# Convert-ToHEVC (V8d)

Convertisseur video vers HEVC (x265) avec interface Windows (PowerShell / WinForms) base sur FFmpeg.

## Fonctions
- **V8d** : verification de tout le systeme au demarrage, en arriere-plan (fenetre jamais figee) : version de l'application, FFmpeg (stable gyan.dev ou build complete BtbN) et coherence ffmpeg/ffprobe, logo (mis a jour automatiquement), capacites (VMAF, libplacebo), pilote NVIDIA / NVENC (alerte si trop ancien) ; bandeau cliquable, rapport detaille dans Parametres (bouton "Tout reverifier maintenant") et dans log.txt
- **V8c** : la variante FFmpeg complete est telechargee depuis BtbN/FFmpeg-Builds (zip GPL, ~200 Mo) car gyan.dev ne la publie qu'en .7z (erreur 404 corrigee) ; nettoyage des anciennes versions Convert-ToHEVC_V* journalise (log.txt) et reessaye jusqu'a la fermeture de l'ancienne version
- **V8b** : changement de variante FFmpeg (essentials -> complete) detecte et propose dans Parametres et au demarrage ; sondes NVENC detaillees (B-frames, B-ref) avec message d'erreur dans Parametres et log.txt. Les binaires FFmpeg ne sont pas dans le depot (trop volumineux) : l'application les telecharge dans son dossier.
- **V8a** : apres une mise a jour (et au demarrage), les versions anterieures `Convert-ToHEVC_V*.exe/.ps1` sont supprimees du dossier de l'application sur le poste de l'utilisateur (le depot GitHub les conserve)
- **V8 (version majeure)** : analyse automatique de chaque video (ffprobe + idet, cropdetect, signalstats sur 3 extraits) et qualite exceptionnelle sans reglage :
  - profils **Rapide / Equilibre / Archivage** (x265 medium / slow / slower ; NVENC p5 / p7) et modes **Automatique** (recherche du CRF/CQ qui atteint un score VMAF 93 / 95 / 96,5, ou SSIM si libvmaf est absent), **Fixe** ou **Debit cible par codec** (MPEG-2 /3,2, MPEG-4 /2,6, H.264 /1,8...) ; plafond = debit de la source (jamais plus gros) hors upscaling
  - traitements automatiques, chacun en Auto / Oui / Non : desentrelacement bwdif meme sans upscaling, telecine inverse (fieldmatch + decimate), recadrage des bandes noires, deblock / hqdn3d / deband selon le debit par pixel normalise par codec, niveaux delaves, encodage 10 bits (Main10), matrice BT.601 vers BT.709 pour SD vers HD (etiquettes BT.709), libplacebo (option)
  - options avancees NVENC (B-frames, b_ref_mode, GOP) et Quick Sync (adaptive_i/b, ICQ) detectees au demarrage avec repli automatique ; ffmpeg complet recommande (VMAF, libplacebo) : case dans Parametres
  - audio : si piste FR -> pistes FR + sous-titres FR forces ; sinon piste par defaut + sous-titres FR complets (ou forces) ; PCM / TrueHD / FLAC / DTS-HD MA convertis en AC3 640k/448k ou AAC (option) ; chapitres conserves ; sources deja HEVC/AV1/VP9 a bas debit ignorees (option)
  - score qualite final (VMAF/SSIM) dans le journal ; apercu avec traitement automatique, curseur avant/apres et test de qualite sur 3 s
  - l'upscaling 1080p garde le comportement V7 (qualite constante CQ 19 / CRF 18, sans plafond de poids)
- **V7d** : `logo.jpg` telecharge depuis GitHub s'il manque (premier lancement, installation, mise a jour) ; fenetre Parametres simplifiee
- **V7c** : verification des mises a jour au demarrage (application + FFmpeg, en arriere-plan, bandeau cliquable, option dans Parametres) ; FFmpeg absent -> telechargement automatique propose ; correctifs (voir ci-dessous)
- **V7b** : fenetre Parametres -> "Faire la mise a jour" (telecharge la nouvelle version depuis GitHub, verifie le SHA-256, redemarre) et mise a jour directe de FFmpeg (derniere version stable, retour arriere si echec)
- **V7a** : logo engrenage (en-tete) -> fenetre Parametres : lien du depot, verification de la nouvelle version (version.json), verification de la mise a jour FFmpeg
- Encodage NVIDIA NVENC, Intel Quick Sync ou x265 CPU (detection automatique)
- Qualite : automatique (VMAF/SSIM), fixe ou debit cible par codec
- Upscaling 1080p optionnel (Lanczos), 2 passes optionnelles
- Conservation HDR10 et des etiquettes de couleur de la source
- Audio et sous-titres : regles FR (voir V8), copie sans reencodage sauf pistes sans perte (option)
- Suppression des metadonnees (chapitres conserves), journal `log.txt`

## Contenu
- `powershell/Convert-ToHEVC_V8d.ps1` : source (version courante) ; V8c, V8b, V8a, V8, V7d, V7c, V7b, V7a et V7 : versions precedentes
- `powershell/Convert-ToHEVC.cmd` : lanceur
- `release/Convert-ToHEVC_V8d.exe` : version compilee (courante) ; V8c, V8b, V8a, V8, V7d, V7c, V7b, V7a et V7 : precedentes
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
