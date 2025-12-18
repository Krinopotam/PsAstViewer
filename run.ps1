###################################### PsAstViewer #######################################
#Author: Zaytsev Maksim
#Version: 1.0.13
#requires -Version 5.1
##########################################################################################

[CmdletBinding()]
param([string]$path = "")

Remove-Module PsAstViewer -ErrorAction SilentlyContinue

Import-Module ".\PsAstViewer.psm1" -Force
Show-AstViewer -path $path
#Show-AstViewer -Path ".\dev\example.ps1"
