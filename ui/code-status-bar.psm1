
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