@{
    RootModule        = 'PsAstViewer.psm1'
    ModuleVersion     = '1.0.11'
    GUID              = '5b9fda12-0d29-4d99-9c47-008d2e857296'
    Author            = 'Maxim Zaytsev'
    Copyright         = '(c) 2025 Maxim Zaytsev. All rights reserved.'
    Description       = 'A graphical viewer and explorer for PowerShell Abstract Syntax Trees (AST)'
    PowerShellVersion = '5.1'
    FunctionsToExport = @('Show-AstViewer')
    CmdletsToExport   = @()
    VariablesToExport = @()
    AliasesToExport   = @()

    # All modules list of the module
    # ModuleList = @()

    # All files list of the module
    # FileList = @()

    PrivateData       = @{
        PSData = @{
            Tags       = @('PowerShell', 'AST', 'Syntax', 'Viewer', 'Explorer', 'GUI', 'Tool')
            LicenseUri = 'https://github.com/Krinopotam/PsAstViewer/blob/master/LICENSE'
            ProjectUri = 'https://github.com/Krinopotam/PsAstViewer'
            IconUri = 'https://raw.githubusercontent.com/Krinopotam/PsAstViewer/main/icons/PsAstViewer_128.png'
            # ReleaseNotes = ''
        }

    } 

    # Help Info URI of this module
    # HelpInfoURI = ''
}

