# 读配置：scripts/napcat/napcat.conf.json（存在就用它，不存在就用调用方给的默认值）
# 格式见 napcat.conf.example.json

function Get-NapCatConfig {
    param([string]$Dir, [string]$Account, [int]$OneBot, [int]$WebUi)
    $conf = Join-Path $PSScriptRoot 'napcat.conf.json'
    if (Test-Path $conf) {
        try {
            $j = Get-Content -LiteralPath $conf -Raw -Encoding UTF8 | ConvertFrom-Json
            if ($j.NapCatDir) { $Dir = [string]$j.NapCatDir }
            if ($null -ne $j.QQAccount) { $Account = [string]$j.QQAccount }
            if ($j.OneBotPort) { $OneBot = [int]$j.OneBotPort }
            if ($j.WebUiPort) { $WebUi = [int]$j.WebUiPort }
        } catch {}
    }
    return [pscustomobject]@{ NapCatDir = $Dir; QQAccount = $Account; OneBotPort = $OneBot; WebUiPort = $WebUi }
}
