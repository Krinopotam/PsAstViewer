using module ..\utils\debounce.psm1

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

        $this.txtSearch = [System.Windows.Forms.TextBox]::new()
        $this.txtSearch.Tag = $this
        $this.txtSearch.Name = "txtSearch"
        $this.txtSearch.Width = 100
        $this.txtSearch.Left = 3
        $this.txtSearch.BackColor = [System.Drawing.Color]::LemonChiffon
        $this.txtSearch.BorderStyle = [System.Windows.Forms.BorderStyle]::None

        $prevButton = [System.Windows.Forms.Button]::new()
        $prevButton.Tag = $this
        $prevButton.Text = "<"
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
                $self.txtSearch.Focus()
                
            })
        $this.panelSearch.Controls.Add($prevButton)
    
        $nextButton = [System.Windows.Forms.Button]::new()
        $nextButton.Tag = $this
        $nextButton.Text = ">"
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
                $self.txtSearch.Focus()
            })
        $this.panelSearch.Controls.Add($nextButton)

        $closeButton = [System.Windows.Forms.Button]::new()
        $closeButton.Tag = $this
        $closeButton.Text = "X"
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
                $self.panelSearch.Visible = $false
                $self.txtSearch.Text = ""
                $self.container.Focus()
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
                    $self.panelSearch.Visible = $false
                    $self.txtSearch.Text = "" 
                    $self.container.Focus()
                    $e.Handled = $true
                    $e.SuppressKeyPress = $true
                }
                elseif (($e.KeyCode -eq [System.Windows.Forms.Keys]::F3 -or $e.KeyCode -eq ([System.Windows.Forms.Keys]::Enter)) -and -not $e.Control) {
                    $direction = if ($e.Shift) { "Prev" } else { "Next" }
                    $self.debounce.run({ param($_self, [string]$txt) $_self.parent.onSearch($txt, $direction) }, @($self, $s.Text))
                    $e.Handled = $true
                    $e.SuppressKeyPress = $true
                }
                if ($e.Control -and $e.KeyCode -eq [System.Windows.Forms.Keys]::F) {
                    $self.toggle()
                    $self.container.Focus()
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
        $this.panelSearch.Visible = $state
        if ($state) { $this.txtSearch.Focus() }
    }

    [void]toggle() {
        $this.show(-not $this.panelSearch.Visible)
    }
}