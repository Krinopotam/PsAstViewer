function Copy-ForPublish {
    param (
        [Parameter(Mandatory)]
        [string]$SourcePath,

        [Parameter(Mandatory)]
        [string]$PublishPath,

        [Parameter(Mandatory)]
        [string[]]$Include
    )

    if (-not (Test-Path $SourcePath)) { throw "Source path '$SourcePath' not found." }

    if (Test-Path $PublishPath) { Remove-Item $PublishPath -Recurse -Force -ErrorAction SilentlyContinue }
    New-Item -ItemType Directory -Path $PublishPath | Out-Null

    foreach ($item in $Include) {
        $srcItem = Join-Path $SourcePath $item
        if (-not (Test-Path $srcItem)) { Write-Warning "Skipping missing item: $srcItem"; continue }

        # Calculate target path
        $clearItemPath = $item.Replace("..\", "")
        $destItem = Join-Path $PublishPath $clearItemPath
        $destDir = Split-Path $destItem -Parent

        # Ensure parent directories exist
        if (-not (Test-Path $destDir)) { New-Item -ItemType Directory -Path $destDir -Force | Out-Null }

        # Copy preserving structure
        Copy-Item -Path $srcItem -Destination $destItem -Recurse -Force
        Write-Host "Copied: $item"
    }

    Write-Host "✅ Publish folder ready at: $PublishPath" -ForegroundColor Green
}