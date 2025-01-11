if ((Get-Module Atuin -ErrorAction Ignore) -or !(Get-Command atuin -ErrorAction Ignore) -or !(Get-Module PSReadLine -ErrorAction Ignore)) {
    return
}

New-Module -Name Atuin -ScriptBlock {
    $env:ATUIN_SESSION = atuin uuid

    $script:atuinHistoryId = $null
    $script:previousPSConsoleHostReadLine = $Function:PSConsoleHostReadLine

    function PSConsoleHostReadLine {
        # This needs to be done as the first thing because any script run will flush $?.
        $lastRunStatus = $?

        # Exit statuses are maintained separately for native and PowerShell commands, take this into account.
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
        $line = [Microsoft.PowerShell.PSConsoleReadLine]::ReadLine($host.Runspace, $ExecutionContext, $lastRunStatus)

        $script:atuinHistoryId = atuin history start -- $line

        $line
    }

    function RunSearch {
        param([string[]]$ExtraArgs = @())

        $line = $null
        [Microsoft.PowerShell.PSConsoleReadLine]::GetBufferState([ref]$line, [ref]$null)
        [Microsoft.PowerShell.PSConsoleReadLine]::InsertLineBelow()

        $resultFile = New-TemporaryFile
        try {
            $env:ATUIN_SHELL_POWERSHELL = "true"
            Start-Process -Wait -NoNewWindow -RedirectStandardError $resultFile.FullName atuin -ArgumentList (@("search", "-i") + $ExtraArgs + @("--", "$line"))
            $suggestion = (Get-Content -Raw $resultFile).Trim()
        }
        finally {
            $env:ATUIN_SHELL_POWERSHELL = $null
            Remove-Item $resultFile
        }

        [Microsoft.PowerShell.PSConsoleReadLine]::RevertLine()

        $previousOutputEncoding = [Console]::OutputEncoding
        try {
            [Console]::OutputEncoding = [Text.Encoding]::UTF8
            [Microsoft.PowerShell.PSConsoleReadLine]::InvokePrompt()
        }
        finally {
            [Console]::OutputEncoding = $previousOutputEncoding
        }

        $acceptPrefix = "__atuin_accept__:"
        if ( $suggestion.StartsWith($acceptPrefix)) {
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
                RunSearch -ExtraArgs @("--shell-up-key-binding")
            }
        }
    }

    $ExecutionContext.SessionState.Module.OnRemove += {
        $env:ATUIN_SESSION = $null
        $Function:PSConsoleHostReadLine = $script:previousPSConsoleHostReadLine
    }

    Export-ModuleMember -Function @("Enable-AtuinSearchKeys", "PSConsoleHostReadLine")
} | Import-Module -Global
