Remove-Module PsAstViewer -ErrorAction SilentlyContinue

Import-Module ".\PsAstViewer.psd1" -Force
Show-AstViewer -Path ".\dev\example.ps1"