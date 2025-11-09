using namespace System.Management.Automation.Language
using namespace System.Drawing

# Class that builds a deterministic, random-looking color map for all PowerShell AST node types.
# Uses custom FNV-1a hash for stability across runs and machines.
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

    # --- FNV-1a 32-bit hash ---
    [uint32] GetStableHash([string] $Key) {
        $bytes = [System.Text.Encoding]::ASCII.GetBytes($Key)
        $hash64 = [uint64]2166136261
        foreach ($b in $bytes) {
            $hash64 = $hash64 -bxor [uint64]$b
            $hash64 = ($hash64 * [uint64]16777619) % [uint64]4294967296
        }
        return [uint32]$hash64
    }

    # --- HSL → RGB ---
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

    # --- Deterministic color generator (bright & high-contrast) ---
    [System.Drawing.Color] NewDeterministicColorFromName([string] $Name, [int] $Depth = 0) {
        $hash32 = $this.GetStableHash($Name)

        # Even hue distribution via golden angle
        $index = [int]($hash32 % 1000)
        $goldenAngle = 137.508
        $h = (($index * $goldenAngle) % 360.0) / 360.0

        # Higher saturation, lower lightness for white background
<#         $s = 0.75 + ((($hash32 -shr 8) -band 0xFF) / 255.0) * 0.25   # 0.75–1.0
        $l = 0.25 + ((($hash32 -shr 16) -band 0xFF) / 255.0) * 0.20  # 0.25–0.45 #>

        $s = 0.75 + ((($hash32 -shr 8) -band 0xFF) / 255.0) * 0.25   # 0.75–1.0
        $l = 0.18 + ((($hash32 -shr 16) -band 0xFF) / 255.0) * 0.18  # 0.18–0.36

        # Alternate brightness for parent/child contrast
        if ($Depth % 2 -eq 0) { $l = [math]::Max(0.22, $l - 0.05) }
        else { $l = [math]::Min(0.50, $l + 0.05) }

        return $this.NewHslColor($h, $s, $l)
    }

    # --- Build the AST color map ---
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


# Example usage:
# $gen = [AstColorsGenerator]::new()
# $map = $gen.GetColorMap()
# $map['ScriptBlockAst']
# $gen.GetColor('BinaryExpressionAst')
