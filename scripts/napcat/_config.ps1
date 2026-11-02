# 读配置：napcat.conf.json（存在就用它，不存在就用调用方给的默认值）
#
# ⚠ 两个坑（都是实测踩到的）：
#   1. 路径必须由调用方用 $PSScriptRoot 算好传进来 —— 函数里的 $PSScriptRoot
#      在不同调用方式下（-File / -Command / dot-source）不一定是本文件所在目录，
#      直接用它会把配置读丢、悄悄退回默认值。
#   2. Windows 用户写路径会顺手写成 "D:\NapCat"（单个反斜杠），那不是合法 JSON，
#      ConvertFrom-Json 会直接失败。这里做一次自动修正，并且**不再静默吞错**。

function ConvertFrom-TolerantJson {
    param([string]$Raw)
    try { return $Raw | ConvertFrom-Json } catch { $first = $_.Exception.Message }
    # 把"不构成合法 JSON 转义"的单反斜杠补成双反斜杠
    $fixed = [regex]::Replace($Raw, '(?<!\\)\\(?!["\\/bfnrtu])', '\\')
    try { return $fixed | ConvertFrom-Json } catch {
        throw "配置文件不是合法 JSON：$first"
    }
}

function Get-NapCatConfig {
    param(
        [string]$Dir,
        [string]$Account,
        [int]$OneBot,
        [int]$WebUi,
        [string]$ConfigPath
    )

    $result = [pscustomobject]@{ NapCatDir = $Dir; QQAccount = $Account; OneBotPort = $OneBot; WebUiPort = $WebUi }
    if (-not $ConfigPath) { return $result }

    if (-not (Test-Path $ConfigPath)) {
        Write-Warning "没找到配置文件：$ConfigPath（用默认值）"
        return $result
    }

    try {
        $j = ConvertFrom-TolerantJson -Raw (Get-Content -LiteralPath $ConfigPath -Raw -Encoding UTF8)
    } catch {
        # ⚠ 以前这里是 catch {} —— 配置写错了却悄悄用默认值，最难查的那种 bug
        Write-Warning ("读配置失败：" + $_.Exception.Message)
        return $result
    }

    if ($j.NapCatDir) { $result.NapCatDir = [string]$j.NapCatDir }
    if ($null -ne $j.QQAccount) { $result.QQAccount = [string]$j.QQAccount }
    if ($j.OneBotPort) { $result.OneBotPort = [int]$j.OneBotPort }
    if ($j.WebUiPort) { $result.WebUiPort = [int]$j.WebUiPort }
    return $result
}
