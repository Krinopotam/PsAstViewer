using module .\progress-bar.psm1
using module ..\models\ast-model.psm1
using module ..\utils\node-drawer.psm1
using module ..\utils\text-tag-parser.psm1
using namespace System.Management.Automation.Language

Class AstTreeView {
    [object]$mainForm # can't use type [MainForm] due to circular dependency
    [System.Windows.Forms.Control]$container
    [System.Windows.Forms.TreeView]$instance
    [System.Windows.Forms.TreeView]$dummyInstance
    [AstModel]$astModel
    [NodeDrawer]$nodeDrawer
    [TextTagParser]$tagParser
    [bool]$inUpdate
    [bool]$isUpdatedFromViewBox
    [hashtable]$astColorsMap

    AstTreeView([object]$mainForm, [System.Windows.Forms.Control]$container, [hashtable]$astColorsMap) {
        $this.mainForm = $mainForm
        $this.container = $container
        $this.astColorsMap = $astColorsMap
        $this.tagParser = [TextTagParser]::new("black", "white")
        $this.nodeDrawer = [NodeDrawer]::new()
        $this.instance = $this.Init()
    }   

    [System.Windows.Forms.TreeView]Init() {
        $label = [System.Windows.Forms.Label]::new()
        $label.Name = "lblAstTreeView"
        $label.Text = "AST tree"
        $label.Top = 20
        $label.Left = 10
        $label.Height = 20
        $this.container.Controls.Add($label)

        $treeView = [System.Windows.Forms.TreeView]::new()
        $treeView.Name = "treeAstView"
        $treeView.Top = $label.Bottom
        $treeView.Left = 10
        $treeView.Height = $this.container.ClientSize.Height - $label.Bottom
        $treeView.Width = $this.container.ClientSize.Width - 12
        $treeView.Anchor = "Top, Bottom, Left, Right"
        $treeView.Font = New-Object System.Drawing.Font("Courier New", 12)
        $treeView.HideSelection = $false
        $treeView.DrawMode = [System.Windows.Forms.TreeViewDrawMode]::OwnerDrawText
        #$treeView.ShowNodeToolTips = $true
        $this.container.Controls.Add($treeView)

        $treeView.Tag = $this
        $treeView.Add_AfterSelect({ 
                param($s, $e)
                $self = $s.Tag
                $node = $e.Node
                $keepCaretPos = $false
                if ($self.isUpdatedFromViewBox) { $keepCaretPos = $true }
                $self.mainForm.onAstNodeSelected($node.Tag.Ast, $node.Tag.Index, $keepCaretPos)
            })

        $treeView.Add_DrawNode({
                param($s, $e)
                if ($s.Tag.inUpdate) { return }
                $s.Tag.nodeDrawer.drawNode($s, $e, $e.Node.Tag.NameParts)
            })

        $dummyTreeView = [System.Windows.Forms.TreeView]::new()
        $dummyTreeView.Name = "dummyTreeView"
        $dummyTreeView.Top = $treeView.Top
        $dummyTreeView.Left = $treeView.Left
        $dummyTreeView.Height = $treeView.Height
        $dummyTreeView.Width = $treeView.Width
        $dummyTreeView.Anchor = $treeView.Anchor
        $dummyTreeView.Font = $treeView.Font
        $dummyTreeView.Visible = $false
        $this.container.Controls.Add($dummyTreeView)
        $this.dummyInstance = $dummyTreeView

        return $treeView
    }

    [void]setAstModel([AstModel]$astModel, [ProgressBar]$pb) {
        $this.freezeUpdates($true)
        $this.astModel = $astModel
        $this.FillTreeView($astModel, $pb)
        #$this.instance.ExpandAll()
        $this.ExpandNodesToLevel($this.instance.Nodes, 2)
        if ($this.instance.Nodes.Count -gt 0) {
            $this.instance.SelectedNode = $this.instance.Nodes[0]
            $this.instance.Nodes[0].EnsureVisible()
        }
        $this.freezeUpdates($false)
    }

    [void]FillTreeView([AstModel]$astModel, [ProgressBar]$pb) {
        $tree = $this.instance
        $tree.Nodes.Clear()
        
        $idx = @{val = -1 }
        function Recurse($astMap, $ast, $parentNode, $idx, $pb) {
            $idx.val = $idx.val + 1
            $pb.Update($idx.val)

            $astName = $ast.GetType().Name
            $color = "Black"
            if ($this.astColorsMap.ContainsKey($astName)) { $color = $this.astColorsMap[$astName] }

            $codeBlockName = ""
            if ($ast.PSObject.Properties["Name"]) {
                $codeBlockName = ": $($ast.Name)"                            
            }

            $node = [System.Windows.Forms.TreeNode]::new()
            $node.Text = "$astName$codeBlockName [$($ast.Extent.StartOffset) - $($ast.Extent.EndOffset)]"
            #$node.ToolTipText = $node.Text
            $taggedText = "<color:$color><b>$astName</b></color><color:#4F4497>$codeBlockName</color> [$($ast.Extent.StartOffset) - $($ast.Extent.EndOffset)]"
            $node.Tag = @{
                Ast       = $ast
                Index     = $idx.val
                NameParts = $this.tagParser.Parse($taggedText)
            }

            $parentNode.Nodes.Add($node)

            if (-not $astMap.Contains($ast)) { return }
            foreach ($child in $astMap[$ast]) {
                Recurse $astMap $child $node $idx $pb
            }
        }

        Recurse $astModel.astMap $astModel.ast $tree $idx $pb
    }

    [void]selectAst([Ast]$ast) {
        if (-not $ast) { return }
        $node = $this.findNodeByAst($this.instance.Nodes, $ast)
        if (-not $node) { return }
        $this.instance.SelectedNode = $null
        $this.instance.SelectedNode = $node
    }

    [void]freezeUpdates([bool]$val) {
        if ($val) {
            $this.dummyInstance.Visible = $true
            $this.instance.Visible = $false
            $this.instance.DrawMode = [System.Windows.Forms.TreeViewDrawMode]::Normal
            $this.inUpdate = $true
            $this.instance.BeginUpdate()
        }
        else {
            $this.instance.EndUpdate()
            $this.instance.DrawMode = [System.Windows.Forms.TreeViewDrawMode]::OwnerDrawText
            $this.inUpdate = $false
            $this.instance.Visible = $true
            $this.dummyInstance.Visible = $false
        }
    }

    [System.Windows.Forms.TreeNode] findNodeByAst([System.Windows.Forms.TreeNodeCollection] $nodes, [Ast] $ast) {
        foreach ($node in $nodes) {
            if ($null -ne $node.Tag -and $node.Tag.Ast -eq $ast) { return $node }
            if ($node.Nodes.Count -gt 0) {
                $found = $this.findNodeByAst($node.Nodes, $ast)
                if ($null -ne $found) { return $found }
            }
        }
        return $null
    }

    [void]ExpandNodesToLevel(
        [System.Windows.Forms.TreeNodeCollection]$Nodes,
        [int]$Level
    ) {
        if ($Level -le 0 -or -not $Nodes) { return }

        foreach ($node in $Nodes) {
            $node.Expand()
            if ($node.Nodes.Count -gt 0 -and $Level -gt 1) {
                $this.ExpandNodesToLevel($node.Nodes, ($Level - 1))
            }
        }
    }

    [void]selectNodeByCharIndex([int]$charIndex) {
        if (-not $this.astModel -or $charIndex -lt 0) { return }

        $this.isUpdatedFromViewBox = $true
        $ast = $this.astModel.FindAstByOffset($charIndex)
        if (-not $ast) { return }

        $this.selectAst($ast)
        $this.isUpdatedFromViewBox = $false
    }
}