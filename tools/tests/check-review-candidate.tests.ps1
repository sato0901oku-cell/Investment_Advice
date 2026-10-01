[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$script:GitExecutable = (Get-Command git.exe -ErrorAction Stop).Source
$script:PowerShellExecutable = (Get-Command powershell.exe -ErrorAction Stop).Source
$script:CheckerSource = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\check-review-candidate.ps1'))
$script:Utf8NoBom = New-Object System.Text.UTF8Encoding($false, $true)
$script:TestRoot = Join-Path ([IO.Path]::GetTempPath()) ("codex-review-checker-tests-{0}" -f [Guid]::NewGuid().ToString('N'))
$script:TestCounter = 0
$script:PassedCount = 0
$script:FailedTests = New-Object System.Collections.Generic.List[string]

function Test-IsSafeCleanupRoot {
    param([Parameter(Mandatory = $true)][string]$Path)

    $candidate = [IO.Path]::GetFullPath($Path).TrimEnd([IO.Path]::DirectorySeparatorChar)
    $tempRoot = [IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd([IO.Path]::DirectorySeparatorChar)
    $parent = [IO.Directory]::GetParent($candidate)
    if ($null -eq $parent) {
        return $false
    }

    $parent.FullName.TrimEnd([IO.Path]::DirectorySeparatorChar).Equals(
        $tempRoot,
        [System.StringComparison]::OrdinalIgnoreCase
    ) -and [IO.Path]::GetFileName($candidate).StartsWith(
        'codex-review-checker-tests-',
        [System.StringComparison]::Ordinal
    )
}

function Invoke-TestGit {
    param(
        [Parameter(Mandatory = $true)][string]$Repository,
        [Parameter(Mandatory = $true)][string[]]$Arguments,
        [switch]$AllowFailure
    )

    $previousErrorActionPreference = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        $output = @(& $script:GitExecutable -C $Repository @Arguments 2>&1)
        $exitCode = $LASTEXITCODE
    } finally {
        $ErrorActionPreference = $previousErrorActionPreference
    }
    $text = [string]::Join("`n", @($output | ForEach-Object { $_.ToString() }))
    if ($exitCode -ne 0 -and -not $AllowFailure) {
        throw "Git command failed ($exitCode): git -C $Repository $([string]::Join(' ', $Arguments))`n$text"
    }

    [pscustomobject]@{
        ExitCode = $exitCode
        Output = $text
    }
}

function Ensure-ParentDirectory {
    param([Parameter(Mandatory = $true)][string]$Path)

    $parent = [IO.Path]::GetDirectoryName([IO.Path]::GetFullPath($Path))
    if (-not [string]::IsNullOrEmpty($parent)) {
        New-Item -ItemType Directory -Path $parent -Force | Out-Null
    }
}

function Write-Utf8Text {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][AllowEmptyString()][string]$Text,
        [switch]$Bom
    )

    Ensure-ParentDirectory -Path $Path
    $encoding = New-Object System.Text.UTF8Encoding([bool]$Bom)
    [IO.File]::WriteAllText([IO.Path]::GetFullPath($Path), $Text, $encoding)
}

function Set-ReviewCandidates {
    param(
        [Parameter(Mandatory = $true)][string]$Repository,
        [Parameter(Mandatory = $true)][AllowEmptyCollection()][string[]]$Paths
    )

    $candidateLines = if ($Paths.Count -eq 0) {
        @('- なし')
    } else {
        @($Paths | ForEach-Object { '- `' + $_ + '`' })
    }
    $progressLines = @(
        '# 進行中の作業',
        '',
        '状態：進行中',
        '',
        '## 記入欄',
        '',
        '### ステージ済みレビュー候補',
        ''
    )
    $progressLines += $candidateLines
    $progressLines += @(
        '',
        '### 検査結果',
        '',
        '- 試験用'
    )
    $progressText = $progressLines -join "`n"
    $progressText += "`n"
    Write-Utf8Text -Path (Join-Path $Repository '作業用\進行中の作業.md') -Text $progressText
}

function New-TestRepository {
    $script:TestCounter++
    $repository = Join-Path $script:TestRoot ("case-{0:D2}" -f $script:TestCounter)
    New-Item -ItemType Directory -Path $repository -Force | Out-Null

    Invoke-TestGit -Repository $repository -Arguments @('init', '--quiet') | Out-Null
    Invoke-TestGit -Repository $repository -Arguments @('config', 'user.name', 'Checker Test') | Out-Null
    Invoke-TestGit -Repository $repository -Arguments @('config', 'user.email', 'checker@example.invalid') | Out-Null
    Invoke-TestGit -Repository $repository -Arguments @('config', 'core.autocrlf', 'false') | Out-Null

    $checkerDestination = Join-Path $repository 'tools\check-review-candidate.ps1'
    Ensure-ParentDirectory -Path $checkerDestination
    [IO.File]::Copy($script:CheckerSource, $checkerDestination, $true)

    Write-Utf8Text -Path (Join-Path $repository 'ゲーム本体\base.ps1') -Text "Write-Output '基準'`r`n" -Bom
    Write-Utf8Text -Path (Join-Path $repository 'README.md') -Text "test repository`n"
    Write-Utf8Text -Path (Join-Path $repository '.gitattributes') -Text "*.ps1 text eol=crlf`n*.psm1 text eol=crlf`n"
    Set-ReviewCandidates -Repository $repository -Paths @()
    foreach ($coordinationPath in @(
        '作業用\実装計画.md',
        '作業用\大規模作業計画.md',
        '作業用\相談・事前調査.md'
    )) {
        Write-Utf8Text -Path (Join-Path $repository $coordinationPath) -Text "# coordination`n`n状態：なし`n"
    }

    Invoke-TestGit -Repository $repository -Arguments @(
        'add', '--',
        'tools/check-review-candidate.ps1',
        'ゲーム本体/base.ps1',
        '作業用/進行中の作業.md',
        '作業用/実装計画.md',
        '作業用/大規模作業計画.md',
        '作業用/相談・事前調査.md',
        'README.md',
        '.gitattributes'
    ) | Out-Null
    Invoke-TestGit -Repository $repository -Arguments @('commit', '--quiet', '-m', 'baseline') | Out-Null
    $repository
}

function Invoke-Checker {
    param(
        [Parameter(Mandatory = $true)][string]$Repository,
        [string]$WorkingDirectory = $Repository,
        [string]$FinalizationTreeId,
        [switch]$RequireAllCoordinationClosed
    )

    $checkerPath = Join-Path $Repository 'tools\check-review-candidate.ps1'
    $startInfo = New-Object System.Diagnostics.ProcessStartInfo
    $startInfo.FileName = $script:PowerShellExecutable
    $startInfo.Arguments = '-NoProfile -ExecutionPolicy Bypass -File "' + $checkerPath + '"'
    if (-not [string]::IsNullOrWhiteSpace($FinalizationTreeId)) {
        $startInfo.Arguments += ' -FinalizationTreeId "' + $FinalizationTreeId + '"'
    }
    if ($RequireAllCoordinationClosed) {
        $startInfo.Arguments += ' -RequireAllCoordinationClosed'
    }
    $startInfo.WorkingDirectory = $WorkingDirectory
    $startInfo.UseShellExecute = $false
    $startInfo.CreateNoWindow = $true
    $startInfo.RedirectStandardOutput = $true
    $startInfo.RedirectStandardError = $true
    if ($startInfo.PSObject.Properties.Name -contains 'StandardOutputEncoding') {
        $startInfo.StandardOutputEncoding = $script:Utf8NoBom
        $startInfo.StandardErrorEncoding = $script:Utf8NoBom
    }

    $process = New-Object System.Diagnostics.Process
    $process.StartInfo = $startInfo
    if (-not $process.Start()) {
        throw 'Checker process did not start.'
    }
    $standardOutput = $process.StandardOutput.ReadToEnd()
    $standardError = $process.StandardError.ReadToEnd()
    $process.WaitForExit()

    [pscustomobject]@{
        ExitCode = $process.ExitCode
        Output = $standardOutput + $standardError
    }
}

function Assert-Equal {
    param(
        [Parameter(Mandatory = $true)]$Expected,
        [Parameter(Mandatory = $true)]$Actual,
        [Parameter(Mandatory = $true)][string]$Message
    )

    if ($Expected -ne $Actual) {
        throw "$Message Expected=[$Expected] Actual=[$Actual]"
    }
}

function Assert-Contains {
    param(
        [Parameter(Mandatory = $true)][string]$Text,
        [Parameter(Mandatory = $true)][string]$Expected,
        [Parameter(Mandatory = $true)][string]$Message
    )

    if ($Text.IndexOf($Expected, [System.StringComparison]::Ordinal) -lt 0) {
        throw "$Message Missing=[$Expected] Output=[$Text]"
    }
}

function Assert-FailedFor {
    param(
        [Parameter(Mandatory = $true)]$Result,
        [Parameter(Mandatory = $true)][string]$ExpectedText
    )

    Assert-Equal -Expected 1 -Actual $Result.ExitCode -Message 'Checker should fail.'
    Assert-Contains -Text $Result.Output -Expected '[NG]' -Message 'Failure marker is missing.'
    Assert-Contains -Text $Result.Output -Expected $ExpectedText -Message 'Expected failure reason is missing.'
}

function Invoke-TestCase {
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)][scriptblock]$Body
    )

    try {
        & $Body
        $script:PassedCount++
        Write-Output "[PASS] $Name"
    } catch {
        $script:FailedTests.Add("$Name : $($_.Exception.Message)") | Out-Null
        Write-Output "[FAIL] $Name"
        Write-Output "  $($_.Exception.Message)"
    }
}

New-Item -ItemType Directory -Path $script:TestRoot -Force | Out-Null

try {
    Invoke-TestCase -Name 'valid candidate succeeds from a subdirectory and reports untracked files' -Body {
        $repository = New-TestRepository
        $candidate = 'ゲーム本体/日本語 ファイル.ps1'
        Write-Utf8Text -Path (Join-Path $repository 'ゲーム本体\日本語 ファイル.ps1') -Text "Write-Output '正常'`r`n" -Bom
        Write-Utf8Text -Path (Join-Path $repository '未追跡.txt') -Text "untracked`n"
        Set-ReviewCandidates -Repository $repository -Paths @($candidate)
        Invoke-TestGit -Repository $repository -Arguments @('add', '--', $candidate) | Out-Null
        $nested = Join-Path $repository 'sandbox\sub directory'
        New-Item -ItemType Directory -Path $nested -Force | Out-Null
        $before = (Invoke-TestGit -Repository $repository -Arguments @('-c', 'core.quotepath=false', 'status', '--porcelain=v1', '-uall')).Output
        $result = Invoke-Checker -Repository $repository -WorkingDirectory $nested
        $after = (Invoke-TestGit -Repository $repository -Arguments @('-c', 'core.quotepath=false', 'status', '--porcelain=v1', '-uall')).Output

        if ($result.ExitCode -ne 0) {
            throw "Valid candidate should pass. Output=[$($result.Output)]"
        }
        Assert-Contains -Text $result.Output -Expected '[OK]' -Message 'Success marker is missing.'
        Assert-Contains -Text $result.Output -Expected '未追跡ファイル: 1件' -Message 'Untracked file report is missing.'
        Assert-Equal -Expected $before -Actual $after -Message 'Checker must not mutate Git or files.'
    }

    Invoke-TestCase -Name 'Japanese PowerShell without BOM fails' -Body {
        $repository = New-TestRepository
        $candidate = 'tools/no-bom.ps1'
        Write-Utf8Text -Path (Join-Path $repository 'tools\no-bom.ps1') -Text "Write-Output '日本語'`r`n"
        Set-ReviewCandidates -Repository $repository -Paths @($candidate)
        Invoke-TestGit -Repository $repository -Arguments @('add', '--', $candidate) | Out-Null
        Assert-FailedFor -Result (Invoke-Checker -Repository $repository) -ExpectedText 'UTF-8 BOM'
    }

    Invoke-TestCase -Name 'LF-only PowerShell fails' -Body {
        $repository = New-TestRepository
        $candidate = 'tools/lf-only.ps1'
        Write-Utf8Text -Path (Join-Path $repository 'tools\lf-only.ps1') -Text "Write-Output 'ascii'`n"
        Set-ReviewCandidates -Repository $repository -Paths @($candidate)
        Invoke-TestGit -Repository $repository -Arguments @('add', '--', $candidate) | Out-Null
        Assert-FailedFor -Result (Invoke-Checker -Repository $repository) -ExpectedText 'CRLF以外'
    }

    Invoke-TestCase -Name 'mixed PowerShell line endings fail' -Body {
        $repository = New-TestRepository
        $candidate = 'tools/mixed.ps1'
        Write-Utf8Text -Path (Join-Path $repository 'tools\mixed.ps1') -Text "Write-Output 'one'`r`nWrite-Output 'two'`n"
        Set-ReviewCandidates -Repository $repository -Paths @($candidate)
        Invoke-TestGit -Repository $repository -Arguments @('add', '--', $candidate) | Out-Null
        Assert-FailedFor -Result (Invoke-Checker -Repository $repository) -ExpectedText '単独LF=1'
    }

    Invoke-TestCase -Name 'invalid UTF-8 PowerShell fails' -Body {
        $repository = New-TestRepository
        $candidate = 'tools/invalid-utf8.ps1'
        $path = Join-Path $repository 'tools\invalid-utf8.ps1'
        Ensure-ParentDirectory -Path $path
        [IO.File]::WriteAllBytes($path, [byte[]]@(0x66, 0x6F, 0x80, 0x0D, 0x0A))
        Set-ReviewCandidates -Repository $repository -Paths @($candidate)
        Invoke-TestGit -Repository $repository -Arguments @('add', '--', $candidate) | Out-Null
        Assert-FailedFor -Result (Invoke-Checker -Repository $repository) -ExpectedText 'UTF-8として読めない'
    }

    Invoke-TestCase -Name 'recorded and staged paths must match exactly' -Body {
        $repository = New-TestRepository
        Write-Utf8Text -Path (Join-Path $repository 'tools\actual.txt') -Text "actual`n"
        Set-ReviewCandidates -Repository $repository -Paths @('tools/expected.txt')
        Invoke-TestGit -Repository $repository -Arguments @('add', '--', 'tools/actual.txt') | Out-Null
        $result = Invoke-Checker -Repository $repository
        Assert-FailedFor -Result $result -ExpectedText 'tools/expected.txt'
        Assert-Contains -Text $result.Output -Expected 'tools/actual.txt' -Message 'Unexpected staged path should be reported.'
    }

    Invoke-TestCase -Name 'duplicate recorded candidate fails' -Body {
        $repository = New-TestRepository
        $candidate = 'tools/duplicate.txt'
        Write-Utf8Text -Path (Join-Path $repository 'tools\duplicate.txt') -Text "duplicate`n"
        Set-ReviewCandidates -Repository $repository -Paths @($candidate, $candidate)
        Invoke-TestGit -Repository $repository -Arguments @('add', '--', $candidate) | Out-Null
        Assert-FailedFor -Result (Invoke-Checker -Repository $repository) -ExpectedText '重複'
    }

    Invoke-TestCase -Name 'staged and unstaged overlap fails' -Body {
        $repository = New-TestRepository
        $candidate = 'README.md'
        Write-Utf8Text -Path (Join-Path $repository 'README.md') -Text "staged version`n"
        Invoke-TestGit -Repository $repository -Arguments @('add', '--', $candidate) | Out-Null
        Write-Utf8Text -Path (Join-Path $repository 'README.md') -Text "unstaged version`n"
        Set-ReviewCandidates -Repository $repository -Paths @($candidate)
        Assert-FailedFor -Result (Invoke-Checker -Repository $repository) -ExpectedText '未ステージ変更'
    }

    Invoke-TestCase -Name 'cached diff whitespace error fails' -Body {
        $repository = New-TestRepository
        $candidate = 'tools/trailing.txt'
        Write-Utf8Text -Path (Join-Path $repository 'tools\trailing.txt') -Text "trailing space `n"
        Set-ReviewCandidates -Repository $repository -Paths @($candidate)
        Invoke-TestGit -Repository $repository -Arguments @('add', '--', $candidate) | Out-Null
        Assert-FailedFor -Result (Invoke-Checker -Repository $repository) -ExpectedText 'git diff --cached --check'
    }

    Invoke-TestCase -Name 'active coordination documents in staged candidate fail' -Body {
        foreach ($candidate in @(
            '作業用/実装計画.md',
            '作業用/進行中の作業.md',
            '作業用/大規模作業計画.md',
            '作業用/相談・事前調査.md'
        )) {
            $repository = New-TestRepository
            if ($candidate -ne '作業用/進行中の作業.md') {
                Write-Utf8Text -Path (Join-Path $repository $candidate.Replace('/', '\')) -Text "# coordination`n`n状態：進行中`n"
            }
            Set-ReviewCandidates -Repository $repository -Paths @($candidate)
            Invoke-TestGit -Repository $repository -Arguments @('add', '--', $candidate) | Out-Null
            Assert-FailedFor -Result (Invoke-Checker -Repository $repository) -ExpectedText '有効な調整文書'
        }
    }

    Invoke-TestCase -Name 'inactive coordination template can be reviewed' -Body {
        $repository = New-TestRepository
        $candidate = '作業用/大規模作業計画.md'
        Write-Utf8Text -Path (Join-Path $repository '作業用\大規模作業計画.md') -Text "# large plan`n`n状態：なし`n"
        Set-ReviewCandidates -Repository $repository -Paths @($candidate)
        Invoke-TestGit -Repository $repository -Arguments @('add', '--', $candidate) | Out-Null
        $result = Invoke-Checker -Repository $repository
        if ($result.ExitCode -ne 0) {
            throw "Inactive coordination template should pass. Output=[$($result.Output)]"
        }
        Assert-Contains -Text $result.Output -Expected '[OK]' -Message 'Success marker is missing.'
    }

    Invoke-TestCase -Name 'consultation notes protect both active states and allow the closed template' -Body {
        foreach ($state in @('調査中', '調査完了', 'なし')) {
            $repository = New-TestRepository
            $candidate = '作業用/相談・事前調査.md'
            Write-Utf8Text -Path (Join-Path $repository $candidate) -Text "# consultation`n`n状態：$state`n"
            Set-ReviewCandidates -Repository $repository -Paths @($candidate)
            Invoke-TestGit -Repository $repository -Arguments @('add', '--', $candidate) | Out-Null
            $result = Invoke-Checker -Repository $repository
            if ($state -eq 'なし') {
                Assert-Equal -Expected 0 -Actual $result.ExitCode -Message "Closed consultation template should pass. $($result.Output)"
            } else {
                Assert-FailedFor -Result $result -ExpectedText '有効な調整文書'
            }
        }
    }

    Invoke-TestCase -Name 'full finalization checks consultation notes outside the candidate' -Body {
        $repository = New-TestRepository
        Write-Utf8Text -Path (Join-Path $repository '作業用/進行中の作業.md') -Text "# progress`n`n状態：なし`n"
        Write-Utf8Text -Path (Join-Path $repository 'README.md') -Text "changed`n"
        Invoke-TestGit -Repository $repository -Arguments @('add', '--', 'README.md') | Out-Null
        $treeId = (Invoke-TestGit -Repository $repository -Arguments @('write-tree')).Output.Trim()
        foreach ($state in @('調査中', '調査完了', 'なし')) {
            Write-Utf8Text -Path (Join-Path $repository '作業用/相談・事前調査.md') -Text "# consultation`n`n状態：$state`n"
            $result = Invoke-Checker -Repository $repository -FinalizationTreeId $treeId -RequireAllCoordinationClosed
            if ($state -eq 'なし') {
                Assert-Equal -Expected 0 -Actual $result.ExitCode -Message "Closed consultation notes should allow finalization. $($result.Output)"
            } else {
                Assert-FailedFor -Result $result -ExpectedText '作業用/相談・事前調査.md'
            }
        }
    }

    Invoke-TestCase -Name 'finalization accepts an inactive progress template with the approved tree' -Body {
        $repository = New-TestRepository
        $progressPath = Join-Path $repository '作業用\進行中の作業.md'
        Write-Utf8Text -Path $progressPath -Text "# progress template`n`n状態：なし`n`n### ステージ済みレビュー候補`n"
        Invoke-TestGit -Repository $repository -Arguments @('add', '--', '作業用/進行中の作業.md') | Out-Null
        $treeId = (Invoke-TestGit -Repository $repository -Arguments @('write-tree')).Output.Trim()
        $result = Invoke-Checker -Repository $repository -FinalizationTreeId $treeId
        if ($result.ExitCode -ne 0) {
            throw "Inactive progress template should pass finalization. Output=[$($result.Output)]"
        }
        Assert-Contains -Text $result.Output -Expected '検査モード: 最終化' -Message 'Finalization mode report is missing.'
        Assert-Contains -Text $result.Output -Expected $treeId -Message 'Finalization tree ID report is missing.'
    }

    Invoke-TestCase -Name 'phase finalization allows an active large-work plan but full closure rejects it' -Body {
        $repository = New-TestRepository
        $progressPath = Join-Path $repository '作業用\進行中の作業.md'
        $largePlanPath = Join-Path $repository '作業用\大規模作業計画.md'
        Write-Utf8Text -Path $progressPath -Text "# progress template`n`n状態：なし`n`n### ステージ済みレビュー候補`n"
        Write-Utf8Text -Path $largePlanPath -Text "# active large plan`n`n状態：進行中`n"
        Invoke-TestGit -Repository $repository -Arguments @('add', '--', '作業用/進行中の作業.md') | Out-Null
        $treeId = (Invoke-TestGit -Repository $repository -Arguments @('write-tree')).Output.Trim()

        $phaseResult = Invoke-Checker -Repository $repository -FinalizationTreeId $treeId
        if ($phaseResult.ExitCode -ne 0) {
            throw "Phase finalization should allow an active large-work plan. Output=[$($phaseResult.Output)]"
        }
        Assert-FailedFor -Result (
            Invoke-Checker -Repository $repository -FinalizationTreeId $treeId -RequireAllCoordinationClosed
        ) -ExpectedText '作業用/大規模作業計画.md'
    }

    Invoke-TestCase -Name 'finalization rejects an active coordination document' -Body {
        $repository = New-TestRepository
        $candidate = 'README.md'
        Write-Utf8Text -Path (Join-Path $repository $candidate) -Text "changed`n"
        Invoke-TestGit -Repository $repository -Arguments @('add', '--', $candidate) | Out-Null
        $treeId = (Invoke-TestGit -Repository $repository -Arguments @('write-tree')).Output.Trim()
        Assert-FailedFor -Result (Invoke-Checker -Repository $repository -FinalizationTreeId $treeId) -ExpectedText '最終化できない調整文書'
    }

    Invoke-TestCase -Name 'finalization rejects a candidate changed after approval' -Body {
        $repository = New-TestRepository
        $progressPath = Join-Path $repository '作業用\進行中の作業.md'
        Write-Utf8Text -Path $progressPath -Text "# progress template`n`n状態：なし`n`n### ステージ済みレビュー候補`n"
        Write-Utf8Text -Path (Join-Path $repository 'README.md') -Text "approved`n"
        Invoke-TestGit -Repository $repository -Arguments @('add', '--', '作業用/進行中の作業.md', 'README.md') | Out-Null
        $approvedTreeId = (Invoke-TestGit -Repository $repository -Arguments @('write-tree')).Output.Trim()
        Write-Utf8Text -Path (Join-Path $repository 'tools\unexpected.txt') -Text "unexpected`n"
        Invoke-TestGit -Repository $repository -Arguments @('add', '--', 'tools/unexpected.txt') | Out-Null
        Assert-FailedFor -Result (Invoke-Checker -Repository $repository -FinalizationTreeId $approvedTreeId) -ExpectedText '承認済み候補と一致しません'
    }

    Invoke-TestCase -Name 'coordination document without one valid state line fails' -Body {
        $repository = New-TestRepository
        $candidate = '作業用/相談・事前調査.md'
        Write-Utf8Text -Path (Join-Path $repository '作業用\相談・事前調査.md') -Text "# research`n"
        Set-ReviewCandidates -Repository $repository -Paths @($candidate)
        Invoke-TestGit -Repository $repository -Arguments @('add', '--', $candidate) | Out-Null
        Assert-FailedFor -Result (Invoke-Checker -Repository $repository) -ExpectedText '状態行を一意に確認できません'
    }

    Invoke-TestCase -Name 'deleted coordination document fails' -Body {
        $repository = New-TestRepository
        $candidate = '作業用/相談・事前調査.md'
        $candidatePath = Join-Path $repository '作業用\相談・事前調査.md'
        Write-Utf8Text -Path $candidatePath -Text "# research`n`n状態：なし`n"
        Invoke-TestGit -Repository $repository -Arguments @('add', '--', $candidate) | Out-Null
        Invoke-TestGit -Repository $repository -Arguments @('commit', '--quiet', '-m', 'add coordination document') | Out-Null
        Set-ReviewCandidates -Repository $repository -Paths @($candidate)
        Remove-Item -LiteralPath $candidatePath
        Invoke-TestGit -Repository $repository -Arguments @('add', '--', $candidate) | Out-Null
        Assert-FailedFor -Result (Invoke-Checker -Repository $repository) -ExpectedText '作業ツリーに存在しません'
    }

    Invoke-TestCase -Name 'invalid UTF-8 coordination document fails' -Body {
        $repository = New-TestRepository
        $candidate = '作業用/相談・事前調査.md'
        $candidatePath = Join-Path $repository '作業用\相談・事前調査.md'
        Ensure-ParentDirectory -Path $candidatePath
        [IO.File]::WriteAllBytes($candidatePath, [byte[]]@(0x23, 0x20, 0x80, 0x0A))
        Set-ReviewCandidates -Repository $repository -Paths @($candidate)
        Invoke-TestGit -Repository $repository -Arguments @('add', '--', $candidate) | Out-Null
        Assert-FailedFor -Result (Invoke-Checker -Repository $repository) -ExpectedText 'UTF-8として読めません'
    }

    Invoke-TestCase -Name 'empty stage fails' -Body {
        $repository = New-TestRepository
        Set-ReviewCandidates -Repository $repository -Paths @()
        Assert-FailedFor -Result (Invoke-Checker -Repository $repository) -ExpectedText 'ステージ済みレビュー候補がありません'
    }

    Invoke-TestCase -Name 'cleanup guard accepts only the dedicated temporary root' -Body {
        Assert-Equal -Expected $true -Actual (Test-IsSafeCleanupRoot -Path $script:TestRoot) -Message 'Dedicated root should be removable.'
        Assert-Equal -Expected $false -Actual (Test-IsSafeCleanupRoot -Path (Get-Location).ProviderPath) -Message 'Workspace must never be removable.'
        Assert-Equal -Expected $false -Actual (Test-IsSafeCleanupRoot -Path ([IO.Path]::GetTempPath())) -Message 'Temp root itself must never be removable.'
    }
} finally {
    if (Test-Path -LiteralPath $script:TestRoot) {
        if (-not (Test-IsSafeCleanupRoot -Path $script:TestRoot)) {
            throw "Unsafe cleanup path rejected: $script:TestRoot"
        }
        Remove-Item -LiteralPath $script:TestRoot -Recurse -Force
    }
}

Write-Output "[SUMMARY] Passed=$($script:PassedCount) Failed=$($script:FailedTests.Count)"
if ($script:FailedTests.Count -ne 0) {
    foreach ($failure in $script:FailedTests) {
        Write-Output "  - $failure"
    }
    exit 1
}

exit 0
