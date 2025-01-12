if (Get-Module Atuin -ErrorAction Ignore) {
    Write-Warning "The Atuin module is already loaded."
    return
}

if (!(Get-Command atuin -ErrorAction Ignore)) {
    Write-Error "The 'atuin' executable needs to be available in the PATH."
    return
}

if (!(Get-Module PSReadLine -ErrorAction Ignore)) {
    Write-Error "Atuin requires the PSReadLine module to be installed."
    return
}

New-Module -Name Atuin -ScriptBlock {
    $env:ATUIN_SESSION = atuin uuid

    $script:atuinHistoryId = $null
    $script:previousPSConsoleHostReadLine = $Function:PSConsoleHostReadLine

    function PSConsoleHostReadLine {
        # This needs to be done as the first thing because any script run will flush $?.
        $lastRunStatus = $?

        # Exit statuses are maintained separately for native and PowerShell commands, this needs to be taken into account.
        $exitCode = if ($lastRunStatus) {
            0
        }
        elseif ($global:LASTEXITCODE) {
            $global:LASTEXITCODE
        }
        else {
            1
        }

        if ($script:atuinHistoryId) {
            $duration = (Get-History -Count 1).Duration.TotalNanoseconds
            atuin history end --exit=$exitCode --duration=$duration -- $script:atuinHistoryId | Out-Null

            $global:LASTEXITCODE = $exitCode
            $script:atuinHistoryId = $null
        }

        # Original PSConsoleHostReadLine implementation from PSReadLine.
        Microsoft.PowerShell.Core\Set-StrictMode -Off
        $line = [Microsoft.PowerShell.PSConsoleReadLine]::ReadLine($Host.Runspace, $ExecutionContext, $lastRunStatus)

        $script:atuinHistoryId = atuin history start -- $line

        return $line
    }

    function RunSearch {
        param([string[]]$ExtraArgs = @())

        $line = $null
        $cursor = $null
        [Microsoft.PowerShell.PSConsoleReadLine]::GetBufferState([ref]$line, [ref]$cursor)

        # Atuin is started through Start-Process to avoid interfering with the current shell,
        # and to capture its output which is provided in stderr (redirected to a temporary file).

        $resultFile = New-TemporaryFile
        try {
            $env:ATUIN_SHELL_POWERSHELL = "true"
            Start-Process -Wait -NoNewWindow -RedirectStandardError $resultFile.FullName -FilePath atuin -ArgumentList (@("search", "-i") + $ExtraArgs + @("--", "$line"))
            $suggestion = (Get-Content -Raw $resultFile).Trim()
        }
        finally {
            $env:ATUIN_SHELL_POWERSHELL = $null
            Remove-Item $resultFile
        }

        $previousOutputEncoding = [Console]::OutputEncoding
        try {
            [Console]::OutputEncoding = [Text.Encoding]::UTF8

            # PSReadLine maintains its own cursor position, which will no longer be valid if Atuin scrolls the display in inline mode.
            # Fortunately, InvokePrompt can receive a new Y position and reset the internal state.
            [Microsoft.PowerShell.PSConsoleReadLine]::InvokePrompt($null, $Host.UI.RawUI.CursorPosition.Y - 1)
        }
        finally {
            [Console]::OutputEncoding = $previousOutputEncoding
        }

        $acceptPrefix = "__atuin_accept__:"

        [Microsoft.PowerShell.PSConsoleReadLine]::RevertLine()

        if ($suggestion -eq "") {
            [Microsoft.PowerShell.PSConsoleReadLine]::Insert($line)
            [Microsoft.PowerShell.PSConsoleReadLine]::SetCursorPosition($cursor)
        }
        elseif ( $suggestion.StartsWith($acceptPrefix)) {
            [Microsoft.PowerShell.PSConsoleReadLine]::Insert($suggestion.Substring($acceptPrefix.Length))
            [Microsoft.PowerShell.PSConsoleReadLine]::AcceptLine()
        }
        else {
            [Microsoft.PowerShell.PSConsoleReadLine]::Insert($suggestion)
        }
    }

    function Enable-AtuinSearchKeys {
        param([bool]$CtrlR = $true, [bool]$UpArrow = $true)

        if ($CtrlR) {
            Set-PSReadLineKeyHandler -Chord "Ctrl+r" -BriefDescription "Runs Atuin search" -ScriptBlock {
                RunSearch
            }
        }

        if ($UpArrow) {
            Set-PSReadLineKeyHandler -Chord "UpArrow" -BriefDescription "Runs Atuin search" -ScriptBlock {
                $line = $null
                [Microsoft.PowerShell.PSConsoleReadLine]::GetBufferState([ref]$line, [ref]$null)

                if (!$line.Contains("`n")) {
                    RunSearch -ExtraArgs @("--shell-up-key-binding")
                }
                else {
                    [Microsoft.PowerShell.PSConsoleReadLine]::PreviousLine()
                }
            }
        }
    }

    $ExecutionContext.SessionState.Module.OnRemove += {
        $env:ATUIN_SESSION = $null
        $Function:PSConsoleHostReadLine = $script:previousPSConsoleHostReadLine
    }

    Export-ModuleMember -Function @("Enable-AtuinSearchKeys", "PSConsoleHostReadLine")
} | Import-Module -Global
