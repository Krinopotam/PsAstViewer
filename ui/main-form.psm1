using module .\code-view-box.psm1
using module .\ast-tree-view.psm1
using module .\ast-property-view.psm1
using module .\progress-bar.psm1
using module ..\models\ast-model.psm1
using module ..\utils\ast-colors-generator.psm1

using namespace System.Management.Automation.Language
using namespace System.Windows.Forms
        
class MainForm {
    # Main form instance
    [System.Windows.Forms.Form]$instance
    # Left panel instance
    [System.Windows.Forms.Panel]$leftTopPanel
    # Left panel instance
    [System.Windows.Forms.Panel]$leftBottomPanel
    # Right panel instance
    [System.Windows.Forms.Panel]$rightPanel
    # Code view box instance
    [CodeViewBox]$codeViewBox
    # Ast tree view instance
    [AstTreeView]$astTreeView
    # Ast property view instance
    [AstPropertyView]$astPropertyView
    # Current shown ast model
    [AstModel]$astModel
    # Last loaded ast model
    [AstModel]$loadedAstModel
    # Filtered ast model
    [AstModel]$filteredAstModel
    # Keep the path of the last loaded script
    [string]$lastLoadedPath
    # Is the control key pressed
    [bool]$ctrlPressed = $false
    # Is the alt key pressed
    [bool]$altPressed = $false
    # Is the shift key pressed
    [bool]$shiftPressed = $false
    # Colors map for ast nodes
    [hashtable]$astColorsMap
    # Keep the offset of the filtered ast extent (ast extent has positions from full script code, but filtered extents code is a subset of the full code)
    [int]$filteredOffset = 0
    # Module Version
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
        $iconPath = Join-Path $PSScriptRoot '..\icons\PsAstViewer.ico'
        if (Test-Path $iconPath) { $form.Icon = New-Object System.Drawing.Icon($iconPath) }
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
                
                # WORKAROUND: bring to front. When run from maximized VsCode, the form is hidden behind other windows
                $self.instance.Activate()
                $self.instance.TopMost = $true
                Start-Sleep -Milliseconds 100
                $self.instance.TopMost = $false

                if ($self.lastLoadedPath) { $self.loadScript($self.lastLoadedPath) }
            })

        #region Horizontal split panels
        $rootSplitContainer = [System.Windows.Forms.SplitContainer]::new()
        $rootSplitContainer.Name = "rootSplitContainer"
        $rootSplitContainer.Dock = 'Fill'
        $rootSplitContainer.Orientation = 'Vertical' 

        $form.Controls.Add($rootSplitContainer)

        $leftPanel = [System.Windows.Forms.Panel]::new()
        $leftPanel.Name = "leftPanel"
        $leftPanel.Dock = 'Fill'
        #$leftPanel.BackColor = 'LightBlue'
        $rootSplitContainer.Panel1.Controls.Add($leftPanel)

        $this.rightPanel = [System.Windows.Forms.Panel]::new()
        $this.rightPanel.Name = "rightPanel"
        $this.rightPanel.Dock = 'Fill'
        #$this.rightPanel.BackColor = 'LightGreen'
        $rootSplitContainer.Panel2.Controls.Add($this.rightPanel)

        [void]$rootSplitContainer.Handle
        [void]$leftPanel.Handle 
        [void]$this.rightPanel.Handle 
        $rootSplitContainer.SplitterDistance = 600
        #endregion Vertical split panels

        #region Left vertical split panels
        $leftSplitContainer = [System.Windows.Forms.SplitContainer]::new()
        $leftSplitContainer.Name = "leftSplitContainer"
        $leftSplitContainer.Dock = 'Fill'
        $leftSplitContainer.Orientation = 'Horizontal' 

        $leftPanel.Controls.Add($leftSplitContainer)

        $this.leftTopPanel = [System.Windows.Forms.Panel]::new()
        $this.leftTopPanel.Name = "leftTopPanel"
        $this.leftTopPanel.Dock = 'Fill'
        #$this.leftTopPanel.BackColor = 'Red'
        $leftSplitContainer.Panel1.Controls.Add($this.leftTopPanel)

        $this.leftBottomPanel = [System.Windows.Forms.Panel]::new()
        $this.leftBottomPanel.Name = "leftBottomPanel"
        $this.leftBottomPanel.Dock = 'Fill'
        #$this.leftBottomPanel.BackColor = 'Green'
        $leftSplitContainer.Panel2.Controls.Add($this.leftBottomPanel)

        [void]$leftSplitContainer.Handle
        [void]$this.leftTopPanel.Handle 
        [void]$this.leftBottomPanel.Handle 
        $leftSplitContainer.SplitterDistance = 500
        #endregion Vertical split panels

        return $form
    }

    [void]Show([string]$scriptPath = "") {
        $this.codeViewBox = [CodeViewBox]::new($this, $this.rightPanel)
        $this.astTreeView = [AstTreeView]::new($this, $this.leftTopPanel, $this.astColorsMap)
        $this.astPropertyView = [AstPropertyView]::new($this, $this.leftBottomPanel, $this.astColorsMap)

        $this.lastLoadedPath = $scriptPath

        #$this.instance.ShowDialog()
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

    # Set Ast filter by $ast.FindAll()
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
}
 