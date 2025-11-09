using namespace System.Management.Automation.Language

Class AstModel {
    [Ast]$ast
    [hashtable]$astMap
    [string]$script
    [int]$nodesCount

    AstModel([string]$Script) {
        $this.init($Script)
    }

    static [AstModel] FromFile([string]$Path) {
        if (-not (Test-Path $Path)) { throw "File not found: $Path" }
        $text = Get-Content -Raw -LiteralPath $Path -Encoding UTF8
        return [AstModel]::new($text)
    }

    static [AstModel] FromScript([string]$Script) {
        return [AstModel]::new($Script)
    }
    
    [void]init([string]$script) {
        try {
            # WORKAROUND: RichTextBox count \r\n as one char, but Ast.Extent count \r\n as two. So we have to convert \r\n to \n to get correct Ast.Extent to RichTextBox position mapping
            $this.script = $script -replace "`r`n", "`n" 
        
            $errors = $null
            $scriptAst = [Parser]::ParseInput($this.script, [ref]$null, [ref]$errors)
            #if ($errors) { throw "Parsing failed" }

            $this.ast = $scriptAst
            $this.astMap = $this.getAstHierarchyMap($scriptAst)
        }
        catch {
            $this.ast = ""
            $this.astMap = @{}
        }
    }

    # Ast have no ability to get strong hierarchy, so we have to build it manually
    # Despite the descriptions, $ast.FindAll( { $true }, $false) returns not only direct children, but for some nodes unfolds their children in a flat list
    #    $ast.FindAll( { $true }, $false) is good to get all variables in scriptBlock, but can't get children scriptBlocks
    #    $ast.FindAll( { $true }, $true) returns all nodes in hierarchy, not only direct children
    [System.Collections.Specialized.OrderedDictionary]getAstHierarchyMap([Ast]$rootAst) {
        $map = [ordered]@{}

        $items = $rootAst.FindAll( { $true }, $true)
        $this.nodesCount = $items.Count
        foreach ($item in $items) {
            if (-not $item.Parent) { continue }
            $parent = $item.Parent
            if (-not $map.Contains($parent)) { $map[$parent] = [System.Collections.ArrayList]@() }
            [void]$map[$parent].Add($item)
        }

        return $map
    }

    # Find specific children of Ast
    [System.Collections.ArrayList]FindAstChildrenByType(
        # Root Ast to start search
        [System.Management.Automation.Language.Ast]$Ast,                 
        # If specified, returns only children of this type
        [Type]$ChildType = $null,
        # Selection type: "allChildren" - returns all children, "firstChildren" - returns first encountered children or "directChildren" - returns only direct children
        [string]$Select = "firstChildren",
        # If specified, returns all children until this type. This type is not included
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

    [Ast]FindAstByOffset([int]$offset) {
        $bestNode = $null
        $bestSpan = [int]::MaxValue

        $nodes = $this.ast.FindAll({ $true }, $true)
        foreach ($node in $nodes) {
            $extent = $node.Extent
            if ($extent -and $extent.StartOffset -le $offset -and $extent.EndOffset -gt $offset) {
                $span = $extent.EndOffset - $extent.StartOffset
                if ($span -le $bestSpan) {
                    $bestNode = $node
                    $bestSpan = $span
                }
            }
        }

        return $bestNode
    }
}