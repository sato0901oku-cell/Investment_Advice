[CmdletBinding()]
param(
    [ValidatePattern('^(?:[0-9A-Fa-f]{40}|[0-9A-Fa-f]{64})$')]
    [string]$FinalizationTreeId,

    [switch]$RequireAllCoordinationClosed
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$script:Failures = New-Object System.Collections.Generic.List[string]
$script:Utf8Strict = New-Object System.Text.UTF8Encoding($false, $true)
$script:Utf8Output = New-Object System.Text.UTF8Encoding($false, $false)
$script:GitExecutable = (Get-Command git.exe -ErrorAction Stop).Source
$script:CoordinationPaths = @(
    '作業用/実装計画.md',
    '作業用/進行中の作業.md',
    '作業用/大規模作業計画.md',
    '作業用/相談・事前調査.md'
)

function Add-CheckFailure {
    param([Parameter(Mandatory = $true)][string]$Message)

    $script:Failures.Add($Message) | Out-Null
}

function Invoke-GitReadOnly {
    param(
        [Parameter(Mandatory = $true)][string]$WorkingDirectory,
        [Parameter(Mandatory = $true)][string[]]$Arguments
    )

    $startInfo = New-Object System.Diagnostics.ProcessStartInfo
    $startInfo.FileName = $script:GitExecutable
    $startInfo.Arguments = [string]::Join(' ', $Arguments)
    $startInfo.WorkingDirectory = $WorkingDirectory
    $startInfo.UseShellExecute = $false
    $startInfo.CreateNoWindow = $true
    $startInfo.RedirectStandardOutput = $true
    $startInfo.RedirectStandardError = $true
    if ($startInfo.PSObject.Properties.Name -contains 'StandardOutputEncoding') {
        $startInfo.StandardOutputEncoding = $script:Utf8Output
        $startInfo.StandardErrorEncoding = $script:Utf8Output
    }

    $process = New-Object System.Diagnostics.Process
    $process.StartInfo = $startInfo
    if (-not $process.Start()) {
        throw 'Gitプロセスを開始できませんでした。'
    }

    $standardOutput = $process.StandardOutput.ReadToEnd()
    $standardError = $process.StandardError.ReadToEnd()
    $process.WaitForExit()

    [pscustomobject]@{
        ExitCode = $process.ExitCode
        StdOut = $standardOutput
        StdErr = $standardError
    }
}

function Get-OutputLines {
    param([AllowEmptyString()][string]$Text)

    if ([string]::IsNullOrEmpty($Text)) {
        return @()
    }

    @($Text -split '\r?\n' | Where-Object { $_ -ne '' })
}

function Normalize-RepositoryPath {
    param([Parameter(Mandatory = $true)][string]$Path)

    $normalized = $Path.Trim().Replace('\', '/')
    while ($normalized.StartsWith('./', [System.StringComparison]::Ordinal)) {
        $normalized = $normalized.Substring(2)
    }
    $normalized
}

function Get-PathKey {
    param([Parameter(Mandatory = $true)][string]$Path)

    (Normalize-RepositoryPath -Path $Path).ToLowerInvariant()
}

function Get-ForbiddenReviewReason {
    param(
        [Parameter(Mandatory = $true)][string]$RepositoryRoot,
        [Parameter(Mandatory = $true)][string]$Path
    )

    $normalized = Normalize-RepositoryPath -Path $Path
    $isCoordinationPath = @($script:CoordinationPaths | Where-Object {
        $normalized.Equals($_, [System.StringComparison]::OrdinalIgnoreCase)
    }).Count -ne 0
    if ($isCoordinationPath) {
        $nativePath = $normalized.Replace('/', [IO.Path]::DirectorySeparatorChar)
        $fullPath = [IO.Path]::GetFullPath((Join-Path $RepositoryRoot $nativePath))
        if (-not (Test-Path -LiteralPath $fullPath -PathType Leaf)) {
            return '調整文書が作業ツリーに存在しません。'
        }
        try {
            $text = [IO.File]::ReadAllText($fullPath, $script:Utf8Strict)
        } catch {
            return "調整文書をUTF-8として読めません: $($_.Exception.Message)"
        }
        $stateMatches = [regex]::Matches($text, '(?m)^状態：([^\r\n]+)\r?$')
        if ($stateMatches.Count -ne 1) {
            return '調整文書の状態行を一意に確認できません。'
        }
        $state = $stateMatches[0].Groups[1].Value.Trim()
        if ($state -ne 'なし') {
            return "有効な調整文書です（状態：$state）。"
        }
        return $null
    }

    foreach ($prefix in @(
        '【ユーザー作業&バックアップ用】/',
        'ユーザーからChatGPTへの提供・連絡用/',
        'ゲーム本体/data/'
    )) {
        if ($normalized.StartsWith($prefix, [System.StringComparison]::OrdinalIgnoreCase)) {
            return 'ユーザー退避領域、入力資料、または実データです。'
        }
    }

    $null
}

function Get-ExpectedCandidatePaths {
    param([Parameter(Mandatory = $true)][string]$ProgressPath)

    if (-not (Test-Path -LiteralPath $ProgressPath -PathType Leaf)) {
        Add-CheckFailure "進行中作業ファイルがありません: $ProgressPath"
        return @()
    }

    try {
        $text = [IO.File]::ReadAllText($ProgressPath, $script:Utf8Strict)
    } catch {
        Add-CheckFailure "進行中作業ファイルをUTF-8として読めません: $($_.Exception.Message)"
        return @()
    }

    $lines = @($text -split '\r?\n')
    $heading = '### ステージ済みレビュー候補'
    $headingIndex = -1
    for ($index = 0; $index -lt $lines.Count; $index++) {
        if ($lines[$index].Trim() -eq $heading) {
            $headingIndex = $index
            break
        }
    }
    if ($headingIndex -lt 0) {
        Add-CheckFailure "進行中作業ファイルに「$heading」がありません。"
        return @()
    }

    $paths = New-Object System.Collections.Generic.List[string]
    for ($index = $headingIndex + 1; $index -lt $lines.Count; $index++) {
        $line = $lines[$index]
        if ($line -match '^###\s+') {
            break
        }
        if ([string]::IsNullOrWhiteSpace($line)) {
            continue
        }
        if ($line -notmatch '^-\s+(.+?)\s*$') {
            Add-CheckFailure "ステージ済みレビュー候補は一ファイル一行の箇条書きで記録してください: $line"
            continue
        }

        $candidate = $Matches[1].Trim()
        if ($candidate.StartsWith('`') -and $candidate.EndsWith('`') -and $candidate.Length -ge 2) {
            $candidate = $candidate.Substring(1, $candidate.Length - 2)
        }
        if ($candidate -eq 'なし' -or $candidate.StartsWith('なし（', [System.StringComparison]::Ordinal)) {
            continue
        }
        if ([IO.Path]::IsPathRooted($candidate)) {
            Add-CheckFailure "レビュー候補はリポジトリ相対パスで記録してください: $candidate"
            continue
        }

        $candidate = Normalize-RepositoryPath -Path $candidate
        if ([string]::IsNullOrWhiteSpace($candidate) -or @($candidate -split '/') -contains '..') {
            Add-CheckFailure "レビュー候補のパスが不正です: $candidate"
            continue
        }
        $paths.Add($candidate) | Out-Null
    }

    @($paths)
}

function Test-ActivePowerShellFiles {
    param(
        [Parameter(Mandatory = $true)][string]$RepositoryRoot,
        [Parameter(Mandatory = $true)][string[]]$Paths
    )

    $checkedCount = 0
    foreach ($relativePath in $Paths) {
        $normalized = Normalize-RepositoryPath -Path $relativePath
        if (-not (
            $normalized.StartsWith('ゲーム本体/', [System.StringComparison]::OrdinalIgnoreCase) -or
            $normalized.StartsWith('tools/', [System.StringComparison]::OrdinalIgnoreCase)
        )) {
            continue
        }
        if (-not (
            $normalized.EndsWith('.ps1', [System.StringComparison]::OrdinalIgnoreCase) -or
            $normalized.EndsWith('.psm1', [System.StringComparison]::OrdinalIgnoreCase)
        )) {
            continue
        }

        $checkedCount++
        $nativeRelativePath = $normalized.Replace('/', [IO.Path]::DirectorySeparatorChar)
        $fullPath = [IO.Path]::GetFullPath((Join-Path $RepositoryRoot $nativeRelativePath))
        if (-not (Test-Path -LiteralPath $fullPath -PathType Leaf)) {
            Add-CheckFailure "現役PowerShellファイルが作業ツリーにありません: $normalized"
            continue
        }

        $bytes = [IO.File]::ReadAllBytes($fullPath)
        $hasBom = $bytes.Length -ge 3 -and
            $bytes[0] -eq 0xEF -and
            $bytes[1] -eq 0xBB -and
            $bytes[2] -eq 0xBF
        $offset = if ($hasBom) { 3 } else { 0 }

        try {
            $text = $script:Utf8Strict.GetString($bytes, $offset, $bytes.Length - $offset)
        } catch {
            Add-CheckFailure "UTF-8として読めないPowerShellファイルです: $normalized"
            continue
        }

        $loneLf = 0
        $loneCr = 0
        for ($index = 0; $index -lt $bytes.Length; $index++) {
            if ($bytes[$index] -eq 0x0A -and ($index -eq 0 -or $bytes[$index - 1] -ne 0x0D)) {
                $loneLf++
            }
            if ($bytes[$index] -eq 0x0D -and ($index + 1 -ge $bytes.Length -or $bytes[$index + 1] -ne 0x0A)) {
                $loneCr++
            }
        }

        if ($loneLf -ne 0 -or $loneCr -ne 0) {
            Add-CheckFailure "CRLF以外の改行があります: $normalized (単独LF=$loneLf, 単独CR=$loneCr)"
        }

        $containsJapanese = [regex]::IsMatch($text, '[\u3000-\u30FF\u3400-\u9FFF\uF900-\uFAFF\uFF00-\uFFEF]')
        if ($containsJapanese -and -not $hasBom) {
            Add-CheckFailure "日本語を含むPowerShellファイルにUTF-8 BOMがありません: $normalized"
        }
    }

    $checkedCount
}

$originalConsoleEncoding = [Console]::OutputEncoding
$exitCode = 1

try {
    [Console]::OutputEncoding = $script:Utf8Output
    $OutputEncoding = [Console]::OutputEncoding

    if ($RequireAllCoordinationClosed -and [string]::IsNullOrWhiteSpace($FinalizationTreeId)) {
        throw '-RequireAllCoordinationClosedは-FinalizationTreeIdと同時に指定してください。'
    }

    $startDirectory = (Get-Location).ProviderPath
    $rootResult = Invoke-GitReadOnly -WorkingDirectory $startDirectory -Arguments @('rev-parse', '--show-toplevel')
    if ($rootResult.ExitCode -ne 0) {
        throw "Gitリポジトリを特定できません: $($rootResult.StdErr.Trim())"
    }

    $rootLines = @(Get-OutputLines -Text $rootResult.StdOut)
    if ($rootLines.Count -ne 1) {
        throw 'Gitリポジトリルートを一意に取得できませんでした。'
    }
    $repositoryRoot = [IO.Path]::GetFullPath($rootLines[0].Trim())

    $stagedResult = Invoke-GitReadOnly -WorkingDirectory $repositoryRoot -Arguments @('-c', 'core.quotepath=false', 'diff', '--cached', '--name-only', '--diff-filter=ACDMRTUXB')
    $unstagedResult = Invoke-GitReadOnly -WorkingDirectory $repositoryRoot -Arguments @('-c', 'core.quotepath=false', 'diff', '--name-only', '--diff-filter=ACDMRTUXB')
    $untrackedResult = Invoke-GitReadOnly -WorkingDirectory $repositoryRoot -Arguments @('-c', 'core.quotepath=false', 'ls-files', '--others', '--exclude-standard')
    $powerShellResult = Invoke-GitReadOnly -WorkingDirectory $repositoryRoot -Arguments @('-c', 'core.quotepath=false', 'ls-files', '--cached', '--', '*.ps1', '*.psm1')

    foreach ($result in @($stagedResult, $unstagedResult, $untrackedResult, $powerShellResult)) {
        if ($result.ExitCode -ne 0) {
            throw "Gitの読取りに失敗しました: $($result.StdErr.Trim())"
        }
    }

    $stagedPaths = @(Get-OutputLines -Text $stagedResult.StdOut | ForEach-Object { Normalize-RepositoryPath -Path $_ })
    $unstagedPaths = @(Get-OutputLines -Text $unstagedResult.StdOut | ForEach-Object { Normalize-RepositoryPath -Path $_ })
    $untrackedPaths = @(Get-OutputLines -Text $untrackedResult.StdOut | ForEach-Object { Normalize-RepositoryPath -Path $_ })
    $powerShellPaths = @(Get-OutputLines -Text $powerShellResult.StdOut | ForEach-Object { Normalize-RepositoryPath -Path $_ })
    $isFinalization = -not [string]::IsNullOrWhiteSpace($FinalizationTreeId)
    $currentTreeId = $null

    if ($stagedPaths.Count -eq 0) {
        Add-CheckFailure 'ステージ済みレビュー候補がありません。'
    }

    if ($isFinalization) {
        $requiredClosedPaths = if ($RequireAllCoordinationClosed) {
            @($script:CoordinationPaths)
        } else {
            @(
                '作業用/実装計画.md',
                '作業用/進行中の作業.md'
            )
        }
        foreach ($coordinationPath in $requiredClosedPaths) {
            $coordinationReason = Get-ForbiddenReviewReason -RepositoryRoot $repositoryRoot -Path $coordinationPath
            if ($null -ne $coordinationReason) {
                Add-CheckFailure "最終化できない調整文書です: $coordinationPath ($coordinationReason)"
            }
        }

        $treeResult = Invoke-GitReadOnly -WorkingDirectory $repositoryRoot -Arguments @('write-tree')
        if ($treeResult.ExitCode -ne 0) {
            throw "Gitインデックスのtree IDを取得できません: $($treeResult.StdErr.Trim())"
        }
        $treeLines = @(Get-OutputLines -Text $treeResult.StdOut)
        if ($treeLines.Count -ne 1) {
            throw 'Gitインデックスのtree IDを一意に取得できませんでした。'
        }
        $currentTreeId = $treeLines[0].Trim()
        if (-not $currentTreeId.Equals($FinalizationTreeId, [System.StringComparison]::OrdinalIgnoreCase)) {
            Add-CheckFailure "最終化対象のtree IDが承認済み候補と一致しません（承認済み=$FinalizationTreeId、現在=$currentTreeId）。"
        }
        $expectedPaths = @($stagedPaths)
    } else {
        $progressPath = Join-Path $repositoryRoot '作業用\進行中の作業.md'
        $expectedPaths = @(Get-ExpectedCandidatePaths -ProgressPath $progressPath)
        if ($expectedPaths.Count -eq 0) {
            Add-CheckFailure '進行中の作業に有効なレビュー候補が記録されていません。'
        }
    }

    $expectedMap = @{}
    foreach ($path in $expectedPaths) {
        $key = Get-PathKey -Path $path
        if ($expectedMap.ContainsKey($key)) {
            Add-CheckFailure "レビュー候補が重複して記録されています: $path"
        } else {
            $expectedMap[$key] = $path
        }
    }

    $stagedMap = @{}
    foreach ($path in $stagedPaths) {
        $key = Get-PathKey -Path $path
        $stagedMap[$key] = $path
        $forbiddenReason = Get-ForbiddenReviewReason -RepositoryRoot $repositoryRoot -Path $path
        if ($null -ne $forbiddenReason) {
            Add-CheckFailure "レビュー候補へ含めてはいけないパスがステージされています: $path ($forbiddenReason)"
        }
    }

    foreach ($key in $expectedMap.Keys) {
        if (-not $stagedMap.ContainsKey($key)) {
            Add-CheckFailure "記録済みですがステージされていません: $($expectedMap[$key])"
        }
    }
    foreach ($key in $stagedMap.Keys) {
        if (-not $expectedMap.ContainsKey($key)) {
            Add-CheckFailure "ステージされていますがレビュー候補へ記録されていません: $($stagedMap[$key])"
        }
    }

    $unstagedMap = @{}
    foreach ($path in $unstagedPaths) {
        $unstagedMap[(Get-PathKey -Path $path)] = $path
    }
    foreach ($key in $stagedMap.Keys) {
        if ($unstagedMap.ContainsKey($key)) {
            Add-CheckFailure "同じファイルにステージ済み変更と未ステージ変更があります: $($stagedMap[$key])"
        }
    }

    $checkedPowerShellCount = Test-ActivePowerShellFiles -RepositoryRoot $repositoryRoot -Paths $powerShellPaths

    $diffCheckResult = Invoke-GitReadOnly -WorkingDirectory $repositoryRoot -Arguments @('diff', '--cached', '--check')
    if ($diffCheckResult.ExitCode -ne 0) {
        Add-CheckFailure "git diff --cached --check が失敗しました:`n$($diffCheckResult.StdOut.Trim())$($diffCheckResult.StdErr.Trim())"
    }

    Write-Output "[情報] リポジトリ: $repositoryRoot"
    if ($isFinalization) {
        Write-Output '[情報] 検査モード: 最終化'
        if ($RequireAllCoordinationClosed) {
            Write-Output '[情報] 調整文書の閉鎖条件: 全体作業終了'
        } else {
            Write-Output '[情報] 調整文書の閉鎖条件: 現在フェーズ終了'
        }
        Write-Output "[情報] Gitインデックスtree ID: $currentTreeId"
    } else {
        Write-Output '[情報] 検査モード: 通常レビュー'
    }
    Write-Output "[情報] ステージ済みレビュー候補: $($stagedPaths.Count)件"
    foreach ($path in $stagedPaths) {
        Write-Output "  - $path"
    }
    Write-Output "[情報] 検査した現役PowerShell: ${checkedPowerShellCount}件"

    if ($untrackedPaths.Count -eq 0) {
        Write-Output '[情報] 未追跡ファイル: 0件'
    } else {
        Write-Output "[情報] 未追跡ファイル: $($untrackedPaths.Count)件（確認用・これだけでは不合格にしません）"
        foreach ($path in $untrackedPaths) {
            Write-Output "  - $path"
        }
    }

    if ($script:Failures.Count -eq 0) {
        Write-Output '[OK] レビュー候補の定型検査に成功しました。'
        $exitCode = 0
    } else {
        Write-Output "[NG] レビュー候補の定型検査で$($script:Failures.Count)件の問題を検出しました。"
        foreach ($failure in $script:Failures) {
            Write-Output "  - $failure"
        }
        $exitCode = 1
    }
} catch {
    Write-Output "[NG] 定型検査を完了できませんでした: $($_.Exception.Message)"
    $exitCode = 1
} finally {
    [Console]::OutputEncoding = $originalConsoleEncoding
}

exit $exitCode
