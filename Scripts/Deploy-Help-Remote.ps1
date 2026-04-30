# Deploy-Help-Remote.ps1
# Wrapper invoked remotely by LabUpdateAgent on already-deployed laptops with
# internet. Pulled from a GitHub Release asset (declared in the `scripts`
# array of update-manifest.json) and executed with elevated rights via the
# agent's standard `& $scriptPath` invocation.
#
# Why a separate wrapper instead of running Deploy-Help.ps1 directly:
#   - The agent fetches a single .ps1 file by URL into its staging dir; it
#     does not clone the repo. Deploy-Help.ps1 lives in Scripts\ in the
#     repo and depends on no other repo files (it fetches HTML straight
#     from raw.githubusercontent.com). So we ship a tiny wrapper that
#     in-line-includes the full Deploy-Help.ps1 logic by `Invoke-Expression`
#     OR by re-fetching it. Re-fetching is cleaner and lets us version-pin.
#
# This wrapper:
#   1. Fetches the latest Scripts\Deploy-Help.ps1 from raw.githubusercontent.com
#      to the agent's staging dir.
#   2. Dot-sources it with -FromGitHub so it pulls the HTML from raw GitHub.
#   3. Cleans up the temp file.
#
# Idempotent. Re-running just refreshes the files. Each manifest version bump
# triggers one execution; the SHA256 in the manifest pins this wrapper, so the
# agent only runs it when the wrapper actually changed - but the wrapper
# always pulls the LATEST Deploy-Help.ps1 + LATEST manifest + LATEST HTML, so
# every run sees the freshest content.

[CmdletBinding()]
param(
    [string]$RepoRawBase = 'https://raw.githubusercontent.com/andrewle8/vietnam-assistive-tech-lab/main'
)

$ErrorActionPreference = 'Stop'

$tempScript = Join-Path $env:TEMP 'Deploy-Help-pulled.ps1'

try {
    Write-Host "Deploy-Help-Remote: fetching Deploy-Help.ps1 from $RepoRawBase..."
    Invoke-WebRequest -Uri "$RepoRawBase/Scripts/Deploy-Help.ps1" -OutFile $tempScript -UseBasicParsing
    Write-Host "Deploy-Help-Remote: running Deploy-Help.ps1 -FromGitHub..."
    & $tempScript -FromGitHub -GitHubRawBase $RepoRawBase
    $deployExit = $LASTEXITCODE
} catch {
    Write-Host "Deploy-Help-Remote: FAILED - $_" -ForegroundColor Red
    $deployExit = 1
} finally {
    Remove-Item -Path $tempScript -Force -ErrorAction SilentlyContinue
}

exit $deployExit
