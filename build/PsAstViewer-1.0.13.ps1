###################################### PsAstViewer #######################################
#Author: Zaytsev Maksim
#Version: 1.0.13
#requires -Version 5.1
##########################################################################################

using assembly System.Windows.Forms
using assembly System.Drawing

using namespace System.Management.Automation.Language
using namespace System.Windows.Forms
using namespace System.Drawing

[CmdletBinding()]
param([string]$path = "")

Add-Type @"
using System;
using System.Runtime.InteropServices;
public class Win32 {
    [DllImport("user32.dll", CharSet = CharSet.Auto)]
    public static extern IntPtr SendMessage(IntPtr hWnd, int msg, int wParam, IntPtr lParam);
}
"@
Add-Type @"
using System;
using System.Runtime.InteropServices;
public static class Keyboard {
    [DllImport("user32.dll")]
    public static extern short GetAsyncKeyState(int key);
}
"@

$__CLASSES_SOURCE_ad0457f118e34fb6bd0df8542399ea77 = @'
class RunApp {
    RunApp([string]$version, [string]$Path) {
        if ($Path) {
            if (-not (Test-Path -LiteralPath $Path)) {
                Write-Host "File not found: $Path" -ForegroundColor Red
                exit 1
            }
            $path = Resolve-Path -LiteralPath $Path
        }
           
        $mainForm = [MainForm]::new($version)
        $mainForm.Show($path)
    }
}

class MainForm {    
    [System.Windows.Forms.Form]$instance    
    [System.Windows.Forms.Panel]$leftTopPanel    
    [System.Windows.Forms.Panel]$leftBottomPanel    
    [System.Windows.Forms.Panel]$rightPanel    
    [CodeViewBox]$codeViewBox    
    [AstTreeView]$astTreeView    
    [AstPropertyView]$astPropertyView    
    [AstModel]$astModel    
    [AstModel]$loadedAstModel    
    [AstModel]$filteredAstModel    
    [string]$lastLoadedPath    
    [bool]$ctrlPressed = $false    
    [bool]$altPressed = $false    
    [bool]$shiftPressed = $false    
    [hashtable]$astColorsMap    
    [int]$filteredOffset = 0    
    [string]$version
    
    MainForm([string]$version) {
        $this.version = $version
        $astColorsGenerator = [AstColorsGenerator]::new()
        $this.astColorsMap = $astColorsGenerator.GetColorsMap()
        $this.instance = $this.Init()
    }    

    [System.Windows.Forms.Form]Init() {
        $form = [System.Windows.Forms.Form]::new()
        $form.Tag = $this                
        $icon = $this.getIcon()
        $form.Icon = $icon
        $form.Text = "Ast Viewer v.$($this.version)"
        $form.Size = New-Object System.Drawing.Size(1200, 800)
        $form.StartPosition = "CenterScreen"
        $form.WindowState = [System.Windows.Forms.FormWindowState]::Normal
        $form.KeyPreview = $true
        $form.Add_KeyDown({
                param($s, $e)
                $self = $s.Tag
                if ($e.Control) { $self.ctrlPressed = $true }
                if ($e.Alt) { $self.altPressed = $true }
                if ($e.Shift) { $self.shiftPressed = $true }
            })

        $form.Add_KeyUp({
                param($s, $e)
                $self = $s.Tag
                if (-not $e.Control) { $self.ctrlPressed = $false }
                if (-not $e.Alt) { $self.altPressed = $false }
                if (-not $e.Shift) { $self.shiftPressed = $false }
            })

        $form.Add_Shown({
                param($s, $e)
                $self = $s.Tag
                                
                $self.instance.Activate()
                $self.instance.TopMost = $true
                Start-Sleep -Milliseconds 100
                $self.instance.TopMost = $false

                if ($self.lastLoadedPath) { $self.loadScript($self.lastLoadedPath) }
            })
        
        $rootSplitContainer = [System.Windows.Forms.SplitContainer]::new()
        $rootSplitContainer.Name = "rootSplitContainer"
        $rootSplitContainer.Dock = 'Fill'
        $rootSplitContainer.Orientation = 'Vertical' 

        $form.Controls.Add($rootSplitContainer)

        $leftPanel = [System.Windows.Forms.Panel]::new()
        $leftPanel.Name = "leftPanel"
        $leftPanel.Dock = 'Fill'        
        $rootSplitContainer.Panel1.Controls.Add($leftPanel)

        $this.rightPanel = [System.Windows.Forms.Panel]::new()
        $this.rightPanel.Name = "rightPanel"
        $this.rightPanel.Dock = 'Fill'        
        $rootSplitContainer.Panel2.Controls.Add($this.rightPanel)

        [void]$rootSplitContainer.Handle
        [void]$leftPanel.Handle 
        [void]$this.rightPanel.Handle 
        $rootSplitContainer.SplitterDistance = 600        
        
        $leftSplitContainer = [System.Windows.Forms.SplitContainer]::new()
        $leftSplitContainer.Name = "leftSplitContainer"
        $leftSplitContainer.Dock = 'Fill'
        $leftSplitContainer.Orientation = 'Horizontal' 

        $leftPanel.Controls.Add($leftSplitContainer)

        $this.leftTopPanel = [System.Windows.Forms.Panel]::new()
        $this.leftTopPanel.Name = "leftTopPanel"
        $this.leftTopPanel.Dock = 'Fill'        
        $leftSplitContainer.Panel1.Controls.Add($this.leftTopPanel)

        $this.leftBottomPanel = [System.Windows.Forms.Panel]::new()
        $this.leftBottomPanel.Name = "leftBottomPanel"
        $this.leftBottomPanel.Dock = 'Fill'        
        $leftSplitContainer.Panel2.Controls.Add($this.leftBottomPanel)

        [void]$leftSplitContainer.Handle
        [void]$this.leftTopPanel.Handle 
        [void]$this.leftBottomPanel.Handle 
        $leftSplitContainer.SplitterDistance = 500        

        return $form
    }

    [void]Show([string]$scriptPath = "") {
        $this.codeViewBox = [CodeViewBox]::new($this, $this.rightPanel)
        $this.astTreeView = [AstTreeView]::new($this, $this.leftTopPanel, $this.astColorsMap)
        $this.astPropertyView = [AstPropertyView]::new($this, $this.leftBottomPanel, $this.astColorsMap)

        $this.lastLoadedPath = $scriptPath
        
        [System.Windows.Forms.Application]::Run($this.instance)
    }

    [void]setAstModel([AstModel]$astModel) {
        $pb = [ProgressBar]::new($this.instance, $astModel.nodesCount, "Building AST tree...")
        $this.instance.SuspendLayout()
        $this.astModel = $astModel
        $this.codeViewBox.setAstModel($astModel, $pb)
        $this.astTreeView.setAstModel($astModel, $pb)
        $this.astPropertyView.setAstModel($astModel, $pb)
        $this.instance.ResumeLayout()
        $pb.close()
    }

    [void]loadScript([string]$path) {
        if (-not (Test-Path -LiteralPath $path -PathType Leaf -ErrorAction SilentlyContinue)) {
            MessageBox::Show("File not found: $path", "Error", [MessageBoxButtons]::OK, [MessageBoxIcon]::Error)
            return
        }

        $this.lastLoadedPath = $path
        $this.loadedAstModel = [AstModel]::FromFile($path)
        $this.filteredAstModel = $null
        $this.filteredOffset = 0
        $this.setAstModel($this.loadedAstModel)
    }

    [void]openScript() {
        $openFileDialog = [System.Windows.Forms.OpenFileDialog]::new()
        $openFileDialog.Title = "Select PowerShell script"
        $openFileDialog.Filter = "PowerShell Scripts (*.ps1;*.psm1)|*.ps1;*.psm1|All Files (*.*)|*.*"
        if ($this.lastLoadedPath) { $openFileDialog.InitialDirectory = [System.IO.Path]::GetDirectoryName($this.lastLoadedPath) } 
        
        if ($openFileDialog.ShowDialog($this.instance) -eq [System.Windows.Forms.DialogResult]::OK) {
            $path = $openFileDialog.FileName
            $this.loadScript($path)
        }
    }

    [void]onAstNodeSelected([Ast]$ast, [int]$index, [bool]$keepScrollPos) {
        $this.codeViewBox.onAstNodeSelected($ast, $index, $keepScrollPos)
        $this.astPropertyView.onAstNodeSelected($ast, $index)
    }

    [void]onParameterSelected([object]$obj, [Ast]$ast) {
        $this.codeViewBox.onParameterSelected($obj, $ast)
    }

    [void]selectAstInTreeView([Ast]$ast) {
        $this.astTreeView.selectAst($ast)
    }

    [void]onCodeChanged([string]$script) {
        $this.loadedAstModel = [AstModel]::FromScript($script)
        $this.filteredAstModel = $null
        $this.filteredOffset = 0
        $this.setAstModel($this.loadedAstModel)
    }

    [void]selectAstNodeByCharPos([int]$charPos) {
        $this.astTreeView.instance.Focus()
        $this.astTreeView.selectNodeByCharIndex($charPos)
    }
    
    [void]filterByFindAllCommand([Ast]$ast, [bool]$includeNested) {
        $this.filteredAstModel = [AstModel]::FromAst($ast, $includeNested)
        $this.filteredOffset = $ast.Extent.StartOffset
        $this.setAstModel($this.filteredAstModel)
    }

    [void]onFilterCleared() {
        $this.filteredAstModel = $null
        $this.filteredOffset = 0
        $this.setAstModel($this.loadedAstModel)
    }

    [System.Drawing.Icon]getIcon() {
        $iconB64 = "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"
        $bytes = [Convert]::FromBase64String($iconB64)
        $stream = [System.IO.MemoryStream]::New($bytes)
        return [System.Drawing.Icon]::New($stream)
    }
}

class CodeViewBox {    
    [object]$mainForm     
    [System.Windows.Forms.Control]$container    
    [System.Windows.Forms.RichTextBox]$instance    
    [SearchPanel]$searchPanel    
    [CodeStatusBar]$codeStatusBar    
    [Debounce]$statusDebounce    
    [AstModel]$astModel    
    [Ast]$selectedAst    
    [Ast]$selectedAstSecondary    
    [hashtable]$foundBlock    
    [string]$currentText    
    [bool]$suppressTextChanged    
    [bool]$suppressSelectionChanged    
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
        $textBox.ScrollBars = "Both"
        $textBox.WordWrap = $false
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
                $cms = $s.GetCurrentParent()
                $rtb = $cms.SourceControl
                $charPos = $rtb.SelectionStart
                $rtb.Tag.selectAstNodeByCharPos($charPos)
            })
        
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
    
    [hashtable[]]getAstHighlightedBlocks() {
        if (-not $this.selectedAst -and -not $this.selectedAstSecondary) { return @() }

        $primaryColor = [System.Drawing.Color]::FromArgb(0, 120, 215)      
        $secondaryColor = [System.Drawing.Color]::FromArgb(61, 160, 236)   
        $overlapColor = [System.Drawing.Color]::FromArgb(0, 99, 174)       
        
        [int]$primaryStart = 0
        [int]$primaryEnd = 0
        if ($this.selectedAst) {
            [int]$primaryStart = $this.selectedAst.Extent.StartOffset - $this.mainForm.filteredOffset
            [int]$primaryEnd = $this.selectedAst.Extent.EndOffset - $this.mainForm.filteredOffset            
        }
        
        [int]$secondaryStart = 0
        [int]$secondaryEnd = 0
        if ($this.selectedAstSecondary) {
            $secondaryStart = [int]$this.selectedAstSecondary.Extent.StartOffset - $this.mainForm.filteredOffset
            $secondaryEnd = [int]$this.selectedAstSecondary.Extent.EndOffset - $this.mainForm.filteredOffset
        }
        
        if ($this.selectedAst -and -not $this.selectedAstSecondary) {
            return @(@{ Type = "PrimaryAst"; Start = $primaryStart; End = $primaryEnd; Color = [System.Drawing.Color]::White; BgColor = $primaryColor })
        }
                
        if ( $this.selectedAstSecondary -and -not $this.selectedAst) {
            return @(@{ Type = "SecondaryAst"; Start = $secondaryStart; End = $secondaryEnd; Color = [System.Drawing.Color]::White; BgColor = $secondaryColor })
        }

                
        if ($primaryEnd -lt $secondaryStart -or $secondaryEnd -lt $primaryStart) {            
            return @(
                @{ Type = "PrimaryAst"; Start = $primaryStart; End = $primaryEnd; Color = [System.Drawing.Color]::White; BgColor = $primaryColor },
                @{ Type = "SecondaryAst"; Start = $secondaryStart; End = $secondaryEnd; Color = [System.Drawing.Color]::White; BgColor = $secondaryColor }
            )
        }
        
        if ($primaryStart -eq $secondaryStart -and $primaryEnd -eq $secondaryEnd) {
            return @(@{ Type = "OverlapAst"; Start = $primaryStart; End = $primaryEnd; Color = [System.Drawing.Color]::White; BgColor = $overlapColor })
        }
        
        [int]$overlapStart = [Math]::Max($primaryStart, $secondaryStart)
        [int]$overlapEnd = [Math]::Min($primaryEnd, $secondaryEnd)

        $result = @()
        
        [int]$leftStart = [Math]::Min($primaryStart, $secondaryStart)
        [int]$leftEnd = $overlapStart

        if ($leftStart -lt $leftEnd) {
            $leftType = if ($primaryStart -lt $secondaryStart) { "PrimaryAst" } else { "SecondaryAst" }
            $leftColor = if ($leftType -eq "PrimaryAst") { $primaryColor } else { $secondaryColor }

            $result += @{ Type = $leftType; Start = $leftStart; End = $leftEnd; Color = [System.Drawing.Color]::White; BgColor = $leftColor }
        }
        
        if ($overlapEnd -gt $overlapStart) {
            $result += @{ Type = "OverlapAst"; Start = $overlapStart; End = $overlapEnd; Color = [System.Drawing.Color]::White; BgColor = $overlapColor }
        }
        
        [int]$rightStart = $overlapEnd
        [int]$rightEnd = [Math]::Max($primaryEnd, $secondaryEnd)

        if ($rightStart -lt $rightEnd) {
            $rightType = if ($primaryEnd -gt $secondaryEnd) { "PrimaryAst" } else { "SecondaryAst" }
            $rightColor = if ($rightType -eq "PrimaryAst") { $primaryColor } else { $secondaryColor }
            $result += @{Type = $rightType; Start = $rightStart; End = $rightEnd; Color = [System.Drawing.Color]::White; BgColor = $rightColor }
        }

        return $result
    }
    
    [hashtable[]] MergeFoundBlock([hashtable[]] $astBlocks, [hashtable] $foundBlock) {
        
        if (-not $foundBlock) { return $astBlocks }

        [int]$foundStart = $foundBlock.Start
        [int]$foundEnd = $foundBlock.End

        $result = @()

        foreach ($block in $astBlocks) {

            [int]$bStart = $block.Start
            [int]$bEnd = $block.End
            
            if ($bEnd -le $foundStart -or $foundEnd -le $bStart) {                
                $result += $block
                continue
            }
            
            if ($foundStart -le $bStart -and $foundEnd -ge $bEnd) { continue }
            
            
            if ($bStart -lt $foundStart) { $result += @{Type = $block.Type; Start = $bStart; End = $foundStart; Color = $block.Color; BgColor = $block.BgColor; } }
            
            if ($bEnd -gt $foundEnd) { $result += @{Type = $block.Type; Start = $foundEnd; End = $bEnd; Color = $block.Color; BgColor = $block.BgColor } }
        }
        
        $result += $foundBlock
        
        return $result | Sort-Object Start
    }
    
    [void]highlightText([string]$scrollToBlock = $null) {
        $this.suppressSelectionChanged = $true
        $rtb = $this.instance

        $currentPos = $rtb.SelectionStart
        $scrollPos = $this.GetScrollPos()
        $this.DisableRedraw()
        
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
    
    [hashtable]GetScrollPos() {
        $wmUser = 0x400
        $emGetScrollPos = $wmUser + 221        
        $ptr = [System.Runtime.InteropServices.Marshal]::AllocHGlobal(8)
        [void][Win32]::SendMessage($this.instance.Handle, $emGetScrollPos, 0, $ptr)
        
        $x = [System.Runtime.InteropServices.Marshal]::ReadInt32($ptr, 0)
        $y = [System.Runtime.InteropServices.Marshal]::ReadInt32($ptr, 4)

        [System.Runtime.InteropServices.Marshal]::FreeHGlobal($ptr)
        return @{X = $x; Y = $y }
    }
    
    [void]SetScrollPos([hashtable]$scrollPos) {
        $wmUser = 0x400
        $emSetScrollPos = $wmUser + 222        
        $ptr = [System.Runtime.InteropServices.Marshal]::AllocHGlobal(8)
        
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
        $pt = $this.instance.GetPositionFromCharIndex($this.instance.SelectionStart)
        
        $clientW = $this.instance.ClientSize.Width
        $clientH = $this.instance.ClientSize.Height

        $visibleY = ($pt.Y -ge 0 -and $pt.Y -lt $clientH)
        $visibleX = ($pt.X -ge 0 -and $pt.X -lt $clientW)

        if ($visibleX -and $visibleY) { return }
        $this.instance.ScrollToCaret()
    }
      
    [void]selectAstNodeByCharPos([int]$charPos) {
        $this.mainForm.selectAstNodeByCharPos($charPos)
    }

    [void]onSearch([string]$text, [string]$direction) { 
        $this.onSearch($text, $direction, $false)
    }
    
    [void]onSearch([string]$text, [string]$direction, [bool]$keepScrollPos) {
        if (-not $text -or -not $this.instance.Text) {
            $this.foundBlock = $null
            $this.highlightText($null)
            return
        }

        $full = $this.instance.Text
   
        $curr = $this.instance.SelectionStart
        if ($direction -eq "Current") { 
            if ($this.foundBlock) { $curr = [Math]::Min($curr, $this.foundBlock.Start) }
            $direction = ""
        }

        $index = -1

        [StringComparison] $ignoreCase = [StringComparison]::InvariantCultureIgnoreCase
        switch ($direction) {

            '' {                
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
    
    [string]getSelectedText() {
        $res = $this.instance.SelectedText
        if (-not $res) { $res = "" }
        return $res
    }
    
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
    
    [bool]isCodeChanged() {
        return $this.currentText -ne $this.astModel.script
    }

}

Class ProgressBar {
    [string]$Label
    [bool]$canStop
    [int]$ThrottlePercent  
    [System.Windows.Forms.Form]$MainForm

    [bool]$IsCanceled
    [int]$CurrentValue = 0
    [int]$Total = 0
    [float]$LastPercent = 0
    [System.Windows.Forms.Form]$ProgressForm
    [System.Windows.Forms.ProgressBar]$ProgressBar
    [System.Windows.Forms.Label]$PercentLabel

    ProgressBar([System.Windows.Forms.Form]$mainForm, [int]$Total) {
        $this.MainForm = $MainForm
        $this.Total = $Total
        $this.Label = "Please wait..."
        $this.canStop = $false
        $this.ThrottlePercent = 5
        $this.Start()
    }

    ProgressBar([System.Windows.Forms.Form]$mainForm, [int]$Total, [string]$Label = "Please wait...") {
        $this.MainForm = $MainForm
        $this.Total = $Total
        $this.Label = $Label
        $this.canStop = $false
        $this.ThrottlePercent = 5
        $this.Start()
    }

    ProgressBar([System.Windows.Forms.Form]$mainForm, [int]$Total, [string]$Label = "Please wait...", [boolean]$canStop = $false) {
        $this.MainForm = $MainForm
        $this.Total = $Total
        $this.Label = $Label
        $this.canStop = $canStop
        $this.ThrottlePercent = 5
        $this.Start()
    }

    ProgressBar([System.Windows.Forms.Form]$mainForm, [int]$Total, [string]$Label = "Please wait...", [boolean]$canStop = $false, [int]$ThrottlePercent = 5) {
        $this.MainForm = $MainForm
        $this.Total = $Total
        $this.Label = $Label
        $this.canStop = $canStop
        $this.ThrottlePercent = $ThrottlePercent
        $this.Start()
    }

    [void]Start() {        
        $formHeight = if ($this.canStop) { 120 } else { 90 }
        $this.ProgressForm = New-Object System.Windows.Forms.Form
        $this.ProgressForm.Tag = $this
        $this.ProgressForm.Text = ""
        $this.ProgressForm.Size = New-Object System.Drawing.Size(300, $formHeight)
        $this.ProgressForm.StartPosition = [System.Windows.Forms.FormStartPosition]::Manual
        $this.ProgressForm.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::FixedDialog
        $this.ProgressForm.ControlBox = $false
        $this.ProgressForm.ShowInTaskbar = $false

        $this.ProgressForm.Top = $this.mainForm.Top + [int](($this.mainForm.Height - $this.ProgressForm.Height) / 2)
        $this.ProgressForm.Left = $this.mainForm.Left + [int](($this.mainForm.Width - $this.ProgressForm.Width) / 2)

        $this.ProgressForm.add_FormClosed({
                param($s, $e)
                $self = $s.Tag
                $self.mainForm.WindowState = [System.Windows.Forms.FormWindowState]::Normal
                $self.mainForm.Activate()
            })
        
        $progressLabel = New-Object System.Windows.Forms.Label
        $progressLabel.AutoSize = $true
        $progressLabel.Location = New-Object System.Drawing.Point(20, 15)
        $progressLabel.Text = $this.Label
        
        $this.ProgressBar = New-Object System.Windows.Forms.ProgressBar
        $this.ProgressBar.Minimum = 0
        $this.ProgressBar.Maximum = 100
        $this.ProgressBar.Value = 0
        $this.ProgressBar.Step = 1
        $this.ProgressBar.Style = "Continuous"
        $this.ProgressBar.Size = New-Object System.Drawing.Size(260, 20)
        $this.ProgressBar.Location = New-Object System.Drawing.Point(20, 35)
        
        $this.percentLabel = New-Object System.Windows.Forms.Label
        $this.percentLabel.AutoSize = $true
        $this.percentLabel.Location = New-Object System.Drawing.Point(130, 60)
        $this.percentLabel.Text = "0 %"
        
        if ($this.canStop) {
            $btnStop = New-Object System.Windows.Forms.Button
            $btnStop.Text = "Cancel"
            $btnStop.Width = 80
            $btnStop.Height = 25
            $btnStop.Location = New-Object System.Drawing.Point(($this.ProgressBar.Right - $btnStop.Width), ($this.ProgressForm.Height - $btnStop.Height - 20))
            $btnStop.Add_Click({ 
                    param($s, $e)
                    $self = $s.Parent.Tag
                    $self.IsCanceled = $true
                    $s.Text = "Cancelling..."
                    $s.Enabled = $false
                })
            $this.ProgressForm.Controls.Add($btnStop)
        }

        $this.ProgressForm.Controls.Add($progressLabel)
        $this.ProgressForm.Controls.Add($this.ProgressBar)
        $this.ProgressForm.Controls.Add($this.percentLabel)

        $this.mainForm.Enabled = $false

        $this.ProgressForm.Show($this.mainForm)
        $this.ProgressForm.Refresh()
    }

    [void]Update([int]$Value) {
        $this.CurrentValue = $Value

        if ($this.Total -eq 0) { return }   

        $percent = [math]::Round(($this.CurrentValue / $this.Total) * 100)
        if ($percent -gt 100) { $percent = 100 }

        if (-not $this.LastPercent) { $this.LastPercent = 0 }
        
        if (($percent - $this.LastPercent) -ge $this.ThrottlePercent -or $percent -eq 100) {
            $this.ProgressBar.Value = $percent
            $this.PercentLabel.Text = "$percent %"
            [System.Windows.Forms.Application]::DoEvents()

            $this.LastPercent = $percent
        }
    }

    [void]close() {        
        $this.ProgressForm.BeginInvoke(
            [Action[System.Windows.Forms.Form, System.Windows.Forms.Form]] {
                param($progressForm, $mainForm)
                if ($progressForm -and -not $progressForm.IsDisposed) {
                    $mainForm.Enabled = $true
                    $progressForm.Close()
                    $progressForm.Dispose()
                }

            }, @($this.ProgressForm, $this.mainForm)
        )
    }

}

Class AstModel {
    [Ast]$ast
    [Token[]]$tokens
    [hashtable]$astMap
    [string]$script
    [int]$nodesCount

    AstModel([string]$Script) {
        $this.init($Script)
    }

    AstModel([Ast]$astRoot, [bool]$includeNested) {
        $this.script = $astRoot.Extent.Text -replace "`r`n", "`n" 
        $this.ast = $astRoot
        $this.astMap = $this.getAstHierarchyMap($astRoot, $includeNested)
    }

    static [AstModel] FromFile([string]$Path) {
        if (-not (Test-Path $Path)) { throw "File not found: $Path" }
        $text = Get-Content -Raw -LiteralPath $Path -Encoding UTF8
        return [AstModel]::new($text)
    }

    static [AstModel] FromScript([string]$Script) {
        return [AstModel]::new($Script)
    }

    static [AstModel] FromAst([Ast]$astRoot, [bool]$includeNested) {
        return [AstModel]::new($astRoot, $includeNested)
    }
    
    [void]init([string]$script) {
        try {            
            $this.script = $script -replace "`r`n", "`n" 
        
            $errors = $null
            $tokensVal = $null
            $scriptAst = [Parser]::ParseInput($this.script, [ref]$tokensVal, [ref]$errors)            

            $this.ast = $scriptAst
            $this.tokens = $tokensVal
            $this.astMap = $this.getAstHierarchyMap($scriptAst, $true)
        }
        catch {
            $this.ast = ""
            $this.astMap = @{}
        }
    }
                
    [System.Collections.Specialized.OrderedDictionary]getAstHierarchyMap([Ast]$rootAst, $includeNested = $true) {
        $map = [ordered]@{}

        $items = $rootAst.FindAll( { $true }, $includeNested)
        $this.nodesCount = $items.Count
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

    [Token]GetTokenByCharIndex([int]$charIndex) {
        if (-not $this.Tokens) { return $null }

        [int]$low = 0
        [int]$high = $this.Tokens.Length - 1

        while ($low -le $high) {            
            [int]$mid = ($low + $high) / 2
            
            [Token]$t = $this.Tokens[$mid]
            
            [int]$start = $t.Extent.StartOffset
            [int]$end = $t.Extent.EndOffset   

            if ($charIndex -lt $start) {                
                $high = $mid - 1
                continue
            }

            if ($charIndex -ge $end) {                
                $low = $mid + 1
                continue
            }
            
            return $t
        }

        return $null
    }
}

Class SearchPanel {
    [object]$parent
    [System.Windows.Forms.Control]$container
    [System.Windows.Forms.Panel]$panelSearch
    [System.Windows.Forms.TextBox]$txtSearch
    [Debounce]$debounce

    SearchPanel([object]$parent, [System.Windows.Forms.Control]$container) {
        $this.parent = $parent
        $this.container = $container
        $this.debounce = [Debounce]::new(300)
        $this.init()
    }

    [void]init() {
        $this.panelSearch = [System.Windows.Forms.Panel]::new()
        $this.panelSearch.Tag = $this
        $this.panelSearch.Add_GotFocus({
                param($s, $e)
                $self = $s.Tag
                $self.txtSearch.Focus()
            })

        $this.txtSearch = [System.Windows.Forms.TextBox]::new()
        $this.txtSearch.Tag = $this
        $this.txtSearch.Name = "txtSearch"
        $this.txtSearch.Width = 250
        $this.txtSearch.Left = 3
        $this.txtSearch.BackColor = [System.Drawing.Color]::LemonChiffon
        $this.txtSearch.BorderStyle = [System.Windows.Forms.BorderStyle]::None

        $prevButton = [System.Windows.Forms.Button]::new()
        $prevButton.Tag = $this
        $prevButton.Text = "▲"
        $prevButton.Font = [System.Drawing.Font]::new("Segoe UI", 10)
        $prevButton.ForeColor = [System.Drawing.Color]::Gray
        $prevButton.Width = $this.txtSearch.Height
        $prevButton.Height = $this.txtSearch.Height
        $prevButton.Left = $this.txtSearch.Right + 3
        $prevButton.Top = $this.txtSearch.Top
        $prevButton.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
        $prevButton.FlatAppearance.BorderSize = 0
        $prevButton.Cursor = [System.Windows.Forms.Cursors]::Arrow
        $prevButton.Add_Click({ 
                param($s, $e)
                $self = $s.Tag
                $self.parent.onSearch($self.txtSearch.Text, "Prev")
                
            })
        $prevButton.Add_GotFocus({
                param($s, $e)
                $self = $s.Tag
                $self.txtSearch.Focus()
            })
        $this.panelSearch.Controls.Add($prevButton)
    
        $nextButton = [System.Windows.Forms.Button]::new()
        $nextButton.Tag = $this
        $nextButton.Text = "▼"
        $nextButton.Font = [System.Drawing.Font]::new("Segoe UI", 10)
        $nextButton.ForeColor = [System.Drawing.Color]::Gray
        $nextButton.Width = $this.txtSearch.Height
        $nextButton.Height = $this.txtSearch.Height
        $nextButton.Left = $prevButton.Right
        $nextButton.Top = $this.txtSearch.Top
        $nextButton.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
        $nextButton.FlatAppearance.BorderSize = 0
        $nextButton.Cursor = [System.Windows.Forms.Cursors]::Arrow
        $nextButton.Add_Click({ 
                param($s, $e)
                $self = $s.Tag
                $self.parent.onSearch($self.txtSearch.Text, "Next")
            })
        $nextButton.Add_GotFocus({
                param($s, $e)
                $self = $s.Tag
                $self.txtSearch.Focus()
            })
        $this.panelSearch.Controls.Add($nextButton)

        $closeButton = [System.Windows.Forms.Button]::new()
        $closeButton.Tag = $this
        $closeButton.Text = "✖"
        $closeButton.Font = [System.Drawing.Font]::new("Segoe UI", 12)
        $closeButton.ForeColor = [System.Drawing.Color]::Red
        $closeButton.Width = $this.txtSearch.Height
        $closeButton.Height = $this.txtSearch.Height
        $closeButton.Left = $nextButton.Right
        $closeButton.Top = $this.txtSearch.Top
        $closeButton.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
        $closeButton.FlatAppearance.BorderSize = 0
        $closeButton.Cursor = [System.Windows.Forms.Cursors]::Arrow
        $closeButton.Add_Click({ 
                param($s, $e)
                $self = $s.Tag
                $self.show($false)
            })
        $this.panelSearch.Controls.Add($closeButton)

        $this.panelSearch.Height = $this.txtSearch.Height
        $this.panelSearch.Width = $closeButton.Right
        $this.panelSearch.BackColor = $this.txtSearch.BackColor
        $this.panelSearch.Visible = $false
        $this.panelSearch.Anchor = "Bottom, Left"
        $this.panelSearch.Top = $this.container.Height - $this.panelSearch.Height - 8
        $this.panelSearch.Left = 5
        $this.panelSearch.BorderStyle = [System.Windows.Forms.BorderStyle]::FixedSingle
        $this.panelSearch.Controls.Add($this.txtSearch)
    
        $this.container.Controls.Add($this.panelSearch)
        $this.panelSearch.BringToFront()
      
        $this.txtSearch.Add_KeyDown({
                param($s, $e)
                $self = $s.Tag
                if ($e.KeyCode -eq [System.Windows.Forms.Keys]::Escape) { 
                    $self.show($false)
                    $e.Handled = $true
                    $e.SuppressKeyPress = $true
                }
                elseif ($e.Control -and $e.KeyCode -eq [System.Windows.Forms.Keys]::F) {
                    $text = $self.parent.getSelectedText().Trim()
                    if ($text) {
                        $self.txtSearch.Text = $text
                        $self.txtSearch.SelectionStart = 0
                        $self.txtSearch.SelectionLength = $text.Length
                    }
                    $e.Handled = $true
                    $e.SuppressKeyPress = $true
                }
                elseif (($e.KeyCode -eq [System.Windows.Forms.Keys]::F3 -or $e.KeyCode -eq ([System.Windows.Forms.Keys]::Enter)) -and -not $e.Control) {
                    $direction = if ($e.Shift) { "Prev" } else { "Next" }
                    $self.parent.onSearch($s.Text, $direction)
                    $e.Handled = $true
                    $e.SuppressKeyPress = $true
                }

            })

        $this.txtSearch.Add_TextChanged({
                param($s, $e)
                $self = $s.Tag
                $self.debounce.run({ param($_self, [string]$txt) $_self.parent.onSearch($txt, "") }, @($self, $s.Text))
            }) 


    }

    [void]show([bool]$state) {
        $this.show($state, "")
    }

    [void]show([bool]$state, [string]$initialVal) {
        $this.panelSearch.Visible = $state

        if ($state) { 
            $this.txtSearch.Focus() 
            $this.txtSearch.Text = $initialVal
            if ($initialVal) { 
                $this.txtSearch.SelectionStart = 0
                $this.txtSearch.SelectionLength = $initialVal.Length
            }
        }
        else { 
            $this.txtSearch.Text = "" 
            $this.container.Focus()
        }
    }

    [void]toggle() {
        $this.toggle("")
    }

    [void]toggle([string]$initialVal) {
        $this.show(-not $this.panelSearch.Visible, $initialVal)
    }

    [bool]isVisible() {
        return $this.panelSearch.Visible
    }

    [string]getSearchText() {
        return $this.txtSearch.Text
    }

    [void]setSearchText([string]$text) {
        $this.txtSearch.Text = $text
    }
        
    [void]invokeDebouncedSearch([string]$direction, [bool]$keepScrollPos) {
        if (-not $this.isVisible()) { return }
        $this.debounce.run({ param($self, [string]$txt, [string]$dir, [bool]$keepScroll) $self.parent.onSearch($txt, $dir, $keepScroll) }, @($this, $this.txtSearch.Text, $direction, $keepScrollPos)) 
    }
}

Class Debounce {
    [System.Windows.Forms.Timer]$timer
    [scriptblock]$action
    [object]$actionParams
    [int]$delayMs

    Debounce([int]$DelayMs = 300) {
        $this.delayMs = $DelayMs
    }

    [void]run([scriptblock]$Action, [object]$actionParams) {        
        if ($this.timer) {
            $this.timer.Stop()
            $this.timer.Dispose()
            $this.timer = $null
        }
        
        $this.timer = [System.Windows.Forms.Timer]::new()
        $this.timer.Interval = $this.delayMs
        
        $this.timer | Add-Member -MemberType NoteProperty -Name "Tag" -Value $this -Force
        $this.action = $Action
        $this.actionParams = $actionParams
        
        $this.timer.Add_Tick({
                param($t, $e)

                $self = $t.Tag
                $self.timer.Stop()
                $self.timer.Dispose()
                $self.timer = $null

                $self.action.Invoke(@($self.actionParams))
            })


        $this.timer.Start()
    }
}

Class CodeStatusBar {
    [object]$mainForm
    [object]$codeViewBox
    [System.Windows.Forms.Control]$container
    [System.Windows.Forms.ToolStripStatusLabel]$instance

    CodeStatusBar($mainForm, $container, $codeViewBox) {
        $this.mainForm = $mainForm
        $this.container = $container
        $this.codeViewBox = $codeViewBox
        $this.Init()
    }

    [void]init() {
        $statusStrip = [System.Windows.Forms.StatusStrip]::new()
        $statusStrip.Name = "statusStrip"
    
        $this.instance = [System.Windows.Forms.ToolStripStatusLabel]::new()
        $this.instance.Name = "txtStatusBar"
        $this.instance.Text = "Ready" 
        $this.instance.BackColor = [System.Drawing.Color]::LightGray
        $this.instance.Spring = $true 
        $this.instance.TextAlign = 'MiddleLeft'
        $statusStrip.Items.Add($this.instance)
        $this.container.Controls.Add($statusStrip)
    }

    [void]update($message) {
        $this.instance.Text = $message
    }
}

Class AstTreeView {
    [object]$mainForm 
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
        $this.container.Controls.Add($treeView)

        $this.InitEvents($treeView) 
        $this.initContextMenu($treeView)                    
        
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

                if ($e.Control -and $e.KeyCode -eq [System.Windows.Forms.Keys]::F) {                    
                    $selText = $self.getSelectedText().trim()
                    if ($self.searchPanel.isVisible() -and -not $selText) { return }
                    $self.searchPanel.show($true, $selText)
                    $e.Handled = $true
                    $e.SuppressKeyPress = $true
                }
                elseif ($e.KeyCode -eq [System.Windows.Forms.Keys]::Escape) {                    
                    if (-not $self.searchPanel.isVisible()) { return }
                    $self.searchPanel.show($false)
                }
                elseif ($e.Control -and $e.KeyCode -eq [System.Windows.Forms.Keys]::C) {                    
                    $self.addSelectedNodeToClipboard()
                }
            })
    }


    [void]initContextMenu([System.Windows.Forms.TreeView]$treeView) {
        $menu = [System.Windows.Forms.ContextMenuStrip]::new()

        $showFindAllUnnested = $menu.Items.Add("Shallow FindAll Result")
        $showFindAllUnnested.Add_Click({ 
                param($s, $e)                
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
        
        [System.Windows.Forms.TreeNode] $initialStart = $null

        $initialStart = $this.instance.SelectedNode
        switch ($direction) {
            "" {                
                if (-not $initialStart) { $initialStart = $this.getFirstNode($null) }
            }
            "next" {
                if ($initialStart) { $initialStart = $this.getNextNode($initialStart) }                
                if (-not $initialStart) { $initialStart = $this.getFirstNode($null) }
            }
            "prev" {
                if ($initialStart) { $initialStart = $this.getPrevNode($initialStart) }                
                if (-not $initialStart) { $initialStart = $this.GetLastNode($null) }
            }
            default {
                $initialStart = $this.getFirstNode($null)
            }
        }

        if (-not $initialStart) { return }

        [StringComparison] $ignoreCase = [StringComparison]::InvariantCultureIgnoreCase
                        
        [System.Windows.Forms.TreeNode] $current = $initialStart
        [System.Windows.Forms.TreeNode] $stopNode = $initialStart
        [System.Windows.Forms.TreeNode] $foundNode = $null

        $isPrev = ($direction -eq "prev")

        while ($current) {
            if ($current.Text.IndexOf($text, 0, $ignoreCase) -ge 0) { $foundNode = $current; break }
            
            if ($isPrev) {
                $current = $this.getPrevNode($current)
                if (-not $current) { $current = $this.GetLastNode($null) }
            }
            else {
                $current = $this.getNextNode($current)
                if (-not $current) { $current = $this.getFirstNode($null) }
            }
            
            if ($current -eq $stopNode) { break }
        }

        if ($foundNode) {
            $this.instance.SelectedNode = $foundNode
            $foundNode.EnsureVisible()
        }
    }

    
       
    [System.Windows.Forms.TreeNode] GetLastNode([System.Windows.Forms.TreeNode] $node) {
        $current = $node
        if (-not $current) { 
            $current = $this.instance 
            if ($current.Nodes.Count -eq 0) { return $null }
        }
        
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
    
    [System.Windows.Forms.TreeNode] getPrevNode([System.Windows.Forms.TreeNode] $node) {
        if (-not $node) { return $this.GetLastNode($null) }

        [System.Windows.Forms.TreeNode] $prev = $node.PrevNode
        if ($prev) { return $this.GetLastNode($prev) }
        return $node.Parent
    }

    [System.Windows.Forms.TreeNode] getNextNode([System.Windows.Forms.TreeNode] $node) {
        if (-not $node) { return $this.getFirstNode($null) }
        
        if ($node.Nodes.Count -gt 0) { return $node.Nodes[0] }
        
        [System.Windows.Forms.TreeNode] $current = $node

        while ($current) {
            if ($current.NextNode) { return $current.NextNode }            
            $current = $current.Parent
        }

        return $null
    }
    
    [void]addSelectedNodeToClipboard() {
        $node = $this.instance.SelectedNode
        if (-not $node) { return }
        $node.Text | Set-Clipboard
    }
}

Class NodeDrawer {
    [void]drawNode([System.Windows.Forms.TreeView]$s, [System.Windows.Forms.DrawTreeNodeEventArgs]$e, [hashtable[]]$nameParts) {
        
        if ($e.Bounds.Y -eq 0 -and $e.Bounds.X -lt 0 -and $e.Node -ne $s.TopNode) { $e.DrawDefault = $true; return }

        $bgColor = $s.BackColor
        $textColor = $s.ForeColor
        
        if ($e.Node.IsSelected) {
            $bgColor = [System.Drawing.SystemColors]::Highlight
            $textColor = [System.Drawing.SystemColors]::HighlightText
        }
        
        $e.Graphics.FillRectangle([System.Drawing.SolidBrush]::new($bgColor), $e.Bounds)

        $x = [float]$e.Bounds.X
        $y = [float]$e.Bounds.Y

        foreach ($part in $nameParts) {
            if (-not $e.Node.IsSelected) { $textColor = [System.Drawing.Color]$part.Color }
            $brush = [System.Drawing.SolidBrush]::new($textColor)

            $style = [System.Drawing.FontStyle]::Regular
            if ($part.Bold) { $style = $style -bor [System.Drawing.FontStyle]::Bold }
            if ($part.Italic) { $style = $style -bor [System.Drawing.FontStyle]::Italic }
            $font = [System.Drawing.Font]::new($s.Font, $style)
                        
            $fmt = [System.Drawing.StringFormat]::GenericTypographic
            $fmt.FormatFlags = $fmt.FormatFlags -bor [System.Drawing.StringFormatFlags]::NoWrap -bor [System.Drawing.StringFormatFlags]::MeasureTrailingSpaces
            $size = $e.Graphics.MeasureString($part.Text, $font, [System.Drawing.PointF]::Empty, $fmt)
            
            $e.Graphics.DrawString($part.Text, $font, $brush, [System.Drawing.PointF]::new($x, $y), $fmt)
            
            $x += $size.Width 

            $font.Dispose()
            $brush.Dispose()
        }

        $e.DrawDefault = $false
    }
}

class TextTagParser {
    [regex] $TagRegex
    [string] $DefaultColor
    [string] $DefaultBgColor

    TextTagParser() {
        $this.init('black', 'white')
    }

    TextTagParser([string]$defaultColor = 'black', [string]$defaultBgColor = 'white') {
        $this.init($defaultColor, $defaultBgColor)
    }

    [void]init([string]$defaultColor, [string]$defaultBgColor) {
        $pattern = '(?:<b>(?<bold>.*?)<\/b>)|(?:<i>(?<italic>.*?)<\/i>)|(?:<color:(?<colorName>[#a-z0-9]{3,15})>(?<colorText>.*?)<\/color>)|(?:<bgColor:(?<bgName>[#a-z0-9]{3,15})>(?<bgText>.*?)<\/bgColor>)'
        $options = [System.Text.RegularExpressions.RegexOptions]::IgnoreCase -bor [System.Text.RegularExpressions.RegexOptions]::Singleline
        $this.TagRegex = [regex]::new($pattern, $options)
        $this.DefaultColor = $defaultColor
        $this.DefaultBgColor = $defaultBgColor
    }

    [System.Collections.ArrayList] Parse([string] $text) {
        $text = $text -replace "(\r?\n)\s*", " "
        $result = [System.Collections.ArrayList]::new()
        $this.ParseRecursive($text, $this.DefaultColor, $this.DefaultBgColor, $false, $false, $result)
        return $result
    }

    hidden [void] ParseRecursive(
        [string] $text,
        [string] $currentColor,
        [string] $currentBgColor,
        [bool] $currentBold,
        [bool] $currentItalic,
        [System.Collections.ArrayList] $collector
    ) {
        if (-not $text) { return }

        $regexMatches = $this.TagRegex.Matches($text)
        if ($regexMatches.Count -eq 0) {
            $null = $collector.Add(@{
                    text    = $text
                    color   = $currentColor
                    bgColor = $currentBgColor
                    bold    = $currentBold
                    italic  = $currentItalic
                })
            return
        }

        $lastIndex = 0
        foreach ($match in $regexMatches) {            
            $prefixLen = $match.Index - $lastIndex
            if ($prefixLen -gt 0) {
                $prefix = $text.Substring($lastIndex, $prefixLen)
                if ($prefix) {
                    $null = $collector.Add(@{
                            text    = $prefix
                            color   = $currentColor
                            bgColor = $currentBgColor
                            bold    = $currentBold
                            italic  = $currentItalic
                        })
                }
            }
            
            if ($match.Groups['bold'].Success) {
                $this.ParseRecursive($match.Groups['bold'].Value, $currentColor, $currentBgColor, $true, $currentItalic, $collector)
            }
            elseif ($match.Groups['italic'].Success) {
                $this.ParseRecursive($match.Groups['italic'].Value, $currentColor, $currentBgColor, $currentBold, $true, $collector)
            }
            elseif ($match.Groups['colorName'].Success -and $match.Groups['colorText'].Success) {
                $this.ParseRecursive($match.Groups['colorText'].Value, $match.Groups['colorName'].Value, $currentBgColor, $currentBold, $currentItalic, $collector)
            }
            elseif ($match.Groups['bgName'].Success -and $match.Groups['bgText'].Success) {
                $this.ParseRecursive($match.Groups['bgText'].Value, $currentColor, $match.Groups['bgName'].Value, $currentBold, $currentItalic, $collector)
            }

            $lastIndex = $match.Index + $match.Length
        }
        
        if ($lastIndex -lt $text.Length) {
            $suffix = $text.Substring($lastIndex)
            if ($suffix) {
                $null = $collector.Add(@{
                        text    = $suffix
                        color   = $currentColor
                        bgColor = $currentBgColor
                        bold    = $currentBold
                        italic  = $currentItalic
                    })
            }
        }
    }
}

class AstPropertyView {
    [object]$mainForm 
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

        $treeView.Add_KeyDown({
                param($s, $e)
                $self = $s.Tag
                if ($e.Control -and $e.KeyCode -eq [System.Windows.Forms.Keys]::C) {                    
                    $self.addSelectedNodeToClipboard()
                }
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
                $isAst =  $obj -is [Ast]
                $s.Items["selectAst"].Visible = $isAst
                $s.Items["showFindAllUnnested"].Visible = $isAst
                $s.Items["copyToClipboard"].Visible = $true
            })
            
        $selectAst = $menu.Items.Add("Select Ast Node   (ctrl+click)")
        $selectAst.Name = "selectAst"
        $selectAst.Add_Click({ 
                param($s, $e)                
                $cms = $s.GetCurrentParent()
                $ctrl = $cms.SourceControl
                $node = $ctrl.SelectedNode
                if (-not $node) { return }

                $self = $ctrl.Tag
                $obj = $node.Tag.Parameter
                if ($obj -is [Ast]) { $self.mainForm.selectAstInTreeView($obj) }
            })

        $showFindAllUnnested = $menu.Items.Add("Filtered Shallow View (FindAll nested = false)")
        $showFindAllUnnested.Name = "showFindAllUnnested"
        $showFindAllUnnested.Add_Click({ 
                param($s, $e)                
                $cms = $s.GetCurrentParent()
                $ctrl = $cms.SourceControl
                $node = $ctrl.SelectedNode
                if (-not $node) { return }

                $self = $ctrl.Tag
                $obj = $node.Tag.Parameter
                if ($obj -is [Ast]) { $self.mainForm.filterByFindAllCommand($obj, $false) }
            })

        $copyToClipboard = $menu.Items.Add("Copy to Clipboard")
        $copyToClipboard.Name = "copyToClipboard"
        $copyToClipboard.Add_Click({ 
                param($s, $e)                
                $cms = $s.GetCurrentParent()
                $ctrl = $cms.SourceControl
                $node = $ctrl.SelectedNode
                if (-not $node) { return }

                $self = $ctrl.Tag
                $self.addSelectedNodeToClipboard()
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
    
    [void]processObjProperty([object]$obj, $parentNode) {
        foreach ($p in ([PSObject]$obj).PSObject.Properties) {
            $type = $this.getPropertyType($p)
            $val = $this.getPropertyValue($p)
            $name = $p.Name
            $taggedType = $type
            $taggedName = "<b>$name</b>"
            $color = "#CD9C6C"
            if ($p.Value -is [Ast]) { 
                if ($this.astColorsMap.ContainsKey($type)) { $color = $this.astColorsMap[$type] }
                $taggedType = "<b>$type</b>" 
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
        $realMethods = ([PSObject]$obj).PSObject.Methods | Where-Object {
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
        $pattern = '\b(?:[A-Za-z_][\w]*\.)+([A-Za-z_][\w]*)\b'

        return [regex]::Replace($str, $pattern, { param($m) $m.Groups[1].Value })
    }

    [string]highlightMethodFullName([string] $str) {        
        $str = [regex]::Replace(
            $str,
            '(?<type>[A-Za-z_]\w*(\[[^\]]+\])?)(?=\s+[A-Za-z_]\w*)',
            '<color:#C480DC>[</color><color:#CD9C6C>${type}</color><color:#C480DC>]</color>'
        ) 
        
        return [regex]::Replace(
            $str,
            '\b([A-Za-z_]\w*)\s*(?=\()',
            '<b>$1</b>'
        )
    }

    [string]getPropertyType([object]$prop) {
        $typeName = [Microsoft.PowerShell.ToStringCodeMethods]::Type([type]$prop.TypeNameOfValue)
        if ($typeName -match '.*ReadOnlyCollection\[(.*)\]') { $typeName = $matches[1] + '[]' }        
        $typeName = $this.removeNamespaces($typeName) 
        return $typeName
    }

    [string]getPropertyValue([object]$prop) {
        if ($null -eq $prop.Value) { return 'null' }

        if ($this.isValuePrimitive($prop.Value) -or $prop.Value -is [enum] -or $prop.Value -is [IScriptExtent]) {
            $val = $prop.Value.ToString() 
            if ($val.Length -gt 200) { $val = $val.Substring(0, 200) + "..." }
            return $val
        }

        if ( $prop.Value -is [System.Collections.IEnumerable]) {
            if ($prop.Value.Count -eq 0) { return "[]" }
            return "[$($prop.Value.Count)]"
        }

        return "object"
    }
    
    [void]addSelectedNodeToClipboard() {
        $node = $this.instance.SelectedNode
        if (-not $node) { return }
        $node.Text | Set-Clipboard
    }
}

class AstColorsGenerator {

    [hashtable] $ColorsMap

    AstColorsGenerator() {
        [System.Reflection.Assembly]::LoadWithPartialName('System.Management.Automation') | Out-Null
        $this.ColorsMap = $this.BuildColorsMap()
    }

    [hashtable] GetColorsMap() {
        return $this.ColorsMap
    }

    [System.Type[]] GetAstTypes() {
        return [Ast].Assembly.GetTypes() |
        Where-Object { $_.IsPublic -and -not $_.IsAbstract -and [Ast].IsAssignableFrom($_) } |
        Sort-Object FullName
    }

    [int] GetAstDepth([System.Type] $Type) {
        $depth = 0
        $t = $Type
        while ($t -and $t -ne [Ast]) {
            $t = $t.BaseType
            $depth++
        }
        return $depth
    }
    
    [uint32] GetStableHash([string] $Key) {
        $bytes = [System.Text.Encoding]::ASCII.GetBytes($Key)
        $hash64 = [uint64]2166136261
        foreach ($b in $bytes) {
            $hash64 = $hash64 -bxor [uint64]$b
            $hash64 = ($hash64 * [uint64]16777619) % [uint64]4294967296
        }
        return [uint32]$hash64
    }
    
    [Color] NewHslColor([double] $H, [double] $S, [double] $L) {
        function Hue2Rgb([double]$p, [double]$q, [double]$t) {
            if ($t -lt 0) { $t += 1 }
            if ($t -gt 1) { $t -= 1 }
            if ($t -lt 1 / 6) { return $p + ($q - $p) * 6 * $t }
            if ($t -lt 1 / 2) { return $q }
            if ($t -lt 2 / 3) { return $p + ($q - $p) * (2 / 3 - $t) * 6 }
            return $p
        }

        if ($S -eq 0) {
            $r = $g = $b = [math]::Round($L * 255)
        }
        else {
            $q = if ($L -lt 0.5) { $L * (1 + $S) } else { $L + $S - $L * $S }
            $p = 2 * $L - $q
            $r = [math]::Round(255 * (Hue2Rgb $p $q ($H + 1 / 3)))
            $g = [math]::Round(255 * (Hue2Rgb $p $q ($H)))
            $b = [math]::Round(255 * (Hue2Rgb $p $q ($H - 1 / 3)))
        }
        return [Color]::FromArgb($r, $g, $b)
    }
    
    [System.Drawing.Color] NewDeterministicColorFromName([string] $Name, [int] $Depth = 0) {
        $hash32 = $this.GetStableHash($Name)
        
        $index = [int]($hash32 % 1000)
        $goldenAngle = 137.508
        $h = (($index * $goldenAngle) % 360.0) / 360.0
        

        $s = 0.75 + ((($hash32 -shr 8) -band 0xFF) / 255.0) * 0.25   
        $l = 0.18 + ((($hash32 -shr 16) -band 0xFF) / 255.0) * 0.18  
        
        if ($Depth % 2 -eq 0) { $l = [math]::Max(0.22, $l - 0.05) }
        else { $l = [math]::Min(0.50, $l + 0.05) }

        return $this.NewHslColor($h, $s, $l)
    }
    
    [hashtable] BuildColorsMap() {
        $map = @{}
        $types = $this.GetAstTypes()

        foreach ($t in $types) {
            $depth = $this.GetAstDepth($t)
            $color = $this.NewDeterministicColorFromName($t.Name, $depth)
            $html = "#{0:X2}{1:X2}{2:X2}" -f $color.R, $color.G, $color.B
            $map[$t.Name] = $html
        }
        return $map
    }
}
'@
Invoke-Expression $__CLASSES_SOURCE_ad0457f118e34fb6bd0df8542399ea77
$__CLASSES_SOURCE_ad0457f118e34fb6bd0df8542399ea77 = $null


$global:__MODULES_8f01c6acde144d299209018fac2b7c2c = @{}


$global:__MODULES_8f01c6acde144d299209018fac2b7c2c["3dc5e28d2f934e2a846b48fbee630e38"] = {
    Set-StrictMode -Version Latest
    
    function Show-AstViewer {    
    
        [CmdletBinding()]
        param (
            [Parameter()]
            [string] $path = ""
        )
    
        $version = $MyInvocation.MyCommand.Module.Version
        $null = [RunApp]::new($version, $path)
    }
}

Remove-Module PsAstViewer -ErrorAction SilentlyContinue

Import-Module (New-Module -Name PsAstViewer -ScriptBlock $global:__MODULES_8f01c6acde144d299209018fac2b7c2c["3dc5e28d2f934e2a846b48fbee630e38"]) -Force -DisableNameChecking
Show-AstViewer -path $path
