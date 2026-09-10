[CmdletBinding()]
param(
    [Parameter(Position = 0)]
    [string]$InputFile,

    [Parameter(Position = 1)]
    [string]$OutputFile
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

if ([string]::IsNullOrWhiteSpace($InputFile)) {
    $InputFile = Join-Path -Path $PSScriptRoot -ChildPath "PTB_config.txt"
}
if ([string]::IsNullOrWhiteSpace($OutputFile)) {
    $OutputFile = Join-Path -Path $PSScriptRoot -ChildPath "PTB_config.bin"
}

$configFields = @("tune", "swd_spi_sclkdiv")
$fieldPattern = '^\s*(?:"(?<quoted_name>[A-Za-z_][A-Za-z0-9_]*)"|(?<plain_name>[A-Za-z_][A-Za-z0-9_]*))\s*(?::|=)\s*(?<value>0[xX][0-9A-Fa-f]+|[0-9]+)\s*,?\s*$'

function ConvertTo-ByteValue {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Text,

        [Parameter(Mandatory = $true)]
        [int]$LineNumber
    )

    if ($Text -match '^0[xX]') {
        $value = [Convert]::ToInt32($Text.Substring(2), 16)
    }
    else {
        $value = [Convert]::ToInt32($Text, 10)
    }

    if ($value -lt 0 -or $value -gt 0xFF) {
        throw "line $LineNumber`: value $value is outside uint8 range"
    }

    return [byte]$value
}

function Read-PtbConfig {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    $values = @{}
    $lines = Get-Content -LiteralPath $Path -Encoding UTF8

    for ($index = 0; $index -lt $lines.Count; $index++) {
        $lineNumber = $index + 1
        $line = $lines[$index]
        $line = $line -replace '(#|//).*$', ''
        $line = $line.Trim()

        if ([string]::IsNullOrWhiteSpace($line)) {
            continue
        }

        $match = [regex]::Match($line, $fieldPattern)
        if (-not $match.Success) {
            throw "line $lineNumber`: invalid configuration syntax"
        }

        $name = $match.Groups["quoted_name"].Value
        if ([string]::IsNullOrEmpty($name)) {
            $name = $match.Groups["plain_name"].Value
        }

        if ($configFields -notcontains $name) {
            throw "line $lineNumber`: unknown field '$name'; expected: $($configFields -join ', ')"
        }
        if ($values.ContainsKey($name)) {
            throw "line $lineNumber`: duplicate field '$name'"
        }

        $values[$name] = ConvertTo-ByteValue `
            -Text $match.Groups["value"].Value `
            -LineNumber $lineNumber
    }

    foreach ($field in $configFields) {
        if (-not $values.ContainsKey($field)) {
            throw "missing required field '$field'"
        }
    }

    return $values
}

function Get-Crc16 {
    param(
        [Parameter(Mandatory = $true)]
        [byte[]]$Data
    )

    $crc = [uint16]0xFFFF
    foreach ($value in $Data) {
        $crc = [uint16]($crc -bxor [uint16]$value)
        for ($bit = 0; $bit -lt 8; $bit++) {
            if (($crc -band 1) -ne 0) {
                $crc = [uint16](($crc -shr 1) -bxor 0xA001)
            }
            else {
                $crc = [uint16]($crc -shr 1)
            }
        }
    }
    # Match PTB crc16.c: return (uchCRCHi << 8) | uchCRCLo.
    # The reflected calculation stores these two bytes in reverse order.
    return [uint16]((($crc -band 0xFF) -shl 8) -bor ($crc -shr 8))
}

$inputPath = [System.IO.Path]::GetFullPath($InputFile)
$outputPath = [System.IO.Path]::GetFullPath($OutputFile)

if (-not [System.IO.File]::Exists($inputPath)) {
    throw "input file does not exist: $inputPath"
}

$config = Read-PtbConfig -Path $inputPath
$payload = [byte[]]@(
    $config["tune"],
    $config["swd_spi_sclkdiv"]
)
$crc = Get-Crc16 -Data $payload

$result = [byte[]]@(
    $payload[0],
    $payload[1],
    [byte]($crc -band 0xFF),
    [byte](($crc -shr 8) -band 0xFF)
)

$outputDirectory = [System.IO.Path]::GetDirectoryName($outputPath)
if (-not [string]::IsNullOrEmpty($outputDirectory)) {
    [System.IO.Directory]::CreateDirectory($outputDirectory) | Out-Null
}
[System.IO.File]::WriteAllBytes($outputPath, $result)

Write-Host ("tune=0x{0:X2}" -f $config["tune"])
Write-Host ("swd_spi_sclkdiv=0x{0:X2}" -f $config["swd_spi_sclkdiv"])
Write-Host ("crc=0x{0:X4}" -f $crc)
Write-Host "generated: $outputPath"
