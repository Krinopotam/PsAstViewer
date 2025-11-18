using module .\progress-bar.psm1
using module ..\models\ast-model.psm1
using module .\search-panel.psm1
using namespace System.Management.Automation.Language

Class CodeViewBox {
    [object]$mainForm # can't use type [MainForm] due to circular dependency
    [System.Windows.Forms.Control]$container
    [System.Windows.Forms.RichTextBox]$instance
    [AstModel]$astModel
    [Ast]$selectedAst
    [Ast]$selectedAstSecondary
    [string]$currentText
    [bool]$suppressTextChanged
    [SearchPanel]$searchPanel
    
    CodeViewBox([object]$mainForm, [System.Windows.Forms.Control]$container) {
        $this.mainForm = $mainForm
        $this.container = $container
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
        $textBox.Height = $this.container.ClientSize.Height - $label.Bottom - 10
        $textBox.Width = $this.container.ClientSize.Width - 12
        $textBox.Multiline = $true          
        $textBox.WordWrap = $true
        $textBox.Font = [System.Drawing.Font]::new("Courier New", 12)
        $textBox.ScrollBars = "Both";
        $textBox.WordWrap = $false;
        $textBox.Anchor = "Top, Bottom, Left, Right"
        $textBox.Tag = $this
        $this.container.Controls.Add($textBox)

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

        $menu = New-Object System.Windows.Forms.ContextMenuStrip

        $findInAstItem = $menu.Items.Add("Find in AST Tree View   (ctrl+click)")
        $findInAstItem.Add_Click({ 
                param($s, $e)
                # sender is a ToolStripMenuItem; get its ContextMenuStrip (owner)
                $cms = $s.GetCurrentParent()
                $rtb = $cms.SourceControl
                $charIndex = $rtb.SelectionStart
                $rtb.Tag.onCharIndexSelected($charIndex)
            })

        # Навешиваем меню
        $textBox.ContextMenuStrip = $menu

        $textBox.add_TextChanged({
                param($s, $e)
                $self = $s.Tag
                if ($self.suppressTextChanged) { return }
                $self.currentText = $s.Text
            })

        $textBox.Add_Leave({
                param($s, $e)
                $self = $s.Tag
                if ($self.currentText -ne $self.astModel.script) {
                    if ($self.currentText) {
                        $result = [System.Windows.Forms.MessageBox]::Show("Script text has changed. Recreate AST tree or cancel changes?",
                            "Confirm",
                            [System.Windows.Forms.MessageBoxButtons]::OKCancel,
                            [System.Windows.Forms.MessageBoxIcon]::Question
                        )

                        if ($result -eq [System.Windows.Forms.DialogResult]::OK) { $self.mainForm.onCodeChanged($self.currentText) }
                        else { $self.instance.Text = $self.astModel.script }
                    }
                    return
                }
            })

        $textBox.Add_GotFocus({
                param($s, $e)
                $rtb = $s.Tag.instance
                $selStart = $rtb.SelectionStart
                $selLength = $rtb.SelectionLength

                # Highlight reset (set background for all text)
                $rtb.SelectAll()
                $rtb.SelectionColor = [System.Drawing.Color]::Black
                $rtb.SelectionBackColor = [System.Drawing.Color]::White

                # Return cursor position
                $rtb.Select($selStart, $selLength)
            })

        $textBox.Add_MouseDown({
                param($s, $e)

                $self = $s.Tag
                $ctrl = $self.mainForm.ctrlPressed
                if ($e.Button -eq [System.Windows.Forms.MouseButtons]::Left -and $ctrl) {
                    $charIndex = $s.GetCharIndexFromPosition($e.Location)
                    $self.onCharIndexSelected($charIndex + $self.mainForm.filteredOffset)
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
                    $self = $s.Tag
                    $self.searchPanel.toggle()
                }
            })


        return $textBox
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
        $this.highlightText(-not $keepScrollPos)
    }

    [void]onParameterSelected([object]$obj, [Ast]$ast) {
        if ($ast) { $this.selectedAstSecondary = $ast }
        else { $this.selectedAstSecondary = $null }
        $this.highlightText($true)
    }

    [void]highlightText($scrollToCaret = $true) {
        $rtb = $this.instance

        $scrollPos = $this.GetScrollPos()
        $this.DisableRedraw()

        # Colors
        <# Green
        $primaryColor = [System.Drawing.Color]::FromArgb(0, 100, 0)     # primary
        $secondaryColor = [System.Drawing.Color]::FromArgb(1, 214, 65)   # secondary
        $mixedColor = [System.Drawing.Color]::FromArgb(0, 172, 52)     # overlap #>
        
        # Blue
        $primaryColor = [System.Drawing.Color]::FromArgb(0, 0, 150)       # primary
        $secondaryColor = [System.Drawing.Color]::FromArgb(35, 150, 230)    # secondary
        $mixedColor = [System.Drawing.Color]::FromArgb(20, 95, 210)     # overlap

        # Reset previous highlighting
        $rtb.SelectAll()
        $rtb.SelectionBackColor = [System.Drawing.Color]::White
        $rtb.SelectionColor = [System.Drawing.Color]::Black
        $rtb.DeselectAll()

        if ($null -eq $this.selectedAst) { return }

        # Primary range (must exist)
        [int]$primaryStart = $this.selectedAst.Extent.StartOffset - $this.mainForm.filteredOffset
        [int]$primaryEnd = $this.selectedAst.Extent.EndOffset - $this.mainForm.filteredOffset

        # Secondary range
        [int]$secondaryStart = 0
        [int]$secondaryEnd = 0
        if ($this.selectedAstSecondary) {
            $secondaryStart = [int]$this.selectedAstSecondary.Extent.StartOffset - $this.mainForm.filteredOffset
            $secondaryEnd = [int]$this.selectedAstSecondary.Extent.EndOffset - $this.mainForm.filteredOffset
        }

        # Only primary highlight and exit
        if (-not $this.selectedAstSecondary) {
            $this.SelectAndColor($primaryStart, $primaryEnd - $primaryStart, $primaryColor, [System.Drawing.Color]::White)
            if ($scrollToCaret) { $this.ScrollToCaret() }
            $rtb.DeselectAll()

            if (-not $scrollToCaret) { $this.RestoreScrollPos($scrollPos) }

            $this.EnableRedraw()
            return
        }

        # Compute overlap (safe: secondaryStart/End are initialized above)
        #[int]$minStart = [Math]::Min($primaryStart, $secondaryStart)
        [int]$overlapStart = [Math]::Max($primaryStart, $secondaryStart)
        [int]$overlapEnd = [Math]::Min($primaryEnd, $secondaryEnd)
        [bool]$hasOverlap = $overlapEnd -gt $overlapStart

        # Paint order: primary -> secondary -> overlap
        $this.SelectAndColor($primaryStart, $primaryEnd - $primaryStart, $primaryColor, [System.Drawing.Color]::White)
        $this.SelectAndColor($secondaryStart, $secondaryEnd - $secondaryStart, $secondaryColor, [System.Drawing.Color]::White)
        if ($hasOverlap) { $this.SelectAndColor($overlapStart, $overlapEnd - $overlapStart, $mixedColor, [System.Drawing.Color]::White) }
        
        $rtb.select($primaryStart, 0) # move caret to the start of the first highlight
        if ($scrollToCaret) { $this.ScrollToCaret() }
        else { $this.RestoreScrollPos($scrollPos) }

        $this.EnableRedraw()
    }

    [void]selectAndColor([int]$start, [int]$length, [System.Drawing.Color]$backColor, [System.Drawing.Color]$foreColor) {
        $textLen = $this.instance.TextLength
        if ($textLen -le 0) { return }

        $start = [Math]::Max(0, [Math]::Min($start, $textLen))
        $length = [Math]::Max(0, [Math]::Min($length, $textLen - $start))
        if ($length -le 0) { return }

        $this.instance.Select($start, $length)
        $this.instance.SelectionBackColor = $backColor
        $this.instance.SelectionColor = $foreColor
    } 

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

    [void]RestoreScrollPos([hashtable]$scrollPos) {
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
   
    [void]DisableRedraw() {
        $this.instance.SuspendLayout()
        $wmSetRedraw = 0xB
        [Win32]::SendMessage($this.instance.Handle, $wmSetRedraw, $false, 0)

    }
    [void]EnableRedraw() {
        $wmSetRedraw = 0xB
        [Win32]::SendMessage($this.instance.Handle, $wmSetRedraw, $true, 0)
        $this.instance.ResumeLayout()
        $this.instance.Refresh()
    }

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
  
    [void]onCharIndexSelected([int]$charIndex) {
        $this.mainForm.onCharIndexSelected($charIndex)
    }

    [void]onSearch([string]$text, [string]$direction) {
        if ([string]::IsNullOrWhiteSpace($text)) { return }

        $full = $this.instance.Text
        if ([string]::IsNullOrEmpty($full)) { return }

        # Reset if new search text
        <#         if ($this.LastText -ne $text) {
            $this.LastText = $text
            # move cursor to top so search always starts clean
            $this.instance.SelectionStart = 0
        } #>
        

        $curr = $this.instance.SelectionStart
        $index = -1

        switch ($direction) {

            '' {
                # first search from beginning
                $index = $full.IndexOf($text, $curr, [StringComparison]::'InvariantCultureIgnoreCase')
            }

            'next' {
                $start = $curr + 1
                if ($start -ge $full.Length) { $start = 0 }
                $index = $full.IndexOf($text, $start, [StringComparison]::'InvariantCultureIgnoreCase')
                if ($index -lt 0) { $index = $full.IndexOf($text, 0, [StringComparison]::'InvariantCultureIgnoreCase') }
            }

            'prev' {
                $start = $curr - 1
                if ($start -lt 0) { $start = $full.Length - 1 }
                $index = $full.LastIndexOf($text, $start, [StringComparison]::'InvariantCultureIgnoreCase')
                if ($index -lt 0) { $index = $full.LastIndexOf($text, $full.Length - 1, [StringComparison]::'InvariantCultureIgnoreCase') }
            }
        }

        if ($index -lt 0) { return }

        # highlight found match
        $this.instance.SelectAll()
        $this.instance.SelectionBackColor = [System.Drawing.Color]::White

        $this.instance.Select($index, $text.Length)
        $this.instance.SelectionBackColor = [System.Drawing.Color]::Yellow
        $this.instance.ScrollToCaret()




        <#         $this.DisableRedraw()
        $rtb = $this.instance
        $rtb.SelectAll()
        $rtb.SelectionBackColor = [System.Drawing.Color]::White

        $search = $text
        if ([string]::IsNullOrWhiteSpace($search)) { return }

        # Find all occurrences
        $startIndex = 0
        while ($true) {
            # Find next index
            $index = $rtb.Text.IndexOf($search, $startIndex, [StringComparison]::InvariantCultureIgnoreCase)

            if ($index -lt 0) { break }

            # Highlight match
            $rtb.Select($index, $search.Length)
            $rtb.SelectionBackColor = [System.Drawing.Color]::Yellow

            # Move past the current match
            $startIndex = $index + $search.Length
        }

        # Reset selection
        $rtb.Select(0, 0)
        $this.EnableRedraw() #>
    }

}
 