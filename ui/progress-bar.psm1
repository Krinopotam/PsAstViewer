Class ProgressBar {
    [string]$Label
    [bool]$canStop
    [int]$ThrottlePercent  # minimum UI update interval in percents
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
        # Create form
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

        # Progress label
        $progressLabel = New-Object System.Windows.Forms.Label
        $progressLabel.AutoSize = $true
        $progressLabel.Location = New-Object System.Drawing.Point(20, 15)
        $progressLabel.Text = $this.Label

        # ProgressBar
        $this.ProgressBar = New-Object System.Windows.Forms.ProgressBar
        $this.ProgressBar.Minimum = 0
        $this.ProgressBar.Maximum = 100
        $this.ProgressBar.Value = 0
        $this.ProgressBar.Step = 1
        $this.ProgressBar.Style = "Continuous"
        $this.ProgressBar.Size = New-Object System.Drawing.Size(260, 20)
        $this.ProgressBar.Location = New-Object System.Drawing.Point(20, 35)

        # Percent label
        $this.percentLabel = New-Object System.Windows.Forms.Label
        $this.percentLabel.AutoSize = $true
        $this.percentLabel.Location = New-Object System.Drawing.Point(130, 60)
        $this.percentLabel.Text = "0 %"

        # Cancel button
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

        # Refresh only if moved at least $ThrottlePercent or reached the end
        if (($percent - $this.LastPercent) -ge $this.ThrottlePercent -or $percent -eq 100) {
            $this.ProgressBar.Value = $percent
            $this.PercentLabel.Text = "$percent %"
            [System.Windows.Forms.Application]::DoEvents()

            $this.LastPercent = $percent
        }
    }

    [void]close() {
        #WORKAROUND: Invoke on UI thread, because if simple Close() is called then main form minimizes
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