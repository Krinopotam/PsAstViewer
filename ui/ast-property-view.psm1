using module .\progress-bar.psm1
using module ..\models\ast-model.psm1
using module ..\utils\node-drawer.psm1
using module ..\utils\text-tag-parser.psm1
using namespace System.Management.Automation.Language

Class AstPropertyView {
    [object]$mainForm # can't use type [MainForm] due to circular dependency
    [System.Windows.Forms.Control]$container
    [System.Windows.Forms.TreeView]$instance
    [AstModel]$astModel
    [NodeDrawer]$nodeDrawer
    [TextTagParser]$tagParser
    [hashtable]$astColorsMap

    AstPropertyView([object]$mainForm, [System.Windows.Forms.Control]$container, [hashtable]$astColorsMap) {
        $this.mainForm = $mainForm
        $this.container = $container
        $this.astColorsMap = $astColorsMap
        $this.tagParser = [TextTagParser]::new("black", "white")
        $this.nodeDrawer = [NodeDrawer]::new()
        $this.instance = $this.Init()
    }   

    [System.Windows.Forms.TreeView]Init() {
        $label = [System.Windows.Forms.Label]::new()
        $label.Name = "lblAstPropView"
        $label.Text = "AST node properties"
        $label.Top = 10
        $label.Left = 10
        $label.Height = 20
        $label.Width = 200
        $this.container.Controls.Add($label)

        $treeView = [System.Windows.Forms.TreeView]::new()
        $treeView.Tag = $this
        $treeView.Name = "treePropView"
        $treeView.Top = $label.Bottom
        $treeView.Left = 10
        $treeView.Height = $this.container.ClientSize.Height - $label.Bottom - 25
        $treeView.Width = $this.container.ClientSize.Width - 12
        $treeView.Anchor = "Top, Bottom, Left, Right"
        $treeView.Font = New-Object System.Drawing.Font("Courier New", 12)
        $treeView.HideSelection = $false
        $treeView.ShowNodeToolTips = $true
        $treeView.DrawMode = [System.Windows.Forms.TreeViewDrawMode]::OwnerDrawText
        $this.container.Controls.Add($treeView)

        $this.InitEvents($treeView) 
        $this.initContextMenu($treeView)  

        return $treeView
    }

    [void]initEvents( [System.Windows.Forms.TreeView]$treeView) {
        $treeView.add_BeforeExpand({
                param($s, $e)
                $self = $s.Tag

                $obj = $e.Node.Tag.Parameter
                $self.addPropertiesNodes($obj, $e.Node)
            })

        $treeView.Add_AfterSelect({ 
                param($s, $e)
                $self = $s.Tag
                $obj = $e.Node.Tag.Parameter
                $ast = $null
                if ($obj -is [Ast]) { $ast = [Ast]$obj }
                $self.mainForm.onParameterSelected($obj, $ast)
            })

        $treeView.Add_NodeMouseClick({
                param($s, $e)
                $self = $s.Tag
                $ctrl = $self.mainForm.ctrlPressed
                if ($e.Button -eq [System.Windows.Forms.MouseButtons]::Left -and $ctrl -and $e.node) {
                    $obj = $e.node.Tag.Parameter
                    if ($obj -is [Ast]) { $self.mainForm.selectAstInTreeView($obj) }
                }
                elseif ($e.Button -eq [System.Windows.Forms.MouseButtons]::Right) { 
                    $self.instance.SelectedNode = $e.Node 
                }
            })

        $treeView.Add_DrawNode({
                param($s, $e)
                $s.Tag.nodeDrawer.drawNode($s, $e, $e.Node.Tag.NameParts)
            })
    }

    [void]initContextMenu([System.Windows.Forms.TreeView]$treeView) {
        $menu = [System.Windows.Forms.ContextMenuStrip]::new()
        $menu.Add_Opening({
                param($s, $e)
                $ctrl = $s.SourceControl
                $node = $ctrl.SelectedNode
                if (-not $node) {
                    $e.Cancel = $true
                    return
                }

                $obj = $node.Tag.Parameter
                if ($obj -is [Ast]) { return }
                $e.Cancel = $true
            })
            
        $selectAst = $menu.Items.Add("Select Ast Node   (ctrl+click)")
        $selectAst.Add_Click({ 
                param($s, $e)
                # sender is a ToolStripMenuItem; get its ContextMenuStrip (owner)
                $cms = $s.GetCurrentParent()
                $ctrl = $cms.SourceControl
                $node = $ctrl.SelectedNode
                if (-not $node) { return }

                $self = $ctrl.Tag
                $obj = $node.Tag.Parameter
                if ($obj -is [Ast]) { $self.mainForm.selectAstInTreeView($obj) }
            })

        $showFindAllUnnested = $menu.Items.Add("Filtered Shallow View (FindAll nested = false)")
        $showFindAllUnnested.Add_Click({ 
                param($s, $e)
                # sender is a ToolStripMenuItem; get its ContextMenuStrip (owner)
                $cms = $s.GetCurrentParent()
                $ctrl = $cms.SourceControl
                $node = $ctrl.SelectedNode
                if (-not $node) { return }

                $self = $ctrl.Tag
                $obj = $node.Tag.Parameter
                if ($obj -is [Ast]) { $self.mainForm.filterByFindAllCommand($obj, $false) }
            })

        $treeView.ContextMenuStrip = $menu
    }

    [void]setAstModel([AstModel]$astModel, [ProgressBar]$pb) {
        $this.astModel = $astModel
    }
    

    [void]onAstNodeSelected([Ast]$ast, [int]$index) {
        $this.fillTree($ast)
    }
 
    [void]fillTree([Ast]$ast) {
        $this.instance.Nodes.Clear()
        $this.addPropertiesNodes($ast, $this.instance)
    }

    [void]addPropertiesNodes([object]$obj, $parentNode) {
        $parentNode.Nodes.Clear()

        if ($this.processArrayProperty($obj, $parentNode)) { return }
        $this.processObjProperty($obj, $parentNode)
        $this.processMethodsProperty($obj, $parentNode)
    }

    # Add array property node
    [boolean]processArrayProperty([object]$obj, $parentNode) {
        if ($obj -isnot [System.Collections.IEnumerable] -or $obj -is [string]) { return $false }
       
        $i = 0
        foreach ($p in $obj) {
            $node = [System.Windows.Forms.TreeNode]::new()
            $type = $p.GetType().Name
            $node.Text = "[$i][$type]"

            $taggedType = $type
            $color = "#CD9C6C"
            if ($p -is [Ast]) { 
                if ($this.astColorsMap.ContainsKey($type)) { $color = $this.astColorsMap[$type] }
                $taggedType = "<b>$taggedType</b>" 
            }
            $node.Tag = @{
                Parameter = $p
                NameParts = $this.tagParser.Parse("[$i]<color:#C480DC>[</color><color:$color>$taggedType</color><color:#C480DC>]</color>")
            }
            if ($p -and -not $this.isValuePrimitive($p)) { $node.Nodes.Add("[Loading...]") }
            $parentNode.Nodes.Add($node)
            $i++
        }

        return $true
    }

    # Add object property node
    [void]processObjProperty([object]$obj, $parentNode) {
        foreach ($p in ([PSObject]$obj).PSObject.Properties) {
            $type = $this.getPropertyType($p)
            $val = $this.getPropertyValue($p)
            $name = $p.Name
            $taggedType = $type
            $taggedName = $name
            $color = "#CD9C6C"
            if ($p.Value -is [Ast]) { 
                if ($this.astColorsMap.ContainsKey($type)) { $color = $this.astColorsMap[$type] }
                $taggedType = "<b>$type</b>" 
                $taggedName = "<b>$name</b>"
            }
            $taggedText = "<color:#C480DC>[</color><color:$color>$taggedType</color><color:#C480DC>]</color> $taggedName"
            $nodeStr = "[$type] $name"
            if ($val) { 
                $taggedText += ": <color:#4F4497>$val</color>" 
                $nodeStr += ": $val" 
            }

            $node = [System.Windows.Forms.TreeNode]::new()
            $node.Text = $nodeStr
            $node.Tag = @{
                Parameter = $p.Value
                NameParts = $this.tagParser.Parse($taggedText)
            }

            if ($p.Value -and -not $this.isValuePrimitive($p.Value)) { 
                $node.Nodes.Add("[Loading...]") 
            }
            $parentNode.Nodes.Add($node)
        }
    }

    [void]processMethodsProperty([object]$obj, $parentNode) {
        #methods processing
        $realMethods = ([PSObject]$obj).PSObject.Methods |  Where-Object {
            $_.Name -notmatch '^(get_|set_)' -and
            $_.Name -notin @('Equals', 'GetHashCode', 'GetType', 'ToString')
        }

        foreach ($m in $realMethods) {
            $name = $this.removeNamespaces($m.toString())
            $taggedName = $this.highlightMethodFullName($name)
            $taggedText = "<color:#3477eb>Method</color>: $taggedName"
            $node = [System.Windows.Forms.TreeNode]::new()
            $node.Text = "Method: $name"
            $node.Tag = @{
                Parameter = $m
                NameParts = $this.tagParser.Parse($taggedText)
            }
            $parentNode.Nodes.Add($node)
        }
    }

    [bool]isValuePrimitive([object]$val) {
        return  $val -is [string] -or $val.GetType().IsPrimitive -or $val -is [type] -or $val -is [ITypeName]
    }

    [string]removeNamespaces([string]$str) {
        # Pattern: match full type name with dots and keep only last identifier
        $pattern = '\b(?:[A-Za-z_][\w]*\.)+([A-Za-z_][\w]*)\b'

        return [regex]::Replace($str, $pattern, { param($m) $m.Groups[1].Value })
    }

    [string]highlightMethodFullName([string] $str) {
        # Highlight method types
        $str = [regex]::Replace(
            $str,
            '(?<type>[A-Za-z_]\w*(\[[^\]]+\])?)(?=\s+[A-Za-z_]\w*)',
            '<color:#C480DC>[</color><color:#CD9C6C>${type}</color><color:#C480DC>]</color>'
        ) 

        # Highlight method names
        return [regex]::Replace(
            $str,
            '\b([A-Za-z_]\w*)\s*(?=\()',
            '<b>$1</b>'
        )
    }

    [string]getPropertyType([object]$prop) {
        $typeName = [Microsoft.PowerShell.ToStringCodeMethods]::Type([type]$prop.TypeNameOfValue)
        if ($typeName -match '.*ReadOnlyCollection\[(.*)\]') { $typeName = $matches[1] + '[]' }
        # Remove the namespace
        $typeName = $this.removeNamespaces($typeName) #$typeName -replace '.*\.', ''
        return $typeName
    }

    [string]getPropertyValue([object]$prop) {
        if ($null -eq $prop.Value) { return 'null' }

        if ($this.isValuePrimitive($prop.Value) -or $prop.Value -is [enum] -or $prop.Value -is [IScriptExtent]) {
            $val = $prop.Value.ToString() 
            if ($val.Length -gt 50) { $val = $val.Substring(0, 50) + "..." }
            return $val
        }

        if ( $prop.Value -is [System.Collections.IEnumerable]) {
            if ($prop.Value.Count -eq 0) { return "[]" }
            return "[$($prop.Value.Count)]"
        }

        return "object"
    }
}