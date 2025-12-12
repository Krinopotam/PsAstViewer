using module .\ui\run-app.psm1

Set-StrictMode -Version Latest

function Show-AstViewer {
    <#
.SYNOPSIS
Opens the graphical AST (Abstract Syntax Tree) viewer for a specified PowerShell script.

.DESCRIPTION
Launches the PsAstViewer module and displays a visual representation of the PowerShell
Abstract Syntax Tree for the provided script file. If no path is specified, the viewer
opens without a preloaded file.

.PARAMETER Path
The path to a PowerShell script (*.ps1) whose AST should be displayed.
If omitted, the viewer is launched without loading a file.

.EXAMPLE
PS> Show-AstViewer -Path .\test.ps1
Opens the AST viewer and loads *test.ps1*.

.EXAMPLE
PS> Show-AstViewer
Starts the AST viewer without loading a file.

.NOTES
Author: Maxim Zaytsev  
#>

    [CmdletBinding()]
    param (
        [Parameter()]
        [string] $path = ""
    )

    $version = $MyInvocation.MyCommand.Module.Version
    $null = [RunApp]::new($version, $path)
}


