# AI向けサーバー操作手順

自宅Windows PC上で、AIが通常利用のゲームサーバーを起動・停止し、改修後に再起動するための手順。利用頻度が低いため、既存の起動処理とWindowsの操作を利用する。専用BAT・常設の管理スクリプト・管理用データは追加しない。操作のたびに本書を読み、ユーザーの現在の依頼範囲を確認する。

自動試験用の隔離サーバーの起動・回収は、既存の[自動検査の手順](技術仕様/自動検査・Git.md)に従う。試験には本書の保存済みキーによる起動例を使用しない。

## 対象と操作前の確認

- 対象は正規ルートの`ゲーム本体`と既定ポート`8788`。普段の入口は`屋外接続用_保存済みAPIキーでGrok接続.bat`である。
- このBATはWindows PowerShell 5.1で`launch-node-grok.ps1 -UseSavedApiKeys -LocalOnly`を実行する。AIからも同じ保存済みキー・localhost限定待受けを使う。
- 保存済みキーを利用できる同じWindowsユーザーで操作する。PC・Windowsユーザー・ゲーム本体の場所が変わった場合のキー再登録は、別のユーザー判断とする。
- 起動・停止・再起動は同時に複数チャットから行わない。再起動前は、ユーザーが必要な保存を済ませ、会話送信・画像生成・保存などの処理中を避ける。現在の依頼で確認できていれば重ねて確認を求めない。
- Tailscale Serveは既存の設定を利用する。ゲームサーバーの停止に伴ってTailscaleを停止・再設定しない。
- APIキー、環境変数の一覧、保存済みキーのファイル、会話・セーブ・画像の本文を操作確認のために出力しない。キーの復号・受渡しは既存のGrok起動処理へ任せる。

## 状態と対象の確認

1. `Get-NetTCPConnection -LocalPort 8788 -State Listen`で待受けPIDを調べる。待受けがない場合も、起動途中の対象Node.js・起動用PowerShellが残っていないか確認する。情報の取得失敗を「停止済み」と解釈しない。
2. `Get-CimInstance Win32_Process`で候補PIDの実行ファイル、起動時刻、親PIDを調べる。コマンドラインは処理内で照合し、全文を出力しない。Node.jsの入口が正規の`ゲーム本体/node-server/src/main.js`で、ポート8788と`--local-only`を使用し、親が対象の保存済みGrok起動処理であることを確認する。
3. Node.js以外の待受け、別コピー、別の起動方式、複数候補、取得不能を認めたら、起動や停止を強行せず状況を報告する。ポート番号、プロセス名、HTTP応答のいずれか一つだけで対象を決めない。
4. 対象が確認できた場合に、次の読取専用APIで応答を確認する。

```powershell
$status = Invoke-RestMethod -Uri 'http://127.0.0.1:8788/api/status' -TimeoutSec 3
$status | Select-Object mode, model, verified
```

通常の対象は`mode = grok`。`verified`はGrok通信の確認状態であり、起動直後に`false`でも起動失敗とは限らない。このAPIは既存状態を返すだけなので、確認のために会話送信や画像生成を行わない。

## 起動

既に対象が起動していれば重複起動せず、その状態を報告する。対象の起動途中・停止途中が残っている場合も追加起動しない。

AIからの起動では、BATが呼ぶ既存の`launch-node-grok.ps1`を直接利用できる。次の例は同じ起動設定に`-NoBrowser`を加えてPCのブラウザ自動表示だけを省き、BAT末尾の`pause`を経由しない。Node.jsの保存先などの既定値は既存スクリプトに任せる。

プロジェクトの正規ルートを作業ディレクトリにし、対象と起動途中プロセスがないことを確認してから実行する。

```powershell
$gameRoot = (Resolve-Path -LiteralPath '.\ゲーム本体').Path
$windowsPowerShell = Join-Path $env:WINDIR 'System32\WindowsPowerShell\v1.0\powershell.exe'
$launchScript = Join-Path $gameRoot 'launch-node-grok.ps1'
$null = Get-Command Start-Process -ErrorAction Stop
$modulePathBefore = [Environment]::GetEnvironmentVariable('PSModulePath', 'Process')
try {
    $windowsModules = Join-Path $env:WINDIR 'System32\WindowsPowerShell\v1.0\Modules'
    [Environment]::SetEnvironmentVariable('PSModulePath', $windowsModules, 'Process')
    $launchArguments = '-NoProfile -NonInteractive -ExecutionPolicy Bypass -File "' +
        $launchScript + '" -UseSavedApiKeys -LocalOnly -NoBrowser'
    $launcher = Start-Process -FilePath $windowsPowerShell -ArgumentList $launchArguments `
        -WorkingDirectory $gameRoot -WindowStyle Hidden -PassThru
} finally {
    [Environment]::SetEnvironmentVariable('PSModulePath', $modulePathBefore, 'Process')
}
$launcher | Select-Object Id, ProcessName, StartTime
```

PowerShell 7の`PSModulePath`をそのままWindows PowerShell 5.1へ渡すと、Securityモジュールの読込みが失敗し、保存済みキーの読取失敗に見える場合がある。上例では、子の起動時だけWindows PowerShellの標準モジュールを優先させる。ユーザー・マシンの永続環境変数は変更しない。

`-Wait`やサーバーの標準出力を終了まで読み続ける方法は使わず、操作の呼出しを終了しても稼働する専用コンソールで起動する。上例はウィンドウを非表示にするため、黒い画面の有無では稼働を判断しない。

起動後は、起動したPowerShellと子Node.jsの実行元・起動時刻、待受け、`/api/status`を確認する。目安30秒で確認できなければ、成功と報告せず追加起動を止め、残存プロセスを調べる。キーの再登録・削除や強制終了を自動的に行わない。ローカルでの起動確認後、必要な場合はユーザーがiPhoneから既存のTailscale URLを開いて確認する。

## 停止

Node.jsは既に`SIGINT`による終了処理を備えている。対象が確定した専用コンソールへCtrl+C相当を送り、この終了処理を利用する。通常のBATをダブルクリックして起動した対象にも同じ考え方を使う。

1. 状態確認の手順で対象Node.jsと親の起動用PowerShell、BAT経由ならその`cmd.exe`を特定し、PIDと起動時刻を控える。操作直前に同一プロセスであることを再確認する。
2. 対象に紐づく専用ターミナルのセッションへCtrl+Cを送れる場合は、そのセッションを利用する。対象不明の画面へキーボード操作を送らない。
3. 専用ターミナルを操作できない場合は、一時的な子Windows PowerShellからWindowsコンソールAPIを呼ぶ。子はウィンドウを非表示にし、常設ファイルを作らず、その操作だけで終了させる。
4. 子で`FreeConsole`、`AttachConsole(対象Node.jsのPID)`を順に実行し、`GetConsoleProcessList`で接続先を確認する。自分自身を除き、確認したゲーム用Node.js・起動用PowerShell・必要なBAT用cmdだけが所属することを確かめる。想定外のプロセス、取得不能、共用コンソールならCtrl+Cを送らず切り離して終了する。
5. **AttachConsoleの後で**`SetConsoleCtrlHandler(NULL, TRUE)`を呼び、操作用の子自身がCtrl+Cで終了しないようにする。その後、`GenerateConsoleCtrlEvent(0, 0)`でCtrl+Cを送る。これは接続先コンソール全体への送信なので、前項の確認を省かない。送信の成否を確認し、最後に`FreeConsole`で切り離す。
6. 対象Node.jsの終了とポート8788の待受け解除を確認する。HTTP接続失敗だけで停止完了としない。目安15秒で終了を確認できなければ、自動強制終了や起動の追加をせず未完了として報告する。
7. Node.js終了後、起動用PowerShellの終了も確認する。BAT経由では`pause`やバッチ終了確認でcmdだけが残る場合がある。専用の起動用プロセスと再確認できたものだけを終了させ、黒い画面を閉じる。ユーザーの共用ターミナルは閉じない。

`Stop-Process`、`taskkill`、同名Node.jsの一括終了を、ゲーム本体の通常停止の代わりに使わない。終了待ちのために別の停止APIをゲームへ追加しない。

## 再起動と結果報告

停止手順で対象Node.jsと起動用プロセスの終了を確認してから、起動手順を一度実行する。停止完了が不明な場合は起動へ進まない。改修したコードが原因で起動できない場合は、停止状態と原因を報告し、勝手にコードを戻さない。

結果は、実行した操作、対象の実行元・ポート、プロセスとローカル応答の確認結果、残っている確認を簡潔に報告する。PC内での確認とiPhoneの接続確認を区別し、iPhone未確認を確認済みとしない。ユーザーは再起動後にページを再読込して改修内容を確認する。

## 照合先

- 起動条件とキー受渡し：`../ゲーム本体/屋外接続用_保存済みAPIキーでGrok接続.bat`、`../ゲーム本体/launch-node-grok.ps1`、`../ゲーム本体/launch-node.ps1`
- 終了処理：`../ゲーム本体/node-server/src/main.js`、`../ゲーム本体/node-server/src/bootstrap/shutdown.js`
- 状態API：`../ゲーム本体/node-server/src/api/read-only.js`、`../ゲーム本体/node-server/src/domain/runtime-model.js`
- 接続・キー保存の前提：[プロジェクト設定](プロジェクト設定.md#接続起動とapiキー)、[実行構成](技術仕様/実行構成・ブラウザ.md#サーバー構成)
