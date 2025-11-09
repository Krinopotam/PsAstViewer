using module .\utils\add-types.psm1
using module .\ui\main-form.psm1
using module .\models\ast-model.psm1

Set-StrictMode -Version Latest

Class AstViewer {
    AstViewer([string]$Path) {
        if ($Path) {
            if (-not (Test-Path -LiteralPath $Path)) {
                Write-Host "File not found: $Path" -ForegroundColor Red
                exit 1
            }
            $path = Resolve-Path -LiteralPath $Path
        }
        
        $mainForm = [MainForm]::new()
        $mainForm.Show($path)
    }
}

function Show-AstViewer {
    [CmdletBinding()]
    param (
        [Parameter()]
        [string] $path = ""
    )

    [AstViewer]::new($path) | Out-Null
}


