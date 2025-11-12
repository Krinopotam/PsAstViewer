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
        $treeView.Name = "treePropView"
        $treeView.Top = $label.Bottom
        $treeView.Left = 10
        $treeView.Height = $this.container.ClientSize.Height - $label.Bottom - 12
        $treeView.Width = $this.container.ClientSize.Width - 12
        $treeView.Anchor = "Top, Bottom, Left, Right"
        $treeView.Font = New-Object System.Drawing.Font("Courier New", 12)
        $treeView.HideSelection = $false
        $treeView.ShowNodeToolTips = $true
        $treeView.Tag = $this
        $treeView.DrawMode = [System.Windows.Forms.TreeViewDrawMode]::OwnerDrawText
        $this.container.Controls.Add($treeView)

        $menu = New-Object System.Windows.Forms.ContextMenuStrip
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

        # Навешиваем меню
        $treeView.ContextMenuStrip = $menu

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

        $treeView.Add_MouseDown({
                param($s, $e)
                $self = $s.Tag
                $ctrl = $self.mainForm.ctrlPressed
                $node = $s.GetNodeAt($e.X, $e.Y)

                if ($e.Button -eq [System.Windows.Forms.MouseButtons]::Left -and $ctrl -and $node) {
                    $self = $s.Tag
                    $obj = $node.Tag.Parameter
                    if ($obj -is [Ast]) { $self.mainForm.selectAstInTreeView($obj) }
                }
            })

        $treeView.Add_DrawNode({
                param($s, $e)
                $s.Tag.nodeDrawer.drawNode($s, $e, $e.Node.Tag.NameParts)
            })

        $treeView.Tag = $this
        return $treeView
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
        if ($obj -is [System.Collections.IEnumerable] -and -not ($obj -is [string])) {
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
            
            return
        }

        foreach ($p in ([PSObject]$obj).PSObject.Properties) {
            $type = $this.getPropertyType($p)
            $val = $this.getPropertyValue($p)
            $name = $p.Name
            $taggedName = $name
            if ($p.Value -is [Ast]) { $taggedName = "<b>$name</b>" }
            $taggedText = "<color:#C480DC>[</color><color:#CD9C6C>$type</color><color:#C480DC>]</color> $taggedName"
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

    [bool]isValuePrimitive([object]$val) {
        return  $val -is [string] -or $val.GetType().IsPrimitive -or $val -is [type] -or $val -is [ITypeName]
    }

    [string]getPropertyType([object]$prop) {
        $typeName = [Microsoft.PowerShell.ToStringCodeMethods]::Type([type]$prop.TypeNameOfValue)
        if ($typeName -match '.*ReadOnlyCollection\[(.*)\]') { $typeName = $matches[1] + '[]' }
        # Remove the namespace
        $typeName = $typeName -replace '.*\.', ''
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