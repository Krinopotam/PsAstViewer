. "$PSScriptRoot\tools\Get-EnvironmentVariable.ps1"
. "$PSScriptRoot\tools\Copy-ForPublish.ps1"

$env = Get-EnvironmentVariable

if (-not $env -or -not $env.ContainsKey("PSGALLERY_API_KEY") -or -not  $env["PSGALLERY_API_KEY"]) { Write-Host "NuGetApiKey not found in credentials file: $envPath" -ForegroundColor Red; exit 1 } 
$nuGetApiKey = $env["PSGALLERY_API_KEY"]


if (-not (Get-PSResourceRepository -Name PSGallery -ErrorAction SilentlyContinue)) {
    Write-Host "PSGallery not registered — adding it..." -ForegroundColor Yellow
    Register-PSResourceRepository -PSGallery
}


$modulePath = Resolve-Path ".\"
$publishPath = Join-Path $modulePath 'publish'

$include = @(
    'PsAstViewer.psd1',
    'PsAstViewer.psm1',
    'models',
    'ui',
    'utils',
    'LICENSE',
    'README.md'
)

Copy-ForPublish -SourcePath $modulePath -PublishPath $publishPath -Include $include

Publish-PSResource -Path $publishPath -ApiKey $nuGetApiKey -Repository PSGallery -Verbose
