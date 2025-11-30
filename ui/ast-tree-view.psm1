using module .\progress-bar.psm1
using module ..\models\ast-model.psm1
using module ..\utils\node-drawer.psm1
using module ..\utils\text-tag-parser.psm1
using module .\search-panel.psm1
using namespace System.Management.Automation.Language

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

Class AstTreeView {
    [object]$mainForm # can't use type [MainForm] due to circular dependency
    [System.Windows.Forms.Control]$container
    [System.Windows.Forms.TreeView]$instance
    [System.Windows.Forms.TreeView]$dummyInstance
    [System.Windows.Forms.Button]$clearFilterButton
    [SearchPanel]$searchPanel
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
        $this.searchPanel = [SearchPanel]::new($this, $this.instance)
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
        $treeView.Tag = $this
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

        $this.InitEvents($treeView) 
        $this.initContextMenu($treeView)                    

        # Dummy TreeView to be used when the real TreeView is not visible
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

        # Clear filter button
        $this.clearFilterButton = [System.Windows.Forms.Button]::new()
        $this.clearFilterButton.Tag = $this
        $this.clearFilterButton.Name
        $this.clearFilterButton.Width = 100
        $this.clearFilterButton.Top = 10
        $this.clearFilterButton.Visible = $false
        $this.clearFilterButton.Text = "Clear filter"
        $this.clearFilterButton.Left = $this.container.ClientSize.Width - $this.clearFilterButton.Width - 10
        $this.clearFilterButton.ForeColor = [System.Drawing.Color]::Blue
        $this.clearFilterButton.Anchor = "Top, Right"
        $this.clearFilterButton.Add_Click({
                param($s, $e)
                $self = $s.Tag
                $self.clearFilterButton.Visible = $false
                $self.mainForm.onFilterCleared()
            })
        $this.container.Controls.Add($this.clearFilterButton)

        return $treeView
    }

    [void]initEvents( [System.Windows.Forms.TreeView]$treeView) {
        $treeView.Add_AfterSelect({
                param($s, $e)
                $self = $s.Tag
                $node = $e.Node
                $keepCaretPos = $false
                if ($self.isUpdatedFromViewBox) { $keepCaretPos = $true }
                $self.mainForm.onAstNodeSelected($node.Tag.Ast, $node.Tag.Index, $keepCaretPos)
            })

        $treeView.Add_NodeMouseClick({
                param($s, $e)
                $self = $s.Tag
                if ($e.Button -eq [System.Windows.Forms.MouseButtons]::Right) { $self.instance.SelectedNode = $e.Node }
            })

        $treeView.Add_DrawNode({
                param($s, $e)
                if ($s.Tag.inUpdate) { return }
                $s.Tag.nodeDrawer.drawNode($s, $e, $e.Node.Tag.NameParts)
            })

        $treeView.Add_KeyDown({
                param($s, $e)
                $self = $s.Tag

                if ($e.Control -and $e.KeyCode -eq 70) {
                    # F key
                    $selText = $self.getSelectedText().trim()
                    if ($self.searchPanel.isVisible() -and -not $selText) { return }
                    $self.searchPanel.show($true, $selText)
                    $e.Handled = $true
                    $e.SuppressKeyPress = $true
                }
                elseif ($e.KeyCode -eq 27) {
                    # Escape key
                    if (-not $self.searchPanel.isVisible()) { return }
                    $self.searchPanel.show($false)
                }
            })
    }


    [void]initContextMenu([System.Windows.Forms.TreeView]$treeView) {
        $menu = [System.Windows.Forms.ContextMenuStrip]::new()

        $showFindAllUnnested = $menu.Items.Add("Shallow FindAll Result")
        $showFindAllUnnested.Add_Click({ 
                param($s, $e)
                # sender is a ToolStripMenuItem; get its ContextMenuStrip (owner)
                $cms = $s.GetCurrentParent()
                $ctrl = $cms.SourceControl
                $node = $ctrl.SelectedNode
                if (-not $node) { return }

                $self = $ctrl.Tag
                $curAst = $node.Tag.Ast
                $self.mainForm.filterByFindAllCommand($curAst, $false)
            })

        $treeView.ContextMenuStrip = $menu
    }

    [void]setAstModel([AstModel]$astModel, [ProgressBar]$pb) {
        $this.freezeUpdates($true)
        $this.astModel = $astModel
        $this.FillTreeView($astModel, $pb)
        #$this.instance.ExpandAll()
        $this.clearFilterButton.Visible = $null -ne $this.mainForm.filteredAstModel

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

    [string]getSelectedText() {
        if ($this.instance.SelectedNode -and $this.instance.SelectedNode.Tag) {
            return $this.instance.SelectedNode.Tag.Ast.GetType().Name
        }
        return ""
    }

    [void]onSearch([string]$text, [string]$direction) {
        $this.onSearch($text, $direction, $false)
    }

    [void]onSearch([string]$text, [string]$direction, [bool]$keepScrollPos) {
        if (-not $text) { return }

        # Determine initial start node
        [System.Windows.Forms.TreeNode] $initialStart = $null

        $initialStart = $this.instance.SelectedNode
        switch ($direction) {
            "" {
                # Search inclusive from current node
                if (-not $initialStart) { $initialStart = $this.getFirstNode($null) }
            }
            "next" {
                if ($initialStart) { $initialStart = $this.getNextNode($initialStart) }
                # Wrap to beginning
                if (-not $initialStart) { $initialStart = $this.getFirstNode($null) }
            }
            "prev" {
                if ($initialStart) { $initialStart = $this.getPrevNode($initialStart) }
                # Wrap to end
                if (-not $initialStart) { $initialStart = $this.GetLastNode($null) }
            }
            default {
                $initialStart = $this.getFirstNode($null)
            }
        }

        if (-not $initialStart) { return }

        [StringComparison] $ignoreCase = [StringComparison]::InvariantCultureIgnoreCase
                
        # Start searching with wrap-around
        [System.Windows.Forms.TreeNode] $current = $initialStart
        [System.Windows.Forms.TreeNode] $stopNode = $initialStart
        [System.Windows.Forms.TreeNode] $foundNode = $null

        $isPrev = ($direction -eq "prev")

        while ($current) {
            if ($current.Text.IndexOf($text, 0, $ignoreCase) -ge 0) { $foundNode = $current; break }

            # Move
            if ($isPrev) {
                $current = $this.getPrevNode($current)
                if (-not $current) { $current = $this.GetLastNode($null) }
            }
            else {
                $current = $this.getNextNode($current)
                if (-not $current) { $current = $this.getFirstNode($null) }
            }

            # Stop if full wrap-around
            if ($current -eq $stopNode) { break }
        }

        if ($foundNode) {
            $this.instance.SelectedNode = $foundNode
            $foundNode.EnsureVisible()
        }
    }

    
   
    # Get last deepest node of the provided node. If no node is provided, the last node in the tree is returned
    [System.Windows.Forms.TreeNode] GetLastNode([System.Windows.Forms.TreeNode] $node) {
        $current = $node
        if (-not $current) { 
            $current = $this.instance 
            if ($current.Nodes.Count -eq 0) { return $null }
        }

        # Go down to the last child repeatedly
        while ($current.Nodes.Count -gt 0) {
            $current = $current.Nodes[$current.Nodes.Count - 1]
        }

        return $current
    }

    [System.Windows.Forms.TreeNode] getFirstNode([System.Windows.Forms.TreeNode] $node) {
        $current = $node
        if (-not $current) { $current = $this.instance }

        if ($current.Nodes.Count -eq 0) { return $null }
        return $current.Nodes[0]

    }

    # Get previous node of the provided node. If no node is provided, the last node in the tree is returned
    [System.Windows.Forms.TreeNode] getPrevNode([System.Windows.Forms.TreeNode] $node) {
        if (-not $node) { return $this.GetLastNode($null) }

        [System.Windows.Forms.TreeNode] $prev = $node.PrevNode
        if ($prev) { return $this.GetLastNode($prev) }
        return $node.Parent
    }

    [System.Windows.Forms.TreeNode] getNextNode([System.Windows.Forms.TreeNode] $node) {
        if (-not $node) { return $this.getFirstNode($null) }

        # if node has children, return first child
        if ($node.Nodes.Count -gt 0) { return $node.Nodes[0] }

        # go to the next sibling or bubble up
        [System.Windows.Forms.TreeNode] $current = $node

        while ($current) {
            if ($current.NextNode) { return $current.NextNode }
            # No sibling found - bubble up
            $current = $current.Parent
        }

        return $null
    }
}