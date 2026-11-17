# ============================================================================
#  Convert-ToHEVC_V8e.ps1  -  Conversion video vers H.265 (HEVC) / MKV avec ffmpeg  (V8e)
#  - File d'attente : plusieurs videos, un seul dossier de sortie
#  - Nom de sortie  : <nom d'origine>_X265.mkv
#  - Video  : HEVC 10 bits, resolution inchangee ; qualite automatique (CRF/CQ cherche pour atteindre
#             un score VMAF/SSIM cible sur 3 extraits), fixe, ou debit cible par codec source
#             NVENC (GPU NVIDIA) ou Quick Sync (GPU Intel) si detectes et cases cochees
#             (NVIDIA prioritaire si les deux sont cochees), sinon libx265 (CPU)
#  - Analyse de chaque video : entrelacement (bwdif), telecine 3:2 (IVTC), bandes noires (recadrage),
#             niveau d'artefacts (deblock / hqdn3d / deband selon le debit par pixel), niveaux delaves
#  - Audio  : copie ; pistes sans perte (PCM, TrueHD, FLAC, DTS-HD MA) converties en AC3/AAC (option)
#  - Pistes : audio FR -> pistes FR + sous-titres FR forces ; sinon piste par defaut + sous-titres FR complets
#  - Couleurs : etiquettes de la source conservees, comparaison original / sortie avant compression
#  - Metadonnees et chapitres supprimes (seule la langue des pistes est conservee)
#  - CPU    : potentiometre de 10 a 100 % (50 % par defaut)
#  - Ligne de commande ffmpeg complete affichee en bas, mise a jour en direct
#  - Design : logo FFmpeg (logo.jpg, 240 px de large) + charte du site ffmpeg.org
#  - Journal: log.txt dans le dossier de sortie (deroulement complet + erreurs)
#  - Notifications a l'ecran : uniquement les erreurs
#  - V2 : upscaling 1080p HD optionnel (Lanczos, qualite constante) + bouton Pause
#  - V5 : encodage 2 passes optionnel (avec ou sans upscaling, coche auto avec l'upscaling), final haute qualite
#  - V6 : etiquettes de couleur de la source relues (ffprobe) et reappliquees a l'identique + controle apres
#         encodage, HDR conserve (x265), ratio de taille 1,8, nettete automatique apres upscaling,
#         fenetre flottante d'apercu avec reglages image (luminosite, contraste, saturation, gamma,
#         nettete, depixelisation) appliques seulement apres validation
#  - V7 : comparaison avant compression (echantillons de l'original encodes avec les memes reglages)
#         et correction automatique de l'assombrissement / des ecarts de couleur, controle final
#         original / sortie, fenetre agrandie, boutons -10 s / +10 s dans l'apercu
#  - V7a : logo engrenage cliquable (en-tete) -> fenetre Parametres : version installee, lien vers le depot
#          GitHub, verification de la nouvelle version (version.json du depot), verification de la mise
#          a jour de ffmpeg (version installee / derniere version stable)
#  - V7b : fenetre Parametres : bouton "Faire la mise a jour" (telecharge la nouvelle version depuis GitHub,
#          verifie le SHA-256, puis redemarre l'application ; exe ou ps1 selon le mode de lancement) et mise
#          a jour directe de ffmpeg / ffprobe / ffplay (derniere version stable gyan.dev, sauvegarde et retour
#          arriere en cas d'echec) ; comparaison par date pour les builds ffmpeg de developpement (git)
#  - V7c : verification des mises a jour au demarrage (application + ffmpeg, sans figer la fenetre, bandeau
#          cliquable, option dans Parametres) ; ffmpeg absent : telechargement automatique propose ;
#          correction : l'ouverture des Parametres ne perturbe plus le chronometre de conversion ;
#          fermeture pendant une conversion : fichier partiel supprime ; alerte si la sortie est plus grosse
#          que la source ; le lanceur .exe affiche les erreurs PowerShell au lieu de s'arreter en silence
#  - V8e : detection NVENC / Quick Sync refaite avec la meme methode que les sondes avancees (le test de base pouvait echouer a tort) ; message d'erreur ffmpeg affiche dans le rapport systeme
#  - V8d : verification de tout le systeme au demarrage (application, FFmpeg + ffprobe, build complet BtbN, logo,
#          pilote NVIDIA / NVENC, capacites) en tache de fond ; rapport dans Parametres et dans log.txt
#  - V8c : FFmpeg complet installe depuis BtbN (zip ; gyan.dev ne publie le full qu'en .7z -> erreur 404) ; nettoyage des anciennes versions journalise et reessaye jusqu'a fermeture
#  - V8b : passage essentials -> full detecte (mise a jour FFmpeg proposee) ; sondes NVENC detaillees avec message d'erreur
#  - V8a : les versions anterieures sont supprimees du dossier de l'utilisateur apres mise a jour (et au demarrage)
#  - V8  : VERSION MAJEURE - analyse automatique des videos et qualite exceptionnelle :
#          profils Rapide / Equilibre / Archivage ; mode Automatique (recherche du CRF/CQ par VMAF ou SSIM),
#          Fixe ou Debit cible par codec ; desentrelacement bwdif meme sans upscaling, telecine inverse,
#          recadrage automatique, deblock / debruitage / deband adaptes au debit par pixel, 10 bits (Main10),
#          matrice BT.709 pour SD -> HD, niveaux, libplacebo (option), options avancees NVENC / Quick Sync
#          detectees au demarrage (repli automatique), sources deja HEVC ignorees, audio sans perte converti,
#          chapitres conserves, score qualite final, apercu avec curseur avant/apres et test de qualite.
#          L'upscaling garde le comportement V7 (qualite constante, sans plafond de poids).
#  - V7d : logo.jpg telecharge depuis GitHub s'il manque (premier lancement, installation, mise a jour) ;
#          fenetre Parametres simplifiee (lien du depot et bouton GitHub supprimes)
#  Prerequis : ffmpeg.exe et ffprobe.exe dans le PATH (ou telecharges automatiquement au premier lancement) (ou dans le dossier du script)
#              ffplay.exe (meme dossier) seulement pour le bouton de lecture d'extrait
#              logo.jpg dans le dossier du script ou de l'exe (sinon logo integre)
#  Note : ce fichier est volontairement en ASCII pur (pas d'accent) pour eviter
#         tout probleme d'encodage avec Windows PowerShell 5.1.
# ============================================================================

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[System.Windows.Forms.Application]::EnableVisualStyles()

# Dossier de l'application : celui de l'exe (variable HEVC_APPDIR posee par l'exe),
# sinon celui du script. ffmpeg.exe, ffprobe.exe et logo.jpg y sont cherches.
$script:appDir = $env:HEVC_APPDIR
if (-not $script:appDir) { $script:appDir = $PSScriptRoot }

# Toute erreur fatale est affichee dans une fenetre (la console est masquee en version exe)
trap {
    try { [System.Windows.Forms.MessageBox]::Show(("Erreur : {0}" -f $_.Exception.Message), 'Erreur', 'OK', 'Error') | Out-Null } catch {}
    exit 2
}

# ------------------------------------------------- Controle potentiometre ---
if (-not ('KnobControl' -as [type])) {
$knobSource = @'
using System;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.Runtime.InteropServices;
using System.Windows.Forms;

public class KnobControl : Control
{
    private int _min = 10;
    private int _max = 100;
    private int _value = 50;
    private bool _dragging = false;
    public event EventHandler ValueChanged;

    public KnobControl()
    {
        SetStyle(ControlStyles.AllPaintingInWmPaint | ControlStyles.OptimizedDoubleBuffer |
                 ControlStyles.ResizeRedraw | ControlStyles.UserPaint | ControlStyles.Selectable, true);
        TabStop = true;
        Size = new Size(90, 90);
        Cursor = Cursors.Hand;
    }

    public int Minimum
    {
        get { return _min; }
        set { _min = value; if (_value < _min) { Value = _min; } Invalidate(); }
    }

    public int Maximum
    {
        get { return _max; }
        set { _max = value; if (_value > _max) { Value = _max; } Invalidate(); }
    }

    public int Value
    {
        get { return _value; }
        set
        {
            int v = Math.Max(_min, Math.Min(_max, value));
            if (v == _value) { return; }
            _value = v;
            Invalidate();
            if (ValueChanged != null) { ValueChanged(this, EventArgs.Empty); }
        }
    }

    protected override void OnPaint(PaintEventArgs e)
    {
        Graphics g = e.Graphics;
        g.SmoothingMode = SmoothingMode.AntiAlias;
        g.Clear(BackColor);

        int m = 6;
        int size = Math.Min(Width, Height) - 2 * m;
        if (size < 24) { return; }
        float cx = Width / 2f;
        float cy = Height / 2f;
        RectangleF arcRect = new RectangleF(cx - size / 2f, cy - size / 2f, size, size);
        float penW = Math.Max(4f, size / 12f);
        Color accent = Enabled ? Color.FromArgb(0, 120, 215) : Color.FromArgb(160, 160, 160);
        float frac = (float)(_value - _min) / (float)(_max - _min);

        // Piste + arc de valeur
        using (Pen track = new Pen(Color.FromArgb(215, 215, 215), penW))
        using (Pen val = new Pen(accent, penW))
        {
            track.StartCap = LineCap.Round;
            track.EndCap = LineCap.Round;
            val.StartCap = LineCap.Round;
            val.EndCap = LineCap.Round;
            g.DrawArc(track, arcRect, 135f, 270f);
            if (frac > 0f) { g.DrawArc(val, arcRect, 135f, 270f * frac); }
        }

        // Corps du bouton
        float inset = penW + 4f;
        RectangleF body = new RectangleF(arcRect.X + inset, arcRect.Y + inset,
                                         arcRect.Width - 2f * inset, arcRect.Height - 2f * inset);
        using (LinearGradientBrush br = new LinearGradientBrush(body, Color.FromArgb(252, 252, 252), Color.FromArgb(185, 185, 185), 60f))
        using (Pen edge = new Pen(Color.FromArgb(140, 140, 140), 1f))
        {
            g.FillEllipse(br, body);
            g.DrawEllipse(edge, body);
        }

        // Aiguille
        double ang = (135.0 + 270.0 * frac) * Math.PI / 180.0;
        float r = body.Width / 2f;
        float x1 = cx + (float)Math.Cos(ang) * r * 0.25f;
        float y1 = cy + (float)Math.Sin(ang) * r * 0.25f;
        float x2 = cx + (float)Math.Cos(ang) * r * 0.88f;
        float y2 = cy + (float)Math.Sin(ang) * r * 0.88f;
        using (Pen p = new Pen(Enabled ? Color.FromArgb(40, 40, 40) : Color.FromArgb(150, 150, 150), Math.Max(2f, penW / 2f)))
        {
            p.StartCap = LineCap.Round;
            p.EndCap = LineCap.Round;
            g.DrawLine(p, x1, y1, x2, y2);
        }

        // Indicateur de focus clavier
        if (Focused)
        {
            using (Pen f = new Pen(Color.FromArgb(120, 120, 120), 1f))
            {
                f.DashStyle = DashStyle.Dot;
                g.DrawEllipse(f, 1f, 1f, Width - 3f, Height - 3f);
            }
        }
    }

    private void SetFromPoint(int x, int y)
    {
        double dx = x - Width / 2.0;
        double dy = y - Height / 2.0;
        if (Math.Abs(dx) < 1.0 && Math.Abs(dy) < 1.0) { return; }
        double deg = Math.Atan2(dy, dx) * 180.0 / Math.PI;
        double rel = deg - 135.0;
        while (rel < 0.0) { rel += 360.0; }
        while (rel >= 360.0) { rel -= 360.0; }
        if (rel > 270.0) { rel = (rel < 315.0) ? 270.0 : 0.0; }
        Value = _min + (int)Math.Round(rel / 270.0 * (_max - _min));
    }

    protected override void OnMouseDown(MouseEventArgs e)
    {
        base.OnMouseDown(e);
        Focus();
        if (e.Button == MouseButtons.Left)
        {
            _dragging = true;
            SetFromPoint(e.X, e.Y);
        }
    }

    protected override void OnMouseMove(MouseEventArgs e)
    {
        base.OnMouseMove(e);
        if (_dragging) { SetFromPoint(e.X, e.Y); }
    }

    protected override void OnMouseUp(MouseEventArgs e)
    {
        base.OnMouseUp(e);
        _dragging = false;
    }

    protected override void OnMouseEnter(EventArgs e)
    {
        base.OnMouseEnter(e);
        if (Enabled && !Focused) { Focus(); }
    }

    protected override void OnMouseWheel(MouseEventArgs e)
    {
        base.OnMouseWheel(e);
        Value = _value + (e.Delta > 0 ? 5 : -5);
    }

    protected override bool IsInputKey(Keys keyData)
    {
        switch (keyData & Keys.KeyCode)
        {
            case Keys.Left:
            case Keys.Right:
            case Keys.Up:
            case Keys.Down:
                return true;
        }
        return base.IsInputKey(keyData);
    }

    protected override void OnKeyDown(KeyEventArgs e)
    {
        base.OnKeyDown(e);
        switch (e.KeyCode)
        {
            case Keys.Left:
            case Keys.Down:     Value = _value - 1;  e.Handled = true; break;
            case Keys.Right:
            case Keys.Up:       Value = _value + 1;  e.Handled = true; break;
            case Keys.PageDown: Value = _value - 10; e.Handled = true; break;
            case Keys.PageUp:   Value = _value + 10; e.Handled = true; break;
            case Keys.Home:     Value = _min;        e.Handled = true; break;
            case Keys.End:      Value = _max;        e.Handled = true; break;
        }
    }

    protected override void OnGotFocus(EventArgs e) { base.OnGotFocus(e); Invalidate(); }
    protected override void OnLostFocus(EventArgs e) { base.OnLostFocus(e); Invalidate(); }
    protected override void OnEnabledChanged(EventArgs e) { base.OnEnabledChanged(e); Invalidate(); }
}

public class FlatProgress : Control
{
    private int _min = 0;
    private int _max = 100;
    private int _value = 0;

    public FlatProgress()
    {
        SetStyle(ControlStyles.AllPaintingInWmPaint | ControlStyles.OptimizedDoubleBuffer |
                 ControlStyles.ResizeRedraw | ControlStyles.UserPaint, true);
        Size = new Size(200, 14);
    }

    public int Minimum { get { return _min; } set { _min = value; Invalidate(); } }
    public int Maximum { get { return _max; } set { _max = value; Invalidate(); } }
    public int Value
    {
        get { return _value; }
        set
        {
            int v = Math.Max(_min, Math.Min(_max, value));
            if (v == _value) { return; }
            _value = v;
            Invalidate();
        }
    }

    protected override void OnPaint(PaintEventArgs e)
    {
        Graphics g = e.Graphics;
        g.Clear(Color.FromArgb(233, 233, 233));
        int range = _max - _min;
        if (range > 0 && _value > _min)
        {
            int w = (int)((long)(Width - 2) * (_value - _min) / range);
            if (w > 0)
            {
                using (SolidBrush b = new SolidBrush(Color.FromArgb(67, 133, 61)))
                {
                    g.FillRectangle(b, 1, 1, w, Height - 2);
                }
            }
        }
        using (Pen p = new Pen(Color.FromArgb(187, 187, 187)))
        {
            g.DrawRectangle(p, 0, 0, Width - 1, Height - 1);
        }
    }
}

// Pause / reprise d'un processus (suspend tous ses threads)
public static class ProcCtl
{
    [DllImport("ntdll.dll")]
    private static extern int NtSuspendProcess(IntPtr processHandle);
    [DllImport("ntdll.dll")]
    private static extern int NtResumeProcess(IntPtr processHandle);

    public static int Suspend(IntPtr handle) { return NtSuspendProcess(handle); }
    public static int Resume(IntPtr handle) { return NtResumeProcess(handle); }
}
'@
Add-Type -TypeDefinition $knobSource -ReferencedAssemblies System.Windows.Forms, System.Drawing
}

$inv = [Globalization.CultureInfo]::InvariantCulture

# ---------------------------------------------------------------- Outils ----
function Find-Tool([string]$name) {
    if ($script:appDir) {
        $local = Join-Path $script:appDir "$name.exe"
        if (Test-Path -LiteralPath $local) { return $local }
    }
    $cmd = Get-Command "$name.exe" -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }
    return $null
}
if (-not $script:appDir) { $script:appDir = [Environment]::CurrentDirectory }

# ------------------------------------------- Version / depot GitHub (V7a) ---
$script:appVersion    = '8e'
$script:repoUrl       = 'https://github.com/agentia-GIT/Convedrt-FFmpeg'
$script:repoRaw       = 'https://raw.githubusercontent.com/agentia-GIT/Convedrt-FFmpeg/main'
$script:logoUrl       = 'https://raw.githubusercontent.com/agentia-GIT/Convedrt-FFmpeg/main/release/logo.jpg'
$script:ffmpegPageUrl = 'https://www.gyan.dev/ffmpeg/builds/'
$script:ffmpegVerUrl  = 'https://www.gyan.dev/ffmpeg/builds/release-version'
$script:setWin        = $null     # controles de la fenetre Parametres (null si fermee)
$script:updInfo       = $null     # contenu de version.json lu sur GitHub (mise a jour disponible)
$script:ffUpdAvail    = $false    # mise a jour de ffmpeg detectee au demarrage
$script:ffLatest      = $null
$script:quitAfterSettings = $false

# ---------------------------------------------- Reglages memorises (V7c) ----
$script:settingsFile = $null
if ($env:LOCALAPPDATA) { $script:settingsFile = Join-Path $env:LOCALAPPDATA 'Convert-ToHEVC\settings.json' }
function Get-AppSetting([string]$name, $default) {
    try {
        if ($script:settingsFile -and (Test-Path -LiteralPath $script:settingsFile)) {
            $o = Get-Content -LiteralPath $script:settingsFile -Raw -ErrorAction Stop | ConvertFrom-Json
            if ($null -ne $o -and $null -ne $o.$name) { return $o.$name }
        }
    } catch {}
    return $default
}
function Set-AppSetting([string]$name, $value) {
    if (-not $script:settingsFile) { return }
    try {
        $h = @{}
        if (Test-Path -LiteralPath $script:settingsFile) {
            $o = Get-Content -LiteralPath $script:settingsFile -Raw -ErrorAction Stop | ConvertFrom-Json
            if ($o) { foreach ($p in $o.PSObject.Properties) { $h[$p.Name] = $p.Value } }
        }
        $h[$name] = $value
        $dir = Split-Path -Parent $script:settingsFile
        if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
        ($h | ConvertTo-Json) | Set-Content -LiteralPath $script:settingsFile -Encoding ASCII
    } catch {}
}

# ------------------------------------------ Reseau, versions, installation ----
function Get-WebText([string]$url, [int]$timeoutMs = 8000) {
    try {
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        $rq = [Net.HttpWebRequest]::Create($url)
        $rq.Timeout = $timeoutMs; $rq.ReadWriteTimeout = $timeoutMs
        $rq.UserAgent = 'Convert-ToHEVC/' + $script:appVersion
        $rq.Headers.Add('Cache-Control', 'no-cache')
        $rs = $rq.GetResponse()
        try {
            $sr = New-Object System.IO.StreamReader($rs.GetResponseStream(), [Text.Encoding]::UTF8)
            $txt = $sr.ReadToEnd(); $sr.Close()
            return $txt
        } finally { $rs.Close() }
    } catch { return $null }
}

# Date de derniere modification d'un fichier distant (requete HEAD) ou $null
function Get-WebLastModified([string]$url, [int]$timeoutMs = 8000) {
    try {
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        $rq = [Net.HttpWebRequest]::Create($url)
        $rq.Method = 'HEAD'; $rq.Timeout = $timeoutMs
        $rq.UserAgent = 'Convert-ToHEVC/' + $script:appVersion
        $rs = $rq.GetResponse()
        try { return $rs.LastModified } finally { $rs.Close() }
    } catch { return $null }
}

# Telechargement avec barre de progression (l'interface reste reactive)
function Download-File([string]$url, [string]$dest, $bar, $lbl, [string]$what, [int]$timeoutMs = 15000) {
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    $rq = [Net.HttpWebRequest]::Create($url)
    $rq.Timeout = $timeoutMs; $rq.ReadWriteTimeout = [Math]::Max(30000, $timeoutMs)
    $rq.UserAgent = 'Convert-ToHEVC/' + $script:appVersion
    $rs = $rq.GetResponse()
    $total = [double]$rs.ContentLength
    $in = $rs.GetResponseStream()
    $out = New-Object System.IO.FileStream($dest, [System.IO.FileMode]::Create, [System.IO.FileAccess]::Write)
    $done = 0.0
    try {
        $buf = New-Object byte[] 65536
        $stopw = [System.Diagnostics.Stopwatch]::StartNew()
        $lastUi = 0
        while ($true) {
            $n = $in.Read($buf, 0, $buf.Length)
            if ($n -le 0) { break }
            $out.Write($buf, 0, $n)
            $done += $n
            if (($stopw.ElapsedMilliseconds - $lastUi) -ge 120) {
                $lastUi = $stopw.ElapsedMilliseconds
                if ($total -gt 0) {
                    $bar.Value = [int](1000.0 * $done / $total)
                    $lbl.Text = '{0} : {1:0.0} / {2:0.0} Mo' -f $what, ($done / 1MB), ($total / 1MB)
                } else {
                    $lbl.Text = '{0} : {1:0.0} Mo' -f $what, ($done / 1MB)
                }
                [System.Windows.Forms.Application]::DoEvents()
            }
        }
    } finally { $out.Close(); $in.Close(); $rs.Close() }
    if ($total -gt 0 -and $done -ne $total) { throw 'Telechargement incomplet.' }
    $bar.Value = 1000
}

function Test-Sha256([string]$file, [string]$expected) {
    if (-not $expected) { return $true }
    $h = (Get-FileHash -LiteralPath $file -Algorithm SHA256).Hash
    return ($h -ieq $expected.Trim())
}

# Version de l'application : "7", "7a", "7b", "8" ... (V7 < V7a < V7b < V8)
function Parse-AppVersion([string]$t) {
    if ("$t" -match '^\s*[Vv]?(\d+)\s*([a-zA-Z]?)\s*$') {
        return [pscustomobject]@{ Num = [int]$Matches[1]; Suf = $Matches[2].ToLower() }
    }
    return $null
}
function Compare-AppVersion($a, $b) {
    if ($a.Num -ne $b.Num) { return ($a.Num - $b.Num) }
    return [string]::CompareOrdinal($a.Suf, $b.Suf)
}

function Get-FfmpegLocalInfo {
    $raw = $null; $ver = $null; $bdate = $null
    try {
        if ($script:ffmpeg) {
            $psi = New-Object System.Diagnostics.ProcessStartInfo
            $psi.FileName = $script:ffmpeg; $psi.Arguments = '-hide_banner -version'
            $psi.UseShellExecute = $false; $psi.CreateNoWindow = $true; $psi.RedirectStandardOutput = $true
            $p = [System.Diagnostics.Process]::Start($psi)
            $out = $p.StandardOutput.ReadToEnd()
            [void]$p.WaitForExit(3000)
            if ($out -match 'ffmpeg version (\S+)') {
                $raw = $Matches[1]
                if ($raw -match '^[nN]?(\d+(\.\d+){1,3})') { $ver = [version]$Matches[1] }
                elseif ($raw -match '^(\d{4})-(\d{2})-(\d{2})') {
                    try { $bdate = New-Object DateTime ([int]$Matches[1]), ([int]$Matches[2]), ([int]$Matches[3]) } catch { $bdate = $null }
                }
            }
        }
    } catch {}
    return [pscustomobject]@{ Raw = $raw; Ver = $ver; BuildDate = $bdate }
}

# Variante du ffmpeg installe : 'full', 'essentials' ou '' (inconnue, ex. build git)
function Get-FfmpegFlavor($loc) {
    $r = "$($loc.Raw)"
    if ($r -match 'full_build') { return 'full' }
    if ($r -match 'essentials_build') { return 'essentials' }
    if ($r -match '^[nN][-\d]' -or $r -match '-g[0-9a-f]{7,}') { return 'full' }      # builds BtbN (GPL complet)
    return ''
}
function Get-WantedFlavor {
    if ([bool](Get-AppSetting 'ffFull' $true)) { return 'full' }
    return 'essentials'
}
$script:zipSha = ''
# Build complete (GPL : libvmaf, libplacebo...) : gyan.dev ne la publie qu'en .7z, on utilise BtbN (zip, GitHub)
function Parse-FullChecksums([string]$txt) {
    $best = $null
    if ($txt) {
        foreach ($ln in ($txt -split "`n")) {
            if ($ln -match '^([0-9a-fA-F]{64})\s+\*?(ffmpeg-n(\d+\.\d+)-latest-win64-gpl-\3\.zip)\s*$') {
                $v = [version]$Matches[3]
                if (-not $best -or $v -gt $best.Ver) { $best = [pscustomobject]@{ Ver = $v; Name = $Matches[2]; Sha = $Matches[1] } }
            }
        }
    }
    return $best
}
function Get-FullInfo {
    $base = 'https://github.com/BtbN/FFmpeg-Builds/releases/download/latest/'
    $url = $base + 'ffmpeg-master-latest-win64-gpl.zip'; $sha = ''; $ver = $null
    try {
        $best = Parse-FullChecksums (Get-WebText ($base + 'checksums.sha256'))
        if ($best) { $url = $base + $best.Name; $sha = $best.Sha; $ver = $best.Ver }
    } catch {}
    return [pscustomobject]@{ Url = $url; Sha = $sha; Ver = $ver }
}
function Get-FfmpegZipUrl($loc) {
    $script:zipSha = ''
    if ([bool](Get-AppSetting 'ffFull' $true)) {
        $fi = Get-FullInfo
        $script:zipSha = $fi.Sha
        return $fi.Url
    }
    return 'https://www.gyan.dev/ffmpeg/builds/ffmpeg-release-essentials.zip'
}

function Open-Url([string]$url) {
    try { Start-Process $url } catch {
        [System.Windows.Forms.MessageBox]::Show(("Impossible d'ouvrir : {0}" -f $url), 'Convert-ToHEVC', 'OK', 'Warning') | Out-Null
    }
}

# Telecharge la derniere version stable de ffmpeg et remplace / installe ffmpeg, ffprobe, ffplay
# (chaque outil est remplace la ou il se trouve, sinon dans le dossier de l'application).
# Retourne une note (texte) ; leve une exception en cas d'echec (apres retour arriere).
function Install-Ffmpeg([string]$zipUrl, $bar, $lbl) {
    $zip = Join-Path ([IO.Path]::GetTempPath()) ('ffmpeg-release_' + [System.Diagnostics.Process]::GetCurrentProcess().Id + '.zip')
    $plan = @()
    $note = ''
    try {
        Download-File $zipUrl $zip $bar $lbl 'Telechargement de FFmpeg'
        $lbl.Text = 'Verification de l''archive...'
        [System.Windows.Forms.Application]::DoEvents()
        $shaVal = $script:zipSha
        if (-not $shaVal) {
            $sha = Get-WebText ($zipUrl + '.sha256')
            if ($sha -and ($sha.Trim() -match '^([0-9a-fA-F]{64})')) { $shaVal = $Matches[1] }
        }
        if ($shaVal) {
            if (-not (Test-Sha256 $zip $shaVal)) { throw 'Somme de controle SHA-256 incorrecte : archive rejetee.' }
        } else { $note = ' (somme de controle SHA-256 indisponible)' }

        $lbl.Text = 'Extraction...'
        [System.Windows.Forms.Application]::DoEvents()
        if (-not (Test-Path -LiteralPath $script:appDir)) { New-Item -ItemType Directory -Path $script:appDir -Force | Out-Null }
        Add-Type -AssemblyName System.IO.Compression.FileSystem
        $za = [System.IO.Compression.ZipFile]::OpenRead($zip)
        try {
            foreach ($name in @('ffmpeg', 'ffprobe', 'ffplay')) {
                $e = $za.Entries | Where-Object { $_.FullName -like "*/bin/$name.exe" } | Select-Object -First 1
                if (-not $e) {
                    if ($name -eq 'ffplay') { continue }
                    throw "$name.exe introuvable dans l'archive."
                }
                $target = Find-Tool $name
                if (-not $target) { $target = Join-Path $script:appDir "$name.exe" }
                $it = [pscustomobject]@{ Target = $target; New = ($target + '.new'); Old = ($target + '.old') }
                foreach ($stale in @($it.New, $it.Old)) { if (Test-Path -LiteralPath $stale) { Remove-Item -LiteralPath $stale -Force } }
                $plan += $it
                [System.IO.Compression.ZipFileExtensions]::ExtractToFile($e, $it.New, $true)
            }
        } finally { $za.Dispose() }

        $lbl.Text = 'Remplacement des fichiers...'
        [System.Windows.Forms.Application]::DoEvents()
        foreach ($it in $plan) {
            if (Test-Path -LiteralPath $it.Target) { Move-Item -LiteralPath $it.Target -Destination $it.Old -Force }
            Move-Item -LiteralPath $it.New -Destination $it.Target -Force
        }
        foreach ($it in $plan) { Remove-Item -LiteralPath $it.Old -Force -ErrorAction SilentlyContinue }
        return $note
    } catch {
        $msg = $_.Exception.Message
        foreach ($it in $plan) {
            try {
                if (Test-Path -LiteralPath $it.Old) {
                    if (Test-Path -LiteralPath $it.Target) { Remove-Item -LiteralPath $it.Target -Force }
                    Move-Item -LiteralPath $it.Old -Destination $it.Target -Force
                }
                if (Test-Path -LiteralPath $it.New) { Remove-Item -LiteralPath $it.New -Force }
            } catch {}
        }
        throw $msg
    } finally {
        try { if (Test-Path -LiteralPath $zip) { Remove-Item -LiteralPath $zip -Force } } catch {}
    }
}

# logo.jpg : telecharge depuis GitHub s'il manque dans le dossier de l'application (ou si son SHA-256
# differe de celui annonce par version.json). Echec silencieux : le logo integre sert alors de secours.
function Ensure-LogoFile([string]$expectedSha = '', [int]$timeoutMs = 4000) {
    $tmp = $null
    try {
        $dest = Join-Path $script:appDir 'logo.jpg'
        if (Test-Path -LiteralPath $dest -PathType Leaf) {
            if (-not $expectedSha) { return $true }
            if (Test-Sha256 $dest $expectedSha) { return $true }
        }
        $tmp = $dest + '.download'
        $dummy = [pscustomobject]@{ Value = 0; Text = '' }
        Download-File $script:logoUrl $tmp $dummy $dummy 'Logo' $timeoutMs
        $hd = New-Object byte[] 2
        $fs = [System.IO.File]::OpenRead($tmp); [void]$fs.Read($hd, 0, 2); $fs.Close()
        if ($hd[0] -ne 0xFF -or $hd[1] -ne 0xD8) { throw 'Le fichier telecharge n''est pas une image JPEG.' }
        if (-not (Test-Sha256 $tmp $expectedSha)) { throw 'SHA-256 du logo incorrect.' }
        Move-Item -LiteralPath $tmp -Destination $dest -Force
        return $true
    } catch {
        try { if ($tmp -and (Test-Path -LiteralPath $tmp)) { Remove-Item -LiteralPath $tmp -Force } } catch {}
        return $false
    }
}

# Petite fenetre de progression utilisee au demarrage quand ffmpeg est absent
function Install-FfmpegWithDialog {
    $d = New-Object System.Windows.Forms.Form
    $d.Text = 'Convert-ToHEVC - installation de FFmpeg'
    $d.AutoScaleMode = [System.Windows.Forms.AutoScaleMode]::None
    $d.ClientSize = New-Object System.Drawing.Size(480, 110)
    $d.StartPosition = 'CenterScreen'
    $d.FormBorderStyle = 'FixedDialog'
    $d.ControlBox = $false; $d.MaximizeBox = $false; $d.MinimizeBox = $false
    $d.BackColor = [System.Drawing.Color]::White
    $d.Font = New-Object System.Drawing.Font('Arial', 9.5)
    $l = New-Object System.Windows.Forms.Label
    $l.Text = 'Telechargement de FFmpeg...'
    $l.AutoSize = $false; $l.Location = New-Object System.Drawing.Point(20, 18); $l.Size = New-Object System.Drawing.Size(440, 24)
    $d.Controls.Add($l)
    $b = New-Object FlatProgress
    $b.Location = New-Object System.Drawing.Point(20, 56); $b.Size = New-Object System.Drawing.Size(440, 14)
    $b.Minimum = 0; $b.Maximum = 1000
    $d.Controls.Add($b)
    $d.Show()
    [System.Windows.Forms.Application]::DoEvents()
    $ok = $false; $err = ''
    try { [void](Install-Ffmpeg (Get-FfmpegZipUrl $null) $b $l); $ok = $true }
    catch { $err = $_.Exception.Message }
    finally { $d.Close(); $d.Dispose() }
    if (-not $ok) {
        [System.Windows.Forms.MessageBox]::Show(("L'installation de FFmpeg a echoue :`n{0}`n`nTelechargez-le manuellement ({1}) et placez ffmpeg.exe, ffprobe.exe et ffplay.exe dans :`n{2}" -f $err, $script:ffmpegPageUrl, $script:appDir), 'Erreur', 'OK', 'Error') | Out-Null
    }
    return $ok
}

$script:ffmpeg  = Find-Tool 'ffmpeg'
$script:ffprobe = Find-Tool 'ffprobe'

# ffmpeg absent : proposition de telechargement automatique (V7c)
if (-not $script:ffmpeg -or -not $script:ffprobe) {
    $askFf = [System.Windows.Forms.MessageBox]::Show(
        ("ffmpeg.exe / ffprobe.exe introuvables.`n`nTelecharger automatiquement la derniere version stable de FFmpeg (environ 30 a 100 Mo) dans :`n{0} ?" -f $script:appDir),
        'Convert-ToHEVC', 'YesNo', 'Question')
    if ($askFf -eq 'Yes') {
        if (Install-FfmpegWithDialog) {
            $script:ffmpeg  = Find-Tool 'ffmpeg'
            $script:ffprobe = Find-Tool 'ffprobe'
        }
    }
    if (-not $script:ffmpeg -or -not $script:ffprobe) {
        if ($askFf -ne 'Yes') {
            [System.Windows.Forms.MessageBox]::Show(
                "ffmpeg.exe / ffprobe.exe introuvables.`nAjoutez-les au PATH ou placez-les dans le dossier de l'application.",
                'Erreur', 'OK', 'Error') | Out-Null
        }
        exit 1
    }
}

function Q([string]$s) { '"' + $s + '"' }


# ---------------------------------------------------------------- Journal ---
$script:logFile = $null
function Write-Log([string]$level, [string]$msg) {
    if (-not $script:logFile) { return }
    $line = '{0} [{1}] {2}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $level, $msg
    try { Add-Content -LiteralPath $script:logFile -Value $line -Encoding UTF8 } catch {}
}

# ------------------------------------------------- Part de processeur -------
$script:logical = [Environment]::ProcessorCount
$script:cpuPct = 50
$script:threads = 1
$script:affinity = $null
function Set-Cpu([int]$pct) {
    $script:cpuPct = $pct
    $t = [int][Math]::Floor($script:logical * $pct / 100.0 + 0.5)
    $t = [Math]::Max(1, [Math]::Min($t, $script:logical))
    $script:threads = $t
    if ($t -ge $script:logical -or $script:logical -gt 62) { $script:affinity = $null }
    else { $script:affinity = [int64]([Math]::Pow(2, $t) - 1) }
}
Set-Cpu 50

# Upscaling 1080p : cadre maximal et qualite constante (a ajuster ici si besoin)
$script:upW   = 1920     # largeur maximale de sortie
$script:upH   = 1080     # hauteur maximale de sortie
$script:upCrf = 18       # x265 (CPU) : plus bas = meilleure qualite (18 = quasi transparent)
$script:upCq  = 19       # NVENC (-cq) et Quick Sync (-global_quality)
$script:sizeRatio = 1.8   # taille finale = original / 1,8 (debit video cible)
$script:autoSharp = 0.25  # nettete automatique (filtre cas, 0 a 1) ajoutee apres un upscaling
$script:twoPassBpp = 0.08  # 2 passes + upscaling : bits par pixel et par image (haute qualite HEVC)

# Detection NVIDIA : test d'encodage reel avec hevc_nvenc
$script:nvProbeErr = ''
$script:qsvProbeErr = ''
function Test-Nvenc {
    try {
        $ok = Test-EncCap '-c:v hevc_nvenc'
        if (-not $ok) { $script:nvProbeErr = "$($script:capErr)" } else { $script:nvProbeErr = '' }
        return $ok
    } catch { $script:nvProbeErr = $_.Exception.Message; return $false }
}
$script:nvDriver = ''
function Get-NvidiaName {
    try {
        $g = Get-CimInstance Win32_VideoController -ErrorAction Stop | Where-Object { $_.Name -match 'NVIDIA' } | Select-Object -First 1
        if ($g) {
            # DriverVersion Windows "31.0.15.5123" -> numero NVIDIA "551.23"
            try {
                $d = ("$($g.DriverVersion)" -replace '\.', '')
                if ($d.Length -ge 5) { $t5 = $d.Substring($d.Length - 5); $script:nvDriver = ('{0}.{1}' -f $t5.Substring(0, 3), $t5.Substring(3)) }
            } catch {}
            return $g.Name
        }
    } catch {}
    return $null
}

# Detection Intel Quick Sync : test d'encodage reel avec hevc_qsv
function Test-Qsv {
    try {
        $ok = Test-EncCap '-vf format=nv12 -c:v hevc_qsv'
        if (-not $ok) { $script:qsvProbeErr = "$($script:capErr)" } else { $script:qsvProbeErr = '' }
        return $ok
    } catch { $script:qsvProbeErr = $_.Exception.Message; return $false }
}
function Get-IntelName {
    try {
        $g = Get-CimInstance Win32_VideoController -ErrorAction Stop | Where-Object { $_.Name -match 'Intel' } | Select-Object -First 1
        if ($g) { return $g.Name }
    } catch {}
    return $null
}

# Encodeur choisi : 'nvenc' (NVIDIA), 'qsv' (Intel) ou 'cpu'. NVIDIA est prioritaire.
function Get-EncoderMode {
    if ($chkNv.Checked) { return 'nvenc' }
    if ($chkIntel.Checked) { return 'qsv' }
    return 'cpu'
}


# Analyse ffprobe d'un fichier (resultat JSON mis en cache dans la file)
function Get-Info([string]$f) {
    try {
        $json = & $script:ffprobe -v error -print_format json -show_streams -show_format $f 2>$null | Out-String
        return ($json | ConvertFrom-Json)
    } catch { return $null }
}


# ----------------------------------------- Etiquettes de couleur (V7) -------
function Clean-Tag($t) {
    $x = "$t".Trim().ToLower()
    if (-not $x -or $x -in @('unknown', 'unspecified', 'reserved', 'n/a')) { return '' }
    return $x
}

# Lit les etiquettes de la source. Source sans etiquette : valeurs que les lecteurs supposent
# (SD = BT.601 / smpte170m, HD = BT.709) pour que l'affichage reste identique.
function Get-ColorTags($v) {
    $w = 0; $h = 0
    [void][int]::TryParse("$($v.width)", [ref]$w); [void][int]::TryParse("$($v.height)", [ref]$h)
    $sd = ($w -le 1024 -and $h -le 576)
    $def = if ($sd) { 'smpte170m' } else { 'bt709' }
    $yuvj = ("$($v.pix_fmt)" -match '^yuvj')
    $range = Clean-Tag $v.color_range
    if ($yuvj) { $range = '' } elseif (-not $range) { $range = 'tv' }
    $space = Clean-Tag $v.color_space
    $trc   = Clean-Tag $v.color_transfer
    $prim  = Clean-Tag $v.color_primaries
    $tagged = [bool]($space -or $trc -or $prim)
    if (-not $space) { $space = $def }
    if (-not $trc)   { $trc = $def }
    if (-not $prim)  { $prim = $(if ($space -like 'bt2020*') { 'bt2020' } else { $def }) }
    $hdr = ($trc -eq 'smpte2084' -or $trc -eq 'arib-std-b67')
    return [pscustomobject]@{ Range = $range; Space = $space; Trc = $trc; Prim = $prim; Hdr = $hdr; Tagged = $tagged }
}

function Frac-Val($s, [double]$unit) {
    $p = "$s".Split('/')
    if ($p.Count -eq 2) {
        $n = [double]::Parse($p[0], $inv); $d = [double]::Parse($p[1], $inv)
        if ($d -ne 0) { return [int][Math]::Round($n / $d * $unit) }
    }
    return [int][Math]::Round([double]::Parse("$s", $inv) * $unit)
}

# Metadonnees HDR10 (master-display, max-cll) lues sur la premiere image
$script:hdrCache = @{}
function Get-HdrParams([string]$src) {
    if ($script:hdrCache.ContainsKey($src)) { return $script:hdrCache[$src] }
    $res = [pscustomobject]@{ Master = ''; Cll = '' }
    try {
        $json = & $script:ffprobe -v error -select_streams v:0 -read_intervals '%+#1' -show_frames `
            -show_entries frame=side_data_list -print_format json $src 2>$null | Out-String
        $o = $json | ConvertFrom-Json
        foreach ($sd in @($o.frames[0].side_data_list)) {
            if ($sd.side_data_type -eq 'Mastering display metadata') {
                $res.Master = 'G({0},{1})B({2},{3})R({4},{5})WP({6},{7})L({8},{9})' -f `
                    (Frac-Val $sd.green_x 50000), (Frac-Val $sd.green_y 50000), (Frac-Val $sd.blue_x 50000), (Frac-Val $sd.blue_y 50000), `
                    (Frac-Val $sd.red_x 50000), (Frac-Val $sd.red_y 50000), (Frac-Val $sd.white_point_x 50000), (Frac-Val $sd.white_point_y 50000), `
                    (Frac-Val $sd.max_luminance 10000), (Frac-Val $sd.min_luminance 10000)
            }
            if ($sd.side_data_type -eq 'Content light level metadata') {
                $res.Cll = '{0},{1}' -f $sd.max_content, $sd.max_average
            }
        }
    } catch {}
    $script:hdrCache[$src] = $res
    return $res
}

# Controle apres encodage : les etiquettes ecrites doivent etre celles attendues. Retourne '' si OK.
function Test-ColorTags([string]$path, $col) {
    try {
        $json = & $script:ffprobe -v error -select_streams v:0 -print_format json -show_streams $path 2>$null | Out-String
        $o = ($json | ConvertFrom-Json).streams[0]
        $diff = @()
        if ($col.Range -and (Clean-Tag $o.color_range) -ne $col.Range) { $diff += "plage attendue $($col.Range) obtenue $($o.color_range)" }
        if ((Clean-Tag $o.color_space) -ne $col.Space)     { $diff += "matrice attendue $($col.Space) obtenue $($o.color_space)" }
        if ((Clean-Tag $o.color_transfer) -ne $col.Trc)    { $diff += "transfert attendu $($col.Trc) obtenu $($o.color_transfer)" }
        if ((Clean-Tag $o.color_primaries) -ne $col.Prim)  { $diff += "primaires attendues $($col.Prim) obtenues $($o.color_primaries)" }
        return ($diff -join ' ; ')
    } catch { return "controle impossible : $($_.Exception.Message)" }
}

# ------------------------------------------- Reglages image (V7) ------------
# Reglages de la fenetre d'apercu : n'agissent sur la conversion qu'apres validation.
$script:imgWork = @{ Bright = 0; Contrast = 100; Sat = 100; Gamma = 100; Sharp = 0; Depix = 0 }
$script:imgValidated = $null
$script:imgOn = $false

function Fmt-Num([double]$x) { return $x.ToString('0.####', $inv) }
function Test-ImgDefault($s) {
    return ($s.Bright -eq 0 -and $s.Contrast -eq 100 -and $s.Sat -eq 100 -and $s.Gamma -eq 100 -and $s.Sharp -eq 0 -and $s.Depix -eq 0)
}
function Get-StreamBits($info) {
    try {
        $vs = @($info.streams | Where-Object { $_.codec_type -eq 'video' })
        if ($vs.Count -gt 0) {
            if ("$($vs[0].pix_fmt)" -match '12') { return 12 }
            if ("$($vs[0].pix_fmt)" -match '10') { return 10 }
        }
    } catch {}
    return 8
}

# Filtres ffmpeg des reglages. Pre = avant mise a l'echelle (depixelisation), Post = apres
# (luminosite/contraste/gamma/saturation via lutyuv, qui conserve la profondeur 8 ou 10 bits, et nettete cas).
function Get-ImageFilter($set, [int]$bits, [bool]$upscaled, [bool]$full = $false) {
    $pre = @(); $post = @(); $sharp = 0.0
    if ($set) {
        $m = [double]((1 -shl $bits) - 1); $mid = ($m + 1) / 2
        $kk = [Math]::Pow(2, $bits - 8)
        if ($full) { $yLo = 0.0; $yHi = $m; $cHi = $m } else { $yLo = 16.0 * $kk; $yHi = 235.0 * $kk; $cHi = 240.0 * $kk }
        $b = [double]$set.Bright / 100.0; $c = [double]$set.Contrast / 100.0
        $g = [double]$set.Gamma / 100.0;  $sa = [double]$set.Sat / 100.0
        $parts = @()
        if ($set.Bright -ne 0 -or $set.Contrast -ne 100 -or $set.Gamma -ne 100) {
            $parts += ("y='clip((pow(val/{0},{1})*{0}-{2})*{3}+{2}+{4},{5},{6})'" -f (Fmt-Num $m), (Fmt-Num (1.0 / $g)), (Fmt-Num $mid), (Fmt-Num $c), (Fmt-Num ($b * $m)), (Fmt-Num $yLo), (Fmt-Num $yHi))
        }
        if ($set.Sat -ne 100) {
            $e = ("clip((val-{0})*{1}+{0},{3},{2})" -f (Fmt-Num $mid), (Fmt-Num $sa), (Fmt-Num $cHi), (Fmt-Num $yLo))
            $parts += "u='$e'"; $parts += "v='$e'"
        }
        if ($parts.Count -gt 0) {
            if ($bits -ge 10) { $post += "format=yuv420p${bits}le" }
            $post += ('lutyuv=' + ($parts -join ':'))
        }
        switch ([int]$set.Depix) {
            1 { $pre += 'deblock=filter=weak:block=8' }
            2 { $pre += 'deblock=filter=strong:block=8' }
            3 { $pre += 'deblock=filter=strong:block=8'; $pre += 'hqdn3d=1.5:1.5:3:3' }
        }
        $sharp = [double]$set.Sharp / 10.0
    }
    if ($upscaled) { $sharp = [Math]::Min(1.0, $sharp + $script:autoSharp) }
    if ($sharp -gt 0) { $post += ('cas=strength=' + (Fmt-Num $sharp)) }
    return [pscustomobject]@{ Pre = ($pre -join ','); Post = ($post -join ',') }
}

function Format-ImgSummary($s) {
    return ('luminosite {0:+0;-0;0}, contraste {1}, saturation {2}, gamma {3}, nettete {4}, depixelisation {5}' -f $s.Bright, $s.Contrast, $s.Sat, $s.Gamma, $s.Sharp, $s.Depix)
}


# ------------------------- Comparaison original / sortie avant compression ---
$script:cmpOn = $true
$script:analyzing = $false
$script:sampleLen = 3.0     # duree de chaque echantillon (secondes)

# Filtre de correction : decalages en unites 8 bits (Y, U, V) ajoutes avant encodage
function Get-CorrFilter($corr, [int]$bits, [bool]$full = $false) {
    if (-not $corr) { return '' }
    $k = [Math]::Pow(2, $bits - 8); $m = (1 -shl $bits) - 1
    $lo = $(if ($full) { 0 } else { [int](16 * $k) })
    $p = @()
    foreach ($c in @(@('y', 'Y'), @('u', 'U'), @('v', 'V'))) {
        $o = [double]$corr[$c[1]]
        if ([Math]::Abs($o) -ge 0.01) {
            $hi = $(if ($full) { $m } elseif ($c[0] -eq 'y') { [int](235 * $k) } else { [int](240 * $k) })
            $p += ("{0}='clip(val+{1},{3},{2})'" -f $c[0], (Fmt-Num ($o * $k)), $hi, $lo)
        }
    }
    if ($p.Count -eq 0) { return '' }
    $pre = $(if ($bits -ge 10) { "format=yuv420p${bits}le," } else { '' })
    return $pre + 'lutyuv=' + ($p -join ':')
}

# Lance ffmpeg en masquant la fenetre, sans bloquer l'interface. Retourne le code de sortie (-1 si inconnu).
function Run-Ffmpeg([string]$argString, [string]$errPath) {
    $p = Start-Process -FilePath $script:ffmpeg -ArgumentList $argString -WorkingDirectory $env:TEMP `
        -WindowStyle Hidden -PassThru -RedirectStandardError $errPath
    $null = $p.Handle
    if ($null -ne $script:affinity) { try { $p.ProcessorAffinity = [IntPtr]$script:affinity } catch {} }
    $sw = [Diagnostics.Stopwatch]::StartNew()
    while (-not $p.HasExited) {
        [System.Windows.Forms.Application]::DoEvents()
        if ($script:cancelled -or $sw.Elapsed.TotalSeconds -gt 900) { try { $p.Kill() } catch {}; break }
        Start-Sleep -Milliseconds 60
    }
    try { $p.WaitForExit() } catch {}
    $code = $p.ExitCode
    if ($null -eq $code) { return -1 }
    return [int]$code
}

# Moyennes Y, U, V (echelle 8 bits) d'une video ou d'un extrait, apres filtres eventuels
function Measure-Stats([string]$file, [double]$ss, [double]$len, [string]$vf, [int]$mapIndex) {
    $err = Join-Path $env:TEMP ('ffm_{0}.txt' -f [guid]::NewGuid().ToString('N'))
    $chain = @()
    if ($vf) { $chain += $vf }
    $chain += 'format=yuv420p'; $chain += 'signalstats'; $chain += 'metadata=print'
    $a = '-hide_banner -nostats -loglevel info'
    if ($ss -ge 0 -and $len -gt 0) { $a += (' -ss {0} -t {1}' -f $ss.ToString('0.###', $inv), $len.ToString('0.###', $inv)) }
    $a += ' -i ' + (Q $file) + ' -map 0:' + $mapIndex + ' -an -sn -vf ' + (Q ($chain -join ',')) + ' -f null -'
    $res = @{}
    try {
        [void](Run-Ffmpeg $a $err)
        $txt = ''
        if (Test-Path -LiteralPath $err) { $txt = [IO.File]::ReadAllText($err) }
        foreach ($k in @('YAVG', 'UAVG', 'VAVG')) {
            $mm = [regex]::Matches($txt, 'lavfi\.signalstats\.' + $k + '=([0-9.]+)')
            if ($mm.Count -gt 0) {
                $sum = 0.0
                foreach ($x in $mm) { $sum += [double]::Parse($x.Groups[1].Value, $inv) }
                $res[$k] = $sum / $mm.Count
            }
        }
    } finally { Remove-Item -LiteralPath $err -Force -ErrorAction SilentlyContinue }
    if ($res.Count -lt 3) { return $null }
    return $res
}

# Positions des echantillons (debut, duree)
function Get-SamplePoints([double]$dur) {
    $len = $script:sampleLen
    if ($dur -ge 30) { return @{ Len = $len; Pos = @(($dur * 0.2), ($dur * 0.5), ($dur * 0.8)) } }
    if ($dur -ge 8)  { return @{ Len = $len; Pos = @(([Math]::Max(0.0, $dur / 2 - $len / 2))) } }
    return @{ Len = [Math]::Max(1.0, [Math]::Floor($dur)); Pos = @(0.0) }
}

# Encode de courts extraits avec les memes reglages que la conversion, puis compare
# l'original (apres les memes filtres) et la sortie : ecarts moyens Y/U/V (echelle 8 bits).
# Si l'ecart depasse 0,5 niveau, une correction opposee est calculee pour l'encodage final.
function Get-ColorCorrection($item, $info, [string]$mode, [bool]$up, $an = $null, [double]$qo = -1.0) {
    $dur = [double]$item.Duration
    if ($dur -le 0) { return $null }
    $pts = Get-SamplePoints $dur
    $len = [double]$pts.Len
    $sumY = 0.0; $sumU = 0.0; $sumV = 0.0; $n = 0
    foreach ($pos0 in $pts.Pos) {
        if ($script:cancelled) { break }
        $pos = [Math]::Max(0.0, [Math]::Min([double]$pos0, $dur - $len - 0.2))
        $id = [guid]::NewGuid().ToString('N')
        $sfile = Join-Path $env:TEMP ("ffsample_{0}.mkv" -f $id)
        $serr  = Join-Path $env:TEMP ("ffsample_{0}.err" -f $id)
        $sprog = Join-Path $env:TEMP ("ffprog_{0}.txt" -f $id)
        try {
            $sp = Build-FfmpegArgs $info $item.Path $sfile $sprog $mode $up $false $null $pos $len $an $qo
            $code = Run-Ffmpeg $sp.Args $serr
            if ($code -ne 0 -or -not (Test-Path -LiteralPath $sfile)) { continue }
            $ref = Measure-Stats $item.Path $pos $len $sp.Vf $sp.MapIndex
            $enc = Measure-Stats $sfile -1.0 0.0 '' 0
            if ($ref -and $enc) {
                $sumY += ($ref.YAVG - $enc.YAVG); $sumU += ($ref.UAVG - $enc.UAVG); $sumV += ($ref.VAVG - $enc.VAVG); $n++
            }
        } catch {
        } finally {
            Remove-Item -LiteralPath $sfile, $serr, $sprog -Force -ErrorAction SilentlyContinue
        }
    }
    if ($n -eq 0) { return $null }
    $dY = $sumY / $n; $dU = $sumU / $n; $dV = $sumV / $n
    $corr = $null
    if ([Math]::Abs($dY) -ge 0.5 -or [Math]::Abs($dU) -ge 0.5 -or [Math]::Abs($dV) -ge 0.5) {
        $cap = { param($x) [Math]::Round([Math]::Max(-10.0, [Math]::Min(10.0, $x)), 2) }
        $corr = @{ Y = (& $cap $dY); U = (& $cap $dU); V = (& $cap $dV) }
        foreach ($k in @('Y', 'U', 'V')) { if ([Math]::Abs($corr[$k]) -lt 0.5) { $corr[$k] = 0.0 } }
    }
    return [pscustomobject]@{ dY = $dY; dU = $dU; dV = $dV; N = $n; Corr = $corr }
}

# Controle final : meme comparaison sur le fichier produit. Retourne un message si l'ecart est trop grand.
function Test-FinalQuality($item, $plan, [string]$tag) {
    try {
        $dur = [double]$item.Duration
        if ($dur -le 0) { return '' }
        $pts = Get-SamplePoints $dur
        $len = [double]$pts.Len
        $pos = [Math]::Max(0.0, [Math]::Min([double]$pts.Pos[[int][Math]::Floor($pts.Pos.Count / 2)], $dur - $len - 0.2))
        $ref = Measure-Stats $item.Path $pos $len $plan.VfBase $plan.MapIndex
        $enc = Measure-Stats $script:dst $pos $len '' 0
        if (-not $ref -or -not $enc) { Write-Log 'AVERT' "$tag Controle final des couleurs impossible (mesure indisponible)"; return '' }
        $dY = $ref.YAVG - $enc.YAVG; $dU = $ref.UAVG - $enc.UAVG; $dV = $ref.VAVG - $enc.VAVG
        Write-Log 'INFO' ('{0} Controle final original / sortie : ecart luminosite {1:+0.0;-0.0;0.0}, bleu {2:+0.0;-0.0;0.0}, rouge {3:+0.0;-0.0;0.0} (echelle 0-255)' -f $tag, $dY, $dU, $dV)
        if ([Math]::Abs($dY) -gt 3 -or [Math]::Abs($dU) -gt 3 -or [Math]::Abs($dV) -gt 3) {
            return ('ecart de couleur ou de luminosite apres encodage (Y {0:+0.0;-0.0;0.0}, U {1:+0.0;-0.0;0.0}, V {2:+0.0;-0.0;0.0})' -f $dY, $dU, $dV)
        }
    } catch { Write-Log 'AVERT' "$tag Controle final impossible : $($_.Exception.Message)" }
    return ''
}

# ------------------------------------------- Construction ligne ffmpeg ------
# $info = $null -> ligne d'exemple (aucune video dans la file)
# ================================================================ V8 : analyse et qualite automatique
# Options (3 etats : auto / on / off), profil de qualite, mode de qualite.
$script:v8 = @{
    Profile = 'equilibre'     # rapide | equilibre | archivage
    QMode   = 'auto'          # auto (recherche VMAF/SSIM) | fixe | debit (cible par codec)
    Opt     = @{
        Deint = 'auto'; Ivtc = 'auto'; Crop = 'auto'; Deblock = 'auto'; Denoise = 'auto'; Deband = 'auto'
        Levels = 'auto'; Tenbit = 'auto'; Matrix = 'auto'; Placebo = 'off'; SkipHevc = 'auto'
        Audio = 'auto'; Chapters = 'on'; Score = 'on'
    }
}
# Capacites detectees au demarrage (filtres et encodeurs) : chaque fonction avancee a un repli.
$script:caps = @{ NvErr = ''; NvBase = $true; NvBref = $false; Vmaf = $false; Placebo = $false; PlaceboOk = $false; NvAdv = $false; Nv10 = $true; QsvAdv = $false; QsvIcq = $true; Qsv10 = $true; Probed = $false }
$script:analysis = @{}        # chemin -> analyse de la video
$script:searchMode = $false   # vrai pendant la recherche de qualite (preset plus rapide)

function Get-V8Profile {
    switch ($script:v8.Profile) {
        'rapide'    { return @{ Name = 'rapide';    CpuPreset = 'medium'; NvPreset = 'p5'; QsvPreset = 'medium'; Vmaf = 93.0; Ssim = 0.980; Crf = 22; Cq = 24; Gq = 22; ForceCpu = $false } }
        'archivage' { return @{ Name = 'archivage'; CpuPreset = 'slower'; NvPreset = 'p7'; QsvPreset = 'slow';   Vmaf = 96.5; Ssim = 0.992; Crf = 18; Cq = 19; Gq = 19; ForceCpu = $true } }
        default     { return @{ Name = 'equilibre'; CpuPreset = 'slow';   NvPreset = 'p7'; QsvPreset = 'slow';   Vmaf = 95.0; Ssim = 0.987; Crf = 20; Cq = 22; Gq = 20; ForceCpu = $false } }
    }
}

# Encodeur reellement utilise : l'archivage impose x265 (CPU), les sources HDR aussi.
function Resolve-Mode([string]$mode, $hdr) {
    $P = Get-V8Profile
    if ($P.ForceCpu -or $hdr) { return 'cpu' }
    return $mode
}

function Test-Opt([string]$name, [bool]$autoValue) {
    switch ("$($script:v8.Opt[$name])") {
        'on'  { return $true }
        'off' { return $false }
        default { return $autoValue }
    }
}

function Get-Fps($v) {
    $fps = 0.0
    foreach ($k in @('avg_frame_rate', 'r_frame_rate')) {
        if ("$($v.$k)" -match '^(\d+)/(\d+)$') {
            $n = [double]$Matches[1]; $d = [double]$Matches[2]
            if ($n -gt 0 -and $d -gt 0) { $fps = $n / $d; break }
        }
    }
    if ($fps -le 0) { $fps = 25.0 }
    return $fps
}

# Debit video d'origine (bits/s) : flux, sinon tag BPS, sinon total - audio
function Get-VideoBitrate($info, $v, $audio) {
    $vbr = 0.0
    if ($v.bit_rate -and $v.bit_rate -ne 'N/A') { $vbr = [double]::Parse("$($v.bit_rate)", $inv) }
    elseif ($v.tags.BPS)                        { $vbr = [double]::Parse("$($v.tags.BPS)", $inv) }
    else {
        $total = 0.0
        if ($info.format.bit_rate) { $total = [double]::Parse("$($info.format.bit_rate)", $inv) }
        $abr = 0.0
        foreach ($a in $audio) { if ($a.bit_rate) { $abr += [double]::Parse("$($a.bit_rate)", $inv) } }
        $vbr = [Math]::Max($total - $abr, 500000)
    }
    return $vbr
}

# Efficacite relative du codec source (bits necessaires pour une meme qualite, H.264 = 1)
function Get-CodecEff([string]$c) {
    switch -regex ($c) {
        '^mpeg1video$'                 { return 0.30 }
        '^mpeg2video$'                 { return 0.35 }
        '^mpeg4$'                      { return 0.60 }
        '^(msmpeg4.*|wmv1|wmv2)$'      { return 0.50 }
        '^(wmv3|vc1)$'                 { return 0.85 }
        '^h264$'                       { return 1.00 }
        '^hevc$'                       { return 1.70 }
        '^vp9$'                        { return 1.60 }
        '^av1$'                        { return 2.00 }
        default                        { return 0.80 }
    }
}
# Rapport de debit cible (mode "Debit cible par codec") : original / ratio
function Get-CodecRatio([string]$c) {
    switch -regex ($c) {
        '^mpeg1video$'                 { return 3.5 }
        '^mpeg2video$'                 { return 3.2 }
        '^(mpeg4|msmpeg4.*)$'          { return 2.6 }
        '^(wmv.*|vc1)$'                { return 2.2 }
        '^h264$'                       { return 1.8 }
        '^vp8$'                        { return 1.6 }
        '^vp9$'                        { return 1.2 }
        '^av1$'                        { return 1.0 }
        '^hevc$'                       { return 1.3 }
        default                        { return 2.0 }
    }
}

# Analyse statique (ffprobe seulement) : instantanee, utilisee aussi pour la commande affichee
function Get-StaticAnalysis($info) {
    $a = [pscustomobject]@{
        Codec = ''; W = 0; H = 0; Fps = 25.0; Vbr = 0.0; Bits = 8; Bpp = 0.0; Ebpp = 0.0; Level = 0
        Sd = $false; Std = ''; Hdr = $false; Interlaced = $false; Telecine = $false; IdetPct = -1.0
        Crop = ''; CropNote = ''; Black = -1.0; White = -1.0; Deep = $false; Report = ''; FieldOrder = ''
    }
    try {
        $video = @($info.streams | Where-Object { $_.codec_type -eq 'video' -and $_.disposition.attached_pic -ne 1 })
        $audio = @($info.streams | Where-Object { $_.codec_type -eq 'audio' })
        if ($video.Count -eq 0) { return $a }
        $v = $video[0]
        $a.Codec = "$($v.codec_name)"
        $a.W = [int]$v.width; $a.H = [int]$v.height
        $a.Fps = Get-Fps $v
        $a.Bits = Get-StreamBits $info
        $a.Vbr = Get-VideoBitrate $info $v $audio
        $col = Get-ColorTags $v
        $a.Hdr = [bool]$col.Hdr
        $a.Sd = ($a.W -le 1024 -and $a.H -le 576)
        # 625 lignes (PAL) ou 525 lignes (NTSC) : la hauteur fait foi, les etiquettes SD sont souvent approximatives
        if ("$($col.Space)" -match '470bg' -or $a.H -ge 540) { $a.Std = '625' } else { $a.Std = '525' }
        if ($a.W -gt 0 -and $a.H -gt 0) { $a.Bpp = $a.Vbr / ($a.W * $a.H * $a.Fps) }
        $a.Ebpp = $a.Bpp / (Get-CodecEff $a.Codec)
        if     ($a.Ebpp -ge 0.12) { $a.Level = 0 }
        elseif ($a.Ebpp -ge 0.08) { $a.Level = 1 }
        elseif ($a.Ebpp -ge 0.05) { $a.Level = 2 }
        else                      { $a.Level = 3 }
        $a.FieldOrder = "$($v.field_order)"
        $a.Interlaced = ($a.FieldOrder -in @('tt', 'bb', 'tb', 'bt'))
    } catch {}
    return $a
}

# Texte du rapport d'analyse (une ligne par video)
function Format-Analysis($a) {
    if ($a.W -le 0) { return 'analyse indisponible' }
    $p = @()
    $p += ('{0} {1}x{2} {3:0.###} i/s, {4:0} kb/s, {5:0.000} bits/pixel (equivalent H.264 {6:0.000}) -> niveau d''artefacts {7}/3' -f $a.Codec, $a.W, $a.H, $a.Fps, ($a.Vbr / 1000), $a.Bpp, $a.Ebpp, $a.Level)
    if ($a.Deep) {
        if ($a.Telecine) { $p += 'telecine 3:2 detecte (IVTC)' }
        elseif ($a.Interlaced) { $p += ('entrelace ({0:0} % des images)' -f $a.IdetPct) }
        else { $p += 'progressif' }
        if ($a.Crop) { $p += ('bandes noires : recadrage {0}' -f $a.CropNote) } else { $p += 'pas de bandes noires' }
        if ($a.Black -ge 0) { $p += ('niveaux Y {0:0}-{1:0}' -f $a.Black, $a.White) }
    } else {
        $p += $(if ($a.Interlaced) { 'entrelace (indicateur du fichier)' } else { 'progressif (analyse detaillee a la conversion)' })
    }
    if ($a.Hdr) { $p += 'HDR' }
    return ($p -join ' | ')
}

# Analyse approfondie : idet (entrelacement/telecine), cropdetect (bandes noires), signalstats (niveaux)
function Get-VideoAnalysis($item, $info) {
    $key = $item.Path
    if ($script:analysis.ContainsKey($key) -and $script:analysis[$key].Deep) { return $script:analysis[$key] }
    $a = Get-StaticAnalysis $info
    $script:analysis[$key] = $a
    $dur = [double]$item.Duration
    if ($dur -le 0 -or $a.W -le 0) { return $a }
    $vs = @($info.streams | Where-Object { $_.codec_type -eq 'video' -and $_.disposition.attached_pic -ne 1 })
    $mapIdx = [int]$vs[0].index
    $pts = Get-SamplePoints $dur
    $win = [Math]::Min(4.0, [double]$pts.Len + 1.0)
    $tff = 0.0; $bff = 0.0; $prg = 0.0; $repN = 0.0; $repT = 0.0
    $x1 = 99999; $y1 = 99999; $x2 = 0; $y2 = 0; $nCrop = 0
    $ymin = 9999.0; $ymax = -1.0
    $k8 = [Math]::Pow(2, $a.Bits - 8)
    foreach ($pos0 in $pts.Pos) {
        if ($script:cancelled) { break }
        $pos = [Math]::Max(0.0, [Math]::Min([double]$pos0, $dur - $win - 0.2))
        $err = Join-Path $env:TEMP ('ffan_{0}.txt' -f [guid]::NewGuid().ToString('N'))
        $chain = 'idet,cropdetect=limit=24:round=2:reset=0,signalstats,metadata=print'
        $arg = '-hide_banner -nostats -loglevel info -ss {0} -t {1} -i {2} -map 0:{3} -an -sn -vf {4} -f null -' -f `
            $pos.ToString('0.###', $inv), $win.ToString('0.###', $inv), (Q $item.Path), $mapIdx, (Q $chain)
        try {
            [void](Run-Ffmpeg $arg $err)
            $txt = ''
            if (Test-Path -LiteralPath $err) { $txt = [IO.File]::ReadAllText($err) }
            # idet ecrit un premier bilan vide puis le bilan final : on retient le dernier
            $mAll = [regex]::Matches($txt, 'Multi frame detection:\s*TFF:\s*(\d+)\s*BFF:\s*(\d+)\s*Progressive:\s*(\d+)')
            if ($mAll.Count -gt 0) {
                $m = $mAll[$mAll.Count - 1]
                $tff += [double]$m.Groups[1].Value; $bff += [double]$m.Groups[2].Value; $prg += [double]$m.Groups[3].Value
            }
            $rAll = [regex]::Matches($txt, 'Repeated Fields:\s*Neither:\s*(\d+)\s*Top:\s*(\d+)\s*Bottom:\s*(\d+)')
            if ($rAll.Count -gt 0) {
                $r = $rAll[$rAll.Count - 1]
                $repN += [double]$r.Groups[1].Value; $repT += [double]$r.Groups[2].Value + [double]$r.Groups[3].Value
            }
            $cm = [regex]::Matches($txt, 'crop=(\d+):(\d+):(\d+):(\d+)')
            if ($cm.Count -gt 0) {
                $c = $cm[$cm.Count - 1]
                $cw = [int]$c.Groups[1].Value; $ch = [int]$c.Groups[2].Value; $cx = [int]$c.Groups[3].Value; $cy = [int]$c.Groups[4].Value
                if ($cx -lt $x1) { $x1 = $cx }
                if ($cy -lt $y1) { $y1 = $cy }
                if (($cx + $cw) -gt $x2) { $x2 = $cx + $cw }
                if (($cy + $ch) -gt $y2) { $y2 = $cy + $ch }
                $nCrop++
            }
            foreach ($mm in [regex]::Matches($txt, 'lavfi\.signalstats\.YMIN=([0-9.]+)')) {
                $y = [double]::Parse($mm.Groups[1].Value, $inv) / $k8
                if ($y -lt $ymin) { $ymin = $y }
            }
            foreach ($mm in [regex]::Matches($txt, 'lavfi\.signalstats\.YMAX=([0-9.]+)')) {
                $y = [double]::Parse($mm.Groups[1].Value, $inv) / $k8
                if ($y -gt $ymax) { $ymax = $y }
            }
        } catch {
        } finally { Remove-Item -LiteralPath $err -Force -ErrorAction SilentlyContinue }
    }
    $tot = $tff + $bff + $prg
    if ($tot -ge 20) {
        $frac = ($tff + $bff) / $tot
        $a.IdetPct = [Math]::Round($frac * 100.0, 1)
        $ntsc = ($a.Fps -ge 29.9 -and $a.Fps -le 30.1)
        $rep = 0.0
        if (($repN + $repT) -gt 0) { $rep = $repT / ($repN + $repT) }
        # telecine 3:2 : champs repetes (~40 % des images) ou melange entrelace/progressif a 29,97 i/s
        if ($ntsc -and ($rep -ge 0.25 -or ($frac -ge 0.35 -and $frac -le 0.85 -and ($prg / $tot) -ge 0.15))) { $a.Telecine = $true; $a.Interlaced = $false }
        else {
            # seuil selon l'indicateur du fichier : un flux marque progressif exige une quasi-certitude
            $thr = 0.75
            if ($a.FieldOrder -in @('tt', 'bb', 'tb', 'bt')) { $thr = 0.5 } elseif ($a.FieldOrder -eq 'progressive') { $thr = 0.9 }
            $a.Interlaced = ($frac -ge $thr)
        }
    }
    if ($nCrop -gt 0 -and $x2 -gt $x1 -and $y2 -gt $y1) {
        $cw = $x2 - $x1; $ch = $y2 - $y1
        $remW = $a.W - $cw; $remH = $a.H - $ch
        $okW = ($remW -ge [Math]::Max(16.0, 0.03 * $a.W)); $okH = ($remH -ge [Math]::Max(16.0, 0.03 * $a.H))
        if (($okW -or $okH) -and $cw -ge ($a.W * 0.6) -and $ch -ge ($a.H * 0.6)) {
            if (-not $okW) { $x1 = 0; $cw = $a.W }
            if (-not $okH) { $y1 = 0; $ch = $a.H }
            $cw = [int]([Math]::Floor($cw / 2.0) * 2); $ch = [int]([Math]::Floor($ch / 2.0) * 2)
            $x1 = [int]([Math]::Floor($x1 / 2.0) * 2); $y1 = [int]([Math]::Floor($y1 / 2.0) * 2)
            $a.Crop = '{0}:{1}:{2}:{3}' -f $cw, $ch, $x1, $y1
            $a.CropNote = '{0}x{1} (retrait {2} px largeur, {3} px hauteur)' -f $cw, $ch, ($a.W - $cw), ($a.H - $ch)
        }
    }
    if ($ymax -ge 0 -and $ymin -le 9000) { $a.Black = [Math]::Round($ymin, 0); $a.White = [Math]::Round($ymax, 0) }
    $a.Deep = $true
    $a.Report = Format-Analysis $a
    $script:analysis[$key] = $a
    return $a
}

# --------------------------------------------------------------------- Audio / sous-titres (V8)
function Is-French($s) {
    $lang = "$($s.tags.language)".Trim().ToLower()
    if ($lang -match '^(fre|fra|fr|french|francais)$' -or $lang -match '^fr([-_]|$)') { return $true }
    if ($lang -eq '' -or $lang -eq 'und') {
        $t = "$($s.tags.title)"
        if ($t -match '(?i)\b(fr|fre|fra|french|vff|vfi|vfq|vf|truefrench)\b' -or $t -match '(?i)fran.ais') { return $true }
    }
    return $false
}
function Is-Forced($s) {
    return ($s.disposition.forced -eq 1 -or "$($s.tags.title)" -match '(?i)forced|forc')
}
function Is-Sdh($s) {
    return ("$($s.tags.title)" -match '(?i)sdh|malentend|hearing|\bcc\b' -or $s.disposition.hearing_impaired -eq 1)
}
$script:subOk = @('subrip', 'srt', 'ass', 'ssa', 'webvtt', 'mov_text', 'hdmv_pgs_subtitle', 'dvd_subtitle', 'dvb_subtitle', 'text')

# Retourne Audio, Subs, Note selon les regles : audio FR -> toutes les pistes FR + sous-titres FR forces ;
# sinon piste par defaut + sous-titres FR complets (ou forces s'il n'y a pas de complet).
function Select-Tracks($audio, $subs) {
    $subs = @($subs | Where-Object { $_.codec_name -in $script:subOk })
    $selA = @(); $selS = @(); $note = ''
    $frA = @($audio | Where-Object { Is-French $_ })
    $frS = @($subs | Where-Object { Is-French $_ })
    if ($frA.Count -gt 0) {
        $selA = $frA
        $selS = @($frS | Where-Object { Is-Forced $_ })
        $note = 'audio FR conserve ; sous-titres : FR forces uniquement'
    } else {
        if ($audio.Count -gt 0) {
            $def = @($audio | Where-Object { $_.disposition.default -eq 1 })
            if ($def.Count -gt 0) { $selA = @($def[0]) } else { $selA = @($audio[0]) }
        }
        $full = @($frS | Where-Object { -not (Is-Forced $_) })
        $fullNo = @($full | Where-Object { -not (Is-Sdh $_) })
        if ($fullNo.Count -gt 0) { $selS = @($fullNo[0]); $note = 'pas d''audio FR : piste par defaut + sous-titres FR complets' }
        elseif ($full.Count -gt 0) { $selS = @($full[0]); $note = 'pas d''audio FR : piste par defaut + sous-titres FR (SDH)' }
        else {
            $fo = @($frS | Where-Object { Is-Forced $_ })
            if ($fo.Count -gt 0) { $selS = @($fo[0]); $note = 'pas d''audio FR : piste par defaut + sous-titres FR forces' }
            else { $note = 'pas d''audio FR : piste par defaut, aucun sous-titre FR' }
        }
    }
    return [pscustomobject]@{ Audio = $selA; Subs = $selS; Note = $note }
}

# Reencodage des pistes sans perte ou tres lourdes (option) : AC3 640k (5.1), AC3 448k (3-5 ca.), AAC 256k (stereo), AAC 128k (mono)
function Get-AudioCodecArgs($s, [int]$n) {
    $c = "$($s.codec_name)"; $prof = "$($s.profile)"
    $heavy = ($c -match '^(pcm_.*|truehd|mlp|flac|alac|wavpack|tta)$') -or ($c -eq 'dts' -and $prof -match 'DTS-HD (MA|HRA)')
    $ch = 2; [void][int]::TryParse("$($s.channels)", [ref]$ch)
    if (-not (Test-Opt 'Audio' $true) -or -not $heavy) { return @{ Args = @("-c:a:$n", 'copy'); Note = '' } }
    if ($ch -ge 6)      { $r = @("-c:a:$n", 'ac3', "-b:a:$n", '640k', "-ar:a:$n", '48000'); if ($ch -gt 6) { $r += @("-ac:a:$n", '6') }; $nt = 'AC3 640k 5.1' }
    elseif ($ch -ge 3)  { $r = @("-c:a:$n", 'ac3', "-b:a:$n", '448k', "-ar:a:$n", '48000'); $nt = 'AC3 448k' }
    elseif ($ch -eq 2)  { $r = @("-c:a:$n", 'aac', "-b:a:$n", '256k'); $nt = 'AAC 256k' }
    else                { $r = @("-c:a:$n", 'aac', "-b:a:$n", '128k'); $nt = 'AAC 128k' }
    return @{ Args = $r; Note = ('piste {0} : {1} -> {2}' -f $n, $c, $nt) }
}

# --------------------------------------------------------------------- Mesure de qualite (V8)
# Compare une sortie encodee a la source filtree (memes filtres) : VMAF si libvmaf est present, sinon SSIM.
function Get-QualityScore([string]$src, [int]$mapIndex, [string]$vfRef, [string]$enc, [double]$encSs, [double]$srcSs, [double]$len, [bool]$useVmaf) {
    $err = Join-Path $env:TEMP ('ffq_{0}.txt' -f [guid]::NewGuid().ToString('N'))
    $rc = @()
    if ($vfRef) { $rc += $vfRef }
    $rc += 'format=yuv420p10le'; $rc += 'setpts=PTS-STARTPTS'
    $nt = [Math]::Max(1, [int]$script:threads)
    $met = $(if ($useVmaf) { "libvmaf=n_threads=${nt}:n_subsample=2" } else { 'ssim' })
    $fc = '[0:{0}]{1}[r];[1:v:0]format=yuv420p10le,setpts=PTS-STARTPTS[d];[d][r]{2}' -f $mapIndex, ($rc -join ','), $met
    $a = '-hide_banner -nostats -loglevel info'
    if ($srcSs -ge 0) { $a += (' -ss {0} -t {1}' -f $srcSs.ToString('0.###', $inv), $len.ToString('0.###', $inv)) }
    $a += ' -i ' + (Q $src)
    if ($encSs -ge 0) { $a += (' -ss {0} -t {1}' -f $encSs.ToString('0.###', $inv), $len.ToString('0.###', $inv)) }
    $a += ' -i ' + (Q $enc) + ' -filter_complex ' + (Q $fc) + ' -f null -'
    $score = $null
    try {
        [void](Run-Ffmpeg $a $err)
        $txt = ''
        if (Test-Path -LiteralPath $err) { $txt = [IO.File]::ReadAllText($err) }
        if ($useVmaf) { $m = [regex]::Match($txt, 'VMAF score:\s*([0-9.]+)') }
        else          { $m = [regex]::Match($txt, 'SSIM[^\r\n]*All:([0-9.]+)') }
        if ($m.Success) { $score = [double]::Parse($m.Groups[1].Value, $inv) }
    } catch {
    } finally { Remove-Item -LiteralPath $err -Force -ErrorAction SilentlyContinue }
    return $score
}

# Encode les extraits avec la qualite $q et retourne la moyenne des scores
function Measure-QualityAt($item, $info, [string]$mode, [double]$q, $an, $pts, [double]$len, [bool]$useVmaf) {
    $sum = 0.0; $n = 0; $dur = [double]$item.Duration
    foreach ($pos0 in $pts.Pos) {
        if ($script:cancelled) { break }
        $pos = [Math]::Max(0.0, [Math]::Min([double]$pos0, $dur - $len - 0.2))
        $id = [guid]::NewGuid().ToString('N')
        $sfile = Join-Path $env:TEMP ("ffsq_{0}.mkv" -f $id)
        $serr  = Join-Path $env:TEMP ("ffsq_{0}.err" -f $id)
        $sprog = Join-Path $env:TEMP ("ffprog_{0}.txt" -f $id)
        try {
            $sp = Build-FfmpegArgs $info $item.Path $sfile $sprog $mode $false $false $null $pos $len $an $q
            $code = Run-Ffmpeg $sp.Args $serr
            if ($code -ne 0 -or -not (Test-Path -LiteralPath $sfile)) { continue }
            $s = Get-QualityScore $item.Path $sp.MapIndex $sp.Vf $sfile -1.0 $pos $len $useVmaf
            if ($null -ne $s) { $sum += $s; $n++ }
        } catch {
        } finally { Remove-Item -LiteralPath $sfile, $serr, $sprog -Force -ErrorAction SilentlyContinue }
    }
    if ($n -eq 0) { return $null }
    return ($sum / $n)
}

# Recherche automatique du CRF / CQ qui atteint le score cible (VMAF ou SSIM) : encadrement + interpolation, 6 essais maximum
function Find-AutoQuality($item, $info, [string]$mode, $an) {
    $P = Get-V8Profile
    $m = Resolve-Mode $mode $an.Hdr
    $dur = [double]$item.Duration
    if ($dur -le 0 -or $an.Hdr) { return $null }
    $pts = Get-SamplePoints $dur
    $len = [double]$pts.Len
    $useV = [bool]$script:caps.Vmaf
    $target = $(if ($useV) { $P.Vmaf } else { $P.Ssim })
    switch ($m) {
        'nvenc' { $q = [double]$P.Cq;  $qMin = 16; $qMax = 36 }
        'qsv'   { $q = [double]$P.Gq;  $qMin = 14; $qMax = 34 }
        default { $q = [double]$P.Crf; $qMin = 14; $qMax = 32 }
    }
    $lo = $null; $hi = $null; $iters = 0; $tried = @{}
    $script:searchMode = $true
    try {
        for ($it = 0; $it -lt 6; $it++) {
            if ($script:cancelled) { return $null }
            if ($tried.ContainsKey([int]$q)) { break }
            $s = Measure-QualityAt $item $info $mode $q $an $pts $len $useV
            if ($null -eq $s) { if ($iters -eq 0) { return $null } else { break } }
            $iters++; $tried[[int]$q] = $s
            if ($s -ge $target) { if ($null -eq $lo -or $q -gt $lo.q) { $lo = @{ q = $q; s = $s } } }
            else                { if ($null -eq $hi -or $q -lt $hi.q) { $hi = @{ q = $q; s = $s } } }
            if ($lo -and $hi) {
                if (($hi.q - $lo.q) -le 1) { break }
                $den = ($lo.s - $hi.s)
                if ($den -le 0) { $qn = ($lo.q + $hi.q) / 2.0 } else { $qn = $lo.q + ($lo.s - $target) / $den * ($hi.q - $lo.q) }
                $qn = [Math]::Round($qn)
                $qn = [Math]::Max($lo.q + 1, [Math]::Min($hi.q - 1, $qn))
            } elseif ($lo) {
                if ($lo.q -ge $qMax) { break }
                $d = [Math]::Min(6, [Math]::Max(1, [Math]::Round(($lo.s - $target) / 0.8)))
                $qn = [Math]::Min($qMax, $lo.q + $d)
            } else {
                if ($hi.q -le $qMin) { break }
                $d = [Math]::Min(6, [Math]::Max(1, [Math]::Round(($target - $hi.s) / 0.8)))
                $qn = [Math]::Max($qMin, $hi.q - $d)
            }
            $q = $qn
        }
    } finally { $script:searchMode = $false }
    if ($lo) { return [pscustomobject]@{ Q = [double]$lo.q; Score = $lo.s; Target = $target; Vmaf = $useV; Iter = $iters; Reached = $true } }
    if ($hi) { return [pscustomobject]@{ Q = [double]$qMin; Score = $hi.s; Target = $target; Vmaf = $useV; Iter = $iters; Reached = $false } }
    return $null
}

# Score final : meme mesure sur 3 extraits de la sortie reelle compares a la source filtree
function Get-FinalScore($item, $plan) {
    $dur = [double]$item.Duration
    if ($dur -le 0) { return $null }
    $pts = Get-SamplePoints $dur
    $len = [double]$pts.Len
    $useV = [bool]$script:caps.Vmaf
    $sum = 0.0; $n = 0
    foreach ($pos0 in $pts.Pos) {
        if ($script:cancelled) { break }
        $pos = [Math]::Max(0.0, [Math]::Min([double]$pos0, $dur - $len - 0.2))
        $s = Get-QualityScore $item.Path $plan.MapIndex $plan.VfBase $script:dst $pos $pos $len $useV
        if ($null -ne $s) { $sum += $s; $n++ }
    }
    if ($n -eq 0) { return $null }
    return [pscustomobject]@{ Score = ($sum / $n); Vmaf = $useV }
}

# Detection des capacites du ffmpeg et des encodeurs (appelee au demarrage et apres une mise a jour de ffmpeg)
function Test-EncCap([string]$argString) {
    try {
        $ef = Join-Path $env:TEMP 'ffcap.err'
        $p = Start-Process -FilePath $script:ffmpeg -ArgumentList ('-hide_banner -loglevel error -f lavfi -i testsrc2=s=640x360:r=25:d=0.4 ' + $argString + ' -f null -') `
            -WorkingDirectory $env:TEMP -WindowStyle Hidden -PassThru -RedirectStandardError $ef
        $null = $p.Handle
        if (-not $p.WaitForExit(20000)) { try { $p.Kill() } catch {}; $script:capErr = 'delai depasse'; return $false }
        if ($p.ExitCode -ne 0) {
            $script:capErr = ''
            try { $l = @(Get-Content -LiteralPath $ef -ErrorAction Stop | Where-Object { $_ -and $_.Trim() }); if ($l.Count -gt 0) { $script:capErr = "$($l[$l.Count - 1])".Trim() } } catch {}
            return $false
        }
        return $true
    } catch { $script:capErr = $_.Exception.Message; return $false }
}
function Update-Capabilities([bool]$nv, [bool]$qsv) {
    $c = $script:caps
    try {
        $f = (& $script:ffmpeg -hide_banner -filters 2>$null | Out-String)
        $c.Vmaf = ($f -match '\blibvmaf\b')
        $c.Placebo = ($f -match '\blibplacebo\b')
    } catch {}
    $c.PlaceboOk = $false
    if ($c.Placebo) { $c.PlaceboOk = Test-EncCap '-vf libplacebo=w=1280:h=720:upscaler=ewa_lanczos:format=yuv420p10le' }
    if ($nv) {
        $c.Nv10 = Test-EncCap '-c:v hevc_nvenc -profile:v main10 -pix_fmt p010le'
        $nvBase = '-c:v hevc_nvenc -preset p7 -tune hq -rc vbr -cq 22 -b:v 0 -multipass fullres -rc-lookahead 32 -spatial_aq 1 -temporal_aq 1'
        $c.NvErr = ''
        $c.NvBase = Test-EncCap $nvBase
        if (-not $c.NvBase) { $c.NvErr = "base : $($script:capErr)" }
        $c.NvAdv = $false; $c.NvBref = $false
        if ($c.NvBase) {
            $c.NvAdv = Test-EncCap ($nvBase + ' -bf 3 -aq-strength 8 -g 250')
            if (-not $c.NvAdv) { $c.NvErr = "B-frames : $($script:capErr)" }
            else {
                $c.NvBref = Test-EncCap ($nvBase + ' -bf 3 -b_ref_mode middle -aq-strength 8 -g 250')
                if (-not $c.NvBref) { $c.NvErr = "b_ref_mode : $($script:capErr)" }
            }
        }
    }
    if ($qsv) {
        $c.QsvIcq = Test-EncCap '-vf format=nv12 -c:v hevc_qsv -global_quality 22'
        $c.QsvAdv = Test-EncCap '-vf format=nv12 -c:v hevc_qsv -global_quality 22 -adaptive_i 1 -adaptive_b 1 -b_strategy 1 -g 250'
        $c.Qsv10 = Test-EncCap '-vf format=yuv420p10le -c:v hevc_qsv -profile:v main10 -pix_fmt p010le'
    }
    $c.Probed = $true
}
function Format-Capabilities {
    $c = $script:caps
    $yn = { param($b) if ($b) { 'oui' } else { 'non' } }
    $nv = ('B-frames {0}, B-ref {1}' -f (& $yn $c.NvAdv), (& $yn $c.NvBref))
    $t = ('Mesure de qualite : {0} | libplacebo : {1} | NVENC avance : {2} | Quick Sync avance : {3}' -f $(if ($c.Vmaf) { 'VMAF' } else { 'SSIM (libvmaf absent)' }), $(if ($c.PlaceboOk) { 'disponible' } elseif ($c.Placebo) { 'present, Vulkan indisponible' } else { 'absent (ffmpeg complet requis)' }), $nv, (& $yn $c.QsvAdv))
    if ($c.NvErr) { $t += ("`r`n" + "NVENC : " + $c.NvErr) }
    return $t
}

function Build-FfmpegArgs($info, [string]$src, [string]$dst, [string]$progressFile, [string]$mode, [bool]$upscale = $false, [bool]$twoPass = $false, $corr = $null, [double]$sampleStart = -1.0, [double]$sampleLen = 0.0, $an = $null, [double]$qo = -1.0) {

    $isSample = ($sampleLen -gt 0)
    if ($isSample) { $twoPass = $false }
    $tpl = ($null -eq $info)
    $duration = 0.0
    $P = Get-V8Profile
    $fmtName = ''

    if ($tpl) {
        $v = [pscustomobject]@{ index = 0; pix_fmt = 'yuv420p'; profile = 'Main'; codec_name = 'h264' }
        $audio = @([pscustomobject]@{ index = 1; codec_name = 'ac3'; channels = 2 })
        $subs  = @()
        $an = Get-StaticAnalysis $null
    } else {
        [void][double]::TryParse("$($info.format.duration)", [Globalization.NumberStyles]::Float, $inv, [ref]$duration)
        $fmtName = "$($info.format.format_name)"
        $video = @($info.streams | Where-Object { $_.codec_type -eq 'video' -and $_.disposition.attached_pic -ne 1 })
        $audio = @($info.streams | Where-Object { $_.codec_type -eq 'audio' })
        $subs  = @($info.streams | Where-Object { $_.codec_type -eq 'subtitle' })
        if ($video.Count -eq 0) { throw "Aucune piste video trouvee." }
        $v = $video[0]
        if (-not $an) {
            if ($script:analysis.ContainsKey($src)) { $an = $script:analysis[$src] } else { $an = Get-StaticAnalysis $info }
        }
    }
    $notes = New-Object System.Collections.Generic.List[string]

    # --- Etiquettes de couleur de la source ---------------------------------
    $modeNote = ''; $hdrP = $null
    if ($tpl) {
        $col = [pscustomobject]@{ Range = '<plage>'; Space = '<matrice>'; Trc = '<transfert>'; Prim = '<primaires>'; Hdr = $false; Tagged = $true }
    } else {
        $col = Get-ColorTags $v
        if ($col.Hdr) {
            if ($col.Trc -eq 'smpte2084') { $hdrP = Get-HdrParams $src }
            if ($mode -ne 'cpu') {
                $mode = 'cpu'
                $modeNote = 'Source HDR : encodage x265 (CPU) impose pour conserver les metadonnees HDR'
            }
        }
    }
    if ($mode -ne 'cpu' -and $P.ForceCpu) {
        $mode = 'cpu'
        $modeNote = 'Profil Archivage : encodage x265 (CPU) impose (preset slower, meilleure qualite par bit)'
    }
    $bits = 8
    if (-not $tpl) { $bits = Get-StreamBits $info }

    # --- 10 bits : toujours (sauf option), si l'encodeur le permet -----------
    $out10 = (($bits -ge 10) -or (Test-Opt 'Tenbit' $true))
    if ($mode -eq 'nvenc' -and -not $script:caps.Nv10) { $out10 = $false }
    if ($mode -eq 'qsv'   -and -not $script:caps.Qsv10) { $out10 = $false }
    $pipeBits = $(if ($out10) { 10 } else { 8 })

    # --- Debit video d'origine et cible --------------------------------------
    $targetK = 0; $vbr = 0.0
    $codec = "$($v.codec_name)"
    if ($tpl) {
        $bTxt = '<debit_cible>k'; $mTxt = '<debit_max>k'; $bufTxt = '<buffer>k'
    } else {
        $vbr = Get-VideoBitrate $info $v $audio
    }
    $upMode = $false     # upscaling actif -> qualite constante V7
    $qmode = "$($script:v8.QMode)"

    # --- Chaine de filtres : desentrelacement / IVTC / recadrage / 10 bits ------
    $chain = @()
    if ($tpl) {
        $chain += '<filtres_analyse>'
    } else {
        $doIvtc = Test-Opt 'Ivtc' ([bool]$an.Telecine)
        $doDeint = ((-not $doIvtc) -and (Test-Opt 'Deint' ([bool]$an.Interlaced)))
        if ($doIvtc) {
            $chain += 'fieldmatch'; $chain += 'yadif=deint=interlaced'; $chain += 'decimate'
            $notes.Add('telecine inverse (fieldmatch + decimate)')
        } elseif ($doDeint) {
            $chain += 'bwdif=mode=0:parity=-1:deint=0'
            $notes.Add('desentrelacement bwdif (toutes les images)')
        }
        $cropTxt = ''
        if ($an.Crop -and (Test-Opt 'Crop' $true)) {
            $chain += ('crop=' + $an.Crop)
            $cropTxt = $an.Crop
            $notes.Add('recadrage ' + $an.CropNote)
        }
        if ($out10 -and "$($v.pix_fmt)" -ne 'yuv420p10le') { $chain += 'format=yuv420p10le' }
    }

    # --- Reglages image valides (fenetre d'apercu) -----------------------------
    $imgSet = $null
    if ($script:imgOn -and $script:imgValidated) { $imgSet = $script:imgValidated }

    # --- Artefacts de compression : deblock / debruitage / deband selon le niveau ---
    $lvl = [int]$an.Level
    if ($imgSet -and [int]$imgSet.Depix -gt 0) { $lvl = 0 }
    if (-not $tpl) {
        if (Test-Opt 'Deblock' ($lvl -ge 1)) {
            $dl = [Math]::Max($lvl, 1)
            $chain += $(if ($dl -ge 2) { 'deblock=filter=strong:block=8' } else { 'deblock=filter=weak:block=8' })
            $notes.Add('deblock ' + $(if ($dl -ge 2) { 'fort' } else { 'leger' }) + (' (niveau d''artefacts {0}/3)' -f $an.Level))
        }
        if (Test-Opt 'Denoise' ($lvl -ge 3)) {
            $chain += $(if ($lvl -ge 3) { 'hqdn3d=1.5:1.5:3:3' } else { 'hqdn3d=1.0:1.0:2:2' })
            $notes.Add('debruitage hqdn3d')
        }
        if (Test-Opt 'Deband' (($bits -lt 10) -and $lvl -ge 2 -and -not $col.Hdr)) {
            $chain += 'deband=1thr=0.015:2thr=0.015:3thr=0.015:range=14:blur=1'
            $notes.Add('anti-banding deband')
        }
    }

    # --- Upscaling 1080p HD (optionnel) : comportement V7 (qualite constante, aucun plafond) ---
    $scaleNote = ''; $quality = $false
    $imfPre = $null
    $placebo = ($script:caps.PlaceboOk -and (Test-Opt 'Placebo' $false))
    if ($upscale) {
        if ($tpl) {
            $chain += 'scale=<largeur>:<hauteur>:flags=lanczos+accurate_rnd+full_chroma_int'
            $chain += 'setsar=1'
            $scaleNote = 'mise a l''echelle vers 1080p (dimensions calculees pour chaque video)'
            $quality = $true
            $upMode = $true
        } else {
            $srcW = [double]$v.width; $srcH = [double]$v.height
            if ($cropTxt -match '^(\d+):(\d+):') { $srcW = [double]$Matches[1]; $srcH = [double]$Matches[2] }
            $sar = 1.0
            if ("$($v.sample_aspect_ratio)" -match '^(\d+):(\d+)$') {
                $sn = [double]$Matches[1]; $sd = [double]$Matches[2]
                if ($sn -gt 0 -and $sd -gt 0) { $sar = $sn / $sd }
            }
            $dispW = $srcW * $sar; $dispH = $srcH
            $fac = 0.0
            if ($dispW -gt 0 -and $dispH -gt 0) { $fac = [Math]::Min($script:upW / $dispW, $script:upH / $dispH) }
            if ($fac -gt 1.0) {
                $ow = [int]([Math]::Round($dispW * $fac / 2.0) * 2)
                $oh = [int]([Math]::Round($dispH * $fac / 2.0) * 2)
                if ($ow -gt $script:upW) { $ow = $script:upW }
                if ($oh -gt $script:upH) { $oh = $script:upH }
                # SD -> HD : matrice BT.601 -> BT.709 (sinon les couleurs virent a l'affichage)
                if ($an.Sd -and -not $col.Hdr -and ("$($col.Space)" -notmatch 'bt709') -and (Test-Opt 'Matrix' $true)) {
                    $iall = $(if ($an.Std -eq '625') { 'bt601-6-625' } else { 'bt601-6-525' })
                    $chain += "colorspace=all=bt709:iall=$iall"
                    $col = [pscustomobject]@{ Range = $col.Range; Space = 'bt709'; Trc = 'bt709'; Prim = 'bt709'; Hdr = $false; Tagged = $true }
                    $notes.Add("matrice $iall -> BT.709")
                }
                $quality = $true
                $upMode = $true
                $scaleTxt = $(if ($placebo) { "libplacebo=w=${ow}:h=${oh}:upscaler=ewa_lanczos:downscaler=ewa_lanczos:format=" + $(if ($out10) { 'yuv420p10le' } else { 'yuv420p' }) } else { "scale=${ow}:${oh}:flags=lanczos+accurate_rnd+full_chroma_int" })
                $chain += $scaleTxt
                $chain += 'setsar=1'
                $scaleNote = '{0:0}x{1:0} -> {2}x{3}' -f $srcW, $srcH, $ow, $oh
                if ($placebo) { $scaleNote += ' (libplacebo ewa_lanczos)' }
            } else {
                $scaleNote = 'deja en 1080p ou plus : aucune mise a l''echelle'
            }
        }
    }
    $upscaled = [bool]$quality

    # --- Niveaux (images delavees) : etirement vers 16-235 apres mesure -------------
    if (-not $tpl -and -not $col.Hdr -and $an.Black -ge 0 -and "$($col.Range)" -ne 'pc' -and "$($v.pix_fmt)" -notmatch '^yuvj') {
        $rng = $an.White - $an.Black
        $autoLv = ($an.Black -ge 22 -and $an.White -le 225 -and $rng -ge 100)
        $onLv = ($rng -lt 215 -and $rng -ge 80)
        $doLv = $false
        switch ("$($script:v8.Opt['Levels'])") { 'on' { $doLv = $onLv } 'off' { $doLv = $false } default { $doLv = $autoLv } }
        if ($doLv) {
            $k = [Math]::Pow(2, $pipeBits - 8)
            $lutExpr = "y='clip((val-{0})*{1}+{2},{2},{3})'" -f (Fmt-Num ($an.Black * $k)), (Fmt-Num (219.0 / $rng)), (Fmt-Num (16 * $k)), (Fmt-Num (235 * $k))
            if ($out10 -and "$($v.pix_fmt)" -ne 'yuv420p10le' -and $chain -notcontains 'format=yuv420p10le') { $chain += 'format=yuv420p10le' }
            $chain += ('lutyuv=' + $lutExpr)
            $notes.Add(('niveaux {0:0}-{1:0} etires vers 16-235' -f $an.Black, $an.White))
        }
    }

    # --- Reglages image valides + nettete automatique apres upscaling -----------------
    $fullRange = (("$($col.Range)" -eq 'pc') -or (("$($v.pix_fmt)" -match '^yuvj') -and -not $out10))
    $imf = Get-ImageFilter $imgSet $pipeBits $upscaled $fullRange
    if ($imf.Pre)  { $chain += $imf.Pre }
    if ($imf.Post) { $chain += $imf.Post }
    $vf = $null
    if ($chain.Count -gt 0) { $vf = ($chain -join ',') }

    # --- Correction de couleur issue de la comparaison avant compression ------------
    $vfBase = $vf
    if ($corr) {
        $cf = Get-CorrFilter $corr $pipeBits $fullRange
        if ($cf) { $vf = $(if ($vf) { $vf + ',' + $cf } else { $cf }) }
    }

    # --- Mode de qualite --------------------------------------------------------------
    $ratio = $script:sizeRatio
    if (-not $upMode -and $qmode -eq 'debit') { $ratio = Get-CodecRatio $codec }
    if (-not $tpl) {
        $targetK = [int][Math]::Max([Math]::Round($vbr / $ratio / 1000), 200)
        $bTxt = "${targetK}k"
        $mTxt = "$([int]($targetK * 1.6))k"
        $bufTxt = "$([int]($targetK * 3))k"
    }
    $constQ = ($upMode -or $qmode -ne 'debit')            # qualite constante (upscaling V7, auto, fixe)
    switch ($mode) {
        'nvenc' { $qFix = [double]$P.Cq }
        'qsv'   { $qFix = [double]$P.Gq }
        default { $qFix = [double]$P.Crf }
    }
    if ($col.Hdr) { $qFix = [double]$P.Crf }
    $qVal = $qFix; $qSrc = 'fixe'
    if ($upMode) {
        $qVal = $(if ($mode -eq 'cpu') { [double]$script:upCrf } else { [double]$script:upCq }); $qSrc = 'upscaling'
    } elseif ($qo -ge 0) { $qVal = $qo; $qSrc = 'auto' }
    elseif ($qmode -eq 'auto' -and -not $col.Hdr) { $qSrc = 'auto-defaut' }
    $qTxt = $qVal.ToString('0.#', $inv)

    # Plafond de debit = debit de la source (jamais plus gros que l'original), hors upscaling et HDR
    $capK = 0
    if (-not $upMode -and -not $col.Hdr -and $constQ -and -not $tpl -and $vbr -ge 300000) { $capK = [int]($vbr / 1000) }
    if ($tpl -and -not $upMode -and $constQ) { $capK = -1 }

    # --- Encodage 2 passes (upscaling ou mode debit cible) ----------------------------
    $twoEff = ($twoPass -and ($upMode -or $qmode -eq 'debit'))
    $passes = 1; $passNote = ''; $statsName = ''
    if ($twoPass -and -not $twoEff) { $passNote = 'Case 2 passes ignoree : le mode qualite constante (automatique/fixe) n''utilise pas de debit cible' }
    if ($twoEff) {
        if ($upMode) {
            if ($tpl) {
                $bTxt = '<debit_2passes>k'; $mTxt = '<debit_max>k'; $bufTxt = '<buffer>k'
            } else {
                $fps = $an.Fps
                $bppK = [int][Math]::Round($ow * $oh * $fps * $script:twoPassBpp / 1000)
                $targetK = [Math]::Max($bppK, $targetK)
                $bTxt = "${targetK}k"
                $mTxt = "$([int]($targetK * 1.6))k"
                $bufTxt = "$([int]($targetK * 3))k"
            }
            $quality = $false
        }
        $constQ = $false
        switch ($mode) {
            'cpu'   { $passes = 2; $passNote = 'Encodage 2 passes x265 : passe 1 (analyse) puis passe 2 (encodage final)' }
            'nvenc' { $passNote = 'Encodage NVENC : 2 passes materielles (multipass fullres), debit cible' }
            default { $passNote = 'Quick Sync : pas de 2 passes materielles, debit cible utilise' }
        }
        $leaf = $progressFile.Substring($progressFile.LastIndexOf('\') + 1)
        $statsName = (($leaf -replace '^ffprog_', 'ff2p_') -replace '\.txt$', '') + '.log'
    }
    # Quick Sync sans ICQ : repli sur le debit cible
    if ($constQ -and $mode -eq 'qsv' -and -not $script:caps.QsvIcq) { $constQ = $false }

    if ($constQ) {
        $unit = $(if ($mode -eq 'cpu') { 'CRF' } else { 'CQ' })
        switch ($qSrc) {
            'upscaling'   { $rateTxt = "qualite constante $unit $qTxt (upscaling)" }
            'auto'        { $rateTxt = "qualite automatique $unit $qTxt" }
            'auto-defaut' { $rateTxt = "qualite automatique ($unit determine a la conversion, cible " + $(if ($script:caps.Vmaf) { ('VMAF {0:0.#}' -f $P.Vmaf) } else { ('SSIM {0:0.000}' -f $P.Ssim) }) + ')' }
            default       { $rateTxt = "qualite fixe $unit $qTxt (profil $($P.Name))" }
        }
    } elseif ($twoEff) {
        $kTxt = if ($tpl) { '<debit>' } else { "$targetK" }
        $rateTxt = switch ($mode) {
            'cpu'   { "2 passes x265, cible ~$kTxt kb/s" }
            'nvenc' { "NVENC 2 passes materielles, cible ~$kTxt kb/s" }
            default { "Quick Sync, cible ~$kTxt kb/s (sans 2 passes materielles)" }
        }
    } elseif ($tpl) { $rateTxt = 'debit cible : original / rapport du codec' }
    else { $rateTxt = 'debit cible ~{0} kb/s (original / {1:0.0})' -f $targetK, $ratio }

    # --- Pistes audio et sous-titres (V8) ---------------------------------------------
    if ($tpl) { $selAudio = @($audio[0]); $selSubs = @(); $trackNote = '' }
    else {
        $sel = Select-Tracks $audio $subs
        $selAudio = @($sel.Audio); $selSubs = @($sel.Subs); $trackNote = $sel.Note
    }
    if ($isSample) { $selAudio = @(); $selSubs = @() }     # extrait de mesure : video seule

    # --- Arguments ---------------------------------------------------------------------
    $a = New-Object System.Collections.Generic.List[string]
    $a.AddRange([string[]]@('-hide_banner', '-loglevel', 'error', '-y', '-nostats', '-progress', (Q $progressFile)))
    $a.AddRange([string[]]@('-threads', "$($script:threads)"))
    if ($mode -eq 'nvenc') { $a.AddRange([string[]]@('-hwaccel', 'cuda')) }
    if ($fmtName -match 'avi|mpeg|asf|flv') { $a.AddRange([string[]]@('-fflags', '+genpts')) }
    if ($isSample) { $a.AddRange([string[]]@('-ss', $sampleStart.ToString('0.###', $inv), '-t', $sampleLen.ToString('0.###', $inv))) }
    $a.AddRange([string[]]@('-i', (Q $src)))

    $a.AddRange([string[]]@('-map', "0:$($v.index)"))
    foreach ($s in $selAudio) { $a.AddRange([string[]]@('-map', "0:$($s.index)")) }
    foreach ($s in $selSubs)  { $a.AddRange([string[]]@('-map', "0:$($s.index)")) }

    # Metadonnees supprimees, chapitres conserves (option)
    $chap = $(if ((Test-Opt 'Chapters' $true) -and -not $isSample) { '0' } else { '-1' })
    $a.AddRange([string[]]@('-map_metadata', '-1', '-map_chapters', $chap,
        '-fflags', '+bitexact', '-flags:v', '+bitexact', '-flags:a', '+bitexact'))
    $a.AddRange([string[]]@('-metadata:s:v:0', 'title=', '-metadata:s:v:0', 'handler_name=', '-metadata:s:v:0', 'vendor_id='))
    for ($i = 0; $i -lt $selAudio.Count; $i++) {
        $a.AddRange([string[]]@("-metadata:s:a:$i", 'title=', "-metadata:s:a:$i", 'handler_name=', "-metadata:s:a:$i", 'vendor_id='))
    }
    for ($i = 0; $i -lt $selSubs.Count; $i++) {
        $a.AddRange([string[]]@("-metadata:s:s:$i", 'title=', "-metadata:s:s:$i", 'handler_name=', "-metadata:s:s:$i", 'vendor_id='))
    }

    if ($vf) { $a.AddRange([string[]]@('-vf', (Q $vf))) }

    $gop = 250
    if (-not $tpl) { $gop = [int][Math]::Max(24, [Math]::Min(600, [Math]::Round($an.Fps * 10))) }
    $capArgs = @()
    if ($capK -gt 0) { $capArgs = @('-maxrate', "${capK}k", '-bufsize', ('{0}k' -f ($capK * 2))) }
    elseif ($capK -lt 0) { $capArgs = @('-maxrate', '<debit_source>k', '-bufsize', '<buffer>k') }

    if ($mode -eq 'nvenc') {
        $a.AddRange([string[]]@('-c:v', 'hevc_nvenc', '-preset', $P.NvPreset, '-tune', 'hq'))
        if ($constQ) { $a.AddRange([string[]]@('-rc', 'vbr', '-cq', $qTxt, '-b:v', '0')); if ($capArgs.Count) { $a.AddRange([string[]]$capArgs) } }
        else         { $a.AddRange([string[]]@('-rc', 'vbr', '-b:v', $bTxt, '-maxrate', $mTxt, '-bufsize', $bufTxt)) }
        $a.AddRange([string[]]@('-multipass', 'fullres', '-rc-lookahead', '32', '-spatial_aq', '1', '-temporal_aq', '1'))
        if ($script:caps.NvAdv) { $a.AddRange([string[]]@('-bf', '3', '-aq-strength', '8', '-g', "$gop")); if ($script:caps.NvBref) { $a.AddRange([string[]]@('-b_ref_mode', 'middle')) } }
        if ($out10) { $a.AddRange([string[]]@('-profile:v', 'main10', '-pix_fmt', 'p010le')) }
        else        { $a.AddRange([string[]]@('-profile:v', 'main')) }
    } elseif ($mode -eq 'qsv') {
        $a.AddRange([string[]]@('-c:v', 'hevc_qsv', '-preset', $P.QsvPreset))
        if ($constQ) { $a.AddRange([string[]]@('-global_quality', ([int]$qVal).ToString())) }
        else         { $a.AddRange([string[]]@('-b:v', $bTxt, '-maxrate', $mTxt, '-bufsize', $bufTxt)) }
        if ($script:caps.QsvAdv) { $a.AddRange([string[]]@('-adaptive_i', '1', '-adaptive_b', '1', '-b_strategy', '1', '-g', "$gop")) }
        if ($out10) { $a.AddRange([string[]]@('-profile:v', 'main10', '-pix_fmt', 'p010le')) }
        else        { $a.AddRange([string[]]@('-profile:v', 'main', '-pix_fmt', 'nv12')) }
    } else {
        $cpuPreset = $(if ($script:searchMode) { 'medium' } else { $P.CpuPreset })
        $a.AddRange([string[]]@('-c:v', 'libx265', '-preset', $cpuPreset))
        if ($constQ) { $a.AddRange([string[]]@('-crf', $qTxt)); if ($capArgs.Count) { $a.AddRange([string[]]$capArgs) } }
        else         { $a.AddRange([string[]]@('-b:v', $bTxt, '-maxrate', $mTxt, '-bufsize', $bufTxt)) }
        $xpBase = "log-level=error:pools=$($script:threads):aq-mode=3:rc-lookahead=40:keyint=$gop"
        $xp = $xpBase
        if ($passes -eq 2) { $xp += ":pass=2:stats=$statsName" }
        if ($col.Hdr) {
            $xp += ':repeat-headers=1'
            if ($col.Trc -eq 'smpte2084') {
                $xp += ':hdr10=1'
                if ($hdrP -and $hdrP.Master) { $xp += ':master-display=' + $hdrP.Master }
                if ($hdrP -and $hdrP.Cll)    { $xp += ':max-cll=' + $hdrP.Cll }
            }
        }
        $a.AddRange([string[]]@('-x265-params', (Q $xp)))
        if ($out10) { $a.AddRange([string[]]@('-pix_fmt', 'yuv420p10le')) }
    }
    # Etiquettes de couleur
    if ($col.Range) { $a.AddRange([string[]]@('-color_range', $col.Range)) }
    $a.AddRange([string[]]@('-colorspace', $col.Space, '-color_trc', $col.Trc, '-color_primaries', $col.Prim))
    $a.AddRange([string[]]@('-threads', "$($script:threads)"))

    # Audio : copie, ou conversion des pistes sans perte / tres lourdes (option)
    $audioNote = ''
    if ($selAudio.Count -gt 0) {
        $an2 = @()
        for ($i = 0; $i -lt $selAudio.Count; $i++) {
            $ca = Get-AudioCodecArgs $selAudio[$i] $i
            $a.AddRange([string[]]$ca.Args)
            if ($ca.Note) { $an2 += $ca.Note }
        }
        $audioNote = ($an2 -join ' ; ')
        for ($i = 0; $i -lt $selAudio.Count; $i++) {
            $a.AddRange([string[]]@("-disposition:a:$i", $(if ($i -eq 0) { 'default' } else { '0' })))
        }
    } else { $a.Add('-an') }

    # Sous-titres : copie (mov_text converti en srt pour MKV), premier sous-titre par defaut
    if ($selSubs.Count -gt 0) {
        $a.AddRange([string[]]@('-c:s', 'copy'))
        for ($i = 0; $i -lt $selSubs.Count; $i++) {
            if ($selSubs[$i].codec_name -eq 'mov_text') { $a.AddRange([string[]]@("-c:s:$i", 'srt')) }
            $dsp = $(if ($i -eq 0) { $(if (Is-Forced $selSubs[$i]) { 'default+forced' } else { 'default' }) } else { '0' })
            $a.AddRange([string[]]@("-disposition:s:$i", $dsp))
        }
    } else { $a.Add('-sn') }

    $a.AddRange([string[]]@('-max_muxing_queue_size', '1024', '-f', 'matroska', (Q $dst)))

    # Passe 1 (analyse x265) : video seule, sortie nulle
    $args1 = $null
    if ($passes -eq 2) {
        $b = New-Object System.Collections.Generic.List[string]
        $b.AddRange([string[]]@('-hide_banner', '-loglevel', 'error', '-y', '-nostats', '-progress', (Q $progressFile)))
        $b.AddRange([string[]]@('-threads', "$($script:threads)"))
        if ($fmtName -match 'avi|mpeg|asf|flv') { $b.AddRange([string[]]@('-fflags', '+genpts')) }
        $b.AddRange([string[]]@('-i', (Q $src), '-map', "0:$($v.index)"))
        if ($vf) { $b.AddRange([string[]]@('-vf', (Q $vf))) }
        $b.AddRange([string[]]@('-c:v', 'libx265', '-preset', $P.CpuPreset, '-b:v', $bTxt, '-maxrate', $mTxt, '-bufsize', $bufTxt,
            '-x265-params', "$xpBase`:pass=1:stats=$statsName"))
        if ($out10) { $b.AddRange([string[]]@('-pix_fmt', 'yuv420p10le')) }
        $b.AddRange([string[]]@('-threads', "$($script:threads)", '-an', '-sn', '-f', 'null', 'NUL'))
        $args1 = ($b -join ' ')
    }

    $colorNote = 'Couleurs : plage {0} | matrice {1} | transfert {2} | primaires {3} ({4})' -f $(if ($col.Range) { $col.Range } else { 'conversion ffmpeg' }), $col.Space, $col.Trc, $col.Prim, $(if ($col.Tagged) { 'etiquettes de la source reappliquees' } else { 'etiquettes absentes de la source : valeurs par defaut ecrites' })

    return [pscustomobject]@{
        Col      = $col
        Vf       = $vf
        VfBase   = $vfBase
        MapIndex = $v.index
        CorrNote = $(if ($corr) { 'correction couleur ajoutee (Y {0:+0.00;-0.00;0.00}, U {1:+0.00;-0.00;0.00}, V {2:+0.00;-0.00;0.00})' -f $corr.Y, $corr.U, $corr.V } else { '' })
        ColorNote = $colorNote
        ModeNote = $modeNote
        ImgNote  = $(if ($imgSet) { Format-ImgSummary $imgSet } else { '' })
        FilterNotes = ($notes -join ' | ')
        TrackNote = $trackNote
        AudioNote = $audioNote
        Args     = ($a -join ' ')
        Args1    = $args1
        Passes   = $passes
        PassNote = $passNote
        StatsName = $statsName
        Duration = $duration
        TargetK  = $targetK
        RateText = $rateTxt
        ScaleNote = $scaleNote
        Quality  = $quality
        UpMode   = $upMode
        ConstQ   = $constQ
        QVal     = $qVal
        Audio    = $selAudio.Count
        Subs     = $selSubs.Count
        Pipe10   = $out10
        Encoder  = $(switch ($mode) { 'nvenc' { 'NVENC (GPU NVIDIA)' } 'qsv' { 'Quick Sync (GPU Intel)' } default { 'libx265 (CPU)' } })
        Mode     = $mode
    }
}

# ---- Sauvegarde / chargement des options V8 (settings.json) ----
$script:v8Names = @('Deint', 'Ivtc', 'Crop', 'Deblock', 'Denoise', 'Deband', 'Levels', 'Tenbit', 'Matrix', 'Placebo', 'SkipHevc', 'Audio', 'Chapters', 'Score')
function Load-V8Settings {
    $p = "$(Get-AppSetting 'q_profile' 'equilibre')"
    if ($p -in @('rapide', 'equilibre', 'archivage')) { $script:v8.Profile = $p }
    $q = "$(Get-AppSetting 'q_mode' 'auto')"
    if ($q -in @('auto', 'fixe', 'debit')) { $script:v8.QMode = $q }
    foreach ($n in $script:v8Names) {
        $v = "$(Get-AppSetting ('q_' + $n) $script:v8.Opt[$n])"
        if ($v -in @('auto', 'on', 'off')) { $script:v8.Opt[$n] = $v }
    }
}
function Save-V8Settings {
    Set-AppSetting 'q_profile' $script:v8.Profile
    Set-AppSetting 'q_mode' $script:v8.QMode
    foreach ($n in $script:v8Names) { Set-AppSetting ('q_' + $n) $script:v8.Opt[$n] }
}
Load-V8Settings

# Source deja moderne (HEVC / AV1 / VP9) : inutile de la reencoder si le debit est deja bas
function Test-SkipSource($an) {
    $opt = "$($script:v8.Opt['SkipHevc'])"
    if ($opt -eq 'off') { return $false }
    if ($an.Codec -notin @('hevc', 'av1', 'vp9')) { return $false }
    if ($opt -eq 'on') { return $true }
    return ($an.Bpp -gt 0 -and $an.Bpp -lt 0.10)
}


# ------------------------------------------------------- Style (ffmpeg.org) --
# Charte inspiree du site ffmpeg.org : fond blanc, vert FFmpeg, texte gris fonce, Arial.
# Ajustez ces couleurs ici pour modifier tout le style.
$script:cGreen     = [System.Drawing.ColorTranslator]::FromHtml('#43853D')
$script:cGreenDark = [System.Drawing.ColorTranslator]::FromHtml('#2F6B2A')
$script:cText      = [System.Drawing.ColorTranslator]::FromHtml('#333333')
$script:cMuted     = [System.Drawing.ColorTranslator]::FromHtml('#777777')
$script:cWell      = [System.Drawing.ColorTranslator]::FromHtml('#F5F5F5')
$script:cBorder    = [System.Drawing.ColorTranslator]::FromHtml('#BBBBBB')
$script:cDisabled  = [System.Drawing.ColorTranslator]::FromHtml('#BDBDBD')
$script:white      = [System.Drawing.Color]::White

# Logo : logo.jpg a cote du script (redimensionne a 240 px de large, proportions
# conservees), sinon copie integree equivalente.
$script:logoB64 = @'
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
lkl0DCGECENEDeoP+84b/jOdGJRQAAFjjAJKOSXExjL+59b6j9Zs8gd8aTUz8PgB82/+9cp/fbRwzdMUU0KJxSy7haW2BVdtc4LT
oVCqOp3OXHDaT5+85SHRh7vfvO+Rtx8QaOaAf2UPHR7a8q0FUfHSraHzw36JRIIQks+kigkViiSbzTpWMuc8P/oYi8XchnhHGQPw
rZUxOGSxMlsnOoIIAoQhghAhhBm3LdMSj07wbjazsYR31Te+/+EGRfZltdxJ3Y576tbZ9andj33wWxMalFKLmvZB3WxTQikhwIYZ
XyBZlcmo5/xg0PzJD4ibznz3oV+9/v9wyN8mmo+wiQCHQLMb0O10+5wZD4VCuq67AV3cdxQsXmsGvVBFRUxSYV8yxsRyOtwmjH4n
uJNfa6r9jGR77gIhPEIhjiJoj7tSHNDQokS3LQwkCOHBWhwIAg6gKELHGGeUMSyhhobE++9vQBDpln5UZZff3zZHpamH3/tNmqkA
cJ2aNrVsZoufhBELEJ5RAvGKrKqdfny/J27+dVgJAAAeXj5nxl+n4pCfu1Pp/osahLBg5WPGWCAQEMGXIlCmlMqynJ9p6SBArIci
QpzdIx6PU0rzzYny8nLxp/YwMwWztQAAwthNp9OWZbVnWgquourqagBAJpMxTVNY6kcGaMhtapq2IUEJQICdg4AQOEXxKKMQg3hc
X7FiIyXMZnZNuHLJ1Hn+IJ7xxkNRK4YAMqhOqG1TYhLborZFLZtbVJX8sXI1o/XvefITN/26RPYDAOaunH/Hy7fikE+kXn8L8GIH
m6Oh8zVWezgQ9/Mo7u9TSpPJ5N69e3Vdb2xsrK+vr6ysHD16dDgc3rBhw6ZNm/bs2WMYRigUOv744/v169ezZ88vn5YkVVZWRqPR
999/f/v27bFYTFiQ1dXVJ5xwQr9+/crKypLJZEEsplKpTCbT1NRUX1+/f/9+Qsj1119fWVm5c+fO9evXb9++3bbtSCTSo0ePnj17
9urVq7KyMplMFt8EKKViEaqqun379k8//bShoUHXdUVRIpFI7969+/bt27VrV1VViytXZ13lcrktW7Zs27atsbHRNM1QKNSzZ88T
TzyxZ8+e6XT6d7/7nSzL3bp1q6mpqaioyHciAQBSOp327Ixul5ZBrtu6hDAHCCGIwCF0LGMUIahrZOUHnxi6xSEPIP+CiQ9071R7
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
Ojm5R4lEYsCAAcccc4zjVIh9Y+rUqdOnT89msyKF31kPl19++dKlS90se2tWWYEyBk78CQLIAMMI19V1uvvv987/cJ5U0hIK4a4X
sHHIAnp5WaaLZdDrho959NoZAIA9yX1jlly1qv59OewuEMMcTCOMcCpSmzlqwc0PDD5xQEZVI5GSYCD0189ev/K5q1WQwbKfUQqg
97UrCCErlr76khtGnt0SGXazDfnH3B0GtKSkxDMdGGPBubr3uHA47GFLcrmcwE2+BOeIv6cn+cf6RUTAyebJd1VFMMIBXCQSccxQ
N76FhZBOpzHGYrwi/CucRc/1mqZ17ty5IOElsLV69eqBAwcOGjTo9NNPp5Ru3Lhx1apVoquOqyrUs8jfQAgNGDBg7NixCxYskCSJ
ECIArarquHHjnnrqqZ/85Ce1tbWapu3bt2/t2rVr164Vt7v44ouXLl167rnnOs8lGAxefPHFDz30kJM3KwY4a9as55577swzz+zb
ty/GeM2aNW+//bZgRfOnTljVYjZataHdlWFtYtfV1j2xetGv/naf69Sq884UACDw6+Ul8U7UppQZW3Z/MnrWDZJf2myu39y0FocK
ljviCEsoGe6U7fHETbN+dsqgxqZGn88XKSlftu2NKxaPVoE7wYO7VDuEENCsft05ExaN+i0AIBptBgC1vIaWcyd3ws0TO7kc+buV
CETl89Ce7oogdkH215kocSbAQVK+EEFZFM54PAhohxhhjImyv/kaSPAJYvMV4xVDLsjROvZxQbZRzAljbMWKFe6irE6ehpgfQsgj
jzxywgknOATlfffd99Zbb+3evduNaQDAqlWrVq1alU+ncM51Xb/00kuXLl16zjnnAABEn8eNG/fMM880Nze7wYox3rdv3x//+EeP
kIKHuMQATdMsBmjH56WM1dXW/X7tszc/PxEF5IPM3KEEBcPAwlk5RrANGXh7+5uAUFChg0qG/QFPngbkiEOOMEbJks65o+ffNOtn
AwY3R6MIofKy8pc/fXX070frUMeyO8EDHtwNIIKcWtaVp09cNGqu+FswEBDv7fQHQrlsNj9C3p680DazRoszCe0kRtqU4LlRa9ZC
a+/UaY99kr+QBBbdcHfSp5xsu5tuuumGG25wf7G6unrJkiUXXHBBc3OzsHedxGU3sSNWr5CmKIqqqqNHj96+fbuwJVRV7d279+zZ
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
'@
$script:logoStream = $null
function Get-LogoBitmap {
    $w = 240
    $img = $null
    if ($script:appDir) {
        $p = Join-Path $script:appDir 'logo.jpg'
        if (Test-Path -LiteralPath $p) { try { $img = [System.Drawing.Image]::FromFile($p) } catch { $img = $null } }
    }
    if ($img) {
        $h = [int][Math]::Round($img.Height * $w / $img.Width)
        $bmp = New-Object System.Drawing.Bitmap($w, $h)
        $g = [System.Drawing.Graphics]::FromImage($bmp)
        $g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
        $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::HighQuality
        $g.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
        $g.Clear([System.Drawing.Color]::White)
        $g.DrawImage($img, 0, 0, $w, $h)
        $g.Dispose(); $img.Dispose()
        return $bmp
    }
    $bytes = [Convert]::FromBase64String(($script:logoB64 -replace '\s', ''))
    $script:logoStream = New-Object System.IO.MemoryStream(, $bytes)
    return (New-Object System.Drawing.Bitmap($script:logoStream))
}

# ------------------------------------------------------------- Interface ----
$form = New-Object System.Windows.Forms.Form
$form.Text = 'Conversion H.265 / MKV V8e - file d''attente'
$form.AutoScaleMode = [System.Windows.Forms.AutoScaleMode]::None
$form.ClientSize = New-Object System.Drawing.Size(900, 934)
$form.StartPosition = 'CenterScreen'
$form.FormBorderStyle = 'FixedDialog'
$form.MaximizeBox = $false
$form.BackColor = $script:white
$form.ForeColor = $script:cText
$form.Font = New-Object System.Drawing.Font('Arial', 9.5)

function Add-Label($text, $x, $y, $parent) {
    if (-not $parent) { $parent = $form }
    $l = New-Object System.Windows.Forms.Label
    $l.Text = $text; $l.Location = New-Object System.Drawing.Point($x, $y); $l.AutoSize = $true
    $l.ForeColor = $script:cText
    $parent.Controls.Add($l); return $l
}
function Add-Heading($text, $x, $y) {
    $l = Add-Label $text $x $y
    $l.Font = New-Object System.Drawing.Font('Arial', 9.5, [System.Drawing.FontStyle]::Bold)
    $l.ForeColor = $script:cGreen
    return $l
}
function Add-Button($text, $x, $y, $w, $h, [bool]$primary = $false, $parent = $null) {
    if (-not $parent) { $parent = $form }
    $b = New-Object System.Windows.Forms.Button
    $b.Text = $text; $b.Location = New-Object System.Drawing.Point($x, $y); $b.Size = New-Object System.Drawing.Size($w, $h)
    $b.FlatStyle = 'Flat'
    $b.UseVisualStyleBackColor = $false
    $b.Cursor = [System.Windows.Forms.Cursors]::Hand
    if ($primary) {
        $b.BackColor = $script:cGreen; $b.ForeColor = $script:white
        $b.Font = New-Object System.Drawing.Font('Arial', 10, [System.Drawing.FontStyle]::Bold)
        $b.FlatAppearance.BorderSize = 0
        $b.FlatAppearance.MouseOverBackColor = $script:cGreenDark
        $b.FlatAppearance.MouseDownBackColor = $script:cGreenDark
        $b.Add_EnabledChanged({
            if ($this.Enabled) { $this.BackColor = $script:cGreen } else { $this.BackColor = $script:cDisabled }
            $this.ForeColor = $script:white
        })
    } else {
        $b.BackColor = $script:white; $b.ForeColor = $script:cText
        $b.FlatAppearance.BorderSize = 1
        $b.FlatAppearance.BorderColor = $script:cBorder
        $b.FlatAppearance.MouseOverBackColor = $script:cWell
        $b.FlatAppearance.MouseDownBackColor = $script:cWell
    }
    $parent.Controls.Add($b); return $b
}

# --- En-tete : logo FFmpeg en haut a gauche (largeur 240 px) + bandeau vert ---
$pnlHead = New-Object System.Windows.Forms.Panel
$pnlHead.Location = New-Object System.Drawing.Point(0, 0)
$pnlHead.Size = New-Object System.Drawing.Size(900, 96)
$pnlHead.BackColor = $script:white
$form.Controls.Add($pnlHead)

[void](Ensure-LogoFile)
$logoBmp = Get-LogoBitmap
$pic = New-Object System.Windows.Forms.PictureBox
$pic.SizeMode = 'Normal'
$pic.Image = $logoBmp
$pic.Size = New-Object System.Drawing.Size($logoBmp.Width, $logoBmp.Height)
$pic.Location = New-Object System.Drawing.Point(16, 10)
$pic.BackColor = $script:white
$pnlHead.Controls.Add($pic)

$lblTitle = New-Object System.Windows.Forms.Label
$lblTitle.Text = 'Conversion video H.265 (HEVC) / MKV - V8e'
$lblTitle.Font = New-Object System.Drawing.Font('Arial', 15, [System.Drawing.FontStyle]::Bold)
$lblTitle.ForeColor = $script:cGreen
$lblTitle.AutoSize = $false
$lblTitle.Location = New-Object System.Drawing.Point(270, 20); $lblTitle.Size = New-Object System.Drawing.Size(566, 30)
$lblTitle.TextAlign = 'MiddleRight'
$pnlHead.Controls.Add($lblTitle)

$lblSub = New-Object System.Windows.Forms.Label
$lblSub.Text = 'Conversion par lots avec ffmpeg - analyse des videos et qualite automatique'
$lblSub.Font = New-Object System.Drawing.Font('Arial', 9)
$lblSub.ForeColor = $script:cMuted
$lblSub.AutoSize = $false
$lblSub.Location = New-Object System.Drawing.Point(270, 52); $lblSub.Size = New-Object System.Drawing.Size(614, 20)
$lblSub.TextAlign = 'MiddleRight'
$pnlHead.Controls.Add($lblSub)

# --- Logo engrenage cliquable (V7a) : ouvre la fenetre Parametres ---
function New-GearBitmap([System.Drawing.Color]$color, [int]$size = 32) {
    $bmp = New-Object System.Drawing.Bitmap($size, $size)
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
    $g.Clear([System.Drawing.Color]::White)
    $c = $size / 2.0
    $rOut = $size * 0.46; $rRoot = $size * 0.34
    $pts = New-Object 'System.Collections.Generic.List[System.Drawing.PointF]'
    for ($i = 0; $i -lt 8; $i++) {
        $a = $i * 45.0
        foreach ($d in @(@(-14.0, $rRoot), @(-9.0, $rOut), @(9.0, $rOut), @(14.0, $rRoot))) {
            $rad = ($a + $d[0]) * [Math]::PI / 180.0
            $pts.Add((New-Object System.Drawing.PointF([single]($c + $d[1] * [Math]::Cos($rad)), [single]($c + $d[1] * [Math]::Sin($rad)))))
        }
    }
    $path = New-Object System.Drawing.Drawing2D.GraphicsPath([System.Drawing.Drawing2D.FillMode]::Alternate)
    $path.AddPolygon($pts.ToArray())
    $rh = $size * 0.16
    $path.AddEllipse([single]($c - $rh), [single]($c - $rh), [single](2 * $rh), [single](2 * $rh))
    $br = New-Object System.Drawing.SolidBrush($color)
    $g.FillPath($br, $path)
    $br.Dispose(); $path.Dispose(); $g.Dispose()
    return $bmp
}
$script:gearOff = New-GearBitmap $script:cMuted 32
$script:gearOn  = New-GearBitmap $script:cGreen 32
$picGear = New-Object System.Windows.Forms.PictureBox
$picGear.SizeMode = 'Normal'
$picGear.Image = $script:gearOff
$picGear.Size = New-Object System.Drawing.Size(32, 32)
$picGear.Location = New-Object System.Drawing.Point(850, 18)
$picGear.BackColor = $script:white
$picGear.Cursor = [System.Windows.Forms.Cursors]::Hand
$picGear.Add_MouseEnter({ $picGear.Image = $script:gearOn })
$picGear.Add_MouseLeave({ $picGear.Image = $script:gearOff })
$picGear.Add_Click({ Show-SettingsWindow })
$pnlHead.Controls.Add($picGear)

$pnlStrip = New-Object System.Windows.Forms.Panel
$pnlStrip.Location = New-Object System.Drawing.Point(0, 96)
$pnlStrip.Size = New-Object System.Drawing.Size(900, 4)
$pnlStrip.BackColor = $script:cGreen
$form.Controls.Add($pnlStrip)

# --- File d'attente ---
Add-Heading 'Videos a convertir (glisser-deposer possible)' 20 116 | Out-Null
$lv = New-Object System.Windows.Forms.ListView
$lv.Location = New-Object System.Drawing.Point(20, 140); $lv.Size = New-Object System.Drawing.Size(860, 150)
$lv.View = 'Details'; $lv.FullRowSelect = $true; $lv.MultiSelect = $true; $lv.GridLines = $true; $lv.AllowDrop = $true
$lv.BorderStyle = 'FixedSingle'
[void]$lv.Columns.Add('Fichier', 500)
[void]$lv.Columns.Add('Duree', 90)
[void]$lv.Columns.Add('Etat', 245)
$form.Controls.Add($lv)

$btnAdd    = Add-Button 'Ajouter des videos...' 20 300 170 30
$btnRemove = Add-Button 'Retirer la selection' 200 300 170 30
$btnClear  = Add-Button 'Vider la liste'       380 300 140 30
$btnPause  = Add-Button 'Pause'              530 300 140 30
$btnPause.Enabled = $false
$btnImg    = Add-Button 'Apercu / reglages image...' 680 300 200 30

# --- Dossier de sortie ---
Add-Heading 'Dossier de sortie (commun a toutes les videos)' 20 346 | Out-Null
$txtOut = New-Object System.Windows.Forms.TextBox
$txtOut.Location = New-Object System.Drawing.Point(20, 370); $txtOut.Size = New-Object System.Drawing.Size(740, 26)
$txtOut.BorderStyle = 'FixedSingle'
$form.Controls.Add($txtOut)
$btnOut = Add-Button 'Parcourir...' 770 368 110 30

# --- Options : NVIDIA + potentiometre CPU + boutons ---
$well = New-Object System.Windows.Forms.Panel
$well.Location = New-Object System.Drawing.Point(20, 414); $well.Size = New-Object System.Drawing.Size(860, 202)
$well.BackColor = $script:cWell
$well.BorderStyle = 'FixedSingle'
$form.Controls.Add($well)

# Case NVIDIA (detection automatique)
$script:nvOk = $false
$chkNv = New-Object System.Windows.Forms.CheckBox
$chkNv.Location = New-Object System.Drawing.Point(14, 8); $chkNv.Size = New-Object System.Drawing.Size(830, 24)
$chkNv.Text = 'Detection de la carte NVIDIA en cours...'
$chkNv.ForeColor = $script:cText
$well.Controls.Add($chkNv)

# Case Intel Quick Sync (detection automatique)
$script:qsvOk = $false
$script:intelText = ''
$chkIntel = New-Object System.Windows.Forms.CheckBox
$chkIntel.Location = New-Object System.Drawing.Point(14, 34); $chkIntel.Size = New-Object System.Drawing.Size(830, 24)
$chkIntel.Text = 'Detection du GPU Intel en cours...'
$chkIntel.ForeColor = $script:cText
$well.Controls.Add($chkIntel)

# Potentiometre processeur
$knob = New-Object KnobControl
$knob.Location = New-Object System.Drawing.Point(14, 76)
$knob.Size = New-Object System.Drawing.Size(62, 62)
$knob.Minimum = 10; $knob.Maximum = 100; $knob.Value = 50
$knob.BackColor = $script:cWell
$well.Controls.Add($knob)

Add-Label 'Utilisation du processeur' 92 72 $well | Out-Null
$lblCpuVal = New-Object System.Windows.Forms.Label
$lblCpuVal.Font = New-Object System.Drawing.Font('Arial', 15, [System.Drawing.FontStyle]::Bold)
$lblCpuVal.ForeColor = $script:cGreen
$lblCpuVal.Location = New-Object System.Drawing.Point(90, 90); $lblCpuVal.Size = New-Object System.Drawing.Size(180, 28)
$well.Controls.Add($lblCpuVal)
$lblThr = Add-Label '' 92 120 $well
$hint = Add-Label 'Glisser, molette ou fleches' 250 123 $well
$hint.Font = New-Object System.Drawing.Font('Arial', 8)
$hint.ForeColor = $script:cMuted

function Update-CpuLabels {
    $lblCpuVal.Text = '{0} %' -f $script:cpuPct
    $lblThr.Text = '{0} thread(s) sur {1}' -f $script:threads, $script:logical
}
Update-CpuLabels

$btnStart  = Add-Button 'Convertir' 330 76 150 44 $true $well
$btnCancel = Add-Button 'Annuler'   494 76 120 44 $false $well
$btnCancel.Enabled = $false

# Case Upscaling 1080p HD (desactivee par defaut)
$chkUp = New-Object System.Windows.Forms.CheckBox
$chkUp.Location = New-Object System.Drawing.Point(640, 80); $chkUp.Size = New-Object System.Drawing.Size(206, 24)
$chkUp.Text = 'Upscaling 1080p HD'
$chkUp.ForeColor = $script:cText
$chkUp.Checked = $false
$well.Controls.Add($chkUp)

# Case Encodage 2 passes : disponible quand l'upscaling est coche, mais jamais forcee
$chkTwo = New-Object System.Windows.Forms.CheckBox
$chkTwo.Location = New-Object System.Drawing.Point(640, 108); $chkTwo.Size = New-Object System.Drawing.Size(206, 24)
$chkTwo.Text = 'Encodage en 2 passes'
$chkTwo.ForeColor = $script:cText
$chkTwo.Checked = $false
$chkTwo.Enabled = $true
$well.Controls.Add($chkTwo)

# Case Comparaison des couleurs avant compression (V7)
$chkCmp = New-Object System.Windows.Forms.CheckBox
$chkCmp.Location = New-Object System.Drawing.Point(14, 138); $chkCmp.Size = New-Object System.Drawing.Size(830, 24)
$chkCmp.Text = 'Comparer l''original et la sortie avant compression et corriger les couleurs (assombrissement)'
$chkCmp.ForeColor = $script:cText
$chkCmp.Checked = $true
$well.Controls.Add($chkCmp)

# Case Reglages image valides (V7) : active apres validation dans la fenetre d'apercu
$chkImg = New-Object System.Windows.Forms.CheckBox
$chkImg.Location = New-Object System.Drawing.Point(14, 166); $chkImg.Size = New-Object System.Drawing.Size(830, 24)
$chkImg.Text = 'Appliquer les reglages image valides (aucun pour l''instant)'
$chkImg.ForeColor = $script:cText
$chkImg.Checked = $false
$chkImg.Enabled = $false
$well.Controls.Add($chkImg)

# --- V8 : profil, mode de qualite et options (colonne de droite) ---
$chkNv.Size = New-Object System.Drawing.Size(610, 24)
$chkIntel.Size = New-Object System.Drawing.Size(610, 24)
$chkCmp.Size = New-Object System.Drawing.Size(620, 24)
$chkImg.Size = New-Object System.Drawing.Size(620, 24)
Add-Label 'Profil' 640 12 $well | Out-Null
$cmbProfile = New-Object System.Windows.Forms.ComboBox
$cmbProfile.DropDownStyle = 'DropDownList'
$cmbProfile.Location = New-Object System.Drawing.Point(700, 8); $cmbProfile.Size = New-Object System.Drawing.Size(145, 26)
[void]$cmbProfile.Items.Add('Rapide'); [void]$cmbProfile.Items.Add('Equilibre'); [void]$cmbProfile.Items.Add('Archivage')
$cmbProfile.SelectedIndex = @{ rapide = 0; equilibre = 1; archivage = 2 }["$($script:v8.Profile)"]
$well.Controls.Add($cmbProfile)
Add-Label 'Qualite' 640 42 $well | Out-Null
$cmbQMode = New-Object System.Windows.Forms.ComboBox
$cmbQMode.DropDownStyle = 'DropDownList'
$cmbQMode.Location = New-Object System.Drawing.Point(700, 38); $cmbQMode.Size = New-Object System.Drawing.Size(145, 26)
[void]$cmbQMode.Items.Add('Automatique'); [void]$cmbQMode.Items.Add('Fixe'); [void]$cmbQMode.Items.Add('Debit cible')
$cmbQMode.SelectedIndex = @{ auto = 0; fixe = 1; debit = 2 }["$($script:v8.QMode)"]
$well.Controls.Add($cmbQMode)
$btnQual = Add-Button 'Options qualite / analyse...' 640 166 205 28 $false $well
$cmbProfile.Add_SelectedIndexChanged({
    $script:v8.Profile = @('rapide', 'equilibre', 'archivage')[$cmbProfile.SelectedIndex]
    if ($script:qw) { $script:qw.cp.SelectedIndex = $cmbProfile.SelectedIndex }
    Save-V8Settings; Update-Preview
})
$cmbQMode.Add_SelectedIndexChanged({
    $script:v8.QMode = @('auto', 'fixe', 'debit')[$cmbQMode.SelectedIndex]
    if ($script:qw) { $script:qw.cm.SelectedIndex = $cmbQMode.SelectedIndex }
    Save-V8Settings; Update-Preview
})
$btnQual.Add_Click({ Show-QualityWindow })

$tip = New-Object System.Windows.Forms.ToolTip
$tip.AutoPopDelay = 25000
$tip.SetToolTip($chkUp, 'Agrandit les videos plus petites que 1080p vers 1920x1080 maximum (proportions conservees). Filtre Lanczos haute precision, desentrelacement si besoin, encodage a qualite constante (le debit n''est plus limite a original/1,8, le fichier peut donc etre plus gros). Une legere nettete automatique est ajoutee apres l''agrandissement. Les videos deja en 1080p ou plus ne sont pas modifiees.')
$tip.SetToolTip($chkTwo, 'Utilisable avec ou sans upscaling (se coche automatiquement avec l''upscaling, decochable). Encodage a debit cible en 2 passes pour un final de haute qualite : sans upscaling le debit vise original/1,8 ; avec upscaling il est calcule pour du 1080p, sans jamais descendre sous original/1,8. Processeur : x265 analyse la video (passe 1) puis l''encode (passe 2), environ 2 fois plus long. NVIDIA : 2 passes materielles (multipass). Intel Quick Sync : pas de 2 passes materielles, debit cible seulement.')
$tip.SetToolTip($btnImg, 'Ouvre une fenetre flottante independante : image originale et apercu avec reglages (luminosite, contraste, saturation, gamma, nettete, depixelisation). Les reglages ne sont appliques a la conversion qu''apres validation.')
$tip.SetToolTip($picGear, 'Parametres : version, depot GitHub, mises a jour (application et ffmpeg)')
$tip.SetToolTip($chkCmp, 'Avant chaque video : encode 3 extraits courts (20, 50 et 80 % de la duree) avec les memes reglages, compare la luminosite et les couleurs moyennes avec l''original, puis corrige l''ecart dans l''encodage final. Un controle final original / sortie est fait a la fin. Ajoute quelques secondes (jusqu''a une minute en processeur) par video.')
$tip.SetToolTip($chkImg, 'Active ou desactive les reglages image valides dans la fenetre d''apercu.')
$tip.SetToolTip($cmbProfile, 'Rapide : x265 medium / NVENC p5. Equilibre : x265 slow / NVENC p7 (recommande). Archivage : x265 slower impose (CPU, tres long).')
$tip.SetToolTip($cmbQMode, 'Automatique : cherche le CRF/CQ qui atteint le score cible (VMAF 93 / 95 / 96,5 ou SSIM) sur 3 extraits. Fixe : CRF/CQ du profil. Debit cible : original / rapport du codec (2 passes possibles).')
$tip.SetToolTip($btnQual, 'Options d''analyse et de traitement (desentrelacement, recadrage, anti-pixelisation, 10 bits, audio...) et analyse de la file d''attente.')
$tip.SetToolTip($knob, 'Glisser, molette ou fleches. Pris en compte au fichier suivant.')

# --- Chronometre ---
$lblChrono = New-Object System.Windows.Forms.Label
$lblChrono.Text = '00:00:00'
$lblChrono.Font = New-Object System.Drawing.Font('Consolas', 28, [System.Drawing.FontStyle]::Bold)
$lblChrono.ForeColor = $script:cText
$lblChrono.Location = New-Object System.Drawing.Point(20, 640); $lblChrono.Size = New-Object System.Drawing.Size(300, 50)
$lblChrono.TextAlign = 'MiddleLeft'
$form.Controls.Add($lblChrono)

$lblFile = New-Object System.Windows.Forms.Label
$lblFile.Text = ''
$lblFile.ForeColor = $script:cMuted
$lblFile.Location = New-Object System.Drawing.Point(360, 644); $lblFile.Size = New-Object System.Drawing.Size(520, 22)
$lblFile.TextAlign = 'MiddleRight'
$form.Controls.Add($lblFile)

$lblPct = New-Object System.Windows.Forms.Label
$lblPct.Text = '0 %'
$lblPct.Font = New-Object System.Drawing.Font('Arial', 14, [System.Drawing.FontStyle]::Bold)
$lblPct.ForeColor = $script:cGreen
$lblPct.Location = New-Object System.Drawing.Point(620, 668); $lblPct.Size = New-Object System.Drawing.Size(260, 28)
$lblPct.TextAlign = 'MiddleRight'
$form.Controls.Add($lblPct)

$l1 = Add-Label 'Fichier en cours' 20 702
$l1.Font = New-Object System.Drawing.Font('Arial', 8.5); $l1.ForeColor = $script:cMuted
$bar = New-Object FlatProgress
$bar.Location = New-Object System.Drawing.Point(20, 722); $bar.Size = New-Object System.Drawing.Size(860, 14)
$bar.Minimum = 0; $bar.Maximum = 1000
$form.Controls.Add($bar)

$l2 = Add-Label 'Progression totale' 20 744
$l2.Font = New-Object System.Drawing.Font('Arial', 8.5); $l2.ForeColor = $script:cMuted
$barAll = New-Object FlatProgress
$barAll.Location = New-Object System.Drawing.Point(20, 764); $barAll.Size = New-Object System.Drawing.Size(860, 14)
$barAll.Minimum = 0; $barAll.Maximum = 1000
$form.Controls.Add($barAll)

$lblStatus = New-Object System.Windows.Forms.Label
$lblStatus.Text = 'Pret.'
$lblStatus.ForeColor = $script:cText
$lblStatus.Location = New-Object System.Drawing.Point(20, 786); $lblStatus.Size = New-Object System.Drawing.Size(860, 20)
$form.Controls.Add($lblStatus)

# --- Ligne de commande ---
Add-Heading 'Ligne de commande ffmpeg (mise a jour automatique)' 20 818 | Out-Null
$txtCmd = New-Object System.Windows.Forms.TextBox
$txtCmd.Location = New-Object System.Drawing.Point(20, 840); $txtCmd.Size = New-Object System.Drawing.Size(860, 76)
$txtCmd.Multiline = $true; $txtCmd.ReadOnly = $true; $txtCmd.ScrollBars = 'Vertical'; $txtCmd.WordWrap = $true
$txtCmd.BorderStyle = 'FixedSingle'
$txtCmd.Font = New-Object System.Drawing.Font('Consolas', 8.5)
$txtCmd.BackColor = $script:cWell
$txtCmd.ForeColor = $script:cText
$form.Controls.Add($txtCmd)

# ------------------------------------------------------------ File d'attente
$script:queue = New-Object System.Collections.Generic.List[object]
$script:running = $false

function Format-Time([double]$sec) {
    $t = [TimeSpan]::FromSeconds([Math]::Max($sec, 0))
    return '{0:00}:{1:00}:{2:00}' -f [int][Math]::Floor($t.TotalHours), $t.Minutes, $t.Seconds
}

# Texte de la ligne de commande (2 lignes en 2 passes x265)
function Format-Cmd($plan, [int]$only = 0) {
    $exe = Q $script:ffmpeg
    if ($plan.Passes -eq 2) {
        $l1 = 'Passe 1/2 : ' + $exe + ' ' + $plan.Args1
        $l2 = 'Passe 2/2 : ' + $exe + ' ' + $plan.Args
        if ($only -eq 1) { return $l1 }
        if ($only -eq 2) { return $l2 }
        return $l1 + "`r`n" + $l2
    }
    return $exe + ' ' + $plan.Args
}

# Rafraichit la ligne de commande affichee (fichier selectionne, sinon le premier, sinon exemple)
function Update-Preview {
    if ($script:running) { return }
    $src = 'source.avi'; $info = $null
    $sel = $null
    if ($lv.SelectedIndices.Count -gt 0) { $sel = $script:queue[$lv.SelectedIndices[0]] }
    elseif ($script:queue.Count -gt 0)   { $sel = $script:queue[0] }
    if ($sel) { $src = $sel.Path; $info = $sel.Info }
    $outDir = $txtOut.Text.Trim()
    if (-not $outDir) { $outDir = '<dossier_sortie>' }
    $dst = $outDir.TrimEnd('\') + '\' + [IO.Path]::GetFileNameWithoutExtension($src) + '_X265.mkv'
    $prog = $env:TEMP + '\ffprog_<id>.txt'
    try {
        $an0 = $null
        if ($sel -and $script:analysis.ContainsKey($sel.Path)) { $an0 = $script:analysis[$sel.Path] }
        $plan = Build-FfmpegArgs $info $src $dst $prog (Get-EncoderMode) $chkUp.Checked $chkTwo.Checked $null -1.0 0.0 $an0
        $txtCmd.Text = Format-Cmd $plan
    } catch {
        $txtCmd.Text = 'Commande indisponible : ' + $_.Exception.Message
    }
}

function Add-Files([string[]]$paths) {
    $form.Cursor = 'WaitCursor'
    foreach ($p in $paths) {
        if (-not (Test-Path -LiteralPath $p -PathType Leaf)) { continue }
        if ($script:queue | Where-Object { $_.Path -eq $p }) { continue }
        $info = Get-Info $p
        $d = 0.0
        if ($info) { [void][double]::TryParse("$($info.format.duration)", [Globalization.NumberStyles]::Float, $inv, [ref]$d) }
        $script:queue.Add([pscustomobject]@{ Path = $p; Duration = $d; Info = $info })
        $row = New-Object System.Windows.Forms.ListViewItem([IO.Path]::GetFileName($p))
        [void]$row.SubItems.Add((Format-Time $d))
        [void]$row.SubItems.Add('En attente')
        $row.ToolTipText = $p
        [void]$lv.Items.Add($row)
        if (-not $txtOut.Text) { $txtOut.Text = [IO.Path]::GetDirectoryName($p) }
    }
    $form.Cursor = 'Default'
    Update-Preview
}

$btnAdd.Add_Click({
    $d = New-Object System.Windows.Forms.OpenFileDialog
    $d.Title = 'Choisir une ou plusieurs videos'
    $d.Multiselect = $true
    $d.Filter = 'Videos|*.avi;*.mkv;*.mp4;*.mov;*.wmv;*.flv;*.webm;*.m4v;*.mpg;*.mpeg;*.ts;*.m2ts;*.vob;*.ogv;*.3gp|Tous les fichiers|*.*'
    if ($d.ShowDialog() -eq 'OK') { Add-Files $d.FileNames }
})
$btnRemove.Add_Click({
    $idx = @($lv.SelectedIndices | Sort-Object -Descending)
    foreach ($i in $idx) { $script:queue.RemoveAt($i); $lv.Items.RemoveAt($i) }
    Update-Preview
})
$btnClear.Add_Click({ $script:queue.Clear(); $lv.Items.Clear(); Update-Preview })

$lv.Add_DragEnter({ if ($_.Data.GetDataPresent([Windows.Forms.DataFormats]::FileDrop)) { $_.Effect = 'Copy' } })
$lv.Add_DragDrop({ if (-not $script:running) { Add-Files ($_.Data.GetData([Windows.Forms.DataFormats]::FileDrop)) } })

$btnOut.Add_Click({
    $d = New-Object System.Windows.Forms.FolderBrowserDialog
    $d.Description = 'Dossier de sortie'
    if ($txtOut.Text -and (Test-Path -LiteralPath $txtOut.Text)) { $d.SelectedPath = $txtOut.Text }
    if ($d.ShowDialog() -eq 'OK') { $txtOut.Text = $d.SelectedPath }
})

# Mises a jour en direct de la ligne de commande
$knob.Add_ValueChanged({ Set-Cpu $knob.Value; Update-CpuLabels; Update-Preview })
function Update-GpuLabels {
    if ($script:qsvOk) {
        if ($chkNv.Checked -and $chkIntel.Checked) { $chkIntel.Text = $script:intelText + '  [NVIDIA prioritaire]' }
        else { $chkIntel.Text = $script:intelText }
    }
}
$chkNv.Add_CheckedChanged({ Update-GpuLabels; Update-Preview })
$chkIntel.Add_CheckedChanged({ Update-GpuLabels; Update-Preview })
$txtOut.Add_TextChanged({ Update-Preview })
$chkUp.Add_CheckedChanged({
    # Cocher l'upscaling coche aussi les 2 passes (decochables) ; la case reste utilisable seule
    if ($chkUp.Checked) { $chkTwo.Checked = $true }
    Update-Preview
})
$chkTwo.Add_CheckedChanged({ Update-Preview })
$lv.Add_SelectedIndexChanged({ Update-Preview })

# Detection NVIDIA et Intel au demarrage
# ================================================================ Fenetre Options qualite (V8)
$script:optDefs = @(
    @('Deint',    'Desentrelacement (bwdif)'),
    @('Ivtc',     'Telecine inverse (IVTC 3:2)'),
    @('Crop',     'Recadrage des bandes noires'),
    @('Deblock',  'Anti-pixelisation (deblock)'),
    @('Denoise',  'Reduction du bruit (hqdn3d)'),
    @('Deband',   'Anti-banding (degrades)'),
    @('Levels',   'Niveaux (images delavees)'),
    @('Tenbit',   'Encodage 10 bits'),
    @('Matrix',   'Matrice HD BT.709 (SD vers HD)'),
    @('Placebo',  'Mise a l''echelle libplacebo (GPU)'),
    @('SkipHevc', 'Ignorer sources deja HEVC/AV1/VP9'),
    @('Audio',    'Audio sans perte vers AC3/AAC'),
    @('Chapters', 'Conserver les chapitres'),
    @('Score',    'Score qualite final (VMAF/SSIM)')
)
$script:optTips = @{
    Deint    = 'Auto : desentrelace toutes les images (bwdif) si l''analyse detecte des lignes entrelacees, meme sans upscaling.'
    Ivtc     = 'Auto : si la source a 29,97 i/s presente le motif de telecine 3:2, retablit les 23,976 images/s d''origine (fieldmatch + decimate).'
    Crop     = 'Auto : retire les bandes noires detectees sur 3 extraits (au moins 16 pixels et 3 % de la dimension).'
    Deblock  = 'Auto : intensite choisie d''apres le debit par pixel de la source (normalise par codec). Aucun filtre si le debit est confortable.'
    Denoise  = 'Auto : hqdn3d seulement pour les sources tres compressees (niveau d''artefacts 3/3).'
    Deband   = 'Auto : adoucit les aplats a degrades en 8 bits sur les sources faiblement dotees en debit.'
    Levels   = 'Auto : etire les niveaux vers 16-235 seulement si noirs releves ET blancs ternes sont mesures. Oui : etire des que la plage est incomplete.'
    Tenbit   = 'Auto/Oui : encode en HEVC Main10 (moins de banding, meilleure efficacite) si l''encodeur le permet.'
    Matrix   = 'Auto : lors d''un upscaling SD vers HD, convertit la matrice BT.601 en BT.709 et ecrit les etiquettes BT.709.'
    Placebo  = 'Mise a l''echelle libplacebo (ewa_lanczos) a la place de Lanczos : exige un ffmpeg complet et un GPU Vulkan. Non par defaut.'
    SkipHevc = 'Auto : saute les sources deja HEVC/AV1/VP9 dont le debit est bas (moins de 0,10 bit/pixel).'
    Audio    = 'Auto : PCM, TrueHD, FLAC, DTS-HD MA... deviennent AC3 640k (5.1), AC3 448k ou AAC 256k/128k. Non : audio toujours copie.'
    Chapters = 'Oui : conserve les chapitres. Les autres metadonnees restent supprimees.'
    Score    = 'Oui : apres l''encodage, mesure VMAF (ou SSIM sans libvmaf) sur 3 extraits de la sortie et l''ecrit dans le journal.'
}
function Set-V8Controls {
    # affiche l'etat courant dans les listes de la fenetre d'options (si ouverte)
    if (-not $script:qw) { return }
    $map = @{ auto = 0; on = 1; off = 2 }
    foreach ($n in $script:v8Names) { $script:qw.cmb[$n].SelectedIndex = [int]$map["$($script:v8.Opt[$n])"] }
}

function Show-QualityWindow {
    if ($script:qualWin -and -not $script:qualWin.IsDisposed) { $script:qualWin.Activate(); return }
    $w = New-Object System.Windows.Forms.Form
    $w.Text = 'Options de qualite et analyse des videos (V8)'
    $w.AutoScaleMode = [System.Windows.Forms.AutoScaleMode]::None
    $w.ClientSize = New-Object System.Drawing.Size(880, 700)
    $w.StartPosition = 'CenterParent'
    $w.FormBorderStyle = 'FixedDialog'
    $w.MaximizeBox = $false; $w.MinimizeBox = $false; $w.ShowInTaskbar = $false
    $w.BackColor = $script:white; $w.ForeColor = $script:cText
    $w.Font = New-Object System.Drawing.Font('Arial', 9.5)
    $script:qualWin = $w
    $script:qw = @{ form = $w; cmb = @{} }
    $tp = New-Object System.Windows.Forms.ToolTip
    $tp.AutoPopDelay = 20000

    $strip = New-Object System.Windows.Forms.Panel
    $strip.Location = New-Object System.Drawing.Point(0, 0); $strip.Size = New-Object System.Drawing.Size(880, 4)
    $strip.BackColor = $script:cGreen
    $w.Controls.Add($strip)

    $h = Add-Label 'Profil et mode de qualite' 20 16 $w
    $h.Font = New-Object System.Drawing.Font('Arial', 10.5, [System.Drawing.FontStyle]::Bold); $h.ForeColor = $script:cGreen

    Add-Label 'Profil' 20 48 $w | Out-Null
    $cp = New-Object System.Windows.Forms.ComboBox
    $cp.DropDownStyle = 'DropDownList'; $cp.Location = New-Object System.Drawing.Point(70, 44); $cp.Size = New-Object System.Drawing.Size(170, 26)
    [void]$cp.Items.Add('Rapide'); [void]$cp.Items.Add('Equilibre'); [void]$cp.Items.Add('Archivage')
    $cp.SelectedIndex = @{ rapide = 0; equilibre = 1; archivage = 2 }["$($script:v8.Profile)"]
    $w.Controls.Add($cp); $script:qw.cp = $cp

    Add-Label 'Mode' 270 48 $w | Out-Null
    $cm = New-Object System.Windows.Forms.ComboBox
    $cm.DropDownStyle = 'DropDownList'; $cm.Location = New-Object System.Drawing.Point(320, 44); $cm.Size = New-Object System.Drawing.Size(330, 26)
    [void]$cm.Items.Add('Automatique : CRF/CQ cherche pour atteindre le score cible')
    [void]$cm.Items.Add('Fixe : CRF/CQ du profil')
    [void]$cm.Items.Add('Debit cible : original / rapport propre au codec')
    $cm.SelectedIndex = @{ auto = 0; fixe = 1; debit = 2 }["$($script:v8.QMode)"]
    $w.Controls.Add($cm); $script:qw.cm = $cm

    $ld = New-Object System.Windows.Forms.Label
    $ld.ForeColor = $script:cMuted; $ld.AutoSize = $false
    $ld.Location = New-Object System.Drawing.Point(20, 80); $ld.Size = New-Object System.Drawing.Size(840, 54)
    $w.Controls.Add($ld); $script:qw.ld = $ld
    $upd = {
        $pf = Get-V8Profile
        $tg = $(if ($script:caps.Vmaf) { ('VMAF {0:0.#}' -f $pf.Vmaf) } else { ('SSIM {0:0.000}' -f $pf.Ssim) })
        $t = switch ($script:v8.Profile) {
            'rapide'    { 'Rapide : x265 preset medium ou NVENC p5, cible ' + $tg + ' (tres bonne qualite, encodage plus court).' }
            'archivage' { 'Archivage : x265 (CPU) preset slower impose, cible ' + $tg + ' (qualite maximale, tres long).' }
            default     { 'Equilibre : x265 preset slow ou NVENC p7, cible ' + $tg + ' (recommande).' }
        }
        $t += "`r`nL'upscaling 1080p garde le comportement V7 (qualite constante, sans plafond de poids)."
        $script:qw.ld.Text = $t
    }
    $script:qw.updDesc = $upd
    & $upd
    $cp.Add_SelectedIndexChanged({
        $script:v8.Profile = @('rapide', 'equilibre', 'archivage')[$script:qw.cp.SelectedIndex]
        if ($script:cmbProfile) { $script:cmbProfile.SelectedIndex = $script:qw.cp.SelectedIndex }
        & $script:qw.updDesc; Save-V8Settings; Update-Preview
    })
    $cm.Add_SelectedIndexChanged({
        $script:v8.QMode = @('auto', 'fixe', 'debit')[$script:qw.cm.SelectedIndex]
        if ($script:cmbQMode) { $script:cmbQMode.SelectedIndex = $script:qw.cm.SelectedIndex }
        Save-V8Settings; Update-Preview
    })

    $h2 = Add-Label 'Traitements de l''image et de l''audio (Auto = decide apres analyse de chaque video)' 20 142 $w
    $h2.Font = New-Object System.Drawing.Font('Arial', 10.5, [System.Drawing.FontStyle]::Bold); $h2.ForeColor = $script:cGreen
    $half = 7
    for ($i = 0; $i -lt $script:optDefs.Count; $i++) {
        $def = $script:optDefs[$i]
        $col = [int][Math]::Floor($i / $half); $row = $i % $half
        $x = 20 + $col * 430; $y = 176 + $row * 34
        $lab = Add-Label $def[1] $x ($y + 4) $w
        $cb = New-Object System.Windows.Forms.ComboBox
        $cb.DropDownStyle = 'DropDownList'; $cb.Location = New-Object System.Drawing.Point(($x + 300), $y); $cb.Size = New-Object System.Drawing.Size(100, 26)
        [void]$cb.Items.Add('Auto'); [void]$cb.Items.Add('Oui'); [void]$cb.Items.Add('Non')
        $cb.Tag = $def[0]
        $w.Controls.Add($cb)
        $script:qw.cmb[$def[0]] = $cb
        $tp.SetToolTip($cb, $script:optTips[$def[0]]); $tp.SetToolTip($lab, $script:optTips[$def[0]])
    }
    Set-V8Controls
    foreach ($n in $script:v8Names) {
        $script:qw.cmb[$n].Add_SelectedIndexChanged({
            $script:v8.Opt[$this.Tag] = @('auto', 'on', 'off')[$this.SelectedIndex]
            Save-V8Settings; Update-Preview
        })
    }

    $h3 = Add-Label 'Analyse des videos de la file d''attente' 20 424 $w
    $h3.Font = New-Object System.Drawing.Font('Arial', 10.5, [System.Drawing.FontStyle]::Bold); $h3.ForeColor = $script:cGreen
    $tb = New-Object System.Windows.Forms.TextBox
    $tb.Multiline = $true; $tb.ReadOnly = $true; $tb.ScrollBars = 'Vertical'; $tb.BorderStyle = 'FixedSingle'
    $tb.Font = New-Object System.Drawing.Font('Consolas', 9)
    $tb.Location = New-Object System.Drawing.Point(20, 450); $tb.Size = New-Object System.Drawing.Size(840, 170)
    $tb.BackColor = $script:white
    $w.Controls.Add($tb); $script:qw.tb = $tb

    $lc = New-Object System.Windows.Forms.Label
    $lc.ForeColor = $script:cMuted; $lc.AutoSize = $false
    $lc.Font = New-Object System.Drawing.Font('Arial', 8.5)
    $lc.Location = New-Object System.Drawing.Point(20, 628); $lc.Size = New-Object System.Drawing.Size(840, 20)
    $lc.Text = Format-Capabilities
    $w.Controls.Add($lc)

    $bAn = Add-Button 'Analyser la file' 20 656 200 32 $true $w
    $bClose = Add-Button 'Fermer' 760 656 100 32 $false $w
    $w.CancelButton = $bClose
    $bClose.Add_Click({ $script:qualWin.Close() })
    $bAn.Add_Click({
        if ($script:running) { [System.Windows.Forms.MessageBox]::Show('Une conversion est en cours.', 'Analyse', 'OK', 'Information') | Out-Null; return }
        if ($script:queue.Count -eq 0) { $script:qw.tb.Text = 'La file d''attente est vide : ajoutez des videos.'; return }
        $script:cancelled = $false
        $script:analyzing = $true
        $script:qw.form.Cursor = [System.Windows.Forms.Cursors]::AppStarting
        $lines = New-Object System.Collections.Generic.List[string]
        $k = 0
        foreach ($it in $script:queue) {
            $k++
            $script:qw.tb.Text = (($lines -join "`r`n") + "`r`nAnalyse $k/$($script:queue.Count) : " + [IO.Path]::GetFileName($it.Path) + ' ...')
            [System.Windows.Forms.Application]::DoEvents()
            try {
                $an = Get-VideoAnalysis $it $it.Info
                $lines.Add([IO.Path]::GetFileName($it.Path))
                $lines.Add('   ' + $an.Report)
                $lines.Add('')
            } catch { $lines.Add([IO.Path]::GetFileName($it.Path) + ' : analyse impossible (' + $_.Exception.Message + ')') }
        }
        $script:qw.tb.Text = ($lines -join "`r`n")
        $script:analyzing = $false
        $script:qw.form.Cursor = [System.Windows.Forms.Cursors]::Default
        Update-Preview
    })
    $w.Add_FormClosed({ $script:qw = $null; $script:qualWin = $null })
    [void]$w.ShowDialog($form)
}

$form.Add_Shown({
    $form.Refresh()
    $gpu = Get-NvidiaName
    $ok = Test-Nvenc
    $script:nvOk = $ok
    $chkNv.Checked = $ok
    $chkNv.Enabled = $ok
    if ($ok) {
        $name = if ($gpu) { $gpu } else { 'carte NVIDIA' }
        $chkNv.Text = "Acceleration NVIDIA (NVENC) - detectee : $name"
    } else {
        $chkNv.Text = 'Acceleration NVIDIA (NVENC) - aucune carte compatible detectee'
    }

    # Detection Intel Quick Sync
    $form.Refresh()
    $igpu = Get-IntelName
    $qok = Test-Qsv
    $script:qsvOk = $qok
    $chkIntel.Checked = $qok
    $chkIntel.Enabled = $qok
    if ($qok) {
        $iname = if ($igpu) { $igpu } else { 'GPU Intel' }
        $script:intelText = "Acceleration Intel (Quick Sync) - detectee : $iname"
        $chkIntel.Text = $script:intelText
    } elseif ($igpu) {
        $chkIntel.Text = "Acceleration Intel (Quick Sync) - $igpu present mais Quick Sync indisponible (pilote ou ffmpeg sans QSV)"
    } else {
        $chkIntel.Text = 'Acceleration Intel (Quick Sync) - aucun GPU Intel compatible detecte'
    }
    Update-GpuLabels
    $oldSt = $lblStatus.Text
    $lblStatus.Text = 'Detection des capacites de ffmpeg (VMAF, libplacebo, options avancees des encodeurs)...'
    $form.Refresh()
    try { Update-Capabilities $script:nvOk $script:qsvOk; Write-Log 'INFO' ((Format-Capabilities) -replace "`r`n", ' | ') } catch {}
    Remove-OldVersions $script:appVersion
    $lblStatus.Text = $oldSt
    Update-Preview
})

# ----------------------------------------------------------- Execution ------
$script:proc = $null
$script:sw = New-Object System.Diagnostics.Stopwatch
$script:fileSw = New-Object System.Diagnostics.Stopwatch
$script:idx = 0
$script:duration = 0.0
$script:totalDur = 0.0
$script:doneDur = 0.0
$script:progressFile = $null
$script:errFile = $null
$script:dst = $null
$script:cancelled = $false
$script:srcSize = 0
$script:okCount = 0
$script:failCount = 0
$script:lastDec = 0
$script:paused = $false
$script:passNo = 1
$script:passTotal = 1
$script:plan = $null

$timer = New-Object System.Windows.Forms.Timer
$timer.Interval = 250

function Read-ProgressTail {
    try {
        $fs = [IO.File]::Open($script:progressFile, 'Open', 'Read', 'ReadWrite')
        try {
            $start = [Math]::Max(0, $fs.Length - 4096)
            $null = $fs.Seek($start, 'Begin')
            $sr = New-Object IO.StreamReader($fs)
            return $sr.ReadToEnd()
        } finally { $fs.Close() }
    } catch { return '' }
}

function Set-Busy([bool]$busy) {
    $script:running = $busy
    $btnStart.Enabled  = -not $busy
    $btnCancel.Enabled = $busy
    $btnPause.Enabled  = $busy
    foreach ($c in @($btnAdd, $btnRemove, $btnClear, $btnOut, $txtOut, $lv, $knob, $chkUp, $cmbProfile, $cmbQMode)) { $c.Enabled = -not $busy }
    $chkTwo.Enabled = (-not $busy)
    $chkCmp.Enabled = (-not $busy)
    $chkImg.Enabled = ((-not $busy) -and ($null -ne $script:imgValidated))
    if ($script:nvOk) { $chkNv.Enabled = -not $busy }
    if ($script:qsvOk) { $chkIntel.Enabled = -not $busy }
}

function Set-RowState([int]$i, [string]$text) { $lv.Items[$i].SubItems[2].Text = $text }

# Lance une passe ffmpeg (dans le dossier temporaire : fichiers de stats x265 relatifs)
function Start-Pass([string]$argString) {
    $script:proc = Start-Process -FilePath $script:ffmpeg -ArgumentList $argString -WorkingDirectory $env:TEMP `
        -WindowStyle Hidden -PassThru -RedirectStandardError $script:errFile
    $null = $script:proc.Handle    # garde le handle ouvert, sinon ExitCode reste vide (PowerShell)
    if ($null -ne $script:affinity) {
        try { $script:proc.ProcessorAffinity = [IntPtr]$script:affinity } catch {}   # limite aux N premiers coeurs
    }
}

# Lance le prochain fichier de la file. Retourne $false s'il n'en reste plus.
function Start-Next {
    while ($script:idx -lt $script:queue.Count) {
        $i = $script:idx
        $item = $script:queue[$i]
        $tag = '[{0}/{1}]' -f ($i + 1), $script:queue.Count
        $dst = Join-Path $txtOut.Text ([IO.Path]::GetFileNameWithoutExtension($item.Path) + '_X265.mkv')

        if (-not (Test-Path -LiteralPath $item.Path)) {
            Set-RowState $i 'Source introuvable'; $script:failCount++
            Write-Log 'ERREUR' "$tag Source introuvable : $($item.Path)"
            $script:doneDur += $item.Duration; $script:idx++; continue
        }
        if (Test-Path -LiteralPath $dst) {
            Set-RowState $i 'Ignore (fichier _X265 existant)'
            Write-Log 'INFO' "$tag Ignore, le fichier existe deja : $dst"
            $script:doneDur += $item.Duration; $script:idx++; continue
        }

        Write-Log 'INFO' "$tag Analyse : $($item.Path)"
        $info = $item.Info
        if (-not $info) { $info = Get-Info $item.Path }
        if (-not $info) {
            Set-RowState $i 'Erreur d''analyse'; $script:failCount++
            Write-Log 'ERREUR' "$tag Analyse impossible (ffprobe) : $($item.Path)"
            $script:doneDur += $item.Duration; $script:idx++; continue
        }
        # --- V8 : sources deja HEVC / analyse de la video ---
        $an0 = Get-StaticAnalysis $info
        if (Test-SkipSource $an0) {
            Set-RowState $i 'Ignore (deja HEVC/AV1/VP9 a faible debit)'
            Write-Log 'INFO' ("$tag Ignore : source deja en {0} a faible debit ({1:0} kb/s, {2:0.000} bit/pixel)" -f $an0.Codec, ($an0.Vbr / 1000), $an0.Bpp)
            $script:doneDur += $item.Duration; $script:idx++; continue
        }
        $script:analyzing = $true
        $an = $null
        Set-RowState $i 'Analyse de la video...'
        $lblStatus.Text = 'Analyse de la video (entrelacement, bandes noires, niveaux, artefacts)...'
        $lblFile.Text = ('Fichier {0}/{1} : {2}' -f ($i + 1), $script:queue.Count, [IO.Path]::GetFileName($item.Path))
        $form.Refresh()
        try { $an = Get-VideoAnalysis $item $info } catch { Write-Log 'AVERT' "$tag Analyse detaillee impossible : $($_.Exception.Message)" }
        $script:analyzing = $false
        if ($script:cancelled) {
            Set-RowState $i 'Annule'
            Write-Log 'AVERT' "$tag Annule pendant l'analyse"
            $script:idx++
            return $false
        }
        if (-not $an) { $an = $an0 }
        Write-Log 'INFO' "$tag Analyse : $($an.Report)"
        $script:progressFile = Join-Path $env:TEMP ("ffprog_{0}.txt" -f [guid]::NewGuid().ToString('N'))
        $script:errFile      = Join-Path $env:TEMP ("fferr_{0}.txt"  -f [guid]::NewGuid().ToString('N'))
        # --- V8 : recherche automatique de la qualite (CRF / CQ) sur 3 extraits ---
        $qo = -1.0; $aqNote = ''
        if ("$($script:v8.QMode)" -eq 'auto' -and -not $an.Hdr -and $item.Duration -gt 0) {
            $pp = $null
            try { $pp = Build-FfmpegArgs $info $item.Path $dst $script:progressFile (Get-EncoderMode) $chkUp.Checked $chkTwo.Checked $null -1.0 0.0 $an } catch {}
            if ($pp -and -not $pp.UpMode) {
                $script:analyzing = $true
                Set-RowState $i 'Recherche de la qualite...'
                $lblStatus.Text = 'Recherche de la qualite optimale (extraits encodes et mesures)...'
                $form.Refresh()
                $aq = $null
                try { $aq = Find-AutoQuality $item $info (Get-EncoderMode) $an }
                catch { Write-Log 'AVERT' "$tag Recherche de qualite impossible : $($_.Exception.Message)" }
                $script:analyzing = $false
                if ($script:cancelled) {
                    Set-RowState $i 'Annule'
                    Write-Log 'AVERT' "$tag Annule pendant la recherche de qualite"
                    $script:idx++
                    return $false
                }
                if ($aq) {
                    $qo = $aq.Q
                    $mname = $(if ($aq.Vmaf) { 'VMAF' } else { 'SSIM' })
                    $aqNote = ('Qualite automatique : {0} {1:0.#} (score {2} moyen {3:0.000}, cible {4}, {5} essai(s){6})' -f $(if ($pp.Mode -eq 'cpu') { 'CRF' } else { 'CQ' }), $aq.Q, $mname, $aq.Score, $aq.Target, $aq.Iter, $(if ($aq.Reached) { '' } else { ' - cible non atteinte, qualite maximale retenue' }))
                    Write-Log $(if ($aq.Reached) { 'INFO' } else { 'AVERT' }) "$tag $aqNote"
                } else {
                    Write-Log 'AVERT' "$tag Qualite automatique indisponible : qualite du profil utilisee"
                }
            }
        }
        $corr = $null
        if ($script:cmpOn) {
            $script:analyzing = $true
            Set-RowState $i 'Comparaison des couleurs...'
            $lblStatus.Text = 'Comparaison original / sortie sur extraits avant compression...'
            $lblFile.Text = ('Fichier {0}/{1} : {2}' -f ($i + 1), $script:queue.Count, [IO.Path]::GetFileName($item.Path))
            $form.Refresh()
            $cc = $null
            try { $cc = Get-ColorCorrection $item $info (Get-EncoderMode) $chkUp.Checked $an $qo }
            catch { Write-Log 'AVERT' "$tag Comparaison des couleurs impossible : $($_.Exception.Message)" }
            $script:analyzing = $false
            if ($script:cancelled) {
                Set-RowState $i 'Annule'
                Write-Log 'AVERT' "$tag Annule pendant la comparaison des couleurs"
                $script:idx++
                return $false
            }
            if ($cc) {
                $corr = $cc.Corr
                Write-Log 'INFO' ('{0} Comparaison avant compression ({1} extrait(s)) : ecart luminosite {2:+0.00;-0.00;0.00}, bleu {3:+0.00;-0.00;0.00}, rouge {4:+0.00;-0.00;0.00} (echelle 0-255) -> {5}' -f $tag, $cc.N, $cc.dY, $cc.dU, $cc.dV, $(if ($corr) { 'correction appliquee' } else { 'aucune correction necessaire' }))
            } else {
                Write-Log 'AVERT' "$tag Comparaison avant compression indisponible : encodage sans correction"
            }
        }
        try {
            $plan = Build-FfmpegArgs $info $item.Path $dst $script:progressFile (Get-EncoderMode) $chkUp.Checked $chkTwo.Checked $corr -1.0 0.0 $an $qo
        } catch {
            Set-RowState $i 'Erreur d''analyse'; $script:failCount++
            Write-Log 'ERREUR' "$tag Analyse impossible : $($_.Exception.Message)"
            $script:doneDur += $item.Duration; $script:idx++; continue
        }

        $script:dst = $dst
        $script:duration = if ($plan.Duration -gt 0) { $plan.Duration } else { $item.Duration }
        $script:srcSize = (Get-Item -LiteralPath $item.Path).Length
        $script:lastDec = 0
        $bar.Value = 0; $lblPct.Text = '0 %'
        $lblFile.Text = ('Fichier {0}/{1} : {2}' -f ($i + 1), $script:queue.Count, [IO.Path]::GetFileName($item.Path))
        Set-RowState $i 'En cours...'
        $lv.Items[$i].EnsureVisible()
        $lblStatus.Text = ('{0} | {1} | {2} piste(s) audio | {3} sous-titre(s)' -f $plan.Encoder, $plan.RateText, $plan.Audio, $plan.Subs)
        $txtCmd.Text = Format-Cmd $plan 1

        Write-Log 'INFO' ("$tag Debut conversion | {0} | CPU {1} % ({2} thread(s)) | {3} | audio {4} | sous-titres {5}" -f $plan.Encoder, $script:cpuPct, $script:threads, $plan.RateText, $plan.Audio, $plan.Subs)
        Write-Log 'INFO' "$tag Destination : $dst"
        if ($plan.ScaleNote) { Write-Log 'INFO' "$tag Upscaling 1080p : $($plan.ScaleNote)" }
        Write-Log 'INFO' "$tag $($plan.ColorNote)"
        if ($plan.FilterNotes) { Write-Log 'INFO' "$tag Filtres automatiques : $($plan.FilterNotes)" }
        if ($plan.TrackNote) { Write-Log 'INFO' "$tag Pistes : $($plan.TrackNote)" }
        if ($plan.AudioNote) { Write-Log 'INFO' "$tag Audio converti : $($plan.AudioNote)" }
        if ($plan.CorrNote) { Write-Log 'INFO' "$tag $($plan.CorrNote)" }
        if ($plan.ModeNote) { Write-Log 'INFO' "$tag $($plan.ModeNote)" }
        if ($plan.ImgNote) { Write-Log 'INFO' "$tag Reglages image : $($plan.ImgNote)" }
        if ($plan.PassNote) { Write-Log 'INFO' "$tag $($plan.PassNote)" }
        if ($plan.Passes -eq 2) { Write-Log 'INFO' "$tag Commande passe 1/2 : ffmpeg $($plan.Args1)" }
        Write-Log 'INFO' "$tag Commande : ffmpeg $($plan.Args)"

        $script:plan = $plan
        $script:planAn = $an
        $script:passNo = 1
        $script:passTotal = $plan.Passes
        if ($plan.Passes -eq 2) { Set-RowState $i 'En cours (passe 1/2)...' }
        $script:fileSw.Restart()
        if ($plan.Passes -eq 2) { Start-Pass $plan.Args1 } else { Start-Pass $plan.Args }
        return $true
    }
    return $false
}

function Finish-Batch {
    $timer.Stop(); $script:sw.Stop()
    $script:paused = $false
    $btnPause.Text = 'Pause'
    $script:proc = $null
    $lblChrono.Text = Format-Time $script:sw.Elapsed.TotalSeconds
    if ($script:cancelled) {
        $lblStatus.Text = 'Conversion annulee.'
        Write-Log 'AVERT' 'Conversion annulee par l''utilisateur.'
    } else {
        $barAll.Value = 1000
        $lblFile.Text = ''
        $lblStatus.Text = ('Termine en {0} : {1} converti(s), {2} erreur(s).' -f $lblChrono.Text, $script:okCount, $script:failCount)
    }
    Write-Log 'INFO' ('Fin de session en {0} : {1} converti(s), {2} erreur(s).' -f $lblChrono.Text, $script:okCount, $script:failCount)
    Write-Log 'INFO' '--------------------------------------------------'
    Set-Busy $false
    Update-Preview
    # Seules les erreurs sont notifiees a l'ecran
    if ($script:failCount -gt 0 -and -not $script:cancelled) {
        [System.Windows.Forms.MessageBox]::Show(
            ("{0} erreur(s) pendant la conversion.`nConsultez le journal :`n{1}" -f $script:failCount, $script:logFile),
            'Erreur', 'OK', 'Error') | Out-Null
    }
}

$timer.Add_Tick({
    $lblChrono.Text = Format-Time $script:sw.Elapsed.TotalSeconds
    if ($script:paused) { return }     # en pause : rien a mettre a jour
    if ($script:analyzing) { return }  # comparaison des couleurs en cours (evite la reentrance)

    if ($script:proc -and -not $script:proc.HasExited) {
        $t = Read-ProgressTail
        $m = [regex]::Matches($t, 'out_time_us=(\d+)')
        if ($m.Count -gt 0 -and $script:duration -gt 0) {
            $sec = [double]$m[$m.Count - 1].Groups[1].Value / 1e6
            $np = $script:passTotal
            $pf = [Math]::Min((($script:passNo - 1) + [Math]::Min($sec / $script:duration, 1.0)) / $np, 1.0)
            $doneWork = $script:doneDur * $np + ($script:passNo - 1) * $script:duration + $sec
            $totalWork = $script:totalDur * $np
            $bar.Value = [int]($pf * 1000)
            $lblPct.Text = ('{0:0.0} %' -f ($pf * 100))
            if ($totalWork -gt 0) {
                $barAll.Value = [int][Math]::Min(($doneWork / $totalWork) * 1000, 1000)
            }
            $dec = [int][Math]::Floor($pf * 10)
            if ($dec -gt $script:lastDec -and $dec -lt 10) {
                $script:lastDec = $dec
                Write-Log 'INFO' ('[{0}/{1}] Progression {2} %' -f ($script:idx + 1), $script:queue.Count, ($dec * 10))
            }
            $eta = ''
            $sp = [regex]::Matches($t, 'speed=\s*([\d\.]+)x')
            if ($sp.Count -gt 0) {
                $speed = [double]::Parse($sp[$sp.Count - 1].Groups[1].Value, $inv)
                if ($speed -gt 0) {
                    $restAll = ($totalWork - $doneWork) / $speed
                    $eta = ' | vitesse x{0:0.00} | reste total ~{1}' -f $speed, (Format-Time $restAll)
                }
            }
            $passTxt = ''
            if ($np -gt 1) { $passTxt = ' - passe {0}/{1}' -f $script:passNo, $np }
            $lblStatus.Text = 'Conversion en cours' + $passTxt + '...' + $eta
        }
        return
    }

    if ($script:proc -and $script:proc.HasExited) {
        $i = $script:idx
        $item = $script:queue[$i]
        $tag = '[{0}/{1}]' -f ($i + 1), $script:queue.Count
        $script:proc.WaitForExit()
        $code = $script:proc.ExitCode
        # Controle de secours : ffmpeg ecrit "progress=end" a la fin d'un encodage reussi
        $finished = ((Read-ProgressTail) -match 'progress=end')
        if ($null -eq $code -and $finished) { $code = 0 }
        $codeTxt = if ($null -eq $code) { 'inconnu' } else { "$code" }
        $errLines = @()
        if (Test-Path -LiteralPath $script:errFile) { $errLines = @(Get-Content -LiteralPath $script:errFile -Tail 10 -ErrorAction SilentlyContinue) }

        # Fin de la passe 1 (x265) : lancer la passe 2 sur le meme fichier
        if (-not $script:cancelled -and $code -eq 0 -and $script:plan.Passes -eq 2 -and $script:passNo -eq 1) {
            Write-Log 'INFO' ('{0} Passe 1/2 terminee en {1}' -f $tag, (Format-Time $script:fileSw.Elapsed.TotalSeconds))
            $script:passNo = 2
            $script:proc = $null
            Start-Pass $script:plan.Args
            Set-RowState $i 'En cours (passe 2/2)...'
            $txtCmd.Text = Format-Cmd $script:plan 2
            $lblStatus.Text = 'Passe 2/2 en cours...'
            return
        }

        if ($script:cancelled) {
            Set-RowState $i 'Annule'
            Write-Log 'AVERT' "$tag Annule : $($item.Path)"
            if (Test-Path -LiteralPath $script:dst) { Remove-Item -LiteralPath $script:dst -Force -ErrorAction SilentlyContinue }
        }
        elseif ($code -eq 0 -and (Test-Path -LiteralPath $script:dst)) {
            $out = (Get-Item -LiteralPath $script:dst).Length
            $ratio = if ($script:srcSize -gt 0) { 100 * $out / $script:srcSize } else { 0 }
            $colDiff = Test-ColorTags $script:dst $script:plan.Col
            if (-not $colDiff -and $script:cmpOn) {
                $script:analyzing = $true
                $lblStatus.Text = 'Controle final original / sortie...'
                $colDiff = Test-FinalQuality $item $script:plan $tag
                $script:analyzing = $false
            }
            if ($colDiff) {
                Set-RowState $i 'Termine - ALERTE couleur'
                $lv.Items[$i].ToolTipText = $colDiff
                $script:failCount++
                Write-Log 'ERREUR' "$tag Etiquettes de couleur differentes apres encodage : $colDiff"
            } else {
                Set-RowState $i ($(if ($ratio -gt 100) { 'Termine - PLUS GROS que l''original ({0:0} %)' } else { 'Termine ({0:0} % de l''original)' }) -f $ratio)
                $script:okCount++
                if ($ratio -gt 100) { Write-Log 'AVERT' ("$tag Le fichier converti est plus gros que l'original ({0:0} %) : conservez la source si la taille compte." -f $ratio) }
                Write-Log 'INFO' "$tag Controle couleurs : etiquettes identiques a la source"
                if (Test-Opt 'Score' $true) {
                    $script:analyzing = $true
                    $lblStatus.Text = 'Mesure du score de qualite final...'
                    $fs = $null
                    try { $fs = Get-FinalScore $item $script:plan } catch {}
                    $script:analyzing = $false
                    if ($fs) {
                        $pfin = Get-V8Profile
                        $tgt = $(if ($fs.Vmaf) { $pfin.Vmaf } else { $pfin.Ssim })
                        $mn = $(if ($fs.Vmaf) { 'VMAF' } else { 'SSIM' })
                        $lvl = $(if ($fs.Score -ge ($tgt - $(if ($fs.Vmaf) { 2.0 } else { 0.01 }))) { 'INFO' } else { 'AVERT' })
                        Write-Log $lvl ('{0} Score qualite final : {1} {2:0.000} sur 3 extraits (cible du profil {3})' -f $tag, $mn, $fs.Score, $tgt)
                        $lv.Items[$i].ToolTipText = ('Score {0} {1:0.00}' -f $mn, $fs.Score)
                    } else { Write-Log 'AVERT' "$tag Score qualite final indisponible" }
                }
            }
            $bar.Value = 1000; $lblPct.Text = '100 %'
            Write-Log 'INFO' ('{0} Termine en {1} : {2:N0} Mo -> {3:N0} Mo ({4:0} % de l''original)' -f $tag, (Format-Time $script:fileSw.Elapsed.TotalSeconds), ($script:srcSize / 1MB), ($out / 1MB), $ratio)
            foreach ($l in $errLines) { Write-Log 'AVERT' "$tag ffmpeg : $l" }
        }
        else {
            Set-RowState $i 'Echec'
            $lv.Items[$i].ToolTipText = ($errLines -join ' ')
            $script:failCount++
            Write-Log 'ERREUR' "$tag Echec ffmpeg (code $codeTxt) : $($item.Path)"
            foreach ($l in $errLines) { Write-Log 'ERREUR' "$tag ffmpeg : $l" }
            if (Test-Path -LiteralPath $script:dst) { Remove-Item -LiteralPath $script:dst -Force -ErrorAction SilentlyContinue }
        }
        Remove-Item $script:progressFile, $script:errFile -Force -ErrorAction SilentlyContinue
        if ($script:plan -and $script:plan.StatsName) {
            Remove-Item (Join-Path $env:TEMP $script:plan.StatsName), (Join-Path $env:TEMP ($script:plan.StatsName + '.cutree')) -Force -ErrorAction SilentlyContinue
        }
        $script:proc = $null
        $script:doneDur += $item.Duration
        $script:idx++

        if ($script:cancelled) { Finish-Batch; return }
        if (-not (Start-Next)) { Finish-Batch }
    }
})

$btnStart.Add_Click({
    if ($script:queue.Count -eq 0) {
        [System.Windows.Forms.MessageBox]::Show('Ajoutez au moins une video a la file d''attente.', 'Erreur', 'OK', 'Warning') | Out-Null; return
    }
    $out = $txtOut.Text.Trim()
    if (-not $out) {
        [System.Windows.Forms.MessageBox]::Show('Choisissez un dossier de sortie.', 'Erreur', 'OK', 'Warning') | Out-Null; return
    }
    if (-not (Test-Path -LiteralPath $out -PathType Container)) {
        try { New-Item -ItemType Directory -Path $out -Force | Out-Null }
        catch {
            [System.Windows.Forms.MessageBox]::Show('Impossible de creer le dossier de sortie.', 'Erreur', 'OK', 'Error') | Out-Null; return
        }
    }

    # Journal : log.txt dans le dossier de sortie (ajout en fin de fichier)
    $script:logFile = Join-Path $out 'log.txt'
    Write-Log 'INFO' '=================================================='
    Write-Log 'INFO' ('Debut de session | {0} video(s) en file | dossier de sortie : {1}' -f $script:queue.Count, $out)
    Write-Log 'INFO' ('Processeur : {0} % ({1} thread(s) sur {2})' -f $script:cpuPct, $script:threads, $script:logical)
    Write-Log 'INFO' ('Upscaling 1080p HD : ' + $(if ($chkUp.Checked) { 'active' } else { 'desactive' }))
    Write-Log 'INFO' ('Comparaison des couleurs avant compression : ' + $(if ($script:cmpOn) { 'activee' } else { 'desactivee' }))
    Write-Log 'INFO' ('Reglages image : ' + $(if ($script:imgOn -and $script:imgValidated) { 'actifs (' + (Format-ImgSummary $script:imgValidated) + ')' } else { 'inactifs' }))
    Write-Log 'INFO' ('Encodage 2 passes : ' + $(if ($chkTwo.Checked) { 'active' } else { 'desactive' }))
    $mode = Get-EncoderMode
    if ($mode -eq 'nvenc') { Write-Log 'INFO' 'Acceleration NVIDIA (NVENC) : activee' }
    elseif ($script:nvOk) { Write-Log 'INFO' 'Acceleration NVIDIA (NVENC) : detectee mais desactivee par l''utilisateur' }
    else { Write-Log 'INFO' 'Acceleration NVIDIA (NVENC) : aucune carte compatible detectee' }
    if ($mode -eq 'qsv') { Write-Log 'INFO' 'Acceleration Intel (Quick Sync) : activee' }
    elseif ($script:qsvOk -and $chkIntel.Checked) { Write-Log 'INFO' 'Acceleration Intel (Quick Sync) : detectee mais non utilisee (NVIDIA prioritaire)' }
    elseif ($script:qsvOk) { Write-Log 'INFO' 'Acceleration Intel (Quick Sync) : detectee mais desactivee par l''utilisateur' }
    else { Write-Log 'INFO' 'Acceleration Intel (Quick Sync) : aucun GPU Intel compatible detecte' }
    if ($mode -eq 'cpu') { Write-Log 'INFO' 'Encodage : libx265 (CPU)' }

    for ($i = 0; $i -lt $lv.Items.Count; $i++) { Set-RowState $i 'En attente'; $lv.Items[$i].ToolTipText = $script:queue[$i].Path }
    $script:totalDur = 0.0
    foreach ($q in $script:queue) { $script:totalDur += $q.Duration }
    $script:passTotal = $(if ((Get-EncoderMode) -eq 'cpu' -and $chkTwo.Checked) { 2 } else { 1 })
    $script:idx = 0; $script:doneDur = 0.0; $script:okCount = 0; $script:failCount = 0
    $script:cancelled = $false
    $bar.Value = 0; $barAll.Value = 0; $lblPct.Text = '0 %'; $lblChrono.Text = '00:00:00'
    Set-Busy $true

    $script:sw.Restart()
    if (Start-Next) { $timer.Start() } else { Finish-Batch }
})

$btnCancel.Add_Click({
    if ($script:analyzing) { $script:cancelled = $true; return }
    if ($script:proc -and -not $script:proc.HasExited) {
        $script:cancelled = $true
        if ($script:paused) { $script:paused = $false; $btnPause.Text = 'Pause' }
        try { $script:proc.Kill() } catch {}
    }
})

# Pause / reprise : suspend le processus ffmpeg et le chronometre
$btnPause.Add_Click({
    if (-not $script:proc -or $script:proc.HasExited) { return }
    $tag = '[{0}/{1}]' -f ($script:idx + 1), $script:queue.Count
    if (-not $script:paused) {
        $r = [ProcCtl]::Suspend($script:proc.Handle)
        if ($r -ne 0) {
            Write-Log 'ERREUR' "$tag Pause impossible (code $r)"
            $lblStatus.Text = 'Pause impossible.'
            return
        }
        $script:paused = $true
        $script:sw.Stop(); $script:fileSw.Stop()
        $btnPause.Text = 'Reprendre'
        Set-RowState $script:idx 'En pause'
        $lblStatus.Text = 'En pause - cliquez sur Reprendre pour continuer.'
        Write-Log 'INFO' "$tag Pause"
    } else {
        $r = [ProcCtl]::Resume($script:proc.Handle)
        if ($r -ne 0) {
            Write-Log 'ERREUR' "$tag Reprise impossible (code $r)"
            $lblStatus.Text = 'Reprise impossible.'
            return
        }
        $script:paused = $false
        $script:sw.Start(); $script:fileSw.Start()
        $btnPause.Text = 'Pause'
        Set-RowState $script:idx 'En cours...'
        $lblStatus.Text = 'Conversion en cours...'
        Write-Log 'INFO' "$tag Reprise"
    }
})


# ======================================================================
#  Fenetre flottante d'apercu et de reglages image (V7)
#  Independante de la fenetre principale. Les reglages ne sont appliques
#  a la conversion qu'apres clic sur "Valider les reglages".
# ======================================================================
$script:imgWin = $null
$script:iw = @{}

function Format-ImgVal([string]$key, [int]$v) {
    switch ($key) {
        'Bright'   { return ($v / 100.0).ToString('+0.00;-0.00;0.00', $inv) }
        'Contrast' { return ($v / 100.0).ToString('0.00', $inv) }
        'Sat'      { return ($v / 100.0).ToString('0.00', $inv) }
        'Gamma'    { return ($v / 100.0).ToString('0.00', $inv) }
        default    { return "$v" }
    }
}

# Extrait une image de la video avec ffmpeg et la retourne en Bitmap (copie, aucun fichier verrouille)
function Render-Frame([string]$src, [double]$t, [string]$vf) {
    $png = Join-Path $env:TEMP ('ffprev_{0}.png' -f [guid]::NewGuid().ToString('N'))
    $err = $png + '.err'
    $argList = '-hide_banner -loglevel error -y -ss {0} -i {1} -frames:v 1 -an -sn -vf {2} -pix_fmt rgb24 {3}' -f $t.ToString('0.###', $inv), (Q $src), (Q $vf), (Q $png)
    $bmp = $null
    try {
        $p = Start-Process -FilePath $script:ffmpeg -ArgumentList $argList -WorkingDirectory $env:TEMP `
            -WindowStyle Hidden -PassThru -RedirectStandardError $err
        $null = $p.Handle
        if (-not $p.WaitForExit(25000)) { try { $p.Kill() } catch {} }
        if (Test-Path -LiteralPath $png) {
            $bytes = [IO.File]::ReadAllBytes($png)
            $ms = New-Object IO.MemoryStream(, $bytes)
            $tmp = New-Object System.Drawing.Bitmap($ms)
            $bmp = New-Object System.Drawing.Bitmap($tmp)
            $tmp.Dispose(); $ms.Dispose()
        }
    } catch {
        $bmp = $null
    } finally {
        Remove-Item -LiteralPath $png, $err -Force -ErrorAction SilentlyContinue
    }
    return $bmp
}

function Get-PreviewItem {
    $i = $script:iw.cmb.SelectedIndex
    if ($i -ge 0 -and $i -lt $script:queue.Count) { return $script:queue[$i] }
    return $null
}

# Chaine de filtres de l'apercu : $withSet = avec les reglages en cours
function Get-PreviewFilter($it, [bool]$withSet) {
    $parts = @()
    if ($withSet) {
        if ($script:iw.chkAuto -and $script:iw.chkAuto.Checked -and $it.Info) {
            $an = $null
            if ($script:analysis.ContainsKey($it.Path)) { $an = $script:analysis[$it.Path] }
            $sv = $script:imgOn; $script:imgOn = $false
            $pl = $null
            try { $pl = Build-FfmpegArgs $it.Info $it.Path 'x.mkv' 'ffprog_p.txt' (Get-EncoderMode) $chkUp.Checked $false $null -1.0 0.0 $an } catch {} finally { $script:imgOn = $sv }
            if ($pl -and $pl.VfBase) { $parts += $pl.VfBase }
        }
        $f = Get-ImageFilter $script:imgWork (Get-StreamBits $it.Info) $false
        if ($f.Pre)  { $parts += $f.Pre }
        if ($f.Post) { $parts += $f.Post }
    }
    return ($parts -join ',')
}

function Update-ImgPreview([bool]$withOriginal) {
    $it = Get-PreviewItem
    if (-not $it) { $script:iw.lblMsg.Text = 'Ajoutez une video a la file d''attente pour voir un apercu.'; return }
    try {
        $dur = [double]$it.Duration
        $t = [double]$script:iw.trk.Value / 1000.0 * $dur
        if ($t -gt ($dur - 0.5)) { $t = [Math]::Max(0.0, $dur - 0.5) }
        $script:iw.lblTime.Text = Format-Time $t
        $script:iw.lblMsg.Text = 'Calcul de l''apercu...'
        $script:iw.form.Refresh()
        if ($script:iw.chkAuto.Checked -and -not ($script:analysis.ContainsKey($it.Path) -and $script:analysis[$it.Path].Deep)) {
            $script:iw.lblMsg.Text = 'Analyse de la video (entrelacement, bandes noires, artefacts)...'
            $script:iw.form.Refresh()
            $script:cancelled = $false
            try { [void](Get-VideoAnalysis $it $it.Info) } catch {}
        }
        if ($script:iw.chkZoom.Checked) { $disp = "crop='min(480,iw)':'min(270,ih)'" }
        else { $disp = "scale='trunc(iw*sar/2)*2':ih,scale=480:-2:flags=bicubic" }

        if ($withOriginal) {
            $bo = Render-Frame $it.Path $t $disp
            if ($script:iw.pbO.Image) { $script:iw.pbO.Image.Dispose() }
            $script:iw.pbO.Image = $bo
        }
        $fx = Get-PreviewFilter $it $true
        $vfp = $(if ($fx) { $fx + ',' + $disp } else { $disp })
        $bp = Render-Frame $it.Path $t $vfp
        if ($script:iw.pbP.Image) { $script:iw.pbP.Image.Dispose() }
        $script:iw.pbP.Image = $bp
        Update-SplitView
        if ($bp) { $script:iw.lblMsg.Text = 'Apercu a jour. HDR : l''apercu n''applique pas le tone mapping.' }
        else { $script:iw.lblMsg.Text = 'Image indisponible a cette position (filtre non pris en charge par ce ffmpeg ?).' }
    } catch {
        $script:iw.lblMsg.Text = 'Erreur apercu : ' + $_.Exception.Message
    }
}

# Mode curseur : original a gauche, resultat a droite, ligne de separation deplacable
function Update-SplitView {
    if (-not $script:iw -or -not $script:iw.chkSplit.Checked) { return }
    $o = $script:iw.pbO.Image; $p = $script:iw.pbP.Image
    if (-not $o -or -not $p) { return }
    $w = $p.Width; $h = $p.Height
    $bmp = New-Object System.Drawing.Bitmap($w, $h)
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    try {
        $g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
        $x = [int]($w * $script:iw.trkSplit.Value / 100.0)
        $g.DrawImage($o, (New-Object System.Drawing.Rectangle(0, 0, $w, $h)))
        if ($x -lt $w) {
            $g.SetClip((New-Object System.Drawing.Rectangle($x, 0, ($w - $x), $h)))
            $g.DrawImage($p, (New-Object System.Drawing.Rectangle(0, 0, $w, $h)))
            $g.ResetClip()
        }
        $pen = New-Object System.Drawing.Pen([System.Drawing.Color]::White, 2)
        $g.DrawLine($pen, $x, 0, $x, $h)
        $pen.Dispose()
        $fnt = New-Object System.Drawing.Font('Arial', 9, [System.Drawing.FontStyle]::Bold)
        $g.DrawString('Avant', $fnt, [System.Drawing.Brushes]::Yellow, 6, 4)
        $g.DrawString('Apres', $fnt, [System.Drawing.Brushes]::Yellow, [single]([Math]::Max($x + 6, 6)), 4)
        $fnt.Dispose()
    } finally { $g.Dispose() }
    if ($script:iw.pbS.Image) { $script:iw.pbS.Image.Dispose() }
    $script:iw.pbS.Image = $bmp
}

function Step-ImgPos([double]$sec) {
    $it = Get-PreviewItem
    if (-not $it -or $it.Duration -le 0) { return }
    $v = [int]($script:iw.trk.Value + $sec / [double]$it.Duration * 1000.0)
    $script:iw.trk.Value = [Math]::Max(0, [Math]::Min(1000, $v))
}

function Request-ImgPreview([bool]$withOriginal) {
    if ($withOriginal) { $script:iw.needOrig = $true }
    $script:iw.tmr.Stop(); $script:iw.tmr.Start()
}

function Show-ImageWindow {
    if ($script:imgWin -and -not $script:imgWin.IsDisposed) {
        $script:imgWin.WindowState = 'Normal'; $script:imgWin.Activate(); return
    }
    $w = New-Object System.Windows.Forms.Form
    $w.Text = 'Apercu et reglages image'
    $w.ClientSize = New-Object System.Drawing.Size(1000, 800)
    $w.StartPosition = 'Manual'
    $w.Location = New-Object System.Drawing.Point(([Math]::Min($form.Left + 60, 200)), 40)
    $w.FormBorderStyle = 'FixedSingle'
    $w.MaximizeBox = $false
    $w.ShowInTaskbar = $true
    $w.BackColor = $script:white
    $w.ForeColor = $script:cText
    $w.Font = New-Object System.Drawing.Font('Arial', 9.5)
    $script:imgWin = $w
    $script:iw = @{ form = $w; needOrig = $true; vals = @{}; trks = @{} }

    $hd = New-Object System.Windows.Forms.Panel
    $hd.Location = New-Object System.Drawing.Point(0, 0); $hd.Size = New-Object System.Drawing.Size(1000, 6)
    $hd.BackColor = $script:cGreen
    $w.Controls.Add($hd)

    $l = New-Object System.Windows.Forms.Label
    $l.Text = 'Video'; $l.Location = New-Object System.Drawing.Point(20, 20); $l.AutoSize = $true
    $l.Font = New-Object System.Drawing.Font('Arial', 9.5, [System.Drawing.FontStyle]::Bold); $l.ForeColor = $script:cGreen
    $w.Controls.Add($l)
    $cmb = New-Object System.Windows.Forms.ComboBox
    $cmb.DropDownStyle = 'DropDownList'
    $cmb.Location = New-Object System.Drawing.Point(70, 16); $cmb.Size = New-Object System.Drawing.Size(640, 26)
    $w.Controls.Add($cmb)
    $script:iw.cmb = $cmb
    foreach ($q in $script:queue) { [void]$cmb.Items.Add([IO.Path]::GetFileName($q.Path)) }
    if ($cmb.Items.Count -gt 0) {
        $k = 0
        if ($lv.SelectedIndices.Count -gt 0) { $k = $lv.SelectedIndices[0] }
        $cmb.SelectedIndex = [Math]::Min($k, $cmb.Items.Count - 1)
    }

    $ca = New-Object System.Windows.Forms.CheckBox
    $ca.Text = 'Traitement auto'; $ca.Checked = $true
    $ca.Location = New-Object System.Drawing.Point(725, 17); $ca.Size = New-Object System.Drawing.Size(130, 24)
    $w.Controls.Add($ca); $script:iw.chkAuto = $ca
    $cs = New-Object System.Windows.Forms.CheckBox
    $cs.Text = 'Curseur A/B'
    $cs.Location = New-Object System.Drawing.Point(865, 17); $cs.Size = New-Object System.Drawing.Size(115, 24)
    $w.Controls.Add($cs); $script:iw.chkSplit = $cs

    foreach ($cfg in @(@('Original', 20), @('Apercu avec reglages', 510))) {
        $t = New-Object System.Windows.Forms.Label
        $t.Text = $cfg[0]; $t.Location = New-Object System.Drawing.Point($cfg[1], 52); $t.AutoSize = $true
        $t.Font = New-Object System.Drawing.Font('Arial', 9.5, [System.Drawing.FontStyle]::Bold); $t.ForeColor = $script:cGreen
        $w.Controls.Add($t)
    }
    $pbO = New-Object System.Windows.Forms.PictureBox
    $pbO.Location = New-Object System.Drawing.Point(20, 74); $pbO.Size = New-Object System.Drawing.Size(470, 264)
    $pbO.SizeMode = 'Zoom'; $pbO.BackColor = [System.Drawing.Color]::Black; $pbO.BorderStyle = 'FixedSingle'
    $w.Controls.Add($pbO); $script:iw.pbO = $pbO
    $pbP = New-Object System.Windows.Forms.PictureBox
    $pbP.Location = New-Object System.Drawing.Point(510, 74); $pbP.Size = New-Object System.Drawing.Size(470, 264)
    $pbP.SizeMode = 'Zoom'; $pbP.BackColor = [System.Drawing.Color]::Black; $pbP.BorderStyle = 'FixedSingle'
    $w.Controls.Add($pbP); $script:iw.pbP = $pbP
    $pbS = New-Object System.Windows.Forms.PictureBox
    $pbS.Location = New-Object System.Drawing.Point(20, 74); $pbS.Size = New-Object System.Drawing.Size(960, 264)
    $pbS.SizeMode = 'Zoom'; $pbS.BackColor = [System.Drawing.Color]::Black; $pbS.BorderStyle = 'FixedSingle'
    $pbS.Visible = $false
    $w.Controls.Add($pbS); $script:iw.pbS = $pbS

    # Position dans la video
    $l = New-Object System.Windows.Forms.Label
    $l.Text = 'Position'; $l.Location = New-Object System.Drawing.Point(20, 358); $l.AutoSize = $true
    $w.Controls.Add($l)
    $trk = New-Object System.Windows.Forms.TrackBar
    $trk.Minimum = 0; $trk.Maximum = 1000; $trk.Value = 300; $trk.TickStyle = 'None'
    $trk.Location = New-Object System.Drawing.Point(190, 352); $trk.Size = New-Object System.Drawing.Size(440, 40)
    $w.Controls.Add($trk); $script:iw.trk = $trk
    $lt = New-Object System.Windows.Forms.Label
    $lt.Text = '00:00:00'; $lt.Location = New-Object System.Drawing.Point(800, 358); $lt.AutoSize = $true
    $lt.Font = New-Object System.Drawing.Font('Consolas', 10)
    $w.Controls.Add($lt); $script:iw.lblTime = $lt
    $cz = New-Object System.Windows.Forms.CheckBox
    $cz.Text = 'Zoom 100 %'; $cz.Location = New-Object System.Drawing.Point(890, 355); $cz.Size = New-Object System.Drawing.Size(105, 24)
    $w.Controls.Add($cz); $script:iw.chkZoom = $cz
    $bBack = Add-Button '-10 s' 640 352 70 30 $false $w
    $bFwd  = Add-Button '+10 s' 716 352 70 30 $false $w
    $bBack.Add_Click({ Step-ImgPos -10.0 })
    $bFwd.Add_Click({ Step-ImgPos 10.0 })

    # Curseurs de reglage
    $rows = @(
        @('Bright',   'Luminosite',                 -30,  30,   0),
        @('Contrast', 'Contraste',                   50, 150, 100),
        @('Sat',      'Saturation',                   0, 200, 100),
        @('Gamma',    'Gamma',                       50, 200, 100),
        @('Sharp',    'Nettete (0 a 10)',             0,  10,   0),
        @('Depix',    'Depixelisation (0 a 3)',       0,   3,   0)
    )
    $y = 404
    foreach ($r in $rows) {
        $lab = New-Object System.Windows.Forms.Label
        $lab.Text = $r[1]; $lab.Location = New-Object System.Drawing.Point(20, ($y + 6)); $lab.AutoSize = $true
        $w.Controls.Add($lab)
        $tb = New-Object System.Windows.Forms.TrackBar
        $tb.Minimum = $r[2]; $tb.Maximum = $r[3]
        $tb.Value = [int]$script:imgWork[$r[0]]
        $tb.TickStyle = 'None'; $tb.Tag = $r[0]
        $tb.Location = New-Object System.Drawing.Point(190, $y); $tb.Size = New-Object System.Drawing.Size(640, 40)
        $w.Controls.Add($tb)
        $vl = New-Object System.Windows.Forms.Label
        $vl.Text = (Format-ImgVal $r[0] $tb.Value); $vl.Location = New-Object System.Drawing.Point(850, ($y + 6)); $vl.AutoSize = $true
        $vl.Font = New-Object System.Drawing.Font('Consolas', 10, [System.Drawing.FontStyle]::Bold); $vl.ForeColor = $script:cGreen
        $w.Controls.Add($vl)
        $script:iw.vals[$r[0]] = $vl; $script:iw.trks[$r[0]] = $tb
        $tb.Add_ValueChanged({
            $script:imgWork[$this.Tag] = [int]$this.Value
            $script:iw.vals[$this.Tag].Text = (Format-ImgVal $this.Tag $this.Value)
            Request-ImgPreview $false
        })
        $y += 44
    }

    $ls = Add-Label 'Separation avant | apres' 20 678 $w
    $ts = New-Object System.Windows.Forms.TrackBar
    $ts.Minimum = 0; $ts.Maximum = 100; $ts.Value = 50; $ts.TickStyle = 'None'
    $ts.Location = New-Object System.Drawing.Point(190, 672); $ts.Size = New-Object System.Drawing.Size(640, 40)
    $w.Controls.Add($ts); $script:iw.trkSplit = $ts
    $ls.Visible = $false; $ts.Visible = $false; $script:iw.lblSplit = $ls
    $lm = New-Object System.Windows.Forms.Label
    $lm.Text = ''; $lm.ForeColor = $script:cMuted; $lm.Location = New-Object System.Drawing.Point(20, 716)
    $lm.Size = New-Object System.Drawing.Size(960, 20)
    $w.Controls.Add($lm); $script:iw.lblMsg = $lm

    $bReset = Add-Button 'Reinitialiser'                20 746 130 36 $false $w
    $bPlay  = Add-Button 'Lire un extrait (ffplay)'    160 746 200 36 $false $w
    $bScore = Add-Button 'Tester la qualite (3 s)'     370 746 210 36 $false $w
    $bOk    = Add-Button 'Valider les reglages'        700 746 190 36 $true  $w
    $bClose = Add-Button 'Fermer'                      900 746 80 36 $false $w
    $ct = New-Object System.Windows.Forms.CheckBox
    $ct.Text = 'Au premier plan'; $ct.Location = New-Object System.Drawing.Point(590, 752); $ct.Size = New-Object System.Drawing.Size(105, 24)
    $ct.Font = New-Object System.Drawing.Font('Arial', 8.5)
    $w.Controls.Add($ct)
    $ct.Add_CheckedChanged({ $script:imgWin.TopMost = $this.Checked })

    $tmr = New-Object System.Windows.Forms.Timer
    $tmr.Interval = 450
    $script:iw.tmr = $tmr
    $tmr.Add_Tick({
        $script:iw.tmr.Stop()
        $o = [bool]$script:iw.needOrig
        $script:iw.needOrig = $false
        Update-ImgPreview $o
    })

    $cs.Add_CheckedChanged({
        $on = $script:iw.chkSplit.Checked
        $script:iw.pbO.Visible = (-not $on); $script:iw.pbP.Visible = (-not $on); $script:iw.pbS.Visible = $on
        $script:iw.trkSplit.Visible = $on; $script:iw.lblSplit.Visible = $on
        Update-SplitView
    })
    $ts.Add_ValueChanged({ Update-SplitView })
    $ca.Add_CheckedChanged({ Request-ImgPreview $false })
    $bScore.Add_Click({
        $it = Get-PreviewItem
        if (-not $it -or $it.Duration -le 0 -or -not $it.Info) { $script:iw.lblMsg.Text = 'Ajoutez une video a la file d''attente.'; return }
        if ($script:running) { $script:iw.lblMsg.Text = 'Une conversion est en cours.'; return }
        $script:iw.lblMsg.Text = 'Encodage d''un extrait de 3 s avec les reglages actuels, puis mesure...'
        $script:iw.form.Refresh()
        $script:cancelled = $false
        $id = [guid]::NewGuid().ToString('N')
        $sfile = Join-Path $env:TEMP ("ffsq_{0}.mkv" -f $id); $serr = $sfile + '.err'; $sprog = Join-Path $env:TEMP ("ffprog_{0}.txt" -f $id)
        try {
            $dur = [double]$it.Duration; $len = 3.0
            $pos = [Math]::Max(0.0, [Math]::Min([double]$script:iw.trk.Value / 1000.0 * $dur, $dur - $len - 0.2))
            $an = $null
            try { $an = Get-VideoAnalysis $it $it.Info } catch {}
            $mode = Get-EncoderMode
            $sp = Build-FfmpegArgs $it.Info $it.Path $sfile $sprog $mode $chkUp.Checked $false $null $pos $len $an
            $t0 = Get-Date
            $code = Run-Ffmpeg $sp.Args $serr
            $sec = ((Get-Date) - $t0).TotalSeconds
            if ($code -ne 0 -or -not (Test-Path -LiteralPath $sfile)) { $script:iw.lblMsg.Text = 'Encodage de l''extrait impossible avec ces reglages.'; return }
            $kb = (Get-Item -LiteralPath $sfile).Length * 8.0 / $len / 1000.0
            $uv = [bool]$script:caps.Vmaf
            $sc = Get-QualityScore $it.Path $sp.MapIndex $sp.Vf $sfile -1.0 $pos $len $uv
            if ($null -ne $sc) {
                $script:iw.lblMsg.Text = ('Extrait a {0} : {1} {2:0.00} | {3:0} kb/s | {4} | {5} | encode en {6:0} s' -f (Format-Time $pos), $(if ($uv) { 'VMAF' } else { 'SSIM' }), $sc, $kb, $sp.Encoder, $sp.RateText, $sec)
            } else { $script:iw.lblMsg.Text = 'Mesure du score impossible (ffmpeg sans libvmaf/ssim ?).' }
        } catch { $script:iw.lblMsg.Text = 'Erreur : ' + $_.Exception.Message }
        finally { Remove-Item -LiteralPath $sfile, $serr, $sprog -Force -ErrorAction SilentlyContinue }
    })
    $trk.Add_ValueChanged({ Request-ImgPreview $true })
    $cz.Add_CheckedChanged({ Request-ImgPreview $true })
    $cmb.Add_SelectedIndexChanged({ Request-ImgPreview $true })

    $bReset.Add_Click({
        foreach ($k in @($script:iw.trks.Keys)) {
            $tb = $script:iw.trks[$k]
            $def = $(if ($k -in @('Contrast', 'Sat', 'Gamma')) { 100 } else { 0 })
            $tb.Value = $def
        }
    })

    $bPlay.Add_Click({
        $it = Get-PreviewItem
        if (-not $it) { return }
        $ffplay = Find-Tool 'ffplay'
        if (-not $ffplay) {
            [System.Windows.Forms.MessageBox]::Show("ffplay.exe introuvable.`nPlacez ffplay.exe dans le meme dossier que ffmpeg.exe (il est fourni avec les builds ffmpeg officiels).", 'Erreur', 'OK', 'Error') | Out-Null
            return
        }
        $t = [double]$script:iw.trk.Value / 1000.0 * [double]$it.Duration
        $fx = Get-PreviewFilter $it $true
        $a = '-hide_banner -loglevel error -an -ss {0} -t 15 -autoexit -x 960 -window_title "Extrait avec reglages" ' -f $t.ToString('0.###', $inv)
        if ($fx) { $a += '-vf ' + (Q $fx) + ' ' }
        $a += '-i ' + (Q $it.Path)
        try { Start-Process -FilePath $ffplay -ArgumentList $a | Out-Null }
        catch { [System.Windows.Forms.MessageBox]::Show("Lecture impossible : $($_.Exception.Message)", 'Erreur', 'OK', 'Error') | Out-Null }
    })

    $bOk.Add_Click({
        if ($script:running) {
            [System.Windows.Forms.MessageBox]::Show('Une conversion est en cours : validez les reglages a la fin de la conversion.', 'Erreur', 'OK', 'Warning') | Out-Null
            return
        }
        $copy = @{}
        foreach ($k in @($script:imgWork.Keys)) { $copy[$k] = [int]$script:imgWork[$k] }
        if (Test-ImgDefault $copy) {
            $script:imgValidated = $null
            $chkImg.Checked = $false
            $chkImg.Enabled = $false
            $chkImg.Text = 'Appliquer les reglages image valides (aucun pour l''instant)'
            $script:iw.lblMsg.Text = 'Tous les reglages sont a leur valeur d''origine : aucun filtre ne sera applique.'
        } else {
            $script:imgValidated = $copy
            $chkImg.Text = 'Appliquer les reglages image valides : ' + (Format-ImgSummary $copy)
            $chkImg.Enabled = $true
            $chkImg.Checked = $true
            $script:iw.lblMsg.Text = 'Reglages valides : ils seront appliques aux prochaines conversions.'
        }
        $script:imgOn = $chkImg.Checked
        Update-Preview
    })

    $bClose.Add_Click({ $script:imgWin.Close() })
    $w.Add_FormClosed({
        try { $script:iw.tmr.Stop(); $script:iw.tmr.Dispose() } catch {}
        try { if ($script:iw.pbO.Image) { $script:iw.pbO.Image.Dispose() } } catch {}
        try { if ($script:iw.pbP.Image) { $script:iw.pbP.Image.Dispose() } } catch {}
        $script:imgWin = $null
    })

    $w.Show()
    Request-ImgPreview $true
}

$btnImg.Add_Click({ Show-ImageWindow })
$chkCmp.Add_CheckedChanged({ $script:cmpOn = $chkCmp.Checked })
$chkImg.Add_CheckedChanged({
    $script:imgOn = ($chkImg.Checked -and ($null -ne $script:imgValidated))
    Update-Preview
})
$form.Add_FormClosed({
    if ($script:imgWin -and -not $script:imgWin.IsDisposed) { try { $script:imgWin.Close() } catch {} }
})

$form.Add_FormClosing({
    if ($script:proc -and -not $script:proc.HasExited) {
        $script:cancelled = $true
        Write-Log 'AVERT' 'Fenetre fermee pendant la conversion, ffmpeg arrete.'
        try { $script:proc.Kill(); [void]$script:proc.WaitForExit(3000) } catch {}
        # fichier partiel supprime (sinon il serait pris pour un fichier deja converti au prochain lancement)
        if ($script:dst -and (Test-Path -LiteralPath $script:dst)) {
            Remove-Item -LiteralPath $script:dst -Force -ErrorAction SilentlyContinue
            Write-Log 'AVERT' "Fichier partiel supprime : $($script:dst)"
        }
    }
})


# ======================================================= Parametres (V7c) ===
# Active / desactive les boutons de la fenetre Parametres pendant une operation
function Set-SwBusy([bool]$busy) {
    $w = $script:setWin
    if (-not $w) { return }
    $w.busy = $busy
    foreach ($k in @('btnChk', 'btnFfChk', 'btnFfWeb', 'btnClose')) { $w[$k].Enabled = (-not $busy) }
    if ($busy) {
        $w.btnUpd.Enabled = $false; $w.btnFfUpd.Enabled = $false
        $w.form.Cursor = [System.Windows.Forms.Cursors]::AppStarting
    } else {
        $w.btnUpd.Enabled = [bool]$w.updOk; $w.btnFfUpd.Enabled = [bool]$w.ffUpdOk
        $w.form.Cursor = [System.Windows.Forms.Cursors]::Default
    }
}

# ---- Mise a jour de l'application : telecharge la nouvelle version puis redemarre ----
# Supprime les versions anterieures de l'application dans le dossier de l'application (poste de l'utilisateur).
# Un fichier verrouille (version en cours d'execution) est supprime par un petit processus differe.
function Remove-OldVersions([string]$keepVersion) {
    try {
        if (-not $script:appDir -or -not (Test-Path -LiteralPath $script:appDir)) { Write-Log 'AVERT' 'Nettoyage des anciennes versions : dossier de l''application introuvable'; return }
        $keep = Parse-AppVersion $keepVersion
        if (-not $keep) { return }
        $left = @(); $nDel = 0; $nSeen = 0
        foreach ($f in @(Get-ChildItem -LiteralPath $script:appDir -File -ErrorAction SilentlyContinue)) {
            if ($f.Name -match '^Convert-ToHEVC[_ -]*V(\d+[a-zA-Z]?)(?![0-9a-zA-Z]).*\.(exe|ps1|download|bak|old|new)$') {
                $nSeen++
                $v = Parse-AppVersion $Matches[1]
                if ($v -and (Compare-AppVersion $v $keep) -lt 0) {
                    try { Remove-Item -LiteralPath $f.FullName -Force -ErrorAction Stop; $nDel++; Write-Log 'INFO' ('Ancienne version supprimee : ' + $f.Name) }
                    catch { $left += $f.FullName; Write-Log 'AVERT' ('Ancienne version verrouillee, suppression differee : ' + $f.Name + ' (' + $_.Exception.Message + ')') }
                }
            }
        }
        Write-Log 'INFO' ('Nettoyage des anciennes versions dans {0} : {1} fichier(s) V* trouve(s), {2} supprime(s), {3} differe(s)' -f $script:appDir, $nSeen, $nDel, $left.Count)
        if ($left.Count -gt 0) {
            # script .cmd temporaire : reessaie pendant 80 s (le temps que l'ancienne version se ferme), puis s'efface
            $cmdPath = Join-Path $env:TEMP ('hevc_clean_{0}.cmd' -f [guid]::NewGuid().ToString('N'))
            $lines = @('@echo off')
            foreach ($l in $left) {
                $lines += 'for /l %%i in (1,1,40) do ('
                $lines += ('  del /f /q "' + $l + '" >nul 2>&1')
                $lines += ('  if not exist "' + $l + '" goto :next' + [Math]::Abs($l.GetHashCode()))
                $lines += '  ping -n 3 127.0.0.1 >nul'
                $lines += ')'
                $lines += (':next' + [Math]::Abs($l.GetHashCode()))
            }
            $lines += '(goto) 2>nul & del /f /q "%~f0"'
            Set-Content -LiteralPath $cmdPath -Value $lines -Encoding ASCII
            Start-Process -FilePath (Join-Path $env:SystemRoot 'System32\cmd.exe') -ArgumentList @('/c', ('"' + $cmdPath + '"')) -WindowStyle Hidden
        }
    } catch { try { Write-Log 'AVERT' ('Nettoyage des anciennes versions impossible : ' + $_.Exception.Message) } catch {} }
}

function Invoke-AppUpdate {
    $w = $script:setWin; $j = $script:updInfo
    $red = [System.Drawing.Color]::FromArgb(176, 32, 32)
    if (-not $j) { return }
    if ($script:running) {
        [System.Windows.Forms.MessageBox]::Show('Une conversion est en cours : terminez-la ou annulez-la avant la mise a jour.', 'Mise a jour', 'OK', 'Warning') | Out-Null
        return
    }
    $isExe = [bool]$env:HEVC_APPDIR
    if ($isExe) { $rel = "$($j.exe)"; $expected = "$($j.sha256_exe)" } else { $rel = "$($j.ps1)"; $expected = "$($j.sha256_ps1)" }
    if (-not $rel) {
        [System.Windows.Forms.MessageBox]::Show('version.json ne contient pas le fichier a telecharger.', 'Mise a jour', 'OK', 'Warning') | Out-Null
        return
    }
    $kind = if ($isExe) { 'binaire (.exe)' } else { 'script (.ps1)' }
    $leaf = $rel.Substring($rel.LastIndexOf('/') + 1)
    $dest = Join-Path $script:appDir $leaf
    $ask = [System.Windows.Forms.MessageBox]::Show(("Installer la version V{0} ({1}) dans :`r`n{2}`r`n`r`nL'application va redemarrer. Les versions anterieures seront supprimees de ce dossier." -f $j.version, $kind, $script:appDir), 'Mise a jour', 'YesNo', 'Question')
    if ($ask -ne 'Yes') { return }

    Set-SwBusy $true
    $w.barApp.Visible = $true; $w.barApp.Value = 0
    $w.lblUpd.ForeColor = $script:cMuted
    $tmp = $dest + '.download'
    try {
        Download-File ($script:repoUrl + '/raw/main/' + ($rel -replace ' ', '%20')) $tmp $w.barApp $w.lblUpd 'Telechargement'
        if (-not (Test-Sha256 $tmp $expected)) { throw 'Somme de controle SHA-256 incorrecte : fichier rejete.' }
        if ($isExe) {
            $hd = New-Object byte[] 2
            $fs = [System.IO.File]::OpenRead($tmp); [void]$fs.Read($hd, 0, 2); $fs.Close()
            if ($hd[0] -ne 0x4D -or $hd[1] -ne 0x5A) { throw 'Le fichier telecharge n''est pas un executable valide.' }
        }
        Move-Item -LiteralPath $tmp -Destination $dest -Force
    } catch {
        try { if (Test-Path -LiteralPath $tmp) { Remove-Item -LiteralPath $tmp -Force } } catch {}
        $w.barApp.Visible = $false
        $w.lblUpd.ForeColor = $red
        $w.lblUpd.Text = 'Echec de la mise a jour : ' + $_.Exception.Message
        Set-SwBusy $false
        return
    }
    Remove-OldVersions "$($j.version)"
    $w.lblUpd.Text = 'Verification du logo...'
    [System.Windows.Forms.Application]::DoEvents()
    try { [void](Ensure-LogoFile "$($j.sha256_logo)" 8000) } catch {}
    $w.lblUpd.ForeColor = $script:cGreen
    $w.lblUpd.Text = ('V{0} installee. Redemarrage de l''application...' -f $j.version)
    [System.Windows.Forms.Application]::DoEvents()
    try {
        if ($isExe) {
            Start-Process -FilePath $dest -WorkingDirectory $script:appDir
        } else {
            $psx = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
            Start-Process -FilePath $psx -WorkingDirectory $script:appDir -WindowStyle Hidden -ArgumentList @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-STA', '-File', ('"' + $dest + '"'))
        }
    } catch {
        $w.lblUpd.ForeColor = $red
        $w.lblUpd.Text = 'Mise a jour installee, mais redemarrage impossible : lancez ' + $leaf + ' manuellement.'
        Set-SwBusy $false
        return
    }
    $script:quitAfterSettings = $true
    $w.busy = $false
    $w.form.Close()
}

# ---- Mise a jour de ffmpeg : telecharge la derniere version stable et remplace les exe ----
function Invoke-FfmpegUpdate {
    $w = $script:setWin
    $red = [System.Drawing.Color]::FromArgb(176, 32, 32)
    if ($script:running) {
        [System.Windows.Forms.MessageBox]::Show('Une conversion est en cours : terminez-la ou annulez-la avant la mise a jour de FFmpeg.', 'Mise a jour FFmpeg', 'OK', 'Warning') | Out-Null
        return
    }
    $loc = $w.ffLocal
    $zipUrl = Get-FfmpegZipUrl $loc
    $dirTxt = if ($script:ffmpeg) { Split-Path -Parent $script:ffmpeg } else { $script:appDir }
    $ask = [System.Windows.Forms.MessageBox]::Show(("Telecharger et installer la derniere version stable de FFmpeg ?`r`n`r`nffmpeg.exe, ffprobe.exe et ffplay.exe seront remplaces la ou ils se trouvent (dossier : {0}).`r`nTelechargement d'environ 30 a 100 Mo." -f $dirTxt), 'Mise a jour FFmpeg', 'YesNo', 'Question')
    if ($ask -ne 'Yes') { return }

    Set-SwBusy $true
    $w.barFf.Visible = $true; $w.barFf.Value = 0
    $w.lblFfUpd.ForeColor = $script:cMuted
    try {
        $note = Install-Ffmpeg $zipUrl $w.barFf $w.lblFfUpd
        $w.ffLocal = Get-FfmpegLocalInfo
        $newTxt = if ($w.ffLocal.Raw) { $w.ffLocal.Raw } else { 'inconnue' }
        $w.lblFfVer.Text = 'Version installee : ' + $newTxt
        try { Update-Capabilities $script:nvOk $script:qsvOk; $w.lblCaps.Text = Format-Capabilities } catch {}
        $w.lblFfUpd.ForeColor = $script:cGreen
        $w.lblFfUpd.Text = ('FFmpeg mis a jour : {0}{1}. Aucun redemarrage necessaire.' -f $newTxt, $note)
        $w.ffUpdOk = $false
        $script:ffUpdAvail = $false
        Update-UpdateBanner
    } catch {
        $w.lblFfUpd.ForeColor = $red
        $w.lblFfUpd.Text = 'Echec de la mise a jour de FFmpeg : ' + $_.Exception.Message + ' Les fichiers d''origine ont ete conserves.'
    } finally {
        $w.barFf.Visible = $false
        Set-SwBusy $false
    }
}

function Show-SettingsWindow {
    if ($script:setWin -and $script:setWin.form -and -not $script:setWin.form.IsDisposed) { $script:setWin.form.Activate(); return }

    $f = New-Object System.Windows.Forms.Form
    $f.Text = 'Parametres - Convert-ToHEVC V' + $script:appVersion
    $f.AutoScaleMode = [System.Windows.Forms.AutoScaleMode]::None
    $f.ClientSize = New-Object System.Drawing.Size(580, 800)
    $f.StartPosition = 'CenterParent'
    $f.FormBorderStyle = 'FixedDialog'
    $f.MaximizeBox = $false; $f.MinimizeBox = $false; $f.ShowInTaskbar = $false
    $f.BackColor = $script:white; $f.ForeColor = $script:cText
    $f.Font = New-Object System.Drawing.Font('Arial', 9.5)
    $sw = @{ form = $f; busy = $false; updOk = $false; ffUpdOk = $false }
    $script:setWin = $sw
    $script:quitAfterSettings = $false

    $strip = New-Object System.Windows.Forms.Panel
    $strip.Location = New-Object System.Drawing.Point(0, 0); $strip.Size = New-Object System.Drawing.Size(580, 4)
    $strip.BackColor = $script:cGreen
    $f.Controls.Add($strip)

    # ---- Application ----
    $h1 = Add-Label 'Application' 20 18 $f
    $h1.Font = New-Object System.Drawing.Font('Arial', 10.5, [System.Drawing.FontStyle]::Bold); $h1.ForeColor = $script:cGreen
    $modeTxt = if ($env:HEVC_APPDIR) { 'binaire (.exe)' } else { 'script PowerShell (.ps1)' }
    Add-Label ('Version installee : V' + $script:appVersion + '  -  ' + $modeTxt) 20 50 $f | Out-Null

    $sw.btnChk = Add-Button 'Verifier la nouvelle version' 20 82 230 32 $true $f
    $sw.lblUpd = New-Object System.Windows.Forms.Label
    $sw.lblUpd.Text = 'Compare la version installee a la derniere version publiee.'
    $sw.lblUpd.ForeColor = $script:cMuted
    $sw.lblUpd.AutoSize = $false
    $sw.lblUpd.Location = New-Object System.Drawing.Point(20, 124); $sw.lblUpd.Size = New-Object System.Drawing.Size(540, 48)
    $f.Controls.Add($sw.lblUpd)
    $sw.btnUpd = Add-Button 'Faire la mise a jour' 20 178 230 32 $false $f
    $sw.btnUpd.Enabled = $false
    $sw.barApp = New-Object FlatProgress
    $sw.barApp.Location = New-Object System.Drawing.Point(262, 188); $sw.barApp.Size = New-Object System.Drawing.Size(298, 12)
    $sw.barApp.Minimum = 0; $sw.barApp.Maximum = 1000; $sw.barApp.Visible = $false
    $f.Controls.Add($sw.barApp)

    $sep = New-Object System.Windows.Forms.Panel
    $sep.Location = New-Object System.Drawing.Point(20, 228); $sep.Size = New-Object System.Drawing.Size(540, 1)
    $sep.BackColor = $script:cBorder
    $f.Controls.Add($sep)

    # ---- FFmpeg ----
    $h2 = Add-Label 'FFmpeg' 20 242 $f
    $h2.Font = New-Object System.Drawing.Font('Arial', 10.5, [System.Drawing.FontStyle]::Bold); $h2.ForeColor = $script:cGreen
    $ff = Get-FfmpegLocalInfo
    $ffTxt = if ($ff.Raw) { $ff.Raw } else { 'inconnue' }
    $sw.lblFfVer = New-Object System.Windows.Forms.Label
    $sw.lblFfVer.Text = 'Version installee : ' + $ffTxt
    $sw.lblFfVer.AutoSize = $false; $sw.lblFfVer.AutoEllipsis = $true
    $sw.lblFfVer.Location = New-Object System.Drawing.Point(20, 272); $sw.lblFfVer.Size = New-Object System.Drawing.Size(540, 20)
    $f.Controls.Add($sw.lblFfVer)
    $sw.lblFfPath = New-Object System.Windows.Forms.Label
    $sw.lblFfPath.Text = $script:ffmpeg
    $sw.lblFfPath.ForeColor = $script:cMuted; $sw.lblFfPath.Font = New-Object System.Drawing.Font('Arial', 8.5)
    $sw.lblFfPath.AutoSize = $false; $sw.lblFfPath.AutoEllipsis = $true
    $sw.lblFfPath.Location = New-Object System.Drawing.Point(20, 296); $sw.lblFfPath.Size = New-Object System.Drawing.Size(540, 18)
    $f.Controls.Add($sw.lblFfPath)
    $sw.ffLocal = $ff

    $sw.chkFull = New-Object System.Windows.Forms.CheckBox
    $sw.chkFull.Text = 'Variante complete BtbN (VMAF, libplacebo) - recommandee pour la V8'
    $sw.chkFull.Location = New-Object System.Drawing.Point(20, 320); $sw.chkFull.Size = New-Object System.Drawing.Size(540, 22)
    $sw.chkFull.Checked = [bool](Get-AppSetting 'ffFull' $true)
    $f.Controls.Add($sw.chkFull)
    $sw.chkFull.Add_CheckedChanged({
        Set-AppSetting 'ffFull' ([bool]$this.Checked)
        $w = $script:setWin
        if ($w -and -not $w.busy) { $w.ffUpdOk = $false; $w.btnFfUpd.Enabled = $false; $w.lblFfUpd.ForeColor = $script:cMuted; $w.lblFfUpd.Text = 'Variante modifiee : cliquez sur "Verifier la mise a jour FFmpeg".' }
    })
    $sw.lblCaps = New-Object System.Windows.Forms.Label
    $sw.lblCaps.Text = Format-Capabilities
    $sw.lblCaps.ForeColor = $script:cMuted; $sw.lblCaps.Font = New-Object System.Drawing.Font('Arial', 8.5)
    $sw.lblCaps.AutoSize = $false
    $sw.lblCaps.Location = New-Object System.Drawing.Point(20, 342); $sw.lblCaps.Size = New-Object System.Drawing.Size(540, 28)
    $f.Controls.Add($sw.lblCaps)
    $sw.btnFfChk = Add-Button 'Verifier la mise a jour FFmpeg' 20 372 230 32 $true $f
    $sw.btnFfWeb = Add-Button 'Page de telechargement' 262 372 200 32 $false $f
    $sw.lblFfUpd = New-Object System.Windows.Forms.Label
    $sw.lblFfUpd.Text = 'Compare la version installee a la derniere version stable (gyan.dev).'
    $sw.lblFfUpd.ForeColor = $script:cMuted
    $sw.lblFfUpd.AutoSize = $false
    $sw.lblFfUpd.Location = New-Object System.Drawing.Point(20, 414); $sw.lblFfUpd.Size = New-Object System.Drawing.Size(540, 64)
    $f.Controls.Add($sw.lblFfUpd)
    $sw.btnFfUpd = Add-Button 'Faire la mise a jour FFmpeg' 20 484 230 32 $false $f
    $sw.btnFfUpd.Enabled = $false
    $sw.barFf = New-Object FlatProgress
    $sw.barFf.Location = New-Object System.Drawing.Point(262, 494); $sw.barFf.Size = New-Object System.Drawing.Size(298, 12)
    $sw.barFf.Minimum = 0; $sw.barFf.Maximum = 1000; $sw.barFf.Visible = $false
    $f.Controls.Add($sw.barFf)

    $sw.btnClose = Add-Button 'Fermer' 460 752 100 32 $false $f
    $f.CancelButton = $sw.btnClose
    $sw.btnClose.Add_Click({ $script:setWin.form.Close() })

    $sw.btnFfWeb.Add_Click({ Open-Url $script:ffmpegPageUrl })
    $sw.btnUpd.Add_Click({ Invoke-AppUpdate })
    $sw.btnFfUpd.Add_Click({ Invoke-FfmpegUpdate })

    # ---- Verification de la nouvelle version de l'application ----
    $sw.btnChk.Add_Click({
        $w = $script:setWin
        $red = [System.Drawing.Color]::FromArgb(176, 32, 32)
        $w.updOk = $false; $w.btnUpd.Enabled = $false
        Set-SwBusy $true
        $w.lblUpd.ForeColor = $script:cMuted; $w.lblUpd.Text = 'Verification en cours...'
        [System.Windows.Forms.Application]::DoEvents()
        $txt = Get-WebText ($script:repoRaw + '/version.json?t=' + [DateTime]::UtcNow.Ticks)
        $j = $null
        if ($txt) { try { $j = $txt | ConvertFrom-Json } catch { $j = $null } }
        if (-not $j -or -not $j.version) {
            $w.lblUpd.ForeColor = $red
            $w.lblUpd.Text = 'Impossible de lire version.json sur GitHub (connexion internet ou depot inaccessible).'
        } else {
            $remote = Parse-AppVersion "$($j.version)"
            $local  = Parse-AppVersion $script:appVersion
            if (-not $remote) {
                $w.lblUpd.ForeColor = $red
                $w.lblUpd.Text = ('Numero de version illisible dans version.json : {0}' -f $j.version)
            } else {
                $cmp = Compare-AppVersion $remote $local
                $notes = ''
                if ($j.notes) { $notes = "`r`n" + "$($j.notes)" }
                if ($cmp -gt 0) {
                    $script:updInfo = $j
                    $w.updOk = $true
                    $w.lblUpd.ForeColor = $script:cGreen
                    $w.lblUpd.Text = ('Nouvelle version disponible : V{0} (installee : V{1}).{2}' -f $j.version, $script:appVersion, $notes)
                } elseif ($cmp -eq 0) {
                    $w.lblUpd.ForeColor = $script:cText
                    $w.lblUpd.Text = ('Vous utilisez la derniere version (V{0}).' -f $script:appVersion)
                } else {
                    $w.lblUpd.ForeColor = $script:cText
                    $w.lblUpd.Text = ('Cette version (V{0}) est plus recente que celle publiee sur GitHub (V{1}).' -f $script:appVersion, $j.version)
                }
            }
        }
        Set-SwBusy $false
    })

    # ---- Verification de la mise a jour de ffmpeg ----
    $sw.btnFfChk.Add_Click({
        $w = $script:setWin
        $red = [System.Drawing.Color]::FromArgb(176, 32, 32)
        $w.ffUpdOk = $false; $w.btnFfUpd.Enabled = $false
        Set-SwBusy $true
        $w.lblFfUpd.ForeColor = $script:cMuted; $w.lblFfUpd.Text = 'Verification en cours...'
        [System.Windows.Forms.Application]::DoEvents()
        if ((Get-WantedFlavor) -eq 'full') {
            $fi = Get-FullInfo
            $loc = $w.ffLocal; $haveFl = Get-FfmpegFlavor $loc
            $fvTxt = $(if ($fi.Ver) { $fi.Ver.ToString() } else { 'derniere build master' })
            if ($haveFl -ne 'full') {
                $w.ffUpdOk = $true; $w.lblFfUpd.ForeColor = $script:cGreen
                $w.lblFfUpd.Text = ('Variante complete disponible (build BtbN {0}, ~200 Mo). Installee : {1}. Cliquez sur "Faire la mise a jour FFmpeg".' -f $fvTxt, $(if ($haveFl) { $haveFl } else { 'inconnue' }))
            } elseif ($fi.Ver -and $loc.Ver -and ($fi.Ver -gt $loc.Ver)) {
                $w.ffUpdOk = $true; $w.lblFfUpd.ForeColor = $script:cGreen
                $w.lblFfUpd.Text = ('Nouvelle version de FFmpeg complet disponible : {0} (installee : {1}).' -f $fi.Ver, $loc.Ver)
            } else {
                $w.lblFfUpd.ForeColor = $script:cText
                $w.lblFfUpd.Text = ('FFmpeg complet a jour (installee : {0}).' -f $(if ($loc.Raw) { $loc.Raw } else { 'inconnue' }))
            }
            Set-SwBusy $false
            return
        }
        $txt = Get-WebText ($script:ffmpegVerUrl + '?t=' + [DateTime]::UtcNow.Ticks)
        $last = $null
        if ($txt) { $t = $txt.Trim(); if ($t -match '^\d+(\.\d+){1,3}$') { $last = [version]$t } }
        if (-not $last) {
            $w.lblFfUpd.ForeColor = $red
            $w.lblFfUpd.Text = 'Impossible de lire la derniere version de FFmpeg (connexion internet ou site inaccessible).'
        } else {
            $loc = $w.ffLocal
            if ($loc.Ver) {
                $haveFl = Get-FfmpegFlavor $loc; $wantFl = Get-WantedFlavor
                if ($haveFl -and $haveFl -ne $wantFl) {
                    $w.ffUpdOk = $true
                    $w.lblFfUpd.ForeColor = $script:cGreen
                    $w.lblFfUpd.Text = ('Changement de variante : installee = {0}, choisie = {1} (version {2}). Cliquez sur "Faire la mise a jour FFmpeg" pour installer la variante {1}.' -f $haveFl, $wantFl, $last)
                } elseif ($last -gt $loc.Ver) {
                    $w.ffUpdOk = $true
                    $w.lblFfUpd.ForeColor = $script:cGreen
                    $w.lblFfUpd.Text = ('Nouvelle version de FFmpeg disponible : {0} (installee : {1}).' -f $last, $loc.Ver)
                } else {
                    $w.lblFfUpd.ForeColor = $script:cText
                    $w.lblFfUpd.Text = ('FFmpeg est a jour (installee : {0}, derniere stable : {1}).' -f $loc.Ver, $last)
                }
            } else {
                # Build de developpement (git) : pas de numero de version, on compare les dates
                $rd = Get-WebLastModified (Get-FfmpegZipUrl $loc)
                $bd = $loc.BuildDate
                if ($bd -and $rd -and ($rd.Date -le $bd.Date)) {
                    $w.lblFfUpd.ForeColor = $script:cText
                    $w.lblFfUpd.Text = ('Votre build de developpement ({0}) est plus recent que la derniere version stable ({1}, publiee le {2}).' -f $bd.ToString('yyyy-MM-dd'), $last, $rd.ToString('yyyy-MM-dd'))
                } else {
                    $w.ffUpdOk = $true
                    $w.lblFfUpd.ForeColor = $script:cGreen
                    $info = if ($rd) { ', publiee le ' + $rd.ToString('yyyy-MM-dd') } else { '' }
                    $bdTxt = if ($bd) { ' du ' + $bd.ToString('yyyy-MM-dd') } else { '' }
                    $w.lblFfUpd.Text = ('Vous utilisez un build de developpement{0} (pas de numero de version). Derniere version stable : {1}{2}. Vous pouvez l''installer.' -f $bdTxt, $last, $info)
                }
            }
        }
        Set-SwBusy $false
    })

    # Mises a jour deja detectees au demarrage : affichees sans nouvelle verification
    if ($script:updInfo) {
        $j0 = $script:updInfo
        $n0 = ''
        if ($j0.notes) { $n0 = "`r`n" + "$($j0.notes)" }
        $sw.updOk = $true; $sw.btnUpd.Enabled = $true
        $sw.lblUpd.ForeColor = $script:cGreen
        $sw.lblUpd.Text = ('Nouvelle version disponible : V{0} (installee : V{1}).{2}' -f $j0.version, $script:appVersion, $n0)
    }
    if ($script:ffUpdAvail -and $ff.Ver -and $script:ffLatest) {
        $sw.ffUpdOk = $true; $sw.btnFfUpd.Enabled = $true
        $sw.lblFfUpd.ForeColor = $script:cGreen
        $sw.lblFfUpd.Text = ('Nouvelle version de FFmpeg disponible : {0} (installee : {1}).' -f $script:ffLatest, $ff.Ver)
    }

    # ---- Verification du systeme (V8d) ----
    $sep2 = New-Object System.Windows.Forms.Panel
    $sep2.Location = New-Object System.Drawing.Point(20, 530); $sep2.Size = New-Object System.Drawing.Size(540, 1)
    $sep2.BackColor = $script:cBorder
    $f.Controls.Add($sep2)
    $h3 = Add-Label 'Verification du systeme' 20 542 $f
    $h3.Font = New-Object System.Drawing.Font('Arial', 10.5, [System.Drawing.FontStyle]::Bold); $h3.ForeColor = $script:cGreen
    $sw.chkAuto = New-Object System.Windows.Forms.CheckBox
    $sw.chkAuto.Text = 'Verifier tout le systeme au demarrage (application, FFmpeg, logo, pilote)'
    $sw.chkAuto.AutoSize = $false
    $sw.chkAuto.Location = New-Object System.Drawing.Point(20, 570); $sw.chkAuto.Size = New-Object System.Drawing.Size(540, 24)
    $sw.chkAuto.Checked = [bool](Get-AppSetting 'checkUpdates' $true)
    $sw.chkAuto.Add_CheckedChanged({ Set-AppSetting 'checkUpdates' ([bool]$script:setWin.chkAuto.Checked) })
    $f.Controls.Add($sw.chkAuto)
    $sw.txtSys = New-Object System.Windows.Forms.TextBox
    $sw.txtSys.Multiline = $true; $sw.txtSys.ReadOnly = $true; $sw.txtSys.ScrollBars = 'Vertical'
    $sw.txtSys.Font = New-Object System.Drawing.Font('Consolas', 8.5)
    $sw.txtSys.Location = New-Object System.Drawing.Point(20, 600); $sw.txtSys.Size = New-Object System.Drawing.Size(540, 136)
    $sw.txtSys.Text = Format-SysReport
    $f.Controls.Add($sw.txtSys)
    $sw.btnSys = Add-Button 'Tout reverifier maintenant' 20 752 230 32 $true $f
    $sw.btnSys.Add_Click({
        if ($script:startupAsync) { return }
        $script:setWin.btnSys.Enabled = $false
        $script:setWin.txtSys.Text = 'Verification en cours (application, FFmpeg, ffprobe, logo, pilote)...'
        try { Update-Capabilities $script:nvOk $script:qsvOk } catch {}
        try { $script:setWin.lblCaps.Text = Format-Capabilities } catch {}
        Start-StartupCheck
    })
    if ($script:startupAsync) { $sw.btnSys.Enabled = $false; $sw.txtSys.Text = 'Verification en cours (application, FFmpeg, ffprobe, logo, pilote)...' }

    $f.Add_FormClosing({ if ($script:setWin -and $script:setWin.busy) { $_.Cancel = $true } })
    $f.Add_FormClosed({ $script:setWin = $null })
    [void]$f.ShowDialog($form)
    if ($script:quitAfterSettings) { $form.Close() }
}

# ------------------------------------------ Verification au demarrage (V7c) ----
# Banniere cliquable dans l'en-tete : s'affiche seulement si une mise a jour existe.
$lblBanner = New-Object System.Windows.Forms.Label
$lblBanner.AutoSize = $false
$lblBanner.Location = New-Object System.Drawing.Point(270, 74); $lblBanner.Size = New-Object System.Drawing.Size(614, 18)
$lblBanner.TextAlign = 'MiddleRight'
$lblBanner.Font = New-Object System.Drawing.Font('Arial', 9, [System.Drawing.FontStyle]::Bold)
$lblBanner.ForeColor = $script:cGreen
$lblBanner.Cursor = [System.Windows.Forms.Cursors]::Hand
$lblBanner.Visible = $false
$lblBanner.Add_Click({ Show-SettingsWindow })
$pnlHead.Controls.Add($lblBanner)

function Update-UpdateBanner {
    $parts = @()
    if ($script:updInfo) { $parts += ('application V' + $script:updInfo.version) }
    if ($script:ffUpdAvail -and $script:ffLatest) { $parts += ('FFmpeg ' + $script:ffLatest) }
    if ($parts.Count -gt 0) {
        $lblBanner.Text = 'Mise a jour disponible : ' + ($parts -join ' et ') + '  (cliquer ici)'
        $lblBanner.Visible = $true
    } else {
        $lblBanner.Visible = $false
    }
}

# Rapport systeme : liste de lignes { St = ok|maj|alerte|info ; Txt }
$script:sysReport = @()
$script:sysChecked = $false
function Add-SysLine([string]$st, [string]$txt) { $script:sysReport += [pscustomobject]@{ St = $st; Txt = $txt } }
function Format-SysReport {
    if (-not $script:sysChecked) { return 'Verification du systeme pas encore effectuee.' }
    $lines = @()
    foreach ($r in $script:sysReport) {
        $tag = switch ($r.St) { 'ok' { '[OK]    ' } 'maj' { '[MAJ]   ' } 'alerte' { '[ALERTE]' } default { '[info]  ' } }
        $lines += ($tag + ' ' + $r.Txt)
    }
    return ($lines -join "`r`n")
}
function Set-SysBusy([bool]$busy) {
    $w = $script:setWin
    if ($w -and $w.btnSys) { $w.btnSys.Enabled = (-not $busy) }
}
function Get-FfprobeVersionText {
    try {
        $fp = Find-Tool 'ffprobe'
        if (-not $fp) { return $null }
        $psi = New-Object System.Diagnostics.ProcessStartInfo
        $psi.FileName = $fp; $psi.Arguments = '-hide_banner -version'
        $psi.UseShellExecute = $false; $psi.CreateNoWindow = $true; $psi.RedirectStandardOutput = $true
        $pr = [System.Diagnostics.Process]::Start($psi)
        $o = $pr.StandardOutput.ReadToEnd(); [void]$pr.WaitForExit(3000)
        if ($o -match 'ffprobe version (\S+)') { return $Matches[1] }
    } catch {}
    return $null
}

function Complete-StartupCheck($res) {
    $script:sysReport = @(); $script:updInfo = $null; $script:ffUpdAvail = $false; $script:ffLatest = $null
    $online = [bool]($res.App -or $res.Ff -or $res.FfFull)
    if ($online) { Add-SysLine 'ok' 'Connexion : en ligne.' } else { Add-SysLine 'alerte' 'Connexion : GitHub / gyan.dev injoignables (hors ligne ou pare-feu) - mises a jour non verifiees.' }

    # --- Application ---
    $j = $null
    if ($res.App) { try { $j = $res.App | ConvertFrom-Json } catch { $j = $null } }
    if ($j -and $j.version) {
        $remote = Parse-AppVersion "$($j.version)"
        $local  = Parse-AppVersion $script:appVersion
        if ($remote -and $local -and ((Compare-AppVersion $remote $local) -gt 0)) {
            $script:updInfo = $j
            Add-SysLine 'maj' ('Application : V{0} disponible (installee : V{1}).' -f $j.version, $script:appVersion)
        } else {
            Add-SysLine 'ok' ('Application : V{0} a jour.' -f $script:appVersion)
        }
    } elseif ($online) { Add-SysLine 'alerte' 'Application : version.json illisible sur GitHub.' }

    # --- FFmpeg ---
    $loc = Get-FfmpegLocalInfo
    $hf = Get-FfmpegFlavor $loc; $wf = Get-WantedFlavor
    $hfTxt = switch ($hf) { 'full' { 'complet' } 'essentials' { 'essentials' } default { 'variante inconnue' } }
    if (-not $loc.Raw) {
        Add-SysLine 'alerte' 'FFmpeg : ffmpeg.exe introuvable ou illisible.'
    } else {
        $ffMsg = ''; $ffSt = 'ok'
        $fullBest = $null
        if ($res.FfFull) { $fullBest = Parse-FullChecksums "$($res.FfFull)" }
        $t = "$($res.Ff)".Trim()
        $stable = $null
        if ($t -match '^\d+(\.\d+){1,3}$') { $stable = [version]$t }
        if ($wf -eq 'full') {
            if ($hf -ne 'full') {
                $ffSt = 'maj'; $ffMsg = 'la build complete (VMAF, libplacebo) est recommandee'
                if ($fullBest) { $script:ffUpdAvail = $true; $script:ffLatest = $fullBest.Ver } elseif ($stable) { $script:ffUpdAvail = $true; $script:ffLatest = $stable }
            } elseif ($fullBest -and $loc.Ver -and $fullBest.Ver -gt $loc.Ver) {
                $ffSt = 'maj'; $ffMsg = ('version {0} disponible' -f $fullBest.Ver); $script:ffUpdAvail = $true; $script:ffLatest = $fullBest.Ver
            } elseif (-not $online) {
                $ffMsg = 'version non verifiee (hors ligne)'; $ffSt = 'info'
            } elseif (-not $fullBest) {
                $ffMsg = 'liste BtbN indisponible, verification impossible'; $ffSt = 'info'
            } elseif (-not $loc.Ver) {
                $ffMsg = 'build de developpement (non comparable, installer la derniere version stable depuis Parametres si besoin)'; $ffSt = 'info'
            } else { $ffMsg = 'a jour' }
        } else {
            if ($stable -and $loc.Ver -and $stable -gt $loc.Ver) { $ffSt = 'maj'; $ffMsg = ('version {0} disponible' -f $stable); $script:ffUpdAvail = $true; $script:ffLatest = $stable }
            elseif ($stable -and $loc.Ver -and $hf -and $hf -ne $wf) { $ffSt = 'maj'; $ffMsg = 'variante differente de celle choisie'; $script:ffUpdAvail = $true; $script:ffLatest = $stable }
            elseif (-not $online) { $ffSt = 'info'; $ffMsg = 'version non verifiee (hors ligne)' }
            elseif ($loc.Ver) { $ffMsg = 'a jour' }
            else { $ffSt = 'info'; $ffMsg = 'build de developpement (comparer dans Parametres)' }
        }
        Add-SysLine $ffSt ('FFmpeg {0} ({1}) : {2}.' -f $loc.Raw, $hfTxt, $ffMsg)
    }

    # --- ffprobe (meme version que ffmpeg) ---
    $fpv = Get-FfprobeVersionText
    if (-not $fpv) { Add-SysLine 'alerte' 'ffprobe : ffprobe.exe introuvable (necessaire a l''analyse des videos).' }
    elseif ($loc.Raw -and $fpv -ne $loc.Raw) { Add-SysLine 'alerte' ('ffprobe {0} different de ffmpeg {1} : refaire la mise a jour FFmpeg.' -f $fpv, $loc.Raw); if (-not $script:ffUpdAvail) { $script:ffUpdAvail = $true; $script:ffLatest = if ($stable) { $stable } else { $loc.Ver } } }
    else { Add-SysLine 'ok' ('ffprobe {0} : coherent avec ffmpeg.' -f $fpv) }

    # --- Capacites ffmpeg ---
    $c = $script:caps
    if ($c.Probed) {
        if ($c.Vmaf -and $c.PlaceboOk) { Add-SysLine 'ok' 'Capacites : VMAF et libplacebo disponibles.' }
        elseif ($c.Vmaf) { Add-SysLine 'info' 'Capacites : VMAF disponible ; libplacebo indisponible (build complet + GPU Vulkan requis).' }
        else { Add-SysLine 'maj' 'Capacites : libvmaf absent -> mesure SSIM (installer la build complete).' }
    }

    # --- Pilote NVIDIA / NVENC ---
    if ($script:nvDriver) {
        $drvTxt = 'Pilote NVIDIA ' + $script:nvDriver
        if ($c.Probed -and $c.NvErr -match 'nvenc API version|driver does not support|Required:|minimum required') {
            Add-SysLine 'alerte' ($drvTxt + ' trop ancien pour ce FFmpeg (NVENC) : installer le dernier pilote Game Ready / Studio sur nvidia.com/drivers.')
        } elseif ($c.Probed -and $script:nvOk -and $c.NvAdv) {
            Add-SysLine 'ok' ($drvTxt + ' : NVENC complet (B-frames) operationnel.')
        } elseif ($c.Probed -and $script:nvOk) {
            Add-SysLine 'maj' ($drvTxt + ' : NVENC limite (' + $c.NvErr + '). Mettre le pilote a jour (nvidia.com/drivers).')
        } elseif ($c.Probed) {
            $e = if ($script:nvProbeErr) { ' Erreur ffmpeg : ' + $script:nvProbeErr } else { '' }
            Add-SysLine 'alerte' ($drvTxt + ' : NVENC inutilisable.' + $e)
        } else { Add-SysLine 'info' ($drvTxt + '.') }
    }

    # --- Logo ---
    if ($j -and $j.sha256_logo) {
        $lp = Join-Path $script:appDir 'logo.jpg'
        $okLogo = $false
        try { if (Test-Path -LiteralPath $lp) { $okLogo = (Test-Sha256 $lp "$($j.sha256_logo)") } } catch {}
        if ($okLogo) { Add-SysLine 'ok' 'Logo : a jour.' }
        elseif ($res.LogoTmp -and (Test-Path -LiteralPath $res.LogoTmp)) {
            $fixed = $false
            try {
                if (Test-Sha256 $res.LogoTmp "$($j.sha256_logo)") { Move-Item -LiteralPath $res.LogoTmp -Destination $lp -Force; $fixed = $true }
            } catch {}
            if ($fixed) { Add-SysLine 'ok' 'Logo : mis a jour automatiquement (visible au prochain lancement).' } else { Add-SysLine 'info' 'Logo : mise a jour impossible (le logo integre est utilise).' }
        } else { Add-SysLine 'info' 'Logo : different de la version publiee (installe avec la prochaine mise a jour).' }
    }

    $script:sysChecked = $true
    foreach ($r in $script:sysReport) { try { Write-Log 'INFO' ('Verification systeme : ' + $r.Txt) } catch {} }
    try { if ($script:setWin -and $script:setWin.txtSys) { $script:setWin.txtSys.Text = Format-SysReport } } catch {}
    Update-UpdateBanner
}

# Les requetes web se font dans un runspace separe : la fenetre ne se fige jamais (meme hors ligne).
$script:startupPs = $null
$script:startupAsync = $null
$script:startupTicks = 0
$script:startupTimer = New-Object System.Windows.Forms.Timer
$script:startupTimer.Interval = 400
$script:startupTimer.Add_Tick({
    if (-not $script:startupAsync) { $script:startupTimer.Stop(); return }
    if (-not $script:startupAsync.IsCompleted) {
        $script:startupTicks++
        if ($script:startupTicks -gt 100) { $script:startupTimer.Stop() }    # abandon apres ~40 s
        return
    }
    $script:startupTimer.Stop()
    $res = $null
    try { $r = $script:startupPs.EndInvoke($script:startupAsync); if ($r -and $r.Count -gt 0) { $res = $r[0] } } catch {}
    try { $script:startupPs.Dispose() } catch {}
    $script:startupPs = $null; $script:startupAsync = $null
    if ($res) { try { Complete-StartupCheck $res } catch {} }
    try { if ($script:setWin) { Set-SysBusy $false } } catch {}
})

function Start-StartupCheck {
    try {
        $jobText = @'
param($u1, $u2, $u3, $ua, $logoUrl, $logoTmp, $logoLocalSha)
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
function Get-T($u, $ua) {
    try {
        $rq = [Net.HttpWebRequest]::Create($u)
        $rq.Timeout = 6000; $rq.ReadWriteTimeout = 6000; $rq.UserAgent = $ua
        $rs = $rq.GetResponse()
        try { $sr = New-Object System.IO.StreamReader($rs.GetResponseStream()); $sr.ReadToEnd() } finally { $rs.Close() }
    } catch { $null }
}
$app = Get-T $u1 $ua
$ff = Get-T $u2 $ua
$full = Get-T $u3 $ua
$tmp = $null
try {
    $j = $null; if ($app) { $j = $app | ConvertFrom-Json }
    if ($j -and $j.sha256_logo -and ("$($j.sha256_logo)" -ine "$logoLocalSha")) {
        $rq = [Net.HttpWebRequest]::Create($logoUrl); $rq.Timeout = 8000; $rq.ReadWriteTimeout = 8000; $rq.UserAgent = $ua
        $rs = $rq.GetResponse()
        try {
            $ms = New-Object System.IO.MemoryStream
            $rs.GetResponseStream().CopyTo($ms)
            [System.IO.File]::WriteAllBytes($logoTmp, $ms.ToArray()); $tmp = $logoTmp
        } finally { $rs.Close() }
    }
} catch { $tmp = $null }
[pscustomobject]@{ App = $app; Ff = $ff; FfFull = $full; LogoTmp = $tmp }
'@
        $stamp = [DateTime]::UtcNow.Ticks
        $lsha = ''
        try { $lp = Join-Path $script:appDir 'logo.jpg'; if (Test-Path -LiteralPath $lp) { $lsha = (Get-FileHash -LiteralPath $lp -Algorithm SHA256).Hash } } catch {}
        $ltmp = Join-Path ([IO.Path]::GetTempPath()) ('hevc_logo_' + [guid]::NewGuid().ToString('N') + '.jpg')
        $ps = [PowerShell]::Create()
        [void]$ps.AddScript($jobText).AddArgument(($script:repoRaw + '/version.json?t=' + $stamp)).AddArgument(($script:ffmpegVerUrl + '?t=' + $stamp)).AddArgument('https://github.com/BtbN/FFmpeg-Builds/releases/download/latest/checksums.sha256').AddArgument('Convert-ToHEVC/' + $script:appVersion).AddArgument($script:logoUrl).AddArgument($ltmp).AddArgument($lsha)
        $script:startupPs = $ps
        $script:startupAsync = $ps.BeginInvoke()
        $script:startupTicks = 0
        $script:startupTimer.Start()
    } catch {}
}

$form.Add_Shown({ if ([bool](Get-AppSetting 'checkUpdates' $true)) { Start-StartupCheck } })

Update-Preview
[System.Windows.Forms.Application]::Run($form)
