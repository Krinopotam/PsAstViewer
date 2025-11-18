Class Debounce {
    [System.Windows.Forms.Timer]$timer
    [scriptblock]$action
    [object]$actionParams
    [int]$delayMs

    Debounce([int]$DelayMs = 300) {
        $this.delayMs = $DelayMs
    }

    [void]run([scriptblock]$Action, [object]$actionParams) {
        # Stop old timer
        if ($this.timer) {
            $this.timer.Stop()
            $this.timer.Dispose()
            $this.timer = $null
        }

        # Create new timer
        $this.timer = [System.Windows.Forms.Timer]::new()
        $this.timer.Interval = $this.delayMs

        # Keep this instance in timer
        $this.timer | Add-Member -MemberType NoteProperty -Name "Tag" -Value $this -Force
        $this.action = $Action
        $this.actionParams = $actionParams

        # Run action when timer ticks and cleanup timer
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