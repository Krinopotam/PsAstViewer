using module ..\models\ast-model.psm1
using module .\ast-tree-view.psm1
using module .\progress-bar.psm1

using namespace System.Management.Automation.Language
using namespace System.Windows.Forms
        
Class FindAllForm {
    [object]$mainForm # can't use type [MainForm] due to circular dependency
    [System.Windows.Forms.Form]$instance
    [AstTreeView]$astTreeView
    [AstModel]$astModel
    [hashtable]$astColorsMap

    FindAllForm([object]$mainForm, [hashtable]$astColorMap, [Ast]$rootAst, [bool]$includeNested) {
        $this.astModel = [AstModel]::FromAst($rootAst, $includeNested)
        $this.mainForm = $mainForm
        $this.astColorsMap = $astColorMap
        $this.Init()
    }    

    [void]Init() {
        $form = [System.Windows.Forms.Form]::new()
        $this.instance = $form
        $form.Tag = $this
        $form.Text = "FindAll command result view"
        $form.Size = New-Object System.Drawing.Size(900, 500)
        $form.StartPosition = "CenterScreen"
        $form.WindowState = [System.Windows.Forms.FormWindowState]::Normal
    }

    [void]Show() {
        $this.astTreeView = [AstTreeView]::new($this.mainForm, $this.instance, $this.astColorsMap, $true)
        
        $pb = [ProgressBar]::new($this.mainForm.instance, $this.astModel.nodesCount, "Building AST tree...")
        $this.astTreeView.setAstModel($this.astModel, $pb)
        $pb.close()

        [System.Windows.Forms.Application]::DoEvents()
        
        $this.instance.ShowDialog()
    }
}
 