Class NodeDrawer {
    [void]drawNode([System.Windows.Forms.TreeView]$s, [System.Windows.Forms.DrawTreeNodeEventArgs]$e, [hashtable[]]$nameParts) {
        
        $bgColor = $s.BackColor
        $textColor = $s.ForeColor

        # Determine base colors
        if ($e.Node.IsSelected) {
            $bgColor = [System.Drawing.SystemColors]::Highlight
            $textColor = [System.Drawing.SystemColors]::HighlightText
        }

        # Draw background
        $e.Graphics.FillRectangle([System.Drawing.SolidBrush]::new($bgColor), $e.Bounds)

        $x = [float]$e.Bounds.X
        $y = [float]$e.Bounds.Y

        foreach ($part in $nameParts) {
            if ($part.Text -eq "[") { 
                $i = 0
            }
            if (-not $e.Node.IsSelected) { $textColor = [System.Drawing.Color]$part.Color }
            $brush = [System.Drawing.SolidBrush]::new($textColor)

            $style = [System.Drawing.FontStyle]::Regular
            if ($part.Bold) { $style = $style -bor [System.Drawing.FontStyle]::Bold }
            if ($part.Italic) { $style = $style -bor [System.Drawing.FontStyle]::Italic }
            $font = [System.Drawing.Font]::new($s.Font, $style)
            
            # Measure width of this part
            $fmt = [System.Drawing.StringFormat]::GenericTypographic
            $fmt.FormatFlags = $fmt.FormatFlags -bor [System.Drawing.StringFormatFlags]::NoWrap -bor [System.Drawing.StringFormatFlags]::MeasureTrailingSpaces
            $size = $e.Graphics.MeasureString($part.Text, $font, [System.Drawing.PointF]::Empty, $fmt)

            # Draw the text part
            $e.Graphics.DrawString($part.Text, $font, $brush, [System.Drawing.PointF]::new($x, $y), $fmt)

            # Shift X for next segment
            $x += $size.Width 

            $font.Dispose()
            $brush.Dispose()
        }

        $e.DrawDefault = $false
    }
}