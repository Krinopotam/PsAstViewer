function Get-EnvironmentVariable {
    $envPath = Join-Path ([Environment]::GetFolderPath('MyDocuments')) "Cridentials\psgallery.env"
    if (-not (Test-Path $envPath)) { Write-Host "Credentials file not found: $envPath" -ForegroundColor Red; return $null } 

    $env = @{}
    Get-Content $envPath | ForEach-Object {
        if ($_ -match "^\s*([^#].*?)\s*=\s*(.*)\s*$") {
            #[System.Environment]::SetEnvironmentVariable($matches[1], $matches[2])
            $env[$matches[1]] = $matches[2]
        }
    }

    return $env
}