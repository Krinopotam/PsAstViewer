using module ..\utils\add-types.psm1
using module .\main-form.psm1
using module ..\models\ast-model.psm1

class RunApp {
    RunApp([string]$version, [string]$Path) {
        if ($Path) {
            if (-not (Test-Path -LiteralPath $Path)) {
                Write-Host "File not found: $Path" -ForegroundColor Red
                exit 1
            }
            $path = Resolve-Path -LiteralPath $Path
        }
           
        $mainForm = [MainForm]::new($version)
        $mainForm.Show($path)
    }
}