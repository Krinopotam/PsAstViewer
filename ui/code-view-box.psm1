using module .\progress-bar.psm1
using module ..\models\ast-model.psm1
using module .\search-panel.psm1
using module .\code-status-bar.psm1
using module ..\utils\debounce.psm1
using namespace System.Management.Automation.Language

Class CodeViewBox {
    # Main form instance
    [object]$mainForm # can't use type [MainForm] due to circular dependency
    # Parent container instance
    [System.Windows.Forms.Control]$container
    # RichTextBox instance
    [System.Windows.Forms.RichTextBox]$instance
    # Search panel instance
    [SearchPanel]$searchPanel
    # Code status bar instance
    [CodeStatusBar]$codeStatusBar
    # Debounce class instance for CodeStatusBar
    [Debounce]$statusDebounce
    # Current Ast model
    [AstModel]$astModel
    # Current selected Ast node
    [Ast]$selectedAst
    # Current selected secondary Ast node
    [Ast]$selectedAstSecondary
    # Current found block (substring) info {text, start, end}
    [hashtable]$foundBlock
    # Current entered text
    [string]$currentText
    # Flag to suppress TextChanged event
    [bool]$suppressTextChanged
    # Flag to suppress SelectionChanged event
    [bool]$suppressSelectionChanged
    # Flag to indicate if CodeViewBox is focused
    [bool]$isFocused
    
    CodeViewBox([object]$mainForm, [System.Windows.Forms.Control]$container) {
        $this.mainForm = $mainForm
        $this.container = $container
        $this.statusDebounce = [Debounce]::new(100)
        $this.instance = $this.Init()
        $this.searchPanel = [SearchPanel]::new($this, $this.instance)
    }    

    [System.Windows.Forms.RichTextBox]Init() {
        $label = [System.Windows.Forms.Label]::new()
        $label.Name = "lblCodeViewBox"
        $label.Text = "Code View"
        $label.Top = 20
        $label.Left = 2
        $label.Height = 20
        $label.Width = 60
        $this.container.Controls.Add($label)

        $textBox = [System.Windows.Forms.RichTextBox]::new()
        $textBox.Name = "txtCodeViewBox"
        $textBox.Top = $label.Bottom
        $textBox.Left = 2
        $textBox.Height = $this.container.ClientSize.Height - $label.Bottom - 25
        $textBox.Width = $this.container.ClientSize.Width - 12
        $textBox.Multiline = $true          
        $textBox.WordWrap = $true
        $textBox.Font = [System.Drawing.Font]::new("Courier New", 12)
        $textBox.ScrollBars = "Both";
        $textBox.WordWrap = $false;
        $textBox.Anchor = "Top, Bottom, Left, Right"
        $textBox.Tag = $this
        $this.container.Controls.Add($textBox)

        $this.codeStatusBar = [CodeStatusBar]::new($this.mainForm, $this.container, $this)

        $btnLoadScript = [System.Windows.Forms.Button]::new()
        $btnLoadScript.Text = "Load Script"
        $btnLoadScript.Width = 80
        $btnLoadScript.Height = 25
        $btnLoadScript.Top = 10
        $btnLoadScript.Left = $this.container.ClientSize.Width - $btnLoadScript.Width - 10
        $btnLoadScript.Anchor = "Top, Right"
        $btnLoadScript.Tag = $this
        $btnLoadScript.Add_Click({
                param($s, $e)
                $self = $s.Tag
                $self.mainForm.openScript()
            })
        $this.container.Controls.Add($btnLoadScript)

        $menu = [System.Windows.Forms.ContextMenuStrip]::new()

        $findInAstItem = $menu.Items.Add("Find in AST Tree View   (ctrl+click)")
        $findInAstItem.Add_Click({ 
                param($s, $e)
                # sender is a ToolStripMenuItem; get its ContextMenuStrip (owner)
                $cms = $s.GetCurrentParent()
                $rtb = $cms.SourceControl
                $charPos = $rtb.SelectionStart
                $rtb.Tag.selectAstNodeByCharPos($charPos)
            })

        # Навешиваем меню
        $textBox.ContextMenuStrip = $menu

        $this.initEvents($textBox)

        return $textBox
    }

    [void]initEvents([System.Windows.Forms.RichTextBox]$textBox) {
        $textBox.add_SelectionChanged({
                param($s, $e)
                if ($s.Tag.suppressSelectionChanged) { return }
                $s.Tag.statusDebounce.run({ param($self, [int]$pos) $self.showCurrentToken($pos) }, @($s.Tag, $s.SelectionStart))
            })

        $textBox.add_TextChanged({
                param($s, $e)
                $self = $s.Tag
                if ($self.currentText -eq $s.Text) { return }
                $self.currentText = $s.Text
                $self.searchPanel.invokeDebouncedSearch("Current", $true)
            })

        $textBox.Add_Leave({
                param($s, $e)
                $self = $s.Tag
                $self.isFocused = $false
                $self.highlightText($null)
                if (-not $self.isCodeChanged()) { return }
                
                if ($self.currentText) {
                    $result = [System.Windows.Forms.MessageBox]::Show("Script text has changed. Recreate AST tree or cancel changes?",
                        "Confirm",
                        [System.Windows.Forms.MessageBoxButtons]::OKCancel,
                        [System.Windows.Forms.MessageBoxIcon]::Question
                    )

                    if ($result -eq [System.Windows.Forms.DialogResult]::OK) { $self.mainForm.onCodeChanged($self.currentText) }
                    else { $self.instance.Text = $self.astModel.script }
                }
                else {
                    $self.mainForm.onCodeChanged($self.currentText)
                }

            })

        $textBox.Add_GotFocus({
                param($s, $e)
                $self = $s.Tag
                $self.isFocused = $true
                $self.highlightText($null)
            })

        $textBox.Add_MouseDown({
                param($s, $e)

                $self = $s.Tag
                $ctrl = $self.mainForm.ctrlPressed
                if ($e.Button -eq [System.Windows.Forms.MouseButtons]::Left -and $ctrl) {
                    $charPos = $s.GetCharIndexFromPosition($e.Location) + $self.mainForm.filteredOffset
                    $self.selectAstNodeByCharPos($charPos )
                }

                if ($e.Button -eq [System.Windows.Forms.MouseButtons]::Right) {
                    $charIndex = $s.GetCharIndexFromPosition($e.Location) 
                    if ($charIndex -ge 0 -and $charIndex -lt $s.TextLength -and $s.SelectionLength -eq 0) { $s.Select($charIndex + $self.mainForm.filteredOffset, 0) }
                }
            })

        $textBox.Add_KeyDown({
                param($s, $e)
                $self = $s.Tag

                if ($e.Control -and $e.KeyCode -eq [System.Windows.Forms.Keys]::F) {
                    $selText = $self.getSelectedText().trim()
                    if ($self.searchPanel.isVisible() -and -not $selText) { return }
                    $self.searchPanel.show($true, $selText)
                }
                elseif ($e.KeyCode -eq [System.Windows.Forms.Keys]::Escape) {
                    if (-not $self.searchPanel.isVisible()) { return }
                    $self.searchPanel.show($false)
                }
            })
    }

    [void]setAstModel([AstModel]$astModel, [ProgressBar]$pb) {
        $this.suppressTextChanged = $true
        $this.astModel = $astModel
        $this.instance.Text = $astModel.script
        $this.currentText = $astModel.script
        $this.suppressTextChanged = $false
    }

    [void]onAstNodeSelected([Ast]$ast, [int]$index, [bool]$keepScrollPos) {
        $this.selectedAst = $ast
        $this.selectedAstSecondary = $null
        $scrollBlockType = $null
        if (-not $keepScrollPos) { $scrollBlockType = "PrimaryAst" }
        $this.highlightText($scrollBlockType)
    }

    [void]onParameterSelected([object]$obj, [Ast]$ast) {
        $scrollBlockType = $null
        $this.selectedAstSecondary = $null
        if ($ast) { 
            $this.selectedAstSecondary = $ast 
            $scrollBlockType = "SecondaryAst"
        }
        $this.highlightText($scrollBlockType)
    }

    # Returns array of hashtable {Start, End, Color, BgColor}, calculated from intersecting selectedAst and selectedAstSecondary extents positions
    [hashtable[]]getAstHighlightedBlocks() {
        if (-not $this.selectedAst -and -not $this.selectedAstSecondary) { return @() }

        $primaryColor = [System.Drawing.Color]::FromArgb(0, 120, 215)      # primary
        $secondaryColor = [System.Drawing.Color]::FromArgb(61, 160, 236)   # secondary
        $overlapColor = [System.Drawing.Color]::FromArgb(0, 99, 174)       # overlap

        # Primary range (must exist)
        [int]$primaryStart = 0
        [int]$primaryEnd = 0
        if ($this.selectedAst) {
            [int]$primaryStart = $this.selectedAst.Extent.StartOffset - $this.mainForm.filteredOffset
            [int]$primaryEnd = $this.selectedAst.Extent.EndOffset - $this.mainForm.filteredOffset            
        }

        # Secondary range
        [int]$secondaryStart = 0
        [int]$secondaryEnd = 0
        if ($this.selectedAstSecondary) {
            $secondaryStart = [int]$this.selectedAstSecondary.Extent.StartOffset - $this.mainForm.filteredOffset
            $secondaryEnd = [int]$this.selectedAstSecondary.Extent.EndOffset - $this.mainForm.filteredOffset
        }

        # Only primary highlight
        if ($this.selectedAst -and -not $this.selectedAstSecondary) {
            return @(@{ Type = "PrimaryAst"; Start = $primaryStart; End = $primaryEnd; Color = [System.Drawing.Color]::White; BgColor = $primaryColor })
        }
        
        # Only secondary highlight 
        if ( $this.selectedAstSecondary -and -not $this.selectedAst) {
            return @(@{ Type = "SecondaryAst"; Start = $secondaryStart; End = $secondaryEnd; Color = [System.Drawing.Color]::White; BgColor = $secondaryColor })
        }

        
        # Check overlap
        if ($primaryEnd -lt $secondaryStart -or $secondaryEnd -lt $primaryStart) {
            # No overlap
            return @(
                @{ Type = "PrimaryAst"; Start = $primaryStart; End = $primaryEnd; Color = [System.Drawing.Color]::White; BgColor = $primaryColor },
                @{ Type = "SecondaryAst"; Start = $secondaryStart; End = $secondaryEnd; Color = [System.Drawing.Color]::White; BgColor = $secondaryColor }
            )
        }

        # Case: equal ranges -> return one block
        if ($primaryStart -eq $secondaryStart -and $primaryEnd -eq $secondaryEnd) {
            return @(@{ Type = "OverlapAst"; Start = $primaryStart; End = $primaryEnd; Color = [System.Drawing.Color]::White; BgColor = $overlapColor })
        }

        # Now we know: ranges overlap but are not equal
        [int]$overlapStart = [Math]::Max($primaryStart, $secondaryStart)
        [int]$overlapEnd = [Math]::Min($primaryEnd, $secondaryEnd)

        $result = @()

        # ----- Left block -----
        [int]$leftStart = [Math]::Min($primaryStart, $secondaryStart)
        [int]$leftEnd = $overlapStart

        if ($leftStart -lt $leftEnd) {
            $leftType = if ($primaryStart -lt $secondaryStart) { "PrimaryAst" } else { "SecondaryAst" }
            $leftColor = if ($leftType -eq "PrimaryAst") { $primaryColor } else { $secondaryColor }

            $result += @{ Type = $leftType; Start = $leftStart; End = $leftEnd; Color = [System.Drawing.Color]::White; BgColor = $leftColor }
        }

        # ----- Overlap block -----
        if ($overlapEnd -gt $overlapStart) {
            $result += @{ Type = "OverlapAst"; Start = $overlapStart; End = $overlapEnd; Color = [System.Drawing.Color]::White; BgColor = $overlapColor }
        }

        # ----- Right block -----
        [int]$rightStart = $overlapEnd
        [int]$rightEnd = [Math]::Max($primaryEnd, $secondaryEnd)

        if ($rightStart -lt $rightEnd) {
            $rightType = if ($primaryEnd -gt $secondaryEnd) { "PrimaryAst" } else { "SecondaryAst" }
            $rightColor = if ($rightType -eq "PrimaryAst") { $primaryColor } else { $secondaryColor }
            $result += @{Type = $rightType; Start = $rightStart; End = $rightEnd; Color = [System.Drawing.Color]::White; BgColor = $rightColor }
        }

        return $result
    }

    # Merge Ast positions blocks with found block. Found block has higher priority
    [hashtable[]] MergeFoundBlock([hashtable[]] $astBlocks, [hashtable] $foundBlock) {

        # If no found block -> return original
        if (-not $foundBlock) { return $astBlocks }

        [int]$foundStart = $foundBlock.Start
        [int]$foundEnd = $foundBlock.End

        $result = @()

        foreach ($block in $astBlocks) {

            [int]$bStart = $block.Start
            [int]$bEnd = $block.End

            # ---- No overlap ----
            if ($bEnd -le $foundStart -or $foundEnd -le $bStart) {
                # keep block unchanged
                $result += $block
                continue
            }

            # ---- Found fully covers block and skip it ----
            if ($foundStart -le $bStart -and $foundEnd -ge $bEnd) { continue }

            # ---- Partial overlap: split into left and right parts ----

            # Left part (block before found)
            if ($bStart -lt $foundStart) { $result += @{Type = $block.Type; Start = $bStart; End = $foundStart; Color = $block.Color; BgColor = $block.BgColor; } }

            # Right part (block after found)
            if ($bEnd -gt $foundEnd) { $result += @{Type = $block.Type; Start = $foundEnd; End = $bEnd; Color = $block.Color; BgColor = $block.BgColor } }
        }

        # Add found block itself (priority)
        $result += $foundBlock

        # Sort final output
        return $result | Sort-Object Start
    }

    # Highlight text
    [void]highlightText([string]$scrollToBlock = $null) {
        $this.suppressSelectionChanged = $true
        $rtb = $this.instance

        $currentPos = $rtb.SelectionStart
        $scrollPos = $this.GetScrollPos()
        $this.DisableRedraw()

        # Reset previous highlighting
        $rtb.SelectAll()
        $rtb.SelectionBackColor = [System.Drawing.Color]::White
        $rtb.SelectionColor = [System.Drawing.Color]::Black
        $rtb.DeselectAll()

        $blocks = @()
        if (-not $this.isFocused) { $blocks = $this.getAstHighlightedBlocks() }
        if ($this.foundBlock) { $blocks = $this.MergeFoundBlock($blocks, $this.foundBlock) }
        
        foreach ($block in $blocks) {
            if ($scrollToBlock -and $block.Type -eq $scrollToBlock) { $currentPos = $block.Start }
            $rtb.Select($block.Start, $block.End - $block.Start)
            $rtb.SelectionBackColor = $block.BgColor
            $rtb.SelectionColor = $block.Color
        }
        $rtb.DeselectAll()
        $rtb.Select($currentPos, 0)
        if ($scrollToBlock) { $this.ScrollToCaret() }
        else { $this.SetScrollPos($scrollPos) }

        $this.EnableRedraw()
        $this.suppressSelectionChanged = $false
    }

    # Get current scroll position
    [hashtable]GetScrollPos() {
        $wmUser = 0x400
        $emGetScrollPos = $wmUser + 221
        # Allocate 8 bytes for POINT structure (x, y)
        $ptr = [System.Runtime.InteropServices.Marshal]::AllocHGlobal(8)
        [void][Win32]::SendMessage($this.instance.Handle, $emGetScrollPos, 0, $ptr)

        # read 2 Int32 from memory
        $x = [System.Runtime.InteropServices.Marshal]::ReadInt32($ptr, 0)
        $y = [System.Runtime.InteropServices.Marshal]::ReadInt32($ptr, 4)

        [System.Runtime.InteropServices.Marshal]::FreeHGlobal($ptr)
        return @{X = $x; Y = $y }
    }

    # Set scroll position
    [void]SetScrollPos([hashtable]$scrollPos) {
        $wmUser = 0x400
        $emSetScrollPos = $wmUser + 222
        # Allocate 8 bytes for POINT structure (x, y)
        $ptr = [System.Runtime.InteropServices.Marshal]::AllocHGlobal(8)

        # write 2 Int32 to memory
        [System.Runtime.InteropServices.Marshal]::WriteInt32($ptr, 0, $scrollPos.X)
        [System.Runtime.InteropServices.Marshal]::WriteInt32($ptr, 4, $scrollPos.Y)

        [void][Win32]::SendMessage($this.instance.Handle, $emSetScrollPos, 0, $ptr)
        [System.Runtime.InteropServices.Marshal]::FreeHGlobal($ptr)
    }
   
    # Disable richTextBox redraw
    [void]DisableRedraw() {
        $this.instance.SuspendLayout()
        $wmSetRedraw = 0xB
        [Win32]::SendMessage($this.instance.Handle, $wmSetRedraw, $false, 0)

    }

    # Enable richTextBox redraw
    [void]EnableRedraw() {
        $wmSetRedraw = 0xB
        [Win32]::SendMessage($this.instance.Handle, $wmSetRedraw, $true, 0)
        $this.instance.ResumeLayout()
        $this.instance.Refresh()
    }

    # Scroll richTextBox to caret. Keep scroll if caret is visible
    [void]ScrollToCaret() {
        # Get caret position in pixels relative to the RichTextBox control
        $pt = $this.instance.GetPositionFromCharIndex($this.instance.SelectionStart)

        # Visible area size
        $clientW = $this.instance.ClientSize.Width
        $clientH = $this.instance.ClientSize.Height

        $visibleY = ($pt.Y -ge 0 -and $pt.Y -lt $clientH)
        $visibleX = ($pt.X -ge 0 -and $pt.X -lt $clientW)

        if ($visibleX -and $visibleY) { return }
        $this.instance.ScrollToCaret()
    }
  
    # Find AST node by char position
    [void]selectAstNodeByCharPos([int]$charPos) {
        $this.mainForm.selectAstNodeByCharPos($charPos)
    }

    [void]onSearch([string]$text, [string]$direction) { 
        $this.onSearch($text, $direction, $false)
    }

    # Search substring
    [void]onSearch([string]$text, [string]$direction, [bool]$keepScrollPos) {
        if (-not $text) { 
            $this.foundBlock = $null
            $this.highlightText($null)
            return 
        }

        $full = $this.instance.Text
        if (-not $full) { return }
   
        $curr = $this.instance.SelectionStart
        if ($direction -eq "Current" -and $this.foundBlock) { 
            $curr =[Math]::Min($curr,  $this.foundBlock.Start) 
            $direction=""
        }

        $index = -1

        [StringComparison] $ignoreCase = [StringComparison]::InvariantCultureIgnoreCase
        switch ($direction) {

            '' {
                # first search from beginning
                $index = $full.IndexOf($text, $curr, $ignoreCase)
                if ($index -lt 0) { $index = $full.IndexOf($text, 0, $ignoreCase) }
            }

            'next' {
                $start = $curr + 1
                if ($start -ge $full.Length) { $start = 0 }
                $index = $full.IndexOf($text, $start, $ignoreCase)
                if ($index -lt 0) { $index = $full.IndexOf($text, 0, $ignoreCase) }
            }

            'prev' {
                $start = $curr - 1
                if ($start -lt 0) { $start = $full.Length - 1 }
                $index = $full.LastIndexOf($text, $start, $ignoreCase)
                if ($index -lt 0) { $index = $full.LastIndexOf($text, $full.Length - 1, $ignoreCase) }
            }
        }

        if ($index -ge 0) { 
            $this.foundBlock = @{ Type = "Found"; Start = $index; End = $index + $text.Length; Color = [System.Drawing.Color]::Black; BgColor = [System.Drawing.Color]::FromArgb(255, 245, 170) }
        }
        else {
            $this.foundBlock = $null
        }

        $scrollToBlock = $null
        if (-not $keepScrollPos) { $scrollToBlock = "Found" }
        $this.highlightText($scrollToBlock)
    }

    # Get selected text in richTextBox
    [string]getSelectedText() {
        $res = $this.instance.SelectedText
        if (-not $res) { $res = "" }
        return $res
    }

    # Show current token in status bar
    [void]showCurrentToken([int]$charIndex) {
        if ($this.isCodeChanged()) { 
            $this.codeStatusBar.update("Code changed, Ast needs to be rebuilt")
            return 
        }

        if (-not $this.astModel) { return }

        $token = $this.astModel.GetTokenByCharIndex($charIndex)
        $tokenName = ""
        $tokenFlags = ""
        if ($token) {
            $tokenName = "      Token: [$($token.Kind)]"
            if ($token.TokenFlags) { 
                $tokenFlags = $token.TokenFlags -join ", " 
                $tokenFlags = "      Flags: [$tokenFlags]"
            }
        }

        $this.codeStatusBar.update("Position: $charIndex$tokenName$tokenFlags")
    }

    # Returns true if text changed and Ast tree needs to be rebuilt
    [bool]isCodeChanged() {
        return $this.currentText -ne $this.astModel.script
    }

}
 