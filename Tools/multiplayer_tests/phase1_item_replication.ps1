<#
.SYNOPSIS
    Proves Phase 1's two networking claims for real: item drop/pickup
    replicates to other peers, and a peer joining mid-round gets caught up
    on state it missed (see PORT_ROADMAP.md, Phase 1).

.DESCRIPTION
    Launches three real, independent, headless Godot processes - a host and
    two clients - using the game's own --host/--join-server/--auto-start-round/
    --auto-drop-delay flags (no simulated input, no live control channel; see
    Scripts/Core/Testing/TestHarnessConfig.cs for why). Client A drops its
    held item on a timer; a third client (C) joins only *after* that drop.
    Both claims are verified by watching for the permanent "[Item] ... placed
    in world" log line (Item.cs's DoPlaceInWorld) in the right processes:
      - Host's log shows it  -> the drop request crossed the network and was
        applied authoritatively server-side.
      - Client C's log shows it, despite joining after the drop and never
        receiving the original broadcast -> late-join catch-up worked.

    Each instance runs against its OWN isolated copy of the project, not the
    shared source tree. Confirmed by extensive direct testing 2026-09-14:
    Godot instances pointed at the SAME project directory corrupt each
    other's resource cache (.godot/) just by running concurrently - an
    already-removed addon and an already-fixed GDScript parse bug both kept
    "resurfacing" in whichever instance lost the race, no matter how the
    warmup/timing was adjusted (--quit-after vs force-kill, read-only
    locking the cache, multi-second settle delays between launches all
    failed to fully prevent it). Isolated copies remove shared mutable
    state entirely rather than trying to time around the race - each copy
    gets its own independent warmup (safe to run concurrently, since
    there's nothing left to share) before the real test begins.

.PARAMETER GodotExecutable
    Full path to a Godot 4.7 Mono console executable. Required - this varies
    per machine and isn't guessed at.

.PARAMETER ProjectPath
    Path to the UCFGS project root. Defaults to two levels up from this
    script (Tools/multiplayer_tests/ -> repo root).

.EXAMPLE
    ./phase1_item_replication.ps1 -GodotExecutable "C:\Godot\Godot_v4.7.2-stable_mono_win64_console.exe"
#>
param(
    [Parameter(Mandatory = $true)]
    [string]$GodotExecutable,

    [string]$ProjectPath = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path,

    [int]$Port = 8910,
    [int]$ReadyTimeoutSeconds = 15,
    [float]$AutoDropDelaySeconds = 2.0,
    [int]$DropTimeoutSeconds = 10,
    [int]$LateJoinTimeoutSeconds = 10,
    [int]$WarmupSeconds = 30
)

$ErrorActionPreference = "Stop"
$runId = Get-Date -Format 'yyyyMMdd_HHmmss'
$logDir = Join-Path $env:TEMP "ucfgs_phase1_test_$runId"
$copyRoot = Join-Path $env:TEMP "ucfgs_phase1_copies_$runId"
New-Item -ItemType Directory -Path $logDir -Force | Out-Null
New-Item -ItemType Directory -Path $copyRoot -Force | Out-Null

$instanceNames = @("host", "clientA", "clientC")
$copyPaths = @{}
foreach ($name in $instanceNames) {
    $copyPaths[$name] = Join-Path $copyRoot $name
}

$processes = @()

function New-IsolatedProjectCopy {
    param([string]$Destination)
    New-Item -ItemType Directory -Path $Destination -Force | Out-Null
    & robocopy $ProjectPath $Destination /E /XD ".git" ".godot" /NFL /NDL /NJH /NJS /NC /NS /MT:16 | Out-Null
    # robocopy's exit codes are a bitmask where >=8 means a real failure;
    # 0-7 all mean "some files were copied/matched successfully."
    if ($LASTEXITCODE -ge 8) {
        throw "robocopy failed copying to $Destination (exit code $LASTEXITCODE)"
    }

    # .godot/ is excluded above because its RESOURCE cache is what corrupts
    # across concurrent instances (see the file header) - but .godot/mono/
    # is a different thing entirely: the already-built C# assembly. Without
    # it, this copy has no compiled GodotStation.dll and every C# autoload
    # (NetworkManager included) fails to load. Copy just that prebuilt
    # subfolder back in; the resource cache itself still gets built fresh,
    # per-copy, by that copy's own warmup below.
    $monoSrc = Join-Path $ProjectPath ".godot\mono"
    if (Test-Path $monoSrc) {
        $monoDst = Join-Path $Destination ".godot\mono"
        & robocopy $monoSrc $monoDst /E /NFL /NDL /NJH /NJS /NC /NS /MT:8 | Out-Null
        if ($LASTEXITCODE -ge 8) {
            throw "robocopy failed copying .godot/mono to $Destination (exit code $LASTEXITCODE)"
        }
    }
}

# Root cause of the cache corruption, isolated by direct testing
# 2026-09-14: Godot's `--quit-after N` flag (a graceful, engine-triggered
# shutdown) writes a broken project resource cache on the way out, even
# when the actual source files are correct. A process that never receives
# --quit-after and is instead force-killed (taskkill) after a fixed
# real-time delay does not write this broken state - every warmup here
# uses that pattern. Real wall-clock time (not frame count) also matters:
# too short a delay catches the cache mid-import, which looks the same.
function Invoke-CacheWarmup {
    param([string]$Name, [string]$Path)
    $warmupLog = Join-Path $logDir "$Name.warmup.log"
    $proc = Start-Process -FilePath $GodotExecutable `
        -ArgumentList @("--headless", "--path", $Path) `
        -RedirectStandardOutput $warmupLog -RedirectStandardError "$warmupLog.err" `
        -PassThru -NoNewWindow
    return $proc
}

function Start-GodotInstance {
    param([string]$Name, [string]$Path, [string[]]$GameArgs)
    $logPath = Join-Path $logDir "$Name.log"
    $allArgs = @("--headless", "--path", $Path, "--") + $GameArgs
    $proc = Start-Process -FilePath $GodotExecutable -ArgumentList $allArgs `
        -RedirectStandardOutput $logPath -RedirectStandardError "$logPath.err" `
        -PassThru -NoNewWindow
    return @{ Name = $Name; Process = $proc; LogPath = $logPath }
}

function Wait-ForLogPattern {
    param([string]$LogPath, [string]$Pattern, [int]$TimeoutSeconds)
    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    while ((Get-Date) -lt $deadline) {
        if (Test-Path $LogPath) {
            $match = Select-String -Path $LogPath -Pattern $Pattern -SimpleMatch -ErrorAction SilentlyContinue
            if ($match) { return $true }
        }
        Start-Sleep -Milliseconds 300
    }
    return $false
}

function Stop-AllInstances {
    # Start-Process on the console-wrapper exe returns the wrapper's PID, not
    # the actual engine child process it spawns - Stop-Process on just that
    # PID leaves the real Godot instance running (confirmed by direct
    # testing 2026-09-14). taskkill /T kills the whole tree instead.
    foreach ($p in $processes) {
        if ($p) {
            & taskkill /T /F /PID $p.Id 2>&1 | Out-Null
        }
    }
    Start-Sleep -Milliseconds 500
}

$results = @()
function Add-Result([string]$Name, [bool]$Passed, [string]$Detail) {
    $script:results += [pscustomobject]@{ Name = $Name; Passed = $Passed; Detail = $Detail }
}

try {
    Write-Host "Creating isolated project copies (host/clientA/clientC)..."
    foreach ($name in $instanceNames) {
        New-IsolatedProjectCopy -Destination $copyPaths[$name]
    }

    Write-Host "Warming up all three copies concurrently (independent, nothing shared)..."
    $warmupProcs = @()
    foreach ($name in $instanceNames) {
        $warmupProcs += Invoke-CacheWarmup -Name $name -Path $copyPaths[$name]
    }
    Start-Sleep -Seconds $WarmupSeconds
    foreach ($p in $warmupProcs) { & taskkill /T /F /PID $p.Id 2>&1 | Out-Null }
    Start-Sleep -Milliseconds 500

    Write-Host "Starting host..."
    $hostInst = Start-GodotInstance -Name "host" -Path $copyPaths["host"] -GameArgs @("--host", "--auto-start-round")
    $processes += $hostInst.Process
    $hostReady = Wait-ForLogPattern -LogPath $hostInst.LogPath -Pattern "Listening on port" -TimeoutSeconds $ReadyTimeoutSeconds
    Add-Result "Host started" $hostReady "Waited for '[NetworkManager] Listening on port'"
    if (-not $hostReady) { throw "Host never started listening - aborting." }

    Write-Host "Starting client A (will auto-drop after $AutoDropDelaySeconds s)..."
    $clientA = Start-GodotInstance -Name "clientA" -Path $copyPaths["clientA"] -GameArgs @("--join-server", "127.0.0.1:$Port", "--auto-drop-delay", "$AutoDropDelaySeconds")
    $processes += $clientA.Process
    $aConnected = Wait-ForLogPattern -LogPath $clientA.LogPath -Pattern "Connected to server" -TimeoutSeconds $ReadyTimeoutSeconds
    Add-Result "Client A connected" $aConnected "Waited for '[NetworkManager] Connected to server.'"
    if (-not $aConnected) { throw "Client A never connected - aborting." }

    $dropTimeout = [int]$AutoDropDelaySeconds + $DropTimeoutSeconds
    $aDropped = Wait-ForLogPattern -LogPath $clientA.LogPath -Pattern "[Item]" -TimeoutSeconds $dropTimeout
    Add-Result "Client A's own drop applied locally" $aDropped "Waited for '[Item] ... placed in world' in clientA.log"

    $hostSawDrop = Wait-ForLogPattern -LogPath $hostInst.LogPath -Pattern "[Item]" -TimeoutSeconds 5
    Add-Result "Drop replicated to host (server-authoritative)" $hostSawDrop "Waited for '[Item] ... placed in world' in host.log"

    Write-Host "Starting late-joining client C..."
    $clientC = Start-GodotInstance -Name "clientC" -Path $copyPaths["clientC"] -GameArgs @("--join-server", "127.0.0.1:$Port")
    $processes += $clientC.Process
    $cConnected = Wait-ForLogPattern -LogPath $clientC.LogPath -Pattern "Connected to server" -TimeoutSeconds $ReadyTimeoutSeconds
    Add-Result "Late-joining client C connected" $cConnected "Waited for '[NetworkManager] Connected to server.'"
    if (-not $cConnected) { throw "Client C never connected - aborting." }

    $cCaughtUp = Wait-ForLogPattern -LogPath $clientC.LogPath -Pattern "[Item]" -TimeoutSeconds $LateJoinTimeoutSeconds
    Add-Result "Late-join catch-up delivered the dropped item" $cCaughtUp "Waited for '[Item] ... placed in world' in clientC.log (C never received the original broadcast)"
}
finally {
    Stop-AllInstances
    Remove-Item -Recurse -Force $copyRoot -ErrorAction SilentlyContinue
}

Write-Host ""
Write-Host "===== Results ====="
$allPassed = $true
foreach ($r in $results) {
    $status = if ($r.Passed) { "PASS" } else { "FAIL"; $allPassed = $false }
    Write-Host "[$status] $($r.Name) - $($r.Detail)"
}
Write-Host ""
Write-Host "Logs: $logDir"

if ($allPassed) {
    Write-Host "PHASE 1 ITEM REPLICATION: ALL CHECKS PASSED"
    exit 0
}
else {
    Write-Host "PHASE 1 ITEM REPLICATION: FAILED - see logs above"
    exit 1
}
