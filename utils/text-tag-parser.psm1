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
            # Text before the current tag
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

            # Determine which tag matched
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

        # Trailing text after the last tag
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
