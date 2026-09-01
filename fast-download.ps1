param(
    [string]$Filter = "",
    [string]$OutDir = ".\downloads",
    [string]$Repo = "Hankyuze/DockerTarBuilder",
    [string]$Tag = "DockerTarBuilder-AMD64",
    [string]$Proxy = "http://127.0.0.1:10808"
)

$ErrorActionPreference = "Stop"

function Find-Aria2 {
    $cmd = Get-Command aria2c.exe -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }
    $cmd = Get-Command aria2c -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }
    return $null
}

$aria2 = Find-Aria2
if (-not $aria2) {
    Write-Host "[ERROR] 未找到 aria2c。"
    Write-Host "推荐使用 winget 安装："
    Write-Host "winget install aria2.aria2"
    exit 1
}

New-Item -ItemType Directory -Force -Path $OutDir | Out-Null

$api = "https://api.github.com/repos/$Repo/releases/tags/$Tag"
Write-Host "=========================================="
Write-Host "GitHub Release 高速下载"
Write-Host "仓库: $Repo"
Write-Host "Tag : $Tag"
Write-Host "筛选: $(if ($Filter) { $Filter } else { '全部文件' })"
Write-Host "目录: $OutDir"
Write-Host "代理: $Proxy"
Write-Host "=========================================="

$irmParams = @{
    Uri = $api
    Headers = @{ "User-Agent" = "DockerTarBuilder-FastDownloader" }
}
if ($Proxy -and $Proxy -ne "none") {
    $irmParams.Proxy = $Proxy
}

$release = Invoke-RestMethod @irmParams
$assets = @($release.assets)
if ($Filter) {
    $assets = @($assets | Where-Object { $_.name -like "*$Filter*" })
}

if (-not $assets -or $assets.Count -eq 0) {
    throw "Release 中没有匹配文件"
}

$listFile = Join-Path $env:TEMP ("aria2-list-" + [guid]::NewGuid().ToString() + ".txt")
try {
    $lines = New-Object System.Collections.Generic.List[string]
    Write-Host "将下载以下文件："
    foreach ($asset in $assets) {
        Write-Host " - $($asset.name)"
        $lines.Add($asset.browser_download_url)
        $lines.Add("  out=$($asset.name)")
    }
    [System.IO.File]::WriteAllLines($listFile, $lines)

    $args = @(
        "--continue=true",
        "--max-connection-per-server=16",
        "--split=16",
        "--min-split-size=1M",
        "--max-concurrent-downloads=3",
        "--file-allocation=none",
        "--connect-timeout=15",
        "--timeout=60",
        "--max-tries=0",
        "--retry-wait=2",
        "--summary-interval=2",
        "--console-log-level=warn",
        "--download-result=full",
        "--dir=$OutDir",
        "--input-file=$listFile"
    )
    if ($Proxy -and $Proxy -ne "none") {
        $args += "--all-proxy=$Proxy"
    }

    Write-Host ""
    Write-Host "[1/3] aria2 多线程下载开始..."
    & $aria2 @args
    if ($LASTEXITCODE -ne 0) { throw "aria2 下载失败，退出码 $LASTEXITCODE" }

    Write-Host ""
    Write-Host "[2/3] 检查分卷并自动合并..."
    Get-ChildItem -Path $OutDir -Filter "*.sha256" | ForEach-Object {
        $shaFile = $_
        $baseName = $shaFile.Name.Substring(0, $shaFile.Name.Length - ".sha256".Length)
        $basePath = Join-Path $OutDir $baseName

        if (-not (Test-Path $basePath)) {
            $parts = Get-ChildItem -Path $OutDir -Filter ($baseName + ".part-*") | Sort-Object Name
            if ($parts.Count -gt 0) {
                Write-Host "合并: $baseName"
                $out = [System.IO.File]::Open($basePath, [System.IO.FileMode]::Create)
                try {
                    foreach ($part in $parts) {
                        $in = [System.IO.File]::OpenRead($part.FullName)
                        try { $in.CopyTo($out) } finally { $in.Dispose() }
                    }
                } finally { $out.Dispose() }
            }
        }
    }

    Write-Host ""
    Write-Host "[3/3] SHA256 校验..."
    Get-ChildItem -Path $OutDir -Filter "*.sha256" | ForEach-Object {
        $shaLine = (Get-Content $_.FullName -Raw).Trim()
        $parts = $shaLine -split '\s+', 2
        $expected = $parts[0].ToLowerInvariant()
        $fileName = $parts[1].TrimStart('*')
        $filePath = Join-Path $OutDir $fileName
        if (-not (Test-Path $filePath)) { throw "缺少待校验文件: $fileName" }
        $actual = (Get-FileHash -Algorithm SHA256 $filePath).Hash.ToLowerInvariant()
        if ($actual -ne $expected) { throw "SHA256 校验失败: $fileName" }
        Write-Host "$fileName : OK"
    }

    Write-Host ""
    Write-Host "=========================================="
    Write-Host "完成"
    Write-Host "下载目录: $OutDir"
    Write-Host "=========================================="
}
finally {
    Remove-Item -Force -ErrorAction SilentlyContinue $listFile
}
