if ((Get-Module Atuin -ErrorAction Ignore) -or !(Get-Command atuin -ErrorAction Ignore) -or !(Get-Module PSReadLine -ErrorAction Ignore))
{
    return
}

New-Module -Name Atuin -ScriptBlock {
    $env:ATUIN_SESSION = (atuin uuid)
    $env:ATUIN_SHELL_POWERSHELL = "true"

    $atuinHistoryId = $null
    $previousPromptFunction = $Function:prompt

    $Function:prompt = {
        $exitCode = $global:LASTEXITCODE

        if ($atuinHistoryId)
        {
            atuin history end --duration (Get-History -Count 1).Duration.TotalNanoseconds --exit $exitCode -- $atuinHistoryId | Out-Null
            $atuinHistoryId = $null
        }

        $global:LASTEXITCODE = $exitCode
        & $previousPromptFunction
    }

    Set-PSReadLineKeyHandler -Chord Enter -BriefDescription "Accepts the input and records the command in Atuin" -ScriptBlock {
        $line = $null
        [Microsoft.PowerShell.PSConsoleReadLine]::GetBufferState([ref]$line, [ref]$null)

        $atuinHistoryId = (atuin history start -- $line)

        [Microsoft.PowerShell.PSConsoleReadLine]::AcceptLine()
    }

    function RunSearch
    {
        param(
            [string[]]$ExtraArgs = @()
        )

        $line = $null
        [Microsoft.PowerShell.PSConsoleReadLine]::GetBufferState([ref]$line, [ref]$null)
        [Microsoft.PowerShell.PSConsoleReadLine]::InsertLineBelow()

        $resultFile = New-TemporaryFile
        try
        {
            Start-Process -Wait -NoNewWindow -RedirectStandardError $resultFile.FullName atuin -ArgumentList (@("search", "-i") + $ExtraArgs + @("--", "$line"))
            $suggestion = (Get-Content -Raw $resultFile).Trim()
        }
        finally
        {
            Remove-Item $resultFile
        }

        [Microsoft.PowerShell.PSConsoleReadLine]::RevertLine()

        $previousOutputEncoding = [Console]::OutputEncoding
        try
        {
            [Console]::OutputEncoding = [Text.Encoding]::UTF8
            [Microsoft.PowerShell.PSConsoleReadLine]::InvokePrompt()
        }
        finally
        {
            [Console]::OutputEncoding = $previousOutputEncoding
        }

        if ( $suggestion.StartsWith("__atuin_accept__:"))
        {
            [Microsoft.PowerShell.PSConsoleReadLine]::Insert($suggestion.Substring(17))
            [Microsoft.PowerShell.PSConsoleReadLine]::AcceptLine()
        }
        else
        {
            [Microsoft.PowerShell.PSConsoleReadLine]::Insert($suggestion)
        }
    }

    function Enable-AtuinSearchKeys
    {
        param(
            [bool]$CtrlR = $true,
            [bool]$UpArrow = $true
        )

        if ($CtrlR)
        {
            Set-PSReadLineKeyHandler -Chord "Ctrl+r" -BriefDescription "Runs Atuin search" -ScriptBlock {
                RunSearch
            }
        }

        if ($UpArrow)
        {
            Set-PSReadLineKeyHandler -Chord "UpArrow" -BriefDescription "Runs Atuin search" -ScriptBlock {
                RunSearch -ExtraArgs @("--shell-up-key-binding")
            }
        }
    }

    Export-ModuleMember -Function @("Enable-AtuinSearchKeys")
} | Import-Module -Global
