using module .\code-view-box.psm1
using module .\ast-tree-view.psm1
using module .\ast-property-view.psm1
using module .\progress-bar.psm1
using module ..\models\ast-model.psm1
using module ..\utils\ast-colors-generator.psm1

using namespace System.Management.Automation.Language
using namespace System.Windows.Forms
        
Class MainForm {
    [System.Windows.Forms.Form]$instance
    [System.Windows.Forms.Panel]$leftTopPanel
    [System.Windows.Forms.Panel]$leftBottomPanel
    [System.Windows.Forms.Panel]$rightPanel
    [CodeViewBox]$codeViewBox
    [AstTreeView]$astTreeView
    [AstPropertyView]$astPropertyView
    [AstModel]$astModel
    [AstModel]$initialAstModel
    [string]$lastLoadedPath
    [bool]$ctrlPressed = $false
    [bool]$altPressed = $false
    [bool]$shiftPressed = $false
    [hashtable]$astColorsMap

    MainForm() {
        $astColorsGenerator = [AstColorsGenerator]::new()
        $this.astColorsMap = $astColorsGenerator.GetColorsMap()
        $this.instance = $this.Init()
    }    

    [System.Windows.Forms.Form]Init() {
        $form = [System.Windows.Forms.Form]::new()
        $form.Tag = $this
        $form.Text = "Ast Viewer"
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
        }

        $this.lastLoadedPath = $path
        $model = [AstModel]::FromFile($path)
        $this.setAstModel($model)
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
        $this.setAstModel([AstModel]::FromScript($script))
    }

    [void]onCharIndexSelected([int]$charIndex) {
        $this.astTreeView.instance.Focus()
        $this.astTreeView.selectNodeByCharIndex($charIndex)
    }
}
 