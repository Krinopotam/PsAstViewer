###################################### PSBundler #########################################
#Author: Zaytsev Maksim
#Version: 2.1.6
#requires -Version 5.1
##########################################################################################

using namespace System.Management.Automation.Language

[CmdletBinding()]
param([string]$configPath = "")

Class PsBundler { 
    [object]$_config

    PsBundler ([string]$configPath) {
        $this.Start($configPath)
    }

    [void]Start ([string]$configPath) {
        try {
            Write-Host "Start building..."

            $this._config = [BundlerConfig]::new($configPath)

            if (-not $this._config.entryPoints) { Throw "HANDLED: No entry points found in config" }

            foreach ($entryPoint in $this._config.entryPoints.Keys) {
                $bundleName = $this._config.entryPoints[$entryPoint]
                Write-Host "    Starting bundle: $entryPoint => $bundleName"
                $scriptBundler = [ScriptBundler]::new($entryPoint, $bundleName, $this._config)
                $resultPath = $scriptBundler.Start()
                if (-not $resultPath) { Throw "HANDLED: Build failed" }

                if ($this._config.obfuscate) {
                    $psObfuscator = [PsObfuscator]::new($resultPath, $null, @(), @(), $this._config.obfuscate)
                    $psObfuscator.Start()
                }

                Write-Host "    Bundle saved at: $resultPath"
            }

            Write-Host "Build completed at: $($this._config.outDir)"
        }
        catch {
            if ($_.Exception.Message -like "HANDLED:*") { Write-Host ($_.Exception.Message -replace "^HANDLED:\s*", "") -ForegroundColor Red }
            else { Write-Error -ErrorRecord $_ }
        }
    }
}

Class ScriptBundler {
    [string]$_entryPath
    [string]$_bundleName
    [BundlerConfig]$_config

    ScriptBundler ([string]$entryPath, [string]$bundleName, [BundlerConfig]$config) {
        $this._entryPath = $entryPath
        $this._bundleName = $bundleName
        $this._config = $config
    }

    [string]Start () {
        if (-not (Test-Path $this._entryPath)) { Throw "HANDLED: Entry point not found: $($this._entryPath)" }

        $importsMapper = [ImportsMapper]::new($this._config)
        $importsMap = $importsMapper.GetImportsMap($this._entryPath)
        if (-not $importsMap) { Throw "HANDLED: Can't build bundle: no modules map created" }

        $entryFile = $importsMapper.GetEntryFile($importsMap)
        if (-not $entryFile) { Throw "HANDLED: Entry file is not found in imports map" }

        $replacer = [Replacer]::new($this._config)
        $replacementsInfo = $replacer.GetReplacements($importsMap)

        $bundleBuilder = [BundleBuilder]::new($this._config)
        $outputPath = $bundleBuilder.Build($importsMap, $replacementsInfo, $this._bundleName)
        return $outputPath
    }
}

class BundlerConfig {    
    [string]$configPath    
    [string]$projectRoot = ".\"    
    [string]$outDir = "build"    
    [hashtable]$entryPoints = @{}    
    [bool]$stripComments = $true    
    [bool]$keepHeaderComments = $true    
    [string]$obfuscate = ""    
    [bool]$deferClassesCompilation = $false    
    [bool]$embedClassesAsBase64 = $false
    
    [string]$modulesSourceMapVarName 

    [ObjectHelpers]$_objectHelpers
    [PathHelpers]$_pathHelpers

    BundlerConfig ([string]$configPath = "") {
        $this._objectHelpers = [ObjectHelpers]::New()
        $this._pathHelpers = [PathHelpers]::New()
        
        if ($configPath) {
            $this.configPath = $this._pathHelpers.GetFullPath($configPath)
        }
        
        if (-not $this.configPath) { 
            $scriptLaunchPath = Get-Location 
            $this.configPath = [System.IO.Path]::Combine($scriptLaunchPath, 'psbundler.config.json')
        }
        
        $this.Load()
        $this.modulesSourceMapVarName = "__MODULES_" + [Guid]::NewGuid().ToString("N")
    }

    [void]Load() {        
        $config = @{
            projectRoot             = ".\"          
            outDir                  = "build"       
            entryPoints             = @{}           
            stripComments           = $true         
            keepHeaderComments      = $true         
            obfuscate               = ""            
            deferClassesCompilation = $false   
            embedClassesAsBase64    = $false      
        }

        $userConfig = $this.GetConfigFromFile()

        foreach ($key in $userConfig.Keys) { $config[$key] = $userConfig[$key] }
        
        $configDir = [System.IO.Path]::GetDirectoryName($this.configPath)
        $root = $this._pathHelpers.GetFullPath($config.projectRoot, $configDir)
        $this.projectRoot = $root
            
        if (-not $config.outDir) { $config.outDir = "" }
        $this.outDir = $this._pathHelpers.GetFullPath($config.outDir, $root)
        
        if (-not $userConfig.entryPoints -or $userConfig.entryPoints.Count -eq 0) { throw "No entry points found in config" }

        $this.entryPoints = @{}
        foreach ($entryPath in $config.entryPoints.Keys) {
            $bundleName = $config.entryPoints[$entryPath]
            if (-not ($this._pathHelpers.IsValidPath($bundleName))) { throw "Invalid bundle name: $bundleName" }
            $entryAbsPath = $this._pathHelpers.GetFullPath($entryPath, $root)
            if (-not $entryAbsPath) { throw "Invalid entry path: $entryPath" }
            $this.entryPoints[$entryAbsPath] = $bundleName
        }

        $this.stripComments = $config.stripComments
        $this.keepHeaderComments = $config.keepHeaderComments
        $this.obfuscate = ""
        if ($config.obfuscate) {
            if ($config.obfuscate -eq "Natural") { $this.obfuscate = $config.obfuscate } 
            else { $this.obfuscate = "Hard" }
        }

        $this.deferClassesCompilation = $config.deferClassesCompilation
        $this.embedClassesAsBase64 = $config.embedClassesAsBase64
    }

    [PSCustomObject]GetConfigFromFile () {
        if (-not (Test-Path $this.configPath)) { 
            throw "HANDLED: Config file not found: $($this.configPath)"
        }
        
        try {
            $config = Get-Content $this.configPath -Raw | ConvertFrom-Json
            $configHashTable = $this._objectHelpers.ConvertToHashtable($config)
            Write-Host "Using config: $($this.configPath)"
            return $configHashTable
        }
        catch {
            throw "HANDLED: Error reading config file: $($_.Exception.Message)"
        }
    }
}

class ObjectHelpers {
    
    [object]ConvertToHashtable([object]$inputObject) {
        if ($null -eq $inputObject) { return $null }
        
        if ($inputObject -is [System.Collections.IDictionary]) {
            $output = @{}
            foreach ($key in $inputObject.Keys) {
                $output[$key] = $this.ConvertToHashtable($inputObject[$key])
            }
            return $output
        }
        
        if ($inputObject -is [System.Collections.IEnumerable] -and -not ($inputObject -is [string])) { return $inputObject }
        
        if ($inputObject -is [psobject]) {
            $output = @{}
            foreach ($property in $inputObject.PSObject.Properties) {
                if ($property.IsGettable) {
                    try {
                        $output[$property.Name] = $this.ConvertToHashtable($property.Value)
                    }
                    catch {
                        $output[$property.Name] = $null
                    }
                }
            }
            return $output
        }
        
        return $inputObject
    }
}

class PathHelpers {    
    [bool]IsValidPath([string]$path) {
        try {
            [System.IO.Path]::GetFullPath($path)
            return $true
        }
        catch {
            return $false
        }
    }
    
    [string]GetFullPath([string]$path) {
        try {
            return [System.IO.Path]::GetFullPath($path)
        }
        catch {
            return ""
        }
    }
    
    [string]GetFullPath([string]$path, [string]$basePath) {
        try {
            if ([System.IO.Path]::IsPathRooted($path)) {
                return [System.IO.Path]::GetFullPath($path)
            }

            $combined = [System.IO.Path]::Combine($basePath, $path)
            return [System.IO.Path]::GetFullPath($combined)
        }
        catch {
            return ""
        }
    }
}

Class ImportsMapper {
    [BundlerConfig]$_config
    [ImportParser]$_importParser

    ImportsMapper ([BundlerConfig]$config) {
        $this._config = $config
        $this._importParser = [ImportParser]::new($config)
    }

    [System.Collections.Specialized.OrderedDictionary]GetImportsMap ([string]$entryPath) {
        $importMap = $this.GenerateMap($entryPath, $true, $null, [ordered]@{})
        $cyclesDetector = [CyclesDetector]::new()
        $hasCycles = $cyclesDetector.Check($importMap)
        if ($hasCycles) { return  $null }
        return $importMap
    }

    [System.Collections.Specialized.OrderedDictionary]GenerateMap (       
        [string]$filePath,
        [bool]$isEntry,
        [hashtable]$consumerInfo,
        [System.Collections.Specialized.OrderedDictionary]$importMap) {

        if ($importMap.Contains($filePath)) {
            $file = $importMap[$filePath]
            $file.LinkToConsumer($consumerInfo)
            return $importMap
        }

        $file = [FileInfo]::new($filePath, $this._config, $isEntry, $consumerInfo)
        $importMap[$file.path] = $file

        $importsInfo = $this._importParser.ParseFile($file)

        foreach ($importInfo in $importsInfo) {
            $consumerInfo = @{
                File      = $file
                PathAst   = $importInfo.PathAst
                ImportAst = $importInfo.ImportAst
                Type      = $importInfo.Type
            }
            $this.GenerateMap( $importInfo.Path, $false, $consumerInfo, $importMap)
        }
       
        return $importMap
    }
    
    [FileInfo]getEntryFile([System.Collections.Specialized.OrderedDictionary]$importsMap) {
        foreach ($file in $importsMap.Values) {
            if ($file.isEntry) { return $file }
        }
        return $null
    }
}

Class CyclesDetector {

    [boolean]Check([System.Collections.Specialized.OrderedDictionary]$importsMap) {
        foreach ($file in $importsMap.Values) {
            $result = $this.FindCycle($file, @{}, @{}, [System.Collections.Generic.List[string]]::new())
            if (-not $result) { continue }
            Write-Host "Circular import of the file '$($file.path)' found:" -ForegroundColor Red
            $this.ShowCycledValsPretty($result)
            return $true
        }

        return $false
    }


    [System.Collections.Generic.List[string]]FindCycle(
        [FileInfo]$file,
        [hashtable]$visited = @{},
        [hashtable]$stack = @{},
        [System.Collections.Generic.List[string]]$pathList = [System.Collections.Generic.List[string]]::new()
    ) {

        $path = $file.path
        
        if ($stack.ContainsKey($path)) {            
            $startIndex = $pathList.IndexOf($path)
            if ($startIndex -ge 0) {                
                return $pathList[$startIndex..($pathList.Count - 1)]
            }
        }
        
        if ($visited.ContainsKey($path)) { return $null }
        
        $stack[$path] = $true
        $pathList.Add($path)
        
        foreach ($importInfo in $file.imports.Values) {
            $importFile = $importInfo.file
            $result = $this.FindCycle( $importFile, $visited, $stack, $pathList)
            if ($result) { return $result }
        }
        
        $stack.Remove($path)
        $visited[$path] = $true
        [void]$pathList.RemoveAt($pathList.Count - 1)
        
        return $null
    }

    [void]ShowCycledValsPretty([array]$Cycles) {
        if (-not $Cycles) { return }

        $maxWidth = 0
        for ($i = 0; $i -lt $Cycles.Count; $i++) {
            $val = $Cycles[$i]
            $gap = "    " * $i
            $maxWidth = [Math]::Max($maxWidth, $gap.Length + 1 + $val.Length ) 
        }
    

        for ($i = 0; $i -lt $Cycles.Count ; $i++) {
            $val = $Cycles[$i]
            $gap = "    " * $i
            $lines1 = "└─>"
            $gap2Len = $maxWidth - $val.Length - $gap.Length
            $lines2 = " " + "$(" " * $gap2Len)│" 
            if ($i -eq 0) {
                $lines1 = "   " 
                $lines2 = "<" + "$("─" * $gap2Len)┐"
            }
            elseif ($i -eq $Cycles.Count - 1) {
                $lines2 = " " + "$("─" * $gap2Len)┘"
            }

            $text = "$gap$lines1 $val $lines2"
            Write-Host $text -ForegroundColor Red
        }
    }
}

Class FileInfo {    
    [BundlerConfig]$_config
    
    [string]$id    
    [string]$path    
    [hashtable]$consumers = @{}    
    [hashtable]$imports = @{}    
    [bool]$isEntry = $false    
    [Ast]$ast = $null    
    [System.Collections.ObjectModel.ReadOnlyCollection[System.Management.Automation.Language.Token]]$tokens = $null    
    [bool]$typesOnly

    FileInfo ([string]$filePath, [BundlerConfig]$config, [bool]$isEntry = $false, [hashtable]$consumerInfo = $null) {
        $this._config = $config

        $this.id = [Guid]::NewGuid().ToString("N")
        $this.path = $filePath
        $this.isEntry = $isEntry
        
        $fileContent = $this.GetFileContent($filePath, $consumerInfo)
        $this.ast = $fileContent.ast
        $this.tokens = $fileContent.tokens
        $this.typesOnly = $this.IsFileContainsTypesOnly()
        $this.LinkToConsumer($consumerInfo)
    }

    [hashtable]GetFileContent([string]$filePath, [hashtable]$consumerInfo = $null) {
        try {

            if (-not (Test-Path $filePath)) {
                $consumerStr = ""
                if ($consumerInfo) { $consumerStr = "imported by $($consumerInfo.file.path)" }
                Throw "File not found: $filePath $consumerStr"
            }

            $source = Get-Content $filePath -Raw 
            if ($this._config.stripComments) { $source = $this.stripComments($source) }

            $errors = $null
            $tokensVal = $null
            $astVal = [System.Management.Automation.Language.Parser]::ParseInput($source, [ref]$tokensVal, [ref]$errors)            
            $realErrors = $errors | Where-Object { $_.ErrorId -notin @('TypeNotFound') }

            if ($realErrors.Count -gt 0) {
                Write-Host "Found syntax errors in script '$filePath':" -ForegroundColor Red
                foreach ($err in $realErrors) {
                    $lineNum = $source.Substring(0, $err.Extent.StartOffset).Split("`n").Count
                    Write-Host ("[{0}] {1}" -f $lineNum, $err.Message) -ForegroundColor Yellow
                }
                throw "Syntax errors in script '$filePath'"
            }

            return @{
                tokens = $tokensVal
                ast    = $astVal
            }
        }
        catch {
            throw "HANDLED: Error parsing file: $($_.Exception.Message)"
        }
    }

    [string]stripComments([string]$source) {
        $errors = $null
        $tokensVal = $null
        [System.Management.Automation.Language.Parser]::ParseInput($source, [ref]$tokensVal, [ref]$errors)

        $replacements = [System.Collections.ArrayList]::new()
        $tokenKind = [System.Management.Automation.Language.TokenKind]

        $fileBegin = $true
        for ($i = 0; $i -lt $tokensVal.Count; $i++) {
            $token = $tokensVal[$i]
            if ( $this._config.keepHeaderComments -and $this.isEntry -and $fileBegin -and ($token.Kind -eq $tokenKind::Comment -or $token.Kind -eq $tokenKind::NewLine)) { continue }

            $fileBegin = $false

            if ($token.Kind -ne $tokenKind::Comment) { continue }

            $replacements.Add(@{start = $token.Extent.StartOffset; Length = $token.Extent.EndOffset - $token.Extent.StartOffset; value = "" })
   
            if (($i - 1) -gt 0 -and $tokensVal[$i - 1].Kind -eq $tokenKind::NewLine) {
                $replacements.Add(@{start = $tokensVal[$i - 1].Extent.StartOffset; Length = $tokensVal[$i - 1].Extent.EndOffset - $tokensVal[$i - 1].Extent.StartOffset; value = "" })
            }
        }
        
        $sorted = ([hashtable[]]$replacements) | Sort-Object { $_['Start'] } -Descending

        $sb = [System.Text.StringBuilder]::new($source)
        foreach ($r in $sorted) {
            $sb.Remove($r.Start, $r.Length)
        }
        return $sb.ToString()
    }

    [void]LinkToConsumer([hashtable]$consumerInfo) {
        if (-not $consumerInfo) { return }
        $this.consumers[$consumerInfo.file.path] = $consumerInfo

        $consumerInfo.file.imports[$this.path] = @{
            File      = $this
            PathAst   = $consumerInfo.pathAst
            ImportAst = $consumerInfo.importAst
            Type      = $consumerInfo.type
        }   
    }

    [bool]IsFileContainsTypesOnly() {
        $types = $this.Ast.FindAll( { $args[0] -is [TypeDefinitionAst] }, $false)
        if (-not $types) { return $false }

        $varsAndFunctions = $this.Ast.FindAll( {
                param($node)
                                
                $p = $node.Parent
                while ($null -ne $p) {
                    if ($p -is [TypeDefinitionAst]) { return $false }
                    $p = $p.Parent
                }

                return $node -is [AssignmentStatementAst] -or $node -is [FunctionDefinitionAst]
            }, $false)
        if ($varsAndFunctions) { return $false }

        return $true
    }
}

Class ImportParser {
    [BundlerConfig]$_config
    [AstHelpers]$_astHelper

    ImportParser ([BundlerConfig]$Config) {
        $this._config = $Config
        $this._astHelper = [AstHelpers]::new()
    }
    
    [hashtable[]]ParseFile([FileInfo]$file) {
        $result = @()
        $result += $this.ParseImportModule($file)
        $result += $this.ParseUsingModuleImports($file)
        $result += $this.ParseDotImports($file)
        $result += $this.ResolveAmpersandImports($file)
        return $result
    }
    
    [hashtable[]]ParseImportModule([FileInfo]$file) {
        $result = @()

        $commandAsts = $file.Ast.FindAll( { $args[0] -is [CommandAst] -and $args[0].CommandElements -and $args[0].CommandElements[0].Value -eq "Import-Module" }, $true)
        if (-not $commandAsts) { return $result }
        
        $type = "Module"
        foreach ($commandAst in $commandAsts) {
            $paths = $this.ParseImportModuleCommandAst($commandAst)
            foreach ($pathInfo in $paths) {
                $importPath = $this.ResolveImportPath($file, $type, $pathInfo.Path)
                if (-not $importPath) { continue }
                $result += @{
                    Path      = $importPath
                    PathAst   = $pathInfo.Ast
                    ImportAst = $commandAst
                    Type      = $type
                }
            }
        }
        
        return $result
    }
    
    [hashtable[]]ParseImportModuleCommandAst([CommandAst]$commandAst) {
        $parameters = $this._astHelper.GetCommandAstParamsAst($commandAst)
        if (-not $parameters) { return @() }

        for ($i = 0; $i -lt $parameters.Count; $i++) {
            $param = $parameters[$i]
            if (($i -eq 0 -and -not $param.name) -or $param.name -eq "Name") {                
                $paths = $this.ParseParameterValueAst($param.value)
                return $paths
            }
        }

        return @()
    }
    
    [hashtable[]]ParseParameterValueAst([ast]$parameter) {
        $result = @()
        $elements = @()
        if ($parameter -is [StringConstantExpressionAst] -or $parameter -is [ExpandableStringExpressionAst]) { $elements = @($parameter) }
        elseif ($parameter -is [ArrayLiteralAst] -and $parameter.Elements) { $elements = $parameter.Elements }
        else { return $result }

        foreach ($element in $elements) {
            if (($element -isnot [StringConstantExpressionAst] -and $element -isnot [ExpandableStringExpressionAst]) -or -not $this.IsStrIsPsFilePath($element.Value)) { continue }
            $result += @{
                Path = $element.Value
                Ast  = $element
            }
            
        }

        return $result
    }
    
    [bool]IsStrIsPsFilePath([string]$str) {
        return  $str.EndsWith(".ps1") -or $str.EndsWith(".psm1")
    }

    
    [hashtable[]]ParseUsingModuleImports([FileInfo]$file) {
        $result = @()
        $usingStatements = $file.Ast.UsingStatements

        if (-not $usingStatements) { return $result }
        $type = "Using"
        foreach ($usingStatement in $usingStatements) {
            if ($usingStatement.UsingStatementKind -ne "Module") { continue }
            
            $importPath = $this.ResolveImportPath($file, $type, $usingStatement.Name.Value) 
            if (-not $importPath) { continue }

            $result += @{
                Path      = $importPath
                PathAst   = $usingStatement.Name
                ImportAst = $usingStatement
                Type      = $type
            }
        }

        return $result
    }
    
    [hashtable[]]ParseInvocationImports([FileInfo]$file, [string]$type) {
        $result = @()
        $commandAsts = $null
        if ($type -eq "Dot") { $commandAsts = $file.Ast.FindAll( { $args[0] -is [CommandAst] -and $args[0].InvocationOperator -eq 'Dot' }, $true) }
        elseif ($type -eq "Ampersand") { $commandAsts = $file.Ast.FindAll( { $args[0] -is [CommandAst] -and $args[0].InvocationOperator -eq 'Ampersand' }, $true) }
        else { return $result }
        
        if (-not $commandAsts) { return $result }
        
        foreach ($commandAst in $commandAsts) {
            if (-not $commandAst.CommandElements `
                    -or ($commandAst.CommandElements[0] -isnot [StringConstantExpressionAst] -and $commandAst.CommandElements[0] -isnot [ExpandableStringExpressionAst]) `
                    -or -not $commandAst.CommandElements[0].Value) { continue }
            $importPath = $this.ResolveImportPath($file, $type, $commandAst.CommandElements[0].Value)
            if (-not $importPath) { continue }
            $result += @{
                Path      = $importPath
                PathAst   = $commandAst.CommandElements[0]
                ImportAst = $commandAst
                Type      = $type
            }
        }
        
        return $result
    }
    
    [hashtable[]]ParseDotImports([FileInfo]$file) {
        return $this.ParseInvocationImports($file, "Dot")
    }
    
    [string[]]ResolveAmpersandImports([FileInfo]$file) {
        return $this.ParseInvocationImports($file, "Ampersand")
    }

    [string] ResolveImportPath(
        [FileInfo]$caller,                             
        [string] $importType,                          
        [string] $importPath                           
    ) {
        if (-not $importPath) { return $null }

        $callerPath = $caller.path
        $projectRoot = $this._config.projectRoot

        $resolved = $importPath

        $callerDir = [System.IO.Path]::GetDirectoryName($callerPath)
        $pathVars = @{
            "PSScriptRoot" = $callerDir
            "PWD"          = $projectRoot         
            "HOME"         = [Environment]::GetFolderPath('UserProfile')
        }
        
        foreach ($key in $pathVars.Keys) {
            $value = $pathVars[$key]
            $resolved = $resolved -replace ("\$\{?$key\}?"), $value
        }
        
        if ($resolved -match '^(~)([\\/]|$)') { $resolved = $resolved -replace '^~', $pathVars['HOME'] }
        
        if ([System.IO.Path]::IsPathRooted($resolved)) { return [System.IO.Path]::GetFullPath($resolved) }
                        
        $baseDir = switch ($importType) {
            'using' { $callerDir }
            'dot' { $projectRoot }
            'ampersand' { $projectRoot }
            'module' { $projectRoot }
        }
        
        $combined = [System.IO.Path]::Combine($baseDir, $resolved)
        return [System.IO.Path]::GetFullPath($combined)
    }

    
    [string]ResolvePath_old([string]$ImportPath) {        
        $baseDir = Split-Path -Path $this.path -Parent
        
        $context = @{
            PSScriptRoot = $baseDir
            PWD          = (Get-Location).Path
            HOME         = [Environment]::GetFolderPath('UserProfile')
        }
        
        $resolved = $ImportPath
        foreach ($key in $context.Keys) {
            $resolved = $resolved -replace ("\$" + $key), [regex]::Escape($context[$key])
        }
        
        if (-not [System.IO.Path]::IsPathRooted($resolved)) {
            $resolved = Join-Path -Path $baseDir -ChildPath $resolved
        }
        
        $resolved = [System.IO.Path]::GetFullPath((Resolve-Path -LiteralPath $resolved -ErrorAction SilentlyContinue).Path)

        return $resolved
    }
}

Class AstHelpers {    
    [hashtable[]]GetCommandAstParamsAst([CommandAst]$commandAst) {
        $result = @()
        $elements = $commandAst.CommandElements
        
        if ($elements.Count -lt 2) { return $result } 
        
        for ($i = 1; $i -lt $elements.Count; $i++) {
            $el = $elements[$i]

            if ($el -isnot [CommandParameterAst]) {
                $result += @{
                    name  = ""
                    value = $el
                }
                continue
            }

            $parName = $el.ParameterName
            $parValue = $null
            if ($i + 1 -lt $elements.Count -and $elements[$i + 1] -isnot [CommandParameterAst]) {
                $parValue = $elements[$i + 1]
                $i++
            }

            $result += @{
                name  = $parName
                value = $parValue
            }
        }
        return $result
    }
    
    [System.Collections.Specialized.OrderedDictionary]GetNamedParametersMap([CommandAst]$commandAst) {
        $paramsList = $this.GetCommandAstParamsAst($commandAst)
        $result = [System.Collections.Specialized.OrderedDictionary]::new()
        foreach ($par in $paramsList) {
            if ($par.name) {
                $result[$par.name] = $par.value
            }
        }

        return $result
    }
    
    [string]ConvertParamsAstMapToString([System.Collections.Specialized.OrderedDictionary]$paramsMap) {
        $paramsStr = ""
        foreach ($key in $paramsMap.Keys) {
            $value = $paramsMap[$key]
            if ($value) { $paramsStr += " -$key " + $value.Extent.Text }
            else { $paramsStr += " -$key" }
        }
        return $paramsStr
    }
}

class Replacer {
    [BundlerConfig]$_config
    [AstHelpers]$_astHelper

    Replacer([BundlerConfig]$config) {
        $this._config = $config
        $this._astHelper = [AstHelpers]::new()
    }

    [hashtable]getReplacements([System.Collections.Specialized.OrderedDictionary]$importsMap) {
        $replacementsMap = @{}
        $namespaces = [System.Collections.Specialized.OrderedDictionary]::new()
        $assemblies = [System.Collections.Specialized.OrderedDictionary]::new()
        $addTypes = [System.Collections.Specialized.OrderedDictionary]::new()
        $classes = [System.Collections.Specialized.OrderedDictionary]::new()
        $headerComments = ""
        $paramBlock = ""

        foreach ($file in $importsMap.Values) {
            $replacements = [System.Collections.ArrayList]::new()
            $replacementsMap[$file.id] = $replacements

            if ($file.isEntry) { 
                $headerComments = $this.fillHeaderCommentsReplacements($file, $replacements) 
                $paramBlock = $this.fillRootParamsReplacements($file, $replacements)
            }
            
            $this.fillImportReplacements($file, $replacements)
            
            $this.fillAssembliesReplacements($file, $assemblies, $replacements)
            
            $this.fillNamespacesReplacements($file, $namespaces, $replacements)
            
            $this.fillAddTypesReplacements($file, $addTypes, $replacements)
            
            $this.fillClassesReplacements($file, $classes, $replacements)
        }

        return @{
            headerComments  = $headerComments
            assemblies      = $assemblies
            namespaces      = $namespaces
            paramBlock      = $paramBlock
            addTypes        = $addTypes
            classes         = $classes
            replacementsMap = $replacementsMap
        }
    }
    
    [void]fillImportReplacements([FileInfo]$file, [System.Collections.ArrayList]$replacements) {
        $processedImports = @{}

        foreach ($importInfo in $file.imports.Values) {
            $importFile = $importInfo.file
            $importId = $importFile.id
            $moduleName = [System.IO.Path]::GetFileNameWithoutExtension($importFile.Path)
            $value = ""
            $replacement = @{
                Start  = $importInfo.ImportAst.Extent.StartOffset
                Length = $importInfo.ImportAst.Extent.EndOffset - $importInfo.ImportAst.Extent.StartOffset                
                Value  = $value
            }

            $replacements.Add($replacement)
            
            if ($importFile.typesOnly) { continue }

            if ($importInfo.type -eq 'dot') {                
                $replacement.Value = '. $global:' + $this._config.modulesSourceMapVarName + '["' + $importId + '"]' 
            }
            elseif ($importInfo.type -eq 'ampersand') {                
                $replacement.Value = '& $global:' + $this._config.modulesSourceMapVarName + '["' + $importId + '"]' 
            }
            elseif ($importInfo.type -eq 'using') {                
                $replacement.Value = 'Import-Module (New-Module -Name ' + $moduleName + ' -ScriptBlock $global:' + $this._config.modulesSourceMapVarName + '["' + $importId + '"]) -DisableNameChecking' 
            }
            elseif ($importInfo.type -eq 'module') {                
                $importParams = $this._astHelper.GetNamedParametersMap($importInfo.ImportAst)
                $importParams["DisableNameChecking"] = $null
                $paramsStr = $this._astHelper.ConvertParamsAstMapToString($importParams)
                
                $value = 'Import-Module (New-Module -Name ' + $moduleName + ' -ScriptBlock $global:' + $this._config.modulesSourceMapVarName + '["' + $importId + '"])' + $paramsStr
                if ($processedImports.ContainsKey($importInfo.ImportAst)) {
                    $replacement = $processedImports[$importInfo.ImportAst]
                    $replacement.Value += [Environment]::NewLine + $value
                }
                else {
                    $replacement.Value = $value
                }
            } 
        }
    }
    
    [void]fillAssembliesReplacements([FileInfo]$file, [System.Collections.Specialized.OrderedDictionary]$assemblies, [System.Collections.ArrayList]$replacements) {
        $usingStatements = $file.Ast.FindAll( { $args[0] -is [UsingStatementAst] -and $args[0].UsingStatementKind -eq "Assembly" }, $false)
        foreach ($usingStatement in $usingStatements) {
            $assemblies[$usingStatement.Name.Extent.ToString()] = "using assembly $($usingStatement.Name.Extent.ToString())"
            $replacements.Add(@{start = $usingStatement.Extent.StartOffset; Length = $usingStatement.Extent.EndOffset - $usingStatement.Extent.StartOffset; value = "" })
        }
    }

    
    [void]fillNamespacesReplacements([FileInfo]$file, [System.Collections.Specialized.OrderedDictionary]$namespaces, [System.Collections.ArrayList]$replacements) {
        $usingStatements = $file.Ast.FindAll( { $args[0] -is [UsingStatementAst] -and $args[0].UsingStatementKind -eq "Namespace" }, $false)
        foreach ($usingStatement in $usingStatements) {
            $namespaces[$usingStatement.Name.Value] = "using namespace $($usingStatement.Name.Value)"
            $replacements.Add(@{start = $usingStatement.Extent.StartOffset; Length = $usingStatement.Extent.EndOffset - $usingStatement.Extent.StartOffset; value = "" })
        }
    }
    
    [void]fillAddTypesReplacements([FileInfo]$file, [System.Collections.Specialized.OrderedDictionary]$addTypes, [System.Collections.ArrayList]$replacements) {
        $usingStatements = $file.Ast.FindAll( { $args[0] -is [CommandAst] -and $args[0].GetCommandName() -eq "Add-Type" }, $false)
        foreach ($usingStatement in $usingStatements) {
            $text = $usingStatement.Extent.Text
            $addTypes[$text] = $text
            $replacements.Add(@{start = $usingStatement.Extent.StartOffset; Length = $usingStatement.Extent.EndOffset - $usingStatement.Extent.StartOffset; value = "" })
        }
    }
    
    [void]fillClassesReplacements([FileInfo]$file, [System.Collections.Specialized.OrderedDictionary]$classes, [System.Collections.ArrayList]$replacements) {
        $typeDefinitions = $file.Ast.FindAll( { $args[0] -is [TypeDefinitionAst] }, $false)
        foreach ($typeDefinition in $typeDefinitions) {
            if ($classes.Contains($typeDefinition.Name)) { Write-Host "        Duplicate class name: '$($typeDefinition.Name)' in file: $($file.path)" -ForegroundColor Orange }
            $classes[$typeDefinition.Name] = $typeDefinition.Extent.Text
            $replacements.Add(@{start = $typeDefinition.Extent.StartOffset; Length = $typeDefinition.Extent.EndOffset - $typeDefinition.Extent.StartOffset; value = "" })
        }
    }
    
    [string]fillHeaderCommentsReplacements([FileInfo]$file, [System.Collections.ArrayList]$replacements) {
        if (-not $file.isEntry -or -not $this._config.keepHeaderComments) { return "" }
        $tokenKind = [System.Management.Automation.Language.TokenKind]
        $header = ""
        $headerEnd = 0
        foreach ($token in $file.tokens) {
            if ($token.Kind -ne $tokenKind::Comment -and $token.Kind -ne $tokenKind::NewLine) { break }
            $headerEnd = $token.Extent.EndOffset
            $header += $token.Extent.Text
        }
        if ($header) {
            $replacements.Add(@{start = 0; Length = $headerEnd; value = "" })
            return $header.Trim()
        }

        return ""
    }
    
    [string]fillRootParamsReplacements([FileInfo]$file, [System.Collections.ArrayList]$replacements) {
        if (-not $file.isEntry -or -not $file.Ast.ParamBlock) { return "" }
        $fileAst = $file.Ast
        $source = $fileAst.Extent.Text

        $startOffset = $fileAst.ParamBlock.Extent.StartOffset
        $endOffset = $fileAst.ParamBlock.Extent.EndOffset

        if ($fileAst.ParamBlock.Attributes) { 
            $startOffset = $fileAst.ParamBlock.Attributes[0].Extent.StartOffset
        }

        $replacements.Add(@{start = $startOffset; Length = $endOffset - $startOffset; value = "" })
        return ($source.Substring($startOffset, $endOffset - $startOffset)).Trim()
    }
}

class BundleBuilder {
    [BundlerConfig]$_config

    BundleBuilder ([BundlerConfig]$config) {
        $this._config = $config
    }

    [string]build([hashtable]$importsMap, [hashtable]$replacementsInfo, [string]$bundleName) {
        try {
            $entryFile = $this.GetEntryFile($importsMap)
            $bundleName = $this.GetBundleName($bundleName, $entryFile)
            $outputPath = Join-Path $this._config.outDir $bundleName

            if ((Test-Path $outputPath)) { Remove-Item -Path $outputPath -Force }
            New-Item -ItemType Directory -Force -Path (Split-Path $outputPath) | Out-Null

            $headerContent = $this.getHeaders($replacementsInfo)
            $modulesContent = $this.getModulesContent($entryFile, $replacementsInfo)

            $this.addContentToFile($outputPath, $headerContent)
            $this.addContentToFile($outputPath, $modulesContent)
            return $outputPath
        }
        catch {
            throw "HANDLED: Error creating bundle: $($_.Exception.Message)"
        }
    }

    [string]getHeaders ([hashtable]$replacementsInfo) {
        $result = ""
        if ($replacementsInfo.headerComments) { $result += ( $replacementsInfo.headerComments + [Environment]::NewLine * 2) }

        $assemblies = $this.getNamespacesString($replacementsInfo.assemblies)
        if ($assemblies) { $result += ($assemblies + [Environment]::NewLine * 2) }

        $namespaces = $this.getNamespacesString($replacementsInfo.namespaces)
        if ($namespaces) { $result += ($namespaces + [Environment]::NewLine * 2) }

        if ($replacementsInfo.paramBlock) { $result += ($replacementsInfo.paramBlock + [Environment]::NewLine * 2) }

        $addTypes = $this.getAddTypesString($replacementsInfo.addTypes)
        if ($addTypes -and $result) { $result += ( $addTypes + [Environment]::NewLine * 2) }

        $classes = $this.getClassesString($replacementsInfo.classes)
        if ($classes) { $result += ($classes + [Environment]::NewLine * 2) }

        return $result
    }

    [string]getAssembliesString ([System.Collections.Specialized.OrderedDictionary]$assemblies) {
        return $assemblies.Values -join [Environment]::NewLine
    }

    [string]getNamespacesString ([System.Collections.Specialized.OrderedDictionary]$namespaces) {
        return $namespaces.Values -join [Environment]::NewLine
    }

    [string]getAddTypesString ([System.Collections.Specialized.OrderedDictionary]$addTypes) {
        return $addTypes.Values -join [Environment]::NewLine
    }

    [string]getClassesString ([System.Collections.Specialized.OrderedDictionary]$classes) {
        if ($classes.Count -eq 0) { return "" }
        $classesStr = $classes.Values -join ([Environment]::NewLine + [Environment]::NewLine)

        if (-not $this._config.deferClassesCompilation) { return $classesStr }

        $uuid = [Guid]::NewGuid().ToString("N")
                
        if (-not $this._config.embedClassesAsBase64) {
            return "`$__CLASSES_SOURCE_$uuid = @'" + [Environment]::NewLine `
                + $classesStr + [Environment]::NewLine `
                + "'@" + [Environment]::NewLine `
                + "Invoke-Expression `$__CLASSES_SOURCE_$uuid" + [Environment]::NewLine `
                + "`$__CLASSES_SOURCE_$uuid = `$null"
        }

        $bytes = [Text.Encoding]::UTF8.GetBytes($classesStr)
        $classesStr = [Convert]::ToBase64String($bytes)
        
        return "`$__CLASSES_B64_$uuid = '$classesStr'" + [Environment]::NewLine `
            + "`$__CLASSES_BYTES_$uuid = [System.Convert]::FromBase64String(`$__CLASSES_B64_$uuid)" + [Environment]::NewLine `
            + "`$__CLASSES_SOURCE_$uuid = [System.Text.Encoding]::UTF8.GetString(`$__CLASSES_BYTES_$uuid)" + [Environment]::NewLine `
            + "Invoke-Expression `$__CLASSES_SOURCE_$uuid" + [Environment]::NewLine `
            + "`$__CLASSES_BYTES_$uuid = `$null" + [Environment]::NewLine `
            + "`$__CLASSES_SOURCE_$uuid = `$null" + [Environment]::NewLine `
            + "`$__CLASSES_B64_$uuid = `$null"
    }

    [FileInfo]getEntryFile ([hashtable]$importsMap) {
        foreach ($file in $importsMap.Values) {
            if ($file.isEntry) { return $file }
        }
        
        throw "Entry file is not found in imports map"
    }

    [hashtable[]]normalizeReplacements([hashtable[]] $replacements) {        
        [hashtable[]]$sorted = $replacements | Sort-Object { $_['Start'] }
        $normalized = @()
        if ($sorted.Count -eq 0) { return $normalized }

        $current = $sorted[0]

        for ($i = 1; $i -lt $sorted.Count; $i++) {
            $r = $sorted[$i]

            $currStart = [int]$current.Start
            $currEnd = $currStart + [int]$current.Length
            $rStart = [int]$r.Start
            $rEnd = $rStart + [int]$r.Length

            if ($rStart -lt $currEnd) {                
                $newStart = [Math]::Min($currStart, $rStart)
                $newEnd = [Math]::Max($currEnd, $rEnd)
                $newLength = $newEnd - $newStart
                $current = @{
                    Start       = $newStart
                    Length      = $newLength
                    Replacement = "$($current.Replacement)$($r.Replacement)"
                }
            }
            else {                
                $normalized += $current
                $current = $r
            }
        }
        
        $normalized += $current

        [hashtable[]]$sortedNormalized = $normalized | Sort-Object { $_['Start'] } -Descending
        return $sortedNormalized
    }

    [string]PrepareSource ([FileInfo]$file, [System.Collections.ArrayList]$replacements) {
        $source = $file.ast.Extent.Text
        $sb = [System.Text.StringBuilder]::new($source)
        $replacements = $this.NormalizeReplacements($replacements)        
        foreach ($r in $replacements) {
            $sb.Remove($r.Start, $r.Length)
            $sb.Insert($r.Start, $r.Value)
        }
        return $sb.ToString().Trim()
    }

    [string]getModulesContent([FileInfo]$entryFile, [hashtable]$replacementsInfo) {
        $contentList = [System.Collections.ArrayList]::new()
        $contentList.Add('$global:' + $this._config.modulesSourceMapVarName + ' = @{}' + [Environment]::NewLine)

        $this.fillModulesContentList($entryFile, $replacementsInfo, $contentList, "", @{})

        if ($contentList.Count -eq 1) { return "" }
        return $contentList -join [Environment]::NewLine * 2
    }

    [void]fillModulesContentList([FileInfo]$file, [hashtable]$replacementsInfo, [System.Collections.ArrayList]$contentList, [string]$importType, [hashtable]$processed = @{}) {
        if ($file.imports.Values.Count -gt 0) {
            foreach ($importInfo in $file.imports.Values) {
                $importFile = $importInfo.file
                if ($processed[$importFile.path]) { continue }
                $this.fillModulesContentList($importFile, $replacementsInfo, $contentList, $importInfo.Type, $processed)
            }
        }

        $processed[$file.path] = $true
                
        if ($file.typesOnly) { Write-Host "        File '$($file.path)' processed." -ForegroundColor Green; return }
        $source = $this.PrepareSource($file, $replacementsInfo.replacementsMap[$file.id])
        if (-not $source) { Write-Host "        File '$($file.path)' processed." -ForegroundColor Green; return }
        
        if (-not $file.isEntry) {
            $source = '$global:' + $this._config.modulesSourceMapVarName + '["' + $file.id + '"] = ' + $this.bracketWrap($source, "    ")
        }

        $contentList.Add($source)
        Write-Host "        File '$($file.path)' processed." -ForegroundColor Green
        return
    }
    
    [string]bracketWrap([string]$str, [string]$indent = "    ") {
        return "{" + [Environment]::NewLine + (($str -split "\r?\n" | ForEach-Object { "$indent$_" }) -join [Environment]::NewLine) + [Environment]::NewLine + "}"
    }

    [void]addContentToFile([string]$path, [string]$content) {
        Add-Content -Path $path -Value $content -Encoding UTF8 | Out-Null
    }   

    [string]GetBundleName ($bundleName, [FileInfo]$entryFile) { 
        $version = $this.ParseVersion($entryFile)
        if (-not $version) { return $bundleName }

        Write-Verbose "    Bundle version detected: $version"

        $name = [System.IO.Path]::GetFileNameWithoutExtension($bundleName)
        $ext = [System.IO.Path]::GetExtension($bundleName)

        return "$name-$version$ext"
    }

    [string]ParseVersion([FileInfo]$file) {
        $tokens = $file.tokens
        
        $versionRegex = '#\s*version[:]?\s*([0-9]+(?:\.[0-9]+){0,3})'

        $tokenKind = [System.Management.Automation.Language.TokenKind]
        foreach ($token in $tokens) {
            if ($token.Kind -ne $tokenKind::Comment -and $token.Kind -ne $tokenKind::NewLine) { break }

            if ($token.Extent.Text -match $versionRegex) { return $matches[1] }
        }

        return ""
    }
}

class PsObfuscator { 
    [hashtable]$config = @{}

    PsObfuscator ([string]$Path,
        [string]$OutPath,
        [string[]]$VarsExclude = @(),
        [string[]]$FuncsExclude = @(),        
        [string]$Mode = "Natural" 
    ) {
        $this.config = @{
            Path         = $Path
            OutPath      = $OutPath
            VarsExclude  = $VarsExclude
            FuncsExclude = $FuncsExclude
            Mode         = $Mode
        }
    }

    [void] Start() {
        Write-Host "Starting obfuscation for file: $($this.config.Path)" -ForegroundColor Green
        $astModel = [AstModel]::new($this.config.Path)

        $replacements = [System.Collections.ArrayList]::new()
        $varReplacer = [VarReplacer]::new($this.config, $astModel)
        Write-Host "    Variables obfuscation..." -ForegroundColor Green
        $varReplacements = $varReplacer.GetReplacements()
        if ($varReplacements) { $replacements.AddRange($varReplacements) }

        $funcReplacer = [FuncReplacer]::new($this.config, $astModel)
        Write-Host "    Functions obfuscation..." -ForegroundColor Green
        $funcReplacements = $funcReplacer.GetReplacements()
        if ($funcReplacements) { $replacements.AddRange($funcReplacements) }

        Write-Host "    Making replacements in script..." -ForegroundColor Green
        $obfuscatedScript = $this.MakeScriptReplacements($astModel.ast.Extent.Text, $replacements)
        Write-Host "    Replacements done. Total replacements: $($replacements.Count)" -ForegroundColor Green
        
        $outPath = $this.config.OutPath
        if (-not $outPath) {
            $base = [System.IO.Path]::GetDirectoryName((Resolve-Path -LiteralPath $this.config.Path).Path)
            $name = [System.IO.Path]::GetFileNameWithoutExtension($this.config.Path)
            $ext = [System.IO.Path]::GetExtension($this.config.Path)
            $outPath = Join-Path $base ("$name.obf$ext")
        }

        [System.IO.File]::WriteAllText($outPath, $obfuscatedScript, [System.Text.Encoding]::UTF8) 

        Write-Host "Obfuscated script saved to: $outPath" -ForegroundColor Green
    }

    [string]MakeScriptReplacements([string]$Script, [System.Collections.ArrayList]$Replacements) {
        if ($Replacements.Count -eq 0) {
            Write-Verbose "No replacements found."
            return ""
        }

        $sb = [System.Text.StringBuilder]::new($Script)
        $replacementsSorted = $Replacements | Sort-Object { $_['Start'] } -Descending
        foreach ($r in $replacementsSorted) {
            $sb.Remove($r.Start, $r.Length) | Out-Null
            $sb.Insert($r.Start, $r.Replacement) | Out-Null
        }
        return $sb.ToString()
    }
}

Class AstModel {
    [hashtable]$builtinVars
    [hashtable]$builtinFuncs
    [Ast]$ast
    [hashtable]$astMap

    AstModel([string]$Path) {
        $this.builtinVars = $this.GetBuiltinVariables()
        $this.builtinFuncs = $this.GetBuiltinFunctions()
        $this.ast = $this.FileToAst($Path)
        $this.astMap = $this.GetAstHierarchyMap($this.ast)
    }
    
    [Ast]FileToAst([string]$Path) {
        if (-not (Test-Path $Path)) { throw "File not found: $Path" }

        $script = Get-Content -Raw -LiteralPath $Path
        return $this.ScriptToAst($script)
    }

    [Ast]ScriptToAst([string]$script) {
        $errors = $null
        $scriptAst = [Parser]::ParseInput($script, [ref]$null, [ref]$errors)
        if ($errors) { throw "Parsing failed" }

        return $scriptAst
    }
                
    [System.Collections.Specialized.OrderedDictionary]GetAstHierarchyMap([Ast]$rootAst) {
        $map = [ordered]@{}

        $items = $rootAst.FindAll( { $true }, $true)
        foreach ($item in $items) {
            if (-not $item.Parent) { continue }
            $parent = $item.Parent
            if (-not $map.Contains($parent)) { $map[$parent] = [System.Collections.ArrayList]@() }
            [void]$map[$parent].Add($item)
        }

        return $map
    }
    
    [System.Collections.ArrayList]FindAstChildrenByType(        
        [System.Management.Automation.Language.Ast]$Ast,                         
        [Type]$ChildType = $null,        
        [string]$Select = "firstChildren",        
        [Type]$UntilType = $null

    ) {
        $result = [System.Collections.ArrayList]::new()

        function Recurse($current) {
            if (-not $this.astMap.Contains($current)) { return }
    
            foreach ($child in $this.astMap[$current]) {
                if ($UntilType -and $child -is $UntilType) { continue }
            
                if (-not $ChildType -or $child -is $ChildType) {
                    [void]$result.Add($child)
                    if ($Select -eq "firstChildren") { continue }
                }

                if ($Select -eq "directChildren") { continue }
                Recurse $child
            }
        }

        Recurse $Ast
        return $result
    }
    
    [VarInfo]GetAstVariableInfo(
        [VariableExpressionAst]$varExpressionAst,
        [ScriptBlockAst]$parentScriptBlockAst

    ) {

        if (-not ($varExpressionAst -is [VariableExpressionAst]) ) { throw "Expected VariableExpressionAst" }
        
        $root = -not $parentScriptBlockAst.Parent
    
        $params = $varExpressionAst.VariablePath

        if (-not $params.IsVariable -or $params.IsDriveQualified -or $this.BuiltinVars[$varExpressionAst.VariablePath.UserPath]) { return $null }

        $originalName = $params.UserPath 

        $scope = "local"
        $name = $originalName
        if (-not $params.IsUnscopedVariable ) {
            if ($params.IsGlobal) { $scope = "global" }
            elseif ($params.IsScript) { $scope = "script" }
            elseif ($params.IsPrivate) { $scope = "private" }

            $name = $originalName.Split(":", 2)[1]
        }
        elseif ($root) { $scope = 'script' }

        return [VarInfo]::new(
            $name, 
            "$($scope):$name", 
            $originalName, 
            $scope, 
            -not $params.IsUnscopedVariable, 
            $varExpressionAst.Splatted, 
            $varExpressionAst.Parent -is [ParameterAst], 
            $varExpressionAst, 
            $parentScriptBlockAst, 
            $false 
        )
    }

    [Ast]GetAstParentByType([Ast]$Ast, [Type]$Type) {
        $current = $Ast.Parent
        while ($current -and -not ($current -is $Type)) {
            $current = $current.Parent
        }

        return $current
    }

    [ScriptBlockAst]GetAstParentScriptBlock([Ast]$Ast) {
        return $this.GetAstParentByType($Ast, [ScriptBlockAst])
    }

    [ScriptBlockAst]GetAstRootScripBlock([Ast]$Ast) {
        if (-not $Ast) { return $null }
        if (-not $Ast.Parent) {
            if ($Ast -is [ScriptBlockAst]) { return $Ast }
            return $null
        }
        return $this.GetAstRootScripBlock($Ast.Parent)
    }

    [hashtable]GetBuiltinFunctions() {
        $runspace = [runspacefactory]::CreateRunspace()
        $runspace.Open()

        $ps = [powershell]::Create()
        $ps.Runspace = $runspace

        $funcs = $ps.AddScript('Get-Command -CommandType Function | Select-Object -ExpandProperty Name').Invoke()

        $ps.Dispose()
        $runspace.Close()
        $runspace.Dispose()

        $cleanFuncs = $funcs | ForEach-Object { $_ -replace '^[A-Z]:', '' }
        $ht = @{}
        foreach ($f in $cleanFuncs) { $ht[$f] = $true }

        return $ht
    }

    [hashtable]GetBuiltinVariables() {
        $runspace = [runspacefactory]::CreateRunspace()
        $runspace.Open()

        $ps = [powershell]::Create()
        $ps.Runspace = $runspace

        $vars = $ps.AddScript('Get-Variable | Select-Object -ExpandProperty Name').Invoke()

        $ps.Dispose()
        $runspace.Close()
        $runspace.Dispose()

        $ht = @{}
        foreach ($v in $vars) { $ht[$v] = $true }

        $ht['_'] = $true
        $ht['s'] = $true
        $ht['p'] = $true
        $ht['PSItem'] = $true
        $ht['sender'] = $true
        $ht['this'] = $true
        $ht['form'] = $true 
        $ht['PSCmdlet'] = $true
        $ht['LASTEXITCODE'] = $true
        $ht['Profile'] = $true
        $ht['matches'] = $true
        
        $ht['ExecutionContext'] = $false 
        return $ht
    }
}

Class VarInfo {    
    [string]$Name    
    [string]$FullName    
    [string]$OriginalName    
    [string]$Scope    
    [bool]$IsScoped    
    [bool]$IsSplatted    
    [Ast]$Ast    
    [ScriptBlockAst]$ScriptBlockAst    
    [bool]$IsParameter    
    [string]$ObfuscatedName=""    
    [bool]$IsString = $false

    VarInfo (
        [string]$Name,
        [string]$FullName,
        [string]$OriginalName,
        [string]$Scope,
        [bool]$IsScoped,
        [bool]$IsSplatted,
        [bool]$IsParameter,
        [Ast]$Ast,
        [ScriptBlockAst]$ScriptBlockAst,
        [bool]$IsString
    ) {
        $this.Name = $Name
        $this.FullName = $FullName
        $this.OriginalName = $OriginalName
        $this.Scope = $Scope
        $this.IsScoped = $IsScoped
        $this.IsSplatted = $IsSplatted
        $this.IsParameter = $IsParameter
        $this.Ast = $Ast
        $this.ScriptBlockAst = $ScriptBlockAst
        $this.ObfuscatedName = $OriginalName
        $this.IsString = $IsString
    }
}

Class VarReplacer {
    [hashtable]$config
    [AstModel]$astModel

    VarReplacer (
        [hashtable]$Config,
        [AstModel]$AstModel
    ) {
        $this.config = $Config
        $this.astModel = $AstModel
    }

    [System.Collections.ArrayList]GetReplacements() {
        $varsMapper = [VarsMapper]::new($this.config, $this.astModel)
        $varsMap = $varsMapper.GetMap()

        $replacements = [System.Collections.ArrayList]::new()
        Write-Host "        Generating variable replacements..." -ForegroundColor Green
        $this.FillVarReplacements($this.AstModel.ast, $varsMap, $replacements)
        Write-Host "        Variable replacements generated. Total replacements: $($replacements.Count)" -ForegroundColor Green
        return $replacements
    }

    [void]FillVarReplacements(
        [ScriptBlockAst]$SbAst,
        [hashtable]$VarsMap,
        [System.Collections.ArrayList]$Replacements
    ) {

        if (-not $SbAst -is [ScriptBlockAst]) { throw "Expected ScriptBlockAst" }
                
        $this.SetVarReplacementsForSb($VarsMap, $SbAst, $Replacements)

        [ScriptBlockAst[]]$childrenSb = $this.astModel.FindAstChildrenByType($SbAst, [ScriptBlockAst], "firstChildren", $null)
            
        foreach ($childSb in $childrenSb) {
            $this.FillVarReplacements($childSb, $VarsMap, $Replacements)
        }
    }
    
    SetVarReplacementsForSb(
        [hashtable]$VarsMap,
        [ScriptBlockAst]$SbAst,
        [System.Collections.ArrayList]$Replacements
    ) {
        

        $varsAst = $sbAst.FindAll({ 
                param($node)
                $node -is [VariableExpressionAst]
            }, $false)

        foreach ($varAst in $varsAst) {
            $varInfo = $this.astModel.GetAstVariableInfo($varAst, $SbAst)
            $specialVarInfo = $this.ProcessSpecialVars($varInfo, $SbAst)
            if ($specialVarInfo) { $varInfo = $specialVarInfo }
            if (-not $varInfo) { continue }            
        
            [VarInfo]$assignedVarInfo = $this.FindAssignedVarInfo($VarsMap, $varInfo, $SbAst)
            if (-not $assignedVarInfo) { 
                if (-not $varInfo.IsScoped -and -not $varInfo.IsParameter -and -not  $this.astModel.builtinVars.Contains($varInfo.OriginalName)) {
                    Write-Warning "The '$($varInfo.OriginalName)' is not defined. It may cause side effects. Line: $($varAst.Extent.StartLineNumber), column: $($varAst.Extent.StartColumnNumber)."
                }
                continue 
            }
            
            if ($assignedVarInfo.IsParameter) { continue }

            $obfuscatedName = $assignedVarInfo.ObfuscatedName
            if ($varInfo.IsScoped) { $obfuscatedName = $varInfo.Scope + ":" + $obfuscatedName }
            
            $startOffset = 1
            $lengthOffset = $startOffset
            if ($varInfo.IsString) { $lengthOffset++ } 
            [void]$Replacements.Add(@{ Start = $varInfo.Ast.Extent.StartOffset + $startOffset; Length = $varInfo.Ast.Extent.EndOffset - $varInfo.Ast.Extent.StartOffset - $lengthOffset; Replacement = $obfuscatedName })
        }
    }
    
    [VarInfo]FindAssignedVarInfo(
        [hashtable]$VarsMap,
        [VarInfo]$VarInfo,
        [ScriptBlockAst]$SbAst
    ) {
        if (-not $VarInfo -or $VarInfo.IsParameter) { return $null }
        
        $assignVarsInfo = $VarsMap[$SbAst]
        
        if ($assignVarsInfo -and $assignVarsInfo.ContainsKey($VarInfo.FullName)) {
            return  $assignVarsInfo[$VarInfo.FullName]
        }
        
        $parentSb = $this.astModel.GetAstParentScriptBlock($SbAst)
        
        if (-not $parentSb -and $VarsMap.ContainsKey($SbAst)) { 
            $assignVarsInfo = $VarsMap[$SbAst]
            
            if ($VarInfo.Scope -eq "global" -or $VarInfo.Scope -eq "script") { 
                if ($assignVarsInfo.ContainsKey($VarInfo.FullName)) { return $assignVarsInfo[$VarInfo.FullName] }
                return $null
            }            
            elseif (-not $VarInfo.IsScoped -and $VarInfo.Scope -eq "local" ) {
                $scriptName = "script:" + $VarInfo.Name
                if ($assignVarsInfo.ContainsKey($scriptName)) { return $assignVarsInfo[$scriptName] }

                $globalName = "global:" + $VarInfo.Name
                if ($assignVarsInfo.ContainsKey($globalName)) { return $assignVarsInfo[$globalName] }
            }

            return $null 
        }

        return $this.FindAssignedVarInfo($VarsMap, $VarInfo, $parentSb)
    }
    
    [VarInfo]ProcessSpecialVars([VarInfo]$VarInfo, [ScriptBlockAst]$SbAst) {
        if (-not $VarInfo) { return $VarInfo }

        if ($VarInfo.Name -eq "ExecutionContext") { return $this.GetVarInfoFromExecutionContext($VarInfo, $SbAst) }
        return $VarInfo
    }
    
    [VarInfo]GetVarInfoFromExecutionContext([VarInfo]$VarInfo, [ScriptBlockAst]$SbAst) {
        $executionContextAst = $VarInfo.Ast
        if ($executionContextAst.Parent -isnot [MemberExpressionAst] -or $executionContextAst.Parent.Member -isnot [CommandElementAst] -or $executionContextAst.Parent.Member.Value -ne "SessionState") { return $null }
        
        $sessionStateAst = $executionContextAst.Parent
        if ($sessionStateAst.Parent -isnot [MemberExpressionAst] -or $sessionStateAst.Parent.Member -isnot [CommandElementAst] -or $sessionStateAst.Parent.Member.Value -ne "PSVariable") { return $null }
        
        $psVariableAst = $sessionStateAst.Parent
        if ($psVariableAst.Parent -isnot [InvokeMemberExpressionAst] -or $psVariableAst.Parent.Member -isnot [CommandElementAst] -or $psVariableAst.Parent.Member.Value -ne "GetValue") { return $null }
        
        $getValueAst = $psVariableAst.Parent
        if (-not $getValueAst.arguments -or $getValueAst.arguments[0] -isnot [StringConstantExpressionAst]) { return $null }

        $varName = $getValueAst.arguments[0].Value
        
        return [VarInfo]::new(
            $varName, 
            "local:$varName", 
            $varName, 
            "local", 
            $false, 
            $false, 
            $false, 
            $getValueAst.arguments[0], 
            $SbAst, 
            $true 
        )
    }
}

Class VarsMapper {
    [hashtable]$config
    [AstModel]$astModel
    [VarsNameGenerator]$nameGenerator
    

    VarsMapper (
        [hashtable]$config,
        [AstModel]$astModel
    ) {
        $this.config = $config
        $this.astModel = $AstModel
        $this.nameGenerator = [VarsNameGenerator]::new($this.astModel.BuiltinVars)
    }

    [hashtable]GetMap() {
        Write-Host "        Generating variables map..." -ForegroundColor Green
        $varsMap = @{}
        $this.FillAssignmentsMap($this.astModel.ast, $this.astModel.ast, $varsMap)
        Write-Host "        Variables map generated. Found variable assignments: $($varsMap.Keys.Count)" -ForegroundColor Green
        return $varsMap
    }

    [void]FillAssignmentsMap(
        [ScriptBlockAst]$SbAst,
        [ScriptBlockAst]$RootSbAst,
        [hashtable]$VarsMap
    ) {

        if (-not $SbAst -is [ScriptBlockAst]) { throw "Expected ScriptBlockAst" }
                
        $varsInfo = $this.GetAssignmentsInfo($SbAst, $RootSbAst, $VarsMap)
        $VarsMap[$SbAst] = $varsInfo

        [ScriptBlockAst[]]$childrenSb = $this.astModel.FindAstChildrenByType($SbAst, [ScriptBlockAst], "firstChildren", $null)
            
        foreach ($childSb in $childrenSb) {
            $this.FillAssignmentsMap($childSb, $RootSbAst, $VarsMap)
        }
    }
    
    [hashtable]GetAssignmentsInfo(
        [ScriptBlockAst]$SbAst,
        [ScriptBlockAst]$RootSbAst,
        [hashtable]$VarsMap
    ) {

        if (-not $sbAst -is [ScriptBlockAst]) { throw "Expected ScriptBlockAst" }

        $assignments = @()
        
        if ($sbAst.Parent -is [FunctionDefinitionAst]) {
            $funcAst = $sbAst.Parent
            if ($funcAst.Parameters) { $assignments += $funcAst.Parameters }
        }
                
        $paramAssignments = $sbAst.FindAll({ 
                param($node)
                $node -is [ParameterAst]
            }, $false)

        if ($paramAssignments -and $paramAssignments.Count -gt 0) { $assignments += $paramAssignments }
        
        $statementsAssignments = $sbAst.FindAll({ 
                param($node)
                ($node -is [AssignmentStatementAst]) -or ($node -is [ForEachStatementAst]) -or ($node -is [ForStatementAst])
            }, $false) 
        if ($statementsAssignments -and $statementsAssignments.Count -gt 0) { $assignments += $statementsAssignments }

        $varsInfo = @{}

        foreach ($assignment in $assignments) {
            $varAst = $null
            if ($assignment -is [ParameterAst]) { $varAst = $assignment.Name }
            elseif ($assignment -is [AssignmentStatementAst]) { $varAst = $assignment.Left }
            elseif ($assignment -is [ForEachStatementAst]) { $varAst = $assignment.Variable }
            elseif ($assignment -is [ForStatementAst]) { $varAst = $assignment.Initializer.Left }
            
            if ($varAst -is [ConvertExpressionAst]) { $varAst = $varAst.Child }
            
            if ($varAst -isnot [VariableExpressionAst]) { continue }

            $varInfo = $this.astModel.GetAstVariableInfo($varAst, $SbAst)
            
            if (-not $varInfo -or $varsInfo.ContainsKey($varInfo.FullName)) { continue }
            
            if ($this.config.VarsExclude -contains $varInfo.OriginalName) { continue }
            
            if ($SbAst -ne $RootSbAst -and $varInfo.IsScoped -and ($varInfo.Scope -eq "script" -or $varInfo.Scope -eq "global")) {
                if (-not $VarsMap.ContainsKey($RootSbAst)) { $VarsMap[$RootSbAst] = @{} }
                
                $varInfo.ObfuscatedName = ($this.nameGenerator.GetObfuscatedName($this.config.Mode))
                if (-not $VarsMap[$RootSbAst].ContainsKey($varInfo.FullName)) { 
                    Write-Warning "A $($varInfo.Scope)-scoped variable '$($varInfo.OriginalName)' defined inside non-root scrip-block. It will persist outside the script-block and may cause side effects. Line: $($varAst.Extent.StartLineNumber), column: $($varAst.Extent.StartColumnNumber)."
                    $VarsMap[$RootSbAst][$varInfo.FullName] = $varInfo 
                }
                continue
            }
            
            if ($varInfo.IsParameter) { $varInfo.ObfuscatedName = $varInfo.OriginalName }
            else { $varInfo.ObfuscatedName = ($this.nameGenerator.GetObfuscatedName($this.config.Mode)) }
        

            $varsInfo[$varInfo.FullName] = $varInfo
        }

        return $varsInfo
    }
}

Class VarsNameGenerator {
    $usedMap = @{}
    $builtinNames = @{}
    $words = @(
        'Id', 'Object', 'Value', 'Table', 'Data', 'Item', 'Row', 'Cell', 'Index', 'Count', 'Filter',
        'Field', 'List', 'Array', 'Node', 'Key', 'Param', 'Entry', 'Type', 'Name', 'Source',
        'Target', 'Range', 'Size', 'Length', 'Result', 'Status', 'Option', 'Group', 'Parent', 'Child',
        'Column', 'Header', 'Record', 'Recordset', 'Buffer', 'Stream', 'Stack', 'Queue', 'Cache', 'Token',
        'Session', 'Context', 'Handle', 'Path', 'File', 'Folder', 'Driver', 'Engine', 'Query', 'Script',
        'Config', 'Method', 'Event', 'Action', 'Command', 'Process', 'Task', 'Thread', 'Lock', 'Flag',
        'Error', 'Message', 'Report', 'Log', 'Trace', 'Level', 'State', 'Mode', 'Format', 'Output',
        'Input', 'Source', 'Destination', 'Time', 'Date', 'Count', 'Limit', 'Offset', 'Filter', 'Pattern',
        'Value', 'Key', 'Index', 'Type', 'Status', 'Version', 'Option', 'Setting', 'Profile', 'Client'
    )

    VarsNameGenerator([hashtable]$builtinNames) {
        $this.builtinNames = $builtinNames
    }

    [string]GetObfuscatedName([string]$Mode) {
        if ($Mode -ieq "Natural") { return $this.GetNaturalName() }
        else { return $this.GetHardName() }
    }

    [string]GetNaturalName() {
        $new = ""

        while (-not $new -or $this.usedMap.ContainsKey($new)) {            
            $count = Get-Random -Minimum 3 -Maximum 5
            $chosen = Get-Random -InputObject $this.words -Count $count
            $new = ($chosen -join '')            
            if ($this.builtinNames.ContainsKey($new)) { $new = "" }
        }
        $this.usedMap[$new] = $true
        return $new
    }


    [string]GetHardName() {
        $chars = @()
        $lChars = [char[]]'abcdefghijklmnopqrstuvwxyz'
        $uChars = [char[]]'ABCDEFGHIJKLMNOPQRSTUVWXYZ'
        $nChars = [char[]]'0123456789'
        $chars += $lChars
        $chars += $uChars
        $chars += $nChars

        $new = ""

        while (-not $new -or $this.usedMap.ContainsKey($new)) {
            $len = Get-Random -Minimum 7 -Maximum 20
            
            $firstChar = Get-Random -InputObject ($lChars + $uChars)

            $rest = ""
            for ($i = 1; $i -lt $len; $i++) {
                $rest += (Get-Random -InputObject $chars)
            }

            $new = "$firstChar$rest"

            if ($this.builtinNames.ContainsKey($new)) { $new = "" }
        }

        $this.usedMap[$new] = $true
        return $new
    }
}

Class FuncReplacer {
    [hashtable]$config
    [AstModel]$astModel

    FuncReplacer (
        [hashtable]$Config,
        [AstModel]$AstModel
    ) {
        $this.config = $Config
        $this.astModel = $AstModel
    }

    [System.Collections.ArrayList]GetReplacements() {
        $funcMapper = [FuncMapper]::new($this.config, $this.astModel)
        $funcMap = $funcMapper.GetMap()

        $replacements = [System.Collections.ArrayList]::new()
        Write-Host "        Generating function replacements..." -ForegroundColor Green
        $this.FillReplacements($funcMap, $replacements)
        Write-Host "        Function replacements generated. Total replacements: $($replacements.Count)" -ForegroundColor Green
        return $replacements
    }


    FillReplacements(
        [hashtable]$FuncsMap,
        [System.Collections.ArrayList]$Replacements
    ) {
        $ast =$this.astModel.ast

        $funcsAst = $ast.FindAll({ 
                param($node)
                ($node -is [CommandAst]) -or ($node -is [FunctionDefinitionAst])
            }, $true)

        foreach ($funcAst in $funcsAst) {
            $element = $null
            $funcName = ""
            $start = 0
            $length = 0            
            if ($funcAst -is [CommandAst]) { 
                $element = $funcAst.CommandElements[0]

                if (-not ($element -is [StringConstantExpressionAst]) -or $element.StringConstantType -ne 'BareWord') { continue }
                $funcName = $element.Value

                if ($funcName -eq "Get-Command") { 
                    $extent = $this.GetSpecialFunctionParameterExtent($funcAst)
                    if (-not $extent) { continue }
                    $funcName = $extent.Value
                    $start = $extent.Start
                    $length = $extent.Length                

                }
                else {
                    $start = $element.Extent.StartOffset
                    $length = $element.Extent.EndOffset - $start
                }
            }            
            elseif ($funcAst -is [FunctionDefinitionAst]) {
                $extent = $this.GetFunctionNameExtent($funcAst)
                if (-not $extent) { continue }
                $funcName = $extent.Value
                $start = $extent.Start
                $length = $extent.Length
            }

            if (-not $funcName) { continue }

            $obfuscatedName = ""
            if ($FuncsMap.ContainsKey($funcName)) { $obfuscatedName = $FuncsMap[$funcName] }
            else { continue }

            [void]$Replacements.Add(@{ Start = $start; Length = $length; Replacement = $obfuscatedName })
        }
    }

    
    [PSCustomObject]GetFunctionNameExtent([FunctionDefinitionAst]$funcAst) {
        $name = $funcAst.Name
        $extent = $funcAst.Extent
        $text = $extent.Text
        $localOffset = $text.IndexOf($name)

        if ($localOffset -lt 0) { return $null }

        $start = $extent.StartOffset + $localOffset
        $length = $name.Length

        return [PSCustomObject]@{
            Value  = $name
            Start  = $start
            Length = $length
        }
    }
    
    [PSCustomObject]GetSpecialFunctionParameterExtent([CommandAst]$funcAst) {
        $elements = $funcAst.CommandElements

        if (-not $elements -or $elements.Count -lt 2) { return $null }
        
        $paramNameFound = $true

        for ($i = 1; $i -lt $elements.Count; $i++) {
            $element = $elements[$i]
            if ($paramNameFound -and $element -is [StringConstantExpressionAst]) {
                return [PSCustomObject]@{
                    Value  = $element.Value
                    Start  = $element.Extent.StartOffset
                    Length = $element.Extent.EndOffset - $element.Extent.StartOffset
                }
            }

            $paramNameFound = $false
            if ($element -is [CommandParameterAst] -and $element.ParameterName -eq "Name") {
                $paramNameFound = $true
                continue
            }
        }
        return $null
    }
}

Class FuncMapper {
    [hashtable]$config
    [AstModel]$astModel
    [FuncNameGenerator]$nameGenerator

    FuncMapper (
        [hashtable]$config,
        [AstModel]$astModel
    ) {
        $this.config = $config
        $this.astModel = $AstModel
        $this.nameGenerator = [FuncNameGenerator]::new($this.astModel.builtinFuncs)
    }
    
    [hashtable]GetMap() {
        Write-Host "        Generating functions map..." -ForegroundColor Green
        $funcsMap = @{}
        $this.FillAssignmentsMap($this.astModel.ast, $funcsMap)
        Write-Host "        Functions map generated. Found function definitions: $($funcsMap.Keys.Count)" -ForegroundColor Green
        return  $funcsMap
    }

    [void]FillAssignmentsMap(
        [ScriptBlockAst]$Ast,
        [hashtable]$FuncsMap
    ) {
        $exclude = $null
        if ($this.config.FuncsExclude.Count) { $exclude = $this.config.FuncsExclude }

        $funcAsts = $Ast.FindAll({ 
                param($n)                 
                $n -is [FunctionDefinitionAst] -and -not ($n.parent -is [FunctionMemberAst])
            }, $true)
        

        $funcNames = @($funcAsts | ForEach-Object { $_.Name } | Where-Object { $_ -and ($_ -notin $exclude) } | Sort-Object -Unique)

        if (-not $funcNames -or $funcNames.Count -eq 0) { return }

        $this.FillObfuscatedMap($funcNames, $FuncsMap)
    }

    [void]FillObfuscatedMap([string[]]$funcNames, [hashtable]$FuncsMap) {
        foreach ($name in $funcNames) {
            $new = $this.nameGenerator.GetObfuscatedName($this.config.Mode)
            $funcsMap[$name] = $new
        }
    }
}

Class FuncNameGenerator {
    $usedMap = @{}
    $builtinNames = @{}
    $words = @(
        'Id', 'Object', 'Value', 'Table', 'Data', 'Item', 'Row', 'Cell', 'Index', 'Count', 'Filter',
        'Field', 'List', 'Array', 'Node', 'Key', 'Param', 'Entry', 'Type', 'Name', 'Source',
        'Target', 'Range', 'Size', 'Length', 'Result', 'Status', 'Option', 'Group', 'Parent', 'Child',
        'Column', 'Header', 'Record', 'Recordset', 'Buffer', 'Stream', 'Stack', 'Queue', 'Cache', 'Token',
        'Session', 'Context', 'Handle', 'Path', 'File', 'Folder', 'Driver', 'Engine', 'Query', 'Script',
        'Config', 'Method', 'Event', 'Action', 'Command', 'Process', 'Task', 'Thread', 'Lock', 'Flag',
        'Error', 'Message', 'Report', 'Log', 'Trace', 'Level', 'State', 'Mode', 'Format', 'Output',
        'Input', 'Source', 'Destination', 'Time', 'Date', 'Count', 'Limit', 'Offset', 'Filter', 'Pattern',
        'Value', 'Key', 'Index', 'Type', 'Status', 'Version', 'Option', 'Setting', 'Profile', 'Client'
    )

    FuncNameGenerator([hashtable]$builtinNames) {
        $this.builtinNames = $builtinNames
    }

    [string]GetObfuscatedName([string]$Mode) {
        if ($Mode -ieq "Natural") { return $this.GetNaturalName() }
        else { return $this.GetHardName() }
    }

    [string]GetNaturalName() {
        $Prefixes = @("Add", "Clear", "Close", "Copy", "Enter", "Exit", "Find", "Format", "Get", "Hide", "Join", "Lock", "Move", "New", "Open", "Pop", "Push", "Redo", "Remove", "Rename", "Reset", "Resize", "Search", "Select", "Set", "Show", "Skip", "Split", "Step", "Switch", "Undo", "Unlock", "Watch", "Read", "Receive", "Send", "Write", "Compare", "Compress", "Convert", "Group", "Initialize", "Mount", "Save", "Sync", "Update", "Resolve", "Test", "Confirm", "Invoke", "Start", "Stop", "Submit")
        $new = ""

        while (-not $new -or $this.usedMap.ContainsKey($new)) {
            $prefix = Get-Random -InputObject $Prefixes            
            $count = Get-Random -Minimum 3 -Maximum 5
            $chosen = Get-Random -InputObject $this.words -Count $count
            $body = ($chosen -join '')
    
            $new = "$prefix-$body"
                    
            if ($this.builtinNames.ContainsKey($new)) { $new = "" }
        }

        $this.usedMap[$new] = $true
        return $new
    }

    [string]GetHardName() {
        $chars = @()
        $lChars = [char[]]'abcdefghijklmnopqrstuvwxyz'
        $uChars = [char[]]'ABCDEFGHIJKLMNOPQRSTUVWXYZ'
        $nChars = [char[]]'0123456789'
        $chars += $lChars
        $chars += $uChars
        $chars += $nChars

        $new = ""

        while (-not $new -or $this.usedMap.ContainsKey($new)) {
            $len = Get-Random -Minimum 7 -Maximum 20
            
            $firstChar = Get-Random -InputObject $uChars

            $rest = ""
            for ($i = 1; $i -lt $len; $i++) {
                $rest += (Get-Random -InputObject $chars)
            }

            $body = "$firstChar$rest"
            $new = "Use-$body"

            if ($this.builtinNames.ContainsKey($new)) { $new = "" }
        }

        $this.usedMap[$new] = $true
        return $new
    }
}


$global:__MODULES_c481812ceb91481e9fcf22d7cfe9f35d = @{}


$global:__MODULES_c481812ceb91481e9fcf22d7cfe9f35d["dec18d6262c64288bab546fabf658d62"] = {
    function Invoke-PSBundler {
        [CmdletBinding()]
        param(
            [string]$configPath = ""
        )
        $null = [PsBundler]::new($configPath) 
    }
}

Import-Module (New-Module -Name PsBundler -ScriptBlock $global:__MODULES_c481812ceb91481e9fcf22d7cfe9f35d["dec18d6262c64288bab546fabf658d62"]) -Force -DisableNameChecking
Invoke-PsBundler -configPath $configPath
