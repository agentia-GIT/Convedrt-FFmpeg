# ============================================================================
#  Convert-ToHEVC_V7c.ps1  -  Conversion video vers H.265 (HEVC) / MKV avec ffmpeg  (V7c)
#  - File d'attente : plusieurs videos, un seul dossier de sortie
#  - Nom de sortie  : <nom d'origine>_X265.mkv
#  - Video  : HEVC, resolution inchangee, taille finale 1,8 fois inferieure a l'original
#             NVENC (GPU NVIDIA) ou Quick Sync (GPU Intel) si detectes et cases cochees
#             (NVIDIA prioritaire si les deux sont cochees), sinon libx265 (CPU)
#  - Audio  : copie sans reencodage, piste francaise (ou piste unique / principale)
#  - Sous-titres : francais forces si audio FR present, sinon sous-titres francais
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
        if (Test-Path $local) { return $local }
    }
    $cmd = Get-Command "$name.exe" -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }
    return $null
}
if (-not $script:appDir) { $script:appDir = [Environment]::CurrentDirectory }

# ------------------------------------------- Version / depot GitHub (V7a) ---
$script:appVersion    = '7c'
$script:repoUrl       = 'https://github.com/agentia-GIT/Convedrt-FFmpeg'
$script:repoRaw       = 'https://raw.githubusercontent.com/agentia-GIT/Convedrt-FFmpeg/main'
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
function Download-File([string]$url, [string]$dest, $bar, $lbl, [string]$what) {
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    $rq = [Net.HttpWebRequest]::Create($url)
    $rq.Timeout = 15000; $rq.ReadWriteTimeout = 30000
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
                if ($raw -match '^(\d+(\.\d+){1,3})') { $ver = [version]$Matches[1] }
                elseif ($raw -match '^(\d{4})-(\d{2})-(\d{2})') {
                    try { $bdate = New-Object DateTime ([int]$Matches[1]), ([int]$Matches[2]), ([int]$Matches[3]) } catch { $bdate = $null }
                }
            }
        }
    } catch {}
    return [pscustomobject]@{ Raw = $raw; Ver = $ver; BuildDate = $bdate }
}

function Get-FfmpegZipUrl($loc) {
    $flavor = 'essentials'
    if ($loc -and "$($loc.Raw)" -match 'full_build') { $flavor = 'full' }
    return ('https://www.gyan.dev/ffmpeg/builds/ffmpeg-release-' + $flavor + '.zip')
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
        $sha = Get-WebText ($zipUrl + '.sha256')
        if ($sha -and ($sha.Trim() -match '^([0-9a-fA-F]{64})')) {
            if (-not (Test-Sha256 $zip $Matches[1])) { throw 'Somme de controle SHA-256 incorrecte : archive rejetee.' }
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
function Test-Nvenc {
    try {
        & $script:ffmpeg -hide_banner -loglevel error -f lavfi -i "nullsrc=s=256x256:d=0.2" `
            -c:v hevc_nvenc -f null - 2>$null
        return ($LASTEXITCODE -eq 0)
    } catch { return $false }
}
function Get-NvidiaName {
    try {
        $g = Get-CimInstance Win32_VideoController -ErrorAction Stop | Where-Object { $_.Name -match 'NVIDIA' } | Select-Object -First 1
        if ($g) { return $g.Name }
    } catch {}
    return $null
}

# Detection Intel Quick Sync : test d'encodage reel avec hevc_qsv
function Test-Qsv {
    try {
        & $script:ffmpeg -hide_banner -loglevel error -f lavfi -i "nullsrc=s=256x256:d=0.2" `
            -vf format=nv12 -c:v hevc_qsv -f null - 2>$null
        return ($LASTEXITCODE -eq 0)
    } catch { return $false }
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

function Is-French($s) {
    $lang = "$($s.tags.language)".ToLower()
    return ($lang -in @('fre', 'fra', 'fr', 'french', 'francais'))
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
function Get-ImageFilter($set, [int]$bits, [bool]$upscaled) {
    $pre = @(); $post = @(); $sharp = 0.0
    if ($set) {
        $m = [double]((1 -shl $bits) - 1); $mid = ($m + 1) / 2
        $b = [double]$set.Bright / 100.0; $c = [double]$set.Contrast / 100.0
        $g = [double]$set.Gamma / 100.0;  $sa = [double]$set.Sat / 100.0
        $parts = @()
        if ($set.Bright -ne 0 -or $set.Contrast -ne 100 -or $set.Gamma -ne 100) {
            $parts += ("y='clip((pow(val/{0},{1})*{0}-{2})*{3}+{2}+{4},0,{0})'" -f (Fmt-Num $m), (Fmt-Num (1.0 / $g)), (Fmt-Num $mid), (Fmt-Num $c), (Fmt-Num ($b * $m)))
        }
        if ($set.Sat -ne 100) {
            $e = ("clip((val-{0})*{1}+{0},0,{2})" -f (Fmt-Num $mid), (Fmt-Num $sa), (Fmt-Num $m))
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
function Get-CorrFilter($corr, [int]$bits) {
    if (-not $corr) { return '' }
    $k = [Math]::Pow(2, $bits - 8); $m = (1 -shl $bits) - 1
    $p = @()
    foreach ($c in @(@('y', 'Y'), @('u', 'U'), @('v', 'V'))) {
        $o = [double]$corr[$c[1]]
        if ([Math]::Abs($o) -ge 0.01) {
            $p += ("{0}='clip(val+{1},0,{2})'" -f $c[0], (Fmt-Num ($o * $k)), $m)
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
function Get-ColorCorrection($item, $info, [string]$mode, [bool]$up) {
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
            $sp = Build-FfmpegArgs $info $item.Path $sfile $sprog $mode $up $false $null $pos $len
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
function Build-FfmpegArgs($info, [string]$src, [string]$dst, [string]$progressFile, [string]$mode, [bool]$upscale = $false, [bool]$twoPass = $false, $corr = $null, [double]$sampleStart = -1.0, [double]$sampleLen = 0.0) {

    $isSample = ($sampleLen -gt 0)
    if ($isSample) { $twoPass = $false }

    $tpl = ($null -eq $info)
    $duration = 0.0

    if ($tpl) {
        $v = [pscustomobject]@{ index = 0; pix_fmt = 'yuv420p'; profile = 'Main' }
        $audio = @([pscustomobject]@{ index = 1 })
        $subs  = @()
    } else {
        [void][double]::TryParse("$($info.format.duration)", [Globalization.NumberStyles]::Float, $inv, [ref]$duration)
        $video = @($info.streams | Where-Object { $_.codec_type -eq 'video' -and $_.disposition.attached_pic -ne 1 })
        $audio = @($info.streams | Where-Object { $_.codec_type -eq 'audio' })
        $subs  = @($info.streams | Where-Object { $_.codec_type -eq 'subtitle' })
        if ($video.Count -eq 0) { throw "Aucune piste video trouvee." }
        $v = $video[0]
    }

    # --- Etiquettes de couleur de la source (V7) ----------------------------
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
    $bits = 8
    if ($tpl) { $bits = 8 } else { $bits = Get-StreamBits $info }

    # --- Bitrate video d'origine -> cible = original / 1,8 ------------------
    $targetK = 0
    if ($tpl) {
        $bTxt = '<debit_cible>k'; $mTxt = '<debit_max>k'; $bufTxt = '<buffer>k'
    } else {
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
        $targetK = [int][Math]::Max([Math]::Round($vbr / $script:sizeRatio / 1000), 200)
        $bTxt = "${targetK}k"
        $mTxt = "$([int]($targetK * 1.6))k"
        $bufTxt = "$([int]($targetK * 3))k"
    }

    # --- Upscaling 1080p HD (optionnel) --------------------------------------
    # Mise a l'echelle Lanczos haute precision, proportions et pixels carres respectes,
    # desentrelacement si la source est entrelacee, puis encodage a qualite constante
    # (un debit limite a original/1,8 ne suffirait pas a remplir une image 1080p).
    $vf = $null; $scaleNote = ''; $quality = $false
    if ($upscale) {
        if ($tpl) {
            $vf = 'scale=<largeur>:<hauteur>:flags=lanczos+accurate_rnd+full_chroma_int,setsar=1'
            $scaleNote = 'mise a l''echelle vers 1080p (dimensions calculees pour chaque video)'
            $quality = $true
        } else {
            $srcW = [double]$v.width; $srcH = [double]$v.height
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
                $chain = @()
                $interlaced = ("$($v.field_order)" -in @('tt', 'bb', 'tb', 'bt'))
                if ($interlaced) { $chain += 'yadif=0:-1:1' }
                $chain += "scale=${ow}:${oh}:flags=lanczos+accurate_rnd+full_chroma_int"
                $chain += 'setsar=1'
                $vf = $chain -join ','
                $quality = $true
                $scaleNote = '{0:0}x{1:0} -> {2}x{3}' -f $srcW, $srcH, $ow, $oh
                if ($interlaced) { $scaleNote += ' (desentrelacement yadif)' }
            } else {
                $scaleNote = 'deja en 1080p ou plus : aucune mise a l''echelle'
            }
        }
    }

    # --- Reglages image valides + nettete automatique apres upscaling (V7) ---
    $upscaled = [bool]$quality
    $imgSet = $null
    if ($script:imgOn -and $script:imgValidated) { $imgSet = $script:imgValidated }
    $imf = Get-ImageFilter $imgSet $bits $upscaled
    if ($imf.Pre)  { $vf = $(if ($vf) { $imf.Pre + ',' + $vf } else { $imf.Pre }) }
    if ($imf.Post) { $vf = $(if ($vf) { $vf + ',' + $imf.Post } else { $imf.Post }) }

    # --- Correction de couleur issue de la comparaison avant compression (V7) --
    $vfBase = $vf
    if ($corr) {
        $cf = Get-CorrFilter $corr $bits
        if ($cf) { $vf = $(if ($vf) { $vf + ',' + $cf } else { $cf }) }
    }

    # --- Encodage 2 passes (optionnel, avec upscaling) ------------------------
    # Une 2 passes travaille a debit cible : avec upscaling, le debit est calcule pour du 1080p
    # (bits par pixel), sans jamais descendre sous le debit cible original/1,8.
    # x265 (CPU) : analyse (passe 1) puis encodage final (passe 2), deux lancements de ffmpeg.
    # NVENC : 2 passes materielles (multipass fullres) ; Quick Sync : pas de 2 passes materielles.
    $passes = 1; $passNote = ''; $statsName = ''
    if ($twoPass) {
        if ($quality) {
            if ($tpl) {
                $bTxt = '<debit_2passes>k'; $mTxt = '<debit_max>k'; $bufTxt = '<buffer>k'
            } else {
                $fps = 25.0
                if ("$($v.avg_frame_rate)" -match '^(\d+)/(\d+)$') {
                    $fn = [double]$Matches[1]; $fd = [double]$Matches[2]
                    if ($fn -gt 0 -and $fd -gt 0) { $fps = $fn / $fd }
                }
                $bppK = [int][Math]::Round($ow * $oh * $fps * $script:twoPassBpp / 1000)
                $targetK = [Math]::Max($bppK, $targetK)
                $bTxt = "${targetK}k"
                $mTxt = "$([int]($targetK * 1.6))k"
                $bufTxt = "$([int]($targetK * 3))k"
            }
            $quality = $false
        }
        switch ($mode) {
            'cpu'   { $passes = 2; $passNote = 'Encodage 2 passes x265 : passe 1 (analyse) puis passe 2 (encodage final)' }
            'nvenc' { $passNote = 'Encodage NVENC : 2 passes materielles (multipass fullres), debit cible' }
            default { $passNote = 'Quick Sync : pas de 2 passes materielles, debit cible utilise' }
        }
        $leaf = $progressFile.Substring($progressFile.LastIndexOf('\') + 1)
        $statsName = (($leaf -replace '^ffprog_', 'ff2p_') -replace '\.txt$', '') + '.log'
    }

    if ($quality) {
        $rateTxt = if ($mode -eq 'cpu') { 'qualite constante CRF {0}' -f $script:upCrf } else { 'qualite constante CQ {0}' -f $script:upCq }
    } elseif ($twoPass) {
        $kTxt = if ($tpl) { '<debit>' } else { "$targetK" }
        $rateTxt = switch ($mode) {
            'cpu'   { "2 passes x265, cible ~$kTxt kb/s" }
            'nvenc' { "NVENC 2 passes materielles, cible ~$kTxt kb/s" }
            default { "Quick Sync, cible ~$kTxt kb/s (sans 2 passes materielles)" }
        }
    } elseif ($tpl) { $rateTxt = 'cible video original / 1,8' } else { $rateTxt = 'cible video ~{0} kb/s' -f $targetK }

    # --- Audio : FR sinon piste unique sinon piste principale ---------------
    $selAudio = @()
    if ($audio.Count -eq 1) { $selAudio = @($audio[0]) }
    elseif ($audio.Count -gt 1) {
        $fr = @($audio | Where-Object { Is-French $_ })
        if ($fr.Count -gt 0) { $selAudio = $fr }
        else {
            $def = @($audio | Where-Object { $_.disposition.default -eq 1 })
            if ($def.Count -gt 0) { $selAudio = @($def[0]) } else { $selAudio = @($audio[0]) }
        }
    }
    $hasFrAudio = (@($selAudio | Where-Object { Is-French $_ })).Count -gt 0

    # --- Sous-titres ---------------------------------------------------------
    $frSubs = @($subs | Where-Object { Is-French $_ })
    if ($hasFrAudio) {
        $selSubs = @($frSubs | Where-Object { $_.disposition.forced -eq 1 -or "$($_.tags.title)" -match '(?i)forced|forc' })
    } else {
        $selSubs = $frSubs
    }

    if ($isSample) { $selAudio = @(); $selSubs = @() }     # extrait de mesure : video seule

    # --- Arguments -----------------------------------------------------------
    $a = New-Object System.Collections.Generic.List[string]
    $a.AddRange([string[]]@('-hide_banner', '-loglevel', 'error', '-y', '-nostats', '-progress', (Q $progressFile)))
    $a.AddRange([string[]]@('-threads', "$($script:threads)"))          # decodage : part de CPU choisie
    if ($mode -eq 'nvenc') { $a.AddRange([string[]]@('-hwaccel', 'cuda')) }
    if ($isSample) { $a.AddRange([string[]]@('-ss', $sampleStart.ToString('0.###', $inv), '-t', $sampleLen.ToString('0.###', $inv))) }
    $a.AddRange([string[]]@('-i', (Q $src)))

    $a.AddRange([string[]]@('-map', "0:$($v.index)"))
    foreach ($s in $selAudio) { $a.AddRange([string[]]@('-map', "0:$($s.index)")) }
    foreach ($s in $selSubs)  { $a.AddRange([string[]]@('-map', "0:$($s.index)")) }

    # Suppression des metadonnees et chapitres
    $a.AddRange([string[]]@('-map_metadata', '-1', '-map_chapters', '-1',
        '-fflags', '+bitexact', '-flags:v', '+bitexact', '-flags:a', '+bitexact'))
    $a.AddRange([string[]]@('-metadata:s:v:0', 'title=', '-metadata:s:v:0', 'handler_name=', '-metadata:s:v:0', 'vendor_id='))
    for ($i = 0; $i -lt $selAudio.Count; $i++) {
        $a.AddRange([string[]]@("-metadata:s:a:$i", 'title=', "-metadata:s:a:$i", 'handler_name=', "-metadata:s:a:$i", 'vendor_id='))
    }
    for ($i = 0; $i -lt $selSubs.Count; $i++) {
        $a.AddRange([string[]]@("-metadata:s:s:$i", 'title=', "-metadata:s:s:$i", 'handler_name=', "-metadata:s:s:$i", 'vendor_id='))
    }

    # Video : resolution identique sauf upscaling coche. 10 bits conserves.
    if ($vf) { $a.AddRange([string[]]@('-vf', (Q $vf))) }
    $tenBit = ("$($v.pix_fmt)" -match '10') -or ("$($v.profile)" -match '10')
    if ($mode -eq 'nvenc') {
        $a.AddRange([string[]]@('-c:v', 'hevc_nvenc', '-preset', 'p7', '-tune', 'hq'))
        if ($quality) { $a.AddRange([string[]]@('-rc', 'vbr', '-cq', "$($script:upCq)", '-b:v', '0')) }
        else          { $a.AddRange([string[]]@('-rc', 'vbr', '-b:v', $bTxt, '-maxrate', $mTxt, '-bufsize', $bufTxt)) }
        $a.AddRange([string[]]@('-multipass', 'fullres', '-rc-lookahead', '32', '-spatial_aq', '1', '-temporal_aq', '1'))
        if ($tenBit) { $a.AddRange([string[]]@('-profile:v', 'main10', '-pix_fmt', 'p010le')) }
        else         { $a.AddRange([string[]]@('-profile:v', 'main')) }
    } elseif ($mode -eq 'qsv') {
        $a.AddRange([string[]]@('-c:v', 'hevc_qsv', '-preset', 'slow'))
        if ($quality) { $a.AddRange([string[]]@('-global_quality', "$($script:upCq)")) }
        else          { $a.AddRange([string[]]@('-b:v', $bTxt, '-maxrate', $mTxt, '-bufsize', $bufTxt)) }
        if ($tenBit) { $a.AddRange([string[]]@('-profile:v', 'main10', '-pix_fmt', 'p010le')) }
        else         { $a.AddRange([string[]]@('-profile:v', 'main', '-pix_fmt', 'nv12')) }
    } else {
        $a.AddRange([string[]]@('-c:v', 'libx265', '-preset', 'slow'))
        if ($quality) { $a.AddRange([string[]]@('-crf', "$($script:upCrf)")) }
        else          { $a.AddRange([string[]]@('-b:v', $bTxt, '-maxrate', $mTxt, '-bufsize', $bufTxt)) }
        $xp = "log-level=error:pools=$($script:threads)"
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
        if ($tenBit) { $a.AddRange([string[]]@('-pix_fmt', 'yuv420p10le')) }
    }
    # Etiquettes de couleur identiques a la source (V7)
    if ($col.Range) { $a.AddRange([string[]]@('-color_range', $col.Range)) }
    $a.AddRange([string[]]@('-colorspace', $col.Space, '-color_trc', $col.Trc, '-color_primaries', $col.Prim))
    $a.AddRange([string[]]@('-threads', "$($script:threads)"))          # encodage : part de CPU choisie

    # Audio : aucun reencodage
    if ($selAudio.Count -gt 0) { $a.AddRange([string[]]@('-c:a', 'copy')) } else { $a.Add('-an') }

    # Sous-titres : copie (mov_text converti en srt pour MKV)
    if ($selSubs.Count -gt 0) {
        $a.AddRange([string[]]@('-c:s', 'copy'))
        for ($i = 0; $i -lt $selSubs.Count; $i++) {
            if ($selSubs[$i].codec_name -eq 'mov_text') { $a.AddRange([string[]]@("-c:s:$i", 'srt')) }
        }
    } else { $a.Add('-sn') }

    $a.AddRange([string[]]@('-max_muxing_queue_size', '1024', '-f', 'matroska', (Q $dst)))

    # Passe 1 (analyse x265) : video seule, sortie nulle. Le fichier de stats est relatif
    # (ffmpeg est lance dans le dossier temporaire) pour eviter le ':' des chemins Windows.
    $args1 = $null
    if ($passes -eq 2) {
        $b = New-Object System.Collections.Generic.List[string]
        $b.AddRange([string[]]@('-hide_banner', '-loglevel', 'error', '-y', '-nostats', '-progress', (Q $progressFile)))
        $b.AddRange([string[]]@('-threads', "$($script:threads)", '-i', (Q $src), '-map', "0:$($v.index)"))
        if ($vf) { $b.AddRange([string[]]@('-vf', (Q $vf))) }
        $b.AddRange([string[]]@('-c:v', 'libx265', '-preset', 'slow', '-b:v', $bTxt, '-maxrate', $mTxt, '-bufsize', $bufTxt,
            '-x265-params', "log-level=error:pools=$($script:threads):pass=1:stats=$statsName"))
        if ($tenBit) { $b.AddRange([string[]]@('-pix_fmt', 'yuv420p10le')) }
        $b.AddRange([string[]]@('-threads', "$($script:threads)", '-an', '-sn', '-f', 'null', 'NUL'))
        $args1 = ($b -join ' ')
    }

    $colorNote = 'Couleurs : plage {0} | matrice {1} | transfert {2} | primaires {3} ({4})' -f $(if ($col.Range) { $col.Range } else { 'conversion ffmpeg' }), $col.Space, $col.Trc, $col.Prim, $(if ($col.Tagged) { 'etiquettes de la source reappliquees' } else { 'source sans etiquette : valeurs par defaut des lecteurs' })

    return [pscustomobject]@{
        Col      = $col
        Vf       = $vf
        VfBase   = $vfBase
        MapIndex = $v.index
        CorrNote = $(if ($corr) { 'correction couleur ajoutee (Y {0:+0.00;-0.00;0.00}, U {1:+0.00;-0.00;0.00}, V {2:+0.00;-0.00;0.00})' -f $corr.Y, $corr.U, $corr.V } else { '' })
        ColorNote = $colorNote
        ModeNote = $modeNote
        ImgNote  = $(if ($imgSet) { Format-ImgSummary $imgSet } else { '' })
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
        Audio    = $selAudio.Count
        Subs     = $selSubs.Count
        Encoder  = $(switch ($mode) { 'nvenc' { 'NVENC (GPU NVIDIA)' } 'qsv' { 'Quick Sync (GPU Intel)' } default { 'libx265 (CPU)' } })
    }
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
$form.Text = 'Conversion H.265 / MKV V7c - file d''attente'
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

$logoBmp = Get-LogoBitmap
$pic = New-Object System.Windows.Forms.PictureBox
$pic.SizeMode = 'Normal'
$pic.Image = $logoBmp
$pic.Size = New-Object System.Drawing.Size($logoBmp.Width, $logoBmp.Height)
$pic.Location = New-Object System.Drawing.Point(16, 10)
$pic.BackColor = $script:white
$pnlHead.Controls.Add($pic)

$lblTitle = New-Object System.Windows.Forms.Label
$lblTitle.Text = 'Conversion video H.265 (HEVC) / MKV - V7c'
$lblTitle.Font = New-Object System.Drawing.Font('Arial', 15, [System.Drawing.FontStyle]::Bold)
$lblTitle.ForeColor = $script:cGreen
$lblTitle.AutoSize = $false
$lblTitle.Location = New-Object System.Drawing.Point(270, 20); $lblTitle.Size = New-Object System.Drawing.Size(566, 30)
$lblTitle.TextAlign = 'MiddleRight'
$pnlHead.Controls.Add($lblTitle)

$lblSub = New-Object System.Windows.Forms.Label
$lblSub.Text = 'Conversion par lots avec ffmpeg - audio copie sans reencodage'
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

$tip = New-Object System.Windows.Forms.ToolTip
$tip.AutoPopDelay = 25000
$tip.SetToolTip($chkUp, 'Agrandit les videos plus petites que 1080p vers 1920x1080 maximum (proportions conservees). Filtre Lanczos haute precision, desentrelacement si besoin, encodage a qualite constante (le debit n''est plus limite a original/1,8, le fichier peut donc etre plus gros). Une legere nettete automatique est ajoutee apres l''agrandissement. Les videos deja en 1080p ou plus ne sont pas modifiees.')
$tip.SetToolTip($chkTwo, 'Utilisable avec ou sans upscaling (se coche automatiquement avec l''upscaling, decochable). Encodage a debit cible en 2 passes pour un final de haute qualite : sans upscaling le debit vise original/1,8 ; avec upscaling il est calcule pour du 1080p, sans jamais descendre sous original/1,8. Processeur : x265 analyse la video (passe 1) puis l''encode (passe 2), environ 2 fois plus long. NVIDIA : 2 passes materielles (multipass). Intel Quick Sync : pas de 2 passes materielles, debit cible seulement.')
$tip.SetToolTip($btnImg, 'Ouvre une fenetre flottante independante : image originale et apercu avec reglages (luminosite, contraste, saturation, gamma, nettete, depixelisation). Les reglages ne sont appliques a la conversion qu''apres validation.')
$tip.SetToolTip($picGear, 'Parametres : version, depot GitHub, mises a jour (application et ffmpeg)')
$tip.SetToolTip($chkCmp, 'Avant chaque video : encode 3 extraits courts (20, 50 et 80 % de la duree) avec les memes reglages, compare la luminosite et les couleurs moyennes avec l''original, puis corrige l''ecart dans l''encodage final. Un controle final original / sortie est fait a la fin. Ajoute quelques secondes (jusqu''a une minute en processeur) par video.')
$tip.SetToolTip($chkImg, 'Active ou desactive les reglages image valides dans la fenetre d''apercu.')
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
        $plan = Build-FfmpegArgs $info $src $dst $prog (Get-EncoderMode) $chkUp.Checked $chkTwo.Checked
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
    foreach ($c in @($btnAdd, $btnRemove, $btnClear, $btnOut, $txtOut, $lv, $knob, $chkUp)) { $c.Enabled = -not $busy }
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
        $script:progressFile = Join-Path $env:TEMP ("ffprog_{0}.txt" -f [guid]::NewGuid().ToString('N'))
        $script:errFile      = Join-Path $env:TEMP ("fferr_{0}.txt"  -f [guid]::NewGuid().ToString('N'))
        $corr = $null
        if ($script:cmpOn) {
            $script:analyzing = $true
            Set-RowState $i 'Comparaison des couleurs...'
            $lblStatus.Text = 'Comparaison original / sortie sur extraits avant compression...'
            $lblFile.Text = ('Fichier {0}/{1} : {2}' -f ($i + 1), $script:queue.Count, [IO.Path]::GetFileName($item.Path))
            $form.Refresh()
            $cc = $null
            try { $cc = Get-ColorCorrection $item $info (Get-EncoderMode) $chkUp.Checked }
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
            $plan = Build-FfmpegArgs $info $item.Path $dst $script:progressFile (Get-EncoderMode) $chkUp.Checked $chkTwo.Checked $corr
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
        if ($plan.CorrNote) { Write-Log 'INFO' "$tag $($plan.CorrNote)" }
        if ($plan.ModeNote) { Write-Log 'INFO' "$tag $($plan.ModeNote)" }
        if ($plan.ImgNote) { Write-Log 'INFO' "$tag Reglages image : $($plan.ImgNote)" }
        if ($plan.PassNote) { Write-Log 'INFO' "$tag $($plan.PassNote)" }
        if ($plan.Passes -eq 2) { Write-Log 'INFO' "$tag Commande passe 1/2 : ffmpeg $($plan.Args1)" }
        Write-Log 'INFO' "$tag Commande : ffmpeg $($plan.Args)"

        $script:plan = $plan
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
        if ($bp) { $script:iw.lblMsg.Text = 'Apercu a jour. HDR : l''apercu n''applique pas le tone mapping.' }
        else { $script:iw.lblMsg.Text = 'Image indisponible a cette position (filtre non pris en charge par ce ffmpeg ?).' }
    } catch {
        $script:iw.lblMsg.Text = 'Erreur apercu : ' + $_.Exception.Message
    }
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
    $w.ClientSize = New-Object System.Drawing.Size(1000, 760)
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
    $cmb.Location = New-Object System.Drawing.Point(70, 16); $cmb.Size = New-Object System.Drawing.Size(910, 26)
    $w.Controls.Add($cmb)
    $script:iw.cmb = $cmb
    foreach ($q in $script:queue) { [void]$cmb.Items.Add([IO.Path]::GetFileName($q.Path)) }
    if ($cmb.Items.Count -gt 0) {
        $k = 0
        if ($lv.SelectedIndices.Count -gt 0) { $k = $lv.SelectedIndices[0] }
        $cmb.SelectedIndex = [Math]::Min($k, $cmb.Items.Count - 1)
    }

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

    $lm = New-Object System.Windows.Forms.Label
    $lm.Text = ''; $lm.ForeColor = $script:cMuted; $lm.Location = New-Object System.Drawing.Point(20, 676)
    $lm.Size = New-Object System.Drawing.Size(960, 20)
    $w.Controls.Add($lm); $script:iw.lblMsg = $lm

    $bReset = Add-Button 'Reinitialiser'                20 706 150 36 $false $w
    $bPlay  = Add-Button 'Lire un extrait (ffplay)'    180 706 220 36 $false $w
    $bOk    = Add-Button 'Valider les reglages'        560 706 230 36 $true  $w
    $bClose = Add-Button 'Fermer'                      800 706 180 36 $false $w
    $ct = New-Object System.Windows.Forms.CheckBox
    $ct.Text = 'Toujours au premier plan'; $ct.Location = New-Object System.Drawing.Point(410, 712); $ct.Size = New-Object System.Drawing.Size(150, 24)
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
    foreach ($k in @('btnChk', 'btnGit', 'btnFfChk', 'btnFfWeb', 'btnClose')) { $w[$k].Enabled = (-not $busy) }
    if ($busy) {
        $w.btnUpd.Enabled = $false; $w.btnFfUpd.Enabled = $false
        $w.form.Cursor = [System.Windows.Forms.Cursors]::AppStarting
    } else {
        $w.btnUpd.Enabled = [bool]$w.updOk; $w.btnFfUpd.Enabled = [bool]$w.ffUpdOk
        $w.form.Cursor = [System.Windows.Forms.Cursors]::Default
    }
}

# ---- Mise a jour de l'application : telecharge la nouvelle version puis redemarre ----
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
    $ask = [System.Windows.Forms.MessageBox]::Show(("Installer la version V{0} ({1}) dans :`r`n{2}`r`n`r`nL'application va redemarrer. L'ancienne version est conservee." -f $j.version, $kind, $script:appDir), 'Mise a jour', 'YesNo', 'Question')
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
    $f.ClientSize = New-Object System.Drawing.Size(580, 616)
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

    # ---- Application / GitHub ----
    $h1 = Add-Label 'Application et depot GitHub' 20 18 $f
    $h1.Font = New-Object System.Drawing.Font('Arial', 10.5, [System.Drawing.FontStyle]::Bold); $h1.ForeColor = $script:cGreen
    $modeTxt = if ($env:HEVC_APPDIR) { 'binaire (.exe)' } else { 'script PowerShell (.ps1)' }
    Add-Label ('Version installee : V' + $script:appVersion + '  -  ' + $modeTxt) 20 50 $f | Out-Null
    Add-Label 'Depot GitHub :' 20 78 $f | Out-Null
    $lnk = New-Object System.Windows.Forms.LinkLabel
    $lnk.Text = $script:repoUrl; $lnk.AutoSize = $true
    $lnk.Location = New-Object System.Drawing.Point(130, 78)
    $lnk.LinkColor = $script:cGreen; $lnk.ActiveLinkColor = $script:cGreenDark
    $lnk.Add_LinkClicked({ Open-Url $script:repoUrl })
    $f.Controls.Add($lnk)

    $sw.btnChk = Add-Button 'Verifier la nouvelle version' 20 110 230 32 $true $f
    $sw.btnGit = Add-Button 'Ouvrir la page GitHub' 262 110 200 32 $false $f
    $sw.lblUpd = New-Object System.Windows.Forms.Label
    $sw.lblUpd.Text = 'Chaque nouveau build est synchronise sur GitHub (fichier version.json).'
    $sw.lblUpd.ForeColor = $script:cMuted
    $sw.lblUpd.AutoSize = $false
    $sw.lblUpd.Location = New-Object System.Drawing.Point(20, 152); $sw.lblUpd.Size = New-Object System.Drawing.Size(540, 56)
    $f.Controls.Add($sw.lblUpd)
    $sw.btnUpd = Add-Button 'Faire la mise a jour' 20 214 230 32 $false $f
    $sw.btnUpd.Enabled = $false
    $sw.barApp = New-Object FlatProgress
    $sw.barApp.Location = New-Object System.Drawing.Point(262, 224); $sw.barApp.Size = New-Object System.Drawing.Size(298, 12)
    $sw.barApp.Minimum = 0; $sw.barApp.Maximum = 1000; $sw.barApp.Visible = $false
    $f.Controls.Add($sw.barApp)

    $sep = New-Object System.Windows.Forms.Panel
    $sep.Location = New-Object System.Drawing.Point(20, 266); $sep.Size = New-Object System.Drawing.Size(540, 1)
    $sep.BackColor = $script:cBorder
    $f.Controls.Add($sep)

    # ---- FFmpeg ----
    $h2 = Add-Label 'FFmpeg' 20 282 $f
    $h2.Font = New-Object System.Drawing.Font('Arial', 10.5, [System.Drawing.FontStyle]::Bold); $h2.ForeColor = $script:cGreen
    $ff = Get-FfmpegLocalInfo
    $ffTxt = if ($ff.Raw) { $ff.Raw } else { 'inconnue' }
    $sw.lblFfVer = New-Object System.Windows.Forms.Label
    $sw.lblFfVer.Text = 'Version installee : ' + $ffTxt
    $sw.lblFfVer.AutoSize = $false; $sw.lblFfVer.AutoEllipsis = $true
    $sw.lblFfVer.Location = New-Object System.Drawing.Point(20, 312); $sw.lblFfVer.Size = New-Object System.Drawing.Size(540, 20)
    $f.Controls.Add($sw.lblFfVer)
    $sw.lblFfPath = New-Object System.Windows.Forms.Label
    $sw.lblFfPath.Text = $script:ffmpeg
    $sw.lblFfPath.ForeColor = $script:cMuted; $sw.lblFfPath.Font = New-Object System.Drawing.Font('Arial', 8.5)
    $sw.lblFfPath.AutoSize = $false; $sw.lblFfPath.AutoEllipsis = $true
    $sw.lblFfPath.Location = New-Object System.Drawing.Point(20, 336); $sw.lblFfPath.Size = New-Object System.Drawing.Size(540, 18)
    $f.Controls.Add($sw.lblFfPath)
    $sw.ffLocal = $ff

    $sw.btnFfChk = Add-Button 'Verifier la mise a jour FFmpeg' 20 366 230 32 $true $f
    $sw.btnFfWeb = Add-Button 'Page de telechargement' 262 366 200 32 $false $f
    $sw.lblFfUpd = New-Object System.Windows.Forms.Label
    $sw.lblFfUpd.Text = 'Compare la version installee a la derniere version stable (gyan.dev).'
    $sw.lblFfUpd.ForeColor = $script:cMuted
    $sw.lblFfUpd.AutoSize = $false
    $sw.lblFfUpd.Location = New-Object System.Drawing.Point(20, 408); $sw.lblFfUpd.Size = New-Object System.Drawing.Size(540, 84)
    $f.Controls.Add($sw.lblFfUpd)
    $sw.btnFfUpd = Add-Button 'Faire la mise a jour FFmpeg' 20 500 230 32 $false $f
    $sw.btnFfUpd.Enabled = $false
    $sw.barFf = New-Object FlatProgress
    $sw.barFf.Location = New-Object System.Drawing.Point(262, 510); $sw.barFf.Size = New-Object System.Drawing.Size(298, 12)
    $sw.barFf.Minimum = 0; $sw.barFf.Maximum = 1000; $sw.barFf.Visible = $false
    $f.Controls.Add($sw.barFf)

    $sw.btnClose = Add-Button 'Fermer' 460 572 100 32 $false $f
    $f.CancelButton = $sw.btnClose
    $sw.btnClose.Add_Click({ $script:setWin.form.Close() })

    $sw.btnGit.Add_Click({ Open-Url $script:repoUrl })
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
        $txt = Get-WebText ($script:ffmpegVerUrl + '?t=' + [DateTime]::UtcNow.Ticks)
        $last = $null
        if ($txt) { $t = $txt.Trim(); if ($t -match '^\d+(\.\d+){1,3}$') { $last = [version]$t } }
        if (-not $last) {
            $w.lblFfUpd.ForeColor = $red
            $w.lblFfUpd.Text = 'Impossible de lire la derniere version de FFmpeg (connexion internet ou site inaccessible).'
        } else {
            $loc = $w.ffLocal
            if ($loc.Ver) {
                if ($last -gt $loc.Ver) {
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

    # Option : verification des mises a jour au demarrage
    $sw.chkAuto = New-Object System.Windows.Forms.CheckBox
    $sw.chkAuto.Text = 'Verifier les mises a jour au demarrage'
    $sw.chkAuto.AutoSize = $false
    $sw.chkAuto.Location = New-Object System.Drawing.Point(20, 576); $sw.chkAuto.Size = New-Object System.Drawing.Size(400, 24)
    $sw.chkAuto.Checked = [bool](Get-AppSetting 'checkUpdates' $true)
    $sw.chkAuto.Add_CheckedChanged({ Set-AppSetting 'checkUpdates' ([bool]$script:setWin.chkAuto.Checked) })
    $f.Controls.Add($sw.chkAuto)

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

function Complete-StartupCheck($res) {
    if ($res.App) {
        $j = $null
        try { $j = $res.App | ConvertFrom-Json } catch { $j = $null }
        if ($j -and $j.version) {
            $remote = Parse-AppVersion "$($j.version)"
            $local  = Parse-AppVersion $script:appVersion
            if ($remote -and $local -and ((Compare-AppVersion $remote $local) -gt 0)) { $script:updInfo = $j }
        }
    }
    if ($res.Ff) {
        $t = "$($res.Ff)".Trim()
        if ($t -match '^\d+(\.\d+){1,3}$') {
            $last = [version]$t
            $loc = Get-FfmpegLocalInfo
            # Un build de developpement (git) n'est jamais signale ici : voir la fenetre Parametres
            if ($loc.Ver -and $last -gt $loc.Ver) { $script:ffUpdAvail = $true; $script:ffLatest = $last }
        }
    }
    Update-UpdateBanner
}

# Les deux requetes web se font dans un runspace separe : la fenetre ne se fige jamais (meme hors ligne).
$script:startupPs = $null
$script:startupAsync = $null
$script:startupTicks = 0
$script:startupTimer = New-Object System.Windows.Forms.Timer
$script:startupTimer.Interval = 400
$script:startupTimer.Add_Tick({
    if (-not $script:startupAsync) { $script:startupTimer.Stop(); return }
    if (-not $script:startupAsync.IsCompleted) {
        $script:startupTicks++
        if ($script:startupTicks -gt 80) { $script:startupTimer.Stop() }     # abandon apres ~32 s
        return
    }
    $script:startupTimer.Stop()
    $res = $null
    try { $r = $script:startupPs.EndInvoke($script:startupAsync); if ($r -and $r.Count -gt 0) { $res = $r[0] } } catch {}
    try { $script:startupPs.Dispose() } catch {}
    $script:startupPs = $null; $script:startupAsync = $null
    if ($res) { try { Complete-StartupCheck $res } catch {} }
})

function Start-StartupCheck {
    try {
        $jobText = @'
param($u1, $u2, $ua)
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
function Get-T($u, $ua) {
    try {
        $rq = [Net.HttpWebRequest]::Create($u)
        $rq.Timeout = 6000; $rq.ReadWriteTimeout = 6000; $rq.UserAgent = $ua
        $rs = $rq.GetResponse()
        try { $sr = New-Object System.IO.StreamReader($rs.GetResponseStream()); $sr.ReadToEnd() } finally { $rs.Close() }
    } catch { $null }
}
[pscustomobject]@{ App = (Get-T $u1 $ua); Ff = (Get-T $u2 $ua) }
'@
        $stamp = [DateTime]::UtcNow.Ticks
        $ps = [PowerShell]::Create()
        [void]$ps.AddScript($jobText).AddArgument(($script:repoRaw + '/version.json?t=' + $stamp)).AddArgument(($script:ffmpegVerUrl + '?t=' + $stamp)).AddArgument('Convert-ToHEVC/' + $script:appVersion)
        $script:startupPs = $ps
        $script:startupAsync = $ps.BeginInvoke()
        $script:startupTicks = 0
        $script:startupTimer.Start()
    } catch {}
}


$form.Add_Shown({ if ([bool](Get-AppSetting 'checkUpdates' $true)) { Start-StartupCheck } })

Update-Preview
[System.Windows.Forms.Application]::Run($form)
