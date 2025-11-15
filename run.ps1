Remove-Module PsAstViewer -ErrorAction SilentlyContinue

Import-Module ".\PsAstViewer.psd1" -Force
#Show-AstViewer -Path ".\dev\example.ps1"
Show-AstViewer -Path "C:\Projects\powershell\PsBundler\build\psbundler-2.0.4.ps1"
#Show-AstViewer