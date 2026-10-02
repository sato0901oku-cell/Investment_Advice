# 自動検査・Git

[技術仕様・保守ガイドへ戻る](../技術仕様・保守ガイド.md)

## 自動検査

- 全体検査と起動基盤検査のBATは`ゲーム本体/検査・テスト`を正規配置とする。`キャラクター素材を事前検査.bat`はキャラクター登録・差し替え時のドラッグ＆ドロップ入口であるため、キャラクター管理BATとともに`ゲーム本体`直下へ残す。

### よく使う入口と実行フォルダ

| 実行フォルダ | 入口 | 用途 |
| --- | --- | --- |
| プロジェクト直下 | `powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\ゲーム本体\validate-project.ps1` | 設定・素材検査 |
| プロジェクト直下 | `powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\ゲーム本体\test-game.ps1 -Area all` | Node全件を含む全領域検査 |
| `ゲーム本体` | `powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\test-game.ps1 -Area <領域名>` | 前段を含む領域別検査 |
| `ゲーム本体/node-server` | `npm test`／`npm run test:affected` | Node全件／影響範囲による検査選択 |
| `ゲーム本体/node-server` | `node --test --test-concurrency=1 test/<ファイル名>.test.js` | 個別Node試験 |

完了検査の選択は次の「変更リスクと完了検査」に従う。機能別の担当試験や保証の詳細は後半の「試験の構成・保証範囲」を参照する。

### `検査・テスト/設定・素材を検査.bat`

- JSON構文、設定ID、必須ファイル、人格、デモ、背景、立ち絵、音源、表示値、HTMLとJavaScriptの依存、全ユーザー向けHTMLの存在と相対リンク先を読み取り専用で検査する。`visual-transitions.json`は版、既知ID、空・正規化重複・ID間衝突、必須の基本服装語彙、禁止した広すぎる背景語彙を検査し、`demo-rules.json`に服装・背景規則が戻っていないことも確認する。文書本文と実装の意味上の一致は自動判定せず、変更影響早見表に沿って確認する。
- Grok・NovelAI APIは使用しない。

### `検査・テスト/ゲーム内部動作を検査.bat`

Node試験の標準完全入口は`ゲーム本体/node-server`で`npm test`（固定並列数2）とする。個別ファイル確認だけは`node --test --test-concurrency=1 test/<ファイル名>`で直列実行する。支援は`test-support/`の通常JSで、importのみで試験登録・サーバー起動・ファイル生成をしない。

- 領域は「ソース契約・画面・HTTP基盤」「シーン画像・アルバム」「設定・素材・音声」「会話・重要記憶・再送」「セーブ・現行形式」「Grok設定・ネットワーク防御」の順に実行する。`検査・テスト/ゲーム内部動作を検査.bat`は全領域を一括実行する。
- 保守作業で途中領域まで確認したい場合は、`ゲーム本体`で`powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\test-game.ps1 -Area chat-memories`のように実行できる。Node全件が確認済みの反復では末尾に`-SkipNodeUnitTests`を追加できる。いずれも指定領域だけを孤立実行するのではなく、依存する前段領域から指定領域までを順番に実行する。並列失敗の切分けには`npm run test:serial`を使う。Node全件だけを確認する場合は`npm test`、全領域まで確認する場合はNode全件を内包する`test-game.ps1 -Area all`を使用し、両方を連続実行しない。
- `-Area`に指定できる値は`source-contracts`、`scene-images`、`configuration-assets`、`chat-memories`、`saves`、`grok-network`である。高リスク・横断・未知変更または節目の全体確認では、`検査・テスト/ゲーム内部動作を検査.bat`または`-Area all`を使用する。
- `configuration-assets`の軽量検査に続き、同じ領域内で`tests/areas/03-character-lifecycle.ps1`を一度実行する。この補助検査は人物パッケージ、登録・差し替え、登録解除の既存保証を所有し、公開`-Area`を増やさない。通常時と`-Area all`では必ず実行する。内部用`-SkipCharacterLifecycleTests`は`chat-memories`、`saves`、`grok-network`に限り受理し、`all`と前3領域では開始前に拒否する。
- 標準BATのNode.js起動ラッパーと検査はWindows PowerShell 5.1を使用し、HTTP／APIサーバー本体はNode.js 24で実行する。日本語を含む`launch-node*.ps1`、`api-key-store.psm1`、`manage-api-keys.ps1`、`validate-project.ps1`、`test-game.ps1`、`tests/test-support.ps1`、`tests/areas`、`tests/source-contracts`、`tests/validation`配下のPS1は、編集後もUTF-8 BOM付きを維持する。セーブ試験では新規スロット名が「セーブ1」と保存されることまで確認する。

### 変更リスクと完了検査

| 区分 | 該当条件 | 完了検査 |
| --- | --- | --- |
| 内部文書だけ | 実行時に読み込まれない`作業用`文書・READMEだけを変更し、コード、設定、素材、ユーザー向け資料、試験、依存、ファイル配置を変えない | 文書の意味と相互整合の差分確認、記載したパス・コマンドの実在確認、`git diff --check`、役割分担時のレビュー候補の定型検査。アプリ自動試験は原則実行しない |
| 影響範囲が明確な通常変更 | 全変更パスが影響表の既知領域に収まり、選択基盤が完全フォールバックを示さず、下記の高リスク条件にも該当しない | 最終候補と同じ差分に対する`npm run test:affected`の全選択検査。必要な実機確認は別途実施する |
| 高リスク・横断・未知変更 | セーブ形式・永続化・保存データ／生成画像の完全削除処理、外部API・課金防止・再送、HTTP防御、同時実行・終了、試験基盤・影響規則・共通支援・依存・起動／検査入口、広範な横断変更、未知パス、選択結果の完全フォールバック、影響を安全に限定できない変更 | 関係する場合は設定・素材検査を実行し、標準全体検査として`test-game.ps1 -Area all`を1回実行する。これは内部で`npm test`を1回実行するため、同じ候補に対して別途`npm test`を重ねない |

作業規模と変更リスクは別に判定する。複数の独立成果物、三領域以上の横断、移行、影響を一候補へ限定しにくい変更は大規模化の警告条件だが、それ自体を高リスク判定の代わりにしない。複数段階では`作業用/大規模作業計画.md`、相談・調査の判断材料を残す場合は任意で`作業用/相談・事前調査.md`を使用し、現在フェーズだけを`作業用/実装計画.md`へ詳細化する。

人物ライフサイクル補助検査の自動省略は、影響規則が不要と明示し、完全フォールバックがなく、最終領域が後続3領域のいずれかである場合だけ行う。試験基盤・影響規則自体の変更は上表の高リスク条件で扱い、全領域検査から補助検査を省かない。

`test:affected`は文書の役割で影響を選ぶ。四つの調整文書（`作業用/実装計画.md`、`作業用/進行中の作業.md`、`作業用/大規模作業計画.md`、`作業用/相談・事前調査.md`）と、`AGENTS.md`、ルートの`README.md`、`ゲーム本体/node-server/README.md`、調整文書を除く`作業用`配下のMarkdown・HTML・TXTは、アプリ検査対象外とする。内部文書の意味と相互整合は上表の専用条件で人が確認する。

`ゲーム本体/ユーザー向け資料`配下のHTMLは設定・素材検査だけを選ぶ。実行時に読み込むプロンプト、画面HTML、音源利用記録、無効化された人物のREADME、人物登録テンプレートのテキストは、それぞれの製品固有規則を適用する。明示規則に当てはまらない新規Markdown等は完全フォールバックとする。内部文書を製品コードと同時に変更しても、製品コード単独と同じ検査を選ぶ。

初回のレビュー候補で`test:affected`を完了根拠にする場合は、全候補パスが表示され、適用規則と選択範囲を説明でき、選択された全検査が成功し、その後に候補が変わっていないことを条件とする。高リスク条件に該当するか判断できない場合は高リスクとして扱う。

実装中の反復は、直接対象試験、変更ファイルの構文・設定検査、必要な非`all`領域を使用する。`test:affected`または`test-game.ps1 -Area all`による完了検査は、レビュー候補を固定して候補定型検査とtree ID確認を済ませた後に実行し、修正のたびに完了検査を繰り返さない。

`test-game.ps1 -Area all`を選ぶ場合は、上表の該当条件または次項の節目と、`test:affected`では不足する責務境界を、計画を作る作業では`作業用/実装計画.md`、それ以外では`作業用/進行中の作業.md`へ短く記録する。「念のため」「重要な変更」だけを選択理由にしない。

高リスクでなくても、複数の通常変更をまとめて統合する節目、配布・大きなバックアップ前、変更領域を越えた不具合が疑われる場合、またはユーザーが全体確認を求めた場合は、健全性確認として`test-game.ps1 -Area all`を1回実行する。節目の全体検査を各小変更へ機械的に重ねない。

### 計画範囲と条件付き随伴ファイル

- 計画では既知の変更予定ファイルを列挙したうえで、主要変更との直接依存があり、既存の不変条件と期待結果を変えずに追随させられる試験fixture、静的契約、必須ファイル一覧などを「条件付き随伴範囲」として事前定義できる。該当する機械的更新は計画内とし、実際のパスと直接依存の根拠を`作業用/進行中の作業.md`へ記録して候補に含める。
- 製品コード、仕様、API、セーブ、完了条件、試験の期待結果を変える変更、直接依存を説明できない変更、または随伴更新を起点に別責務へ広がる変更は条件付き随伴範囲に含めない。計画・差分レビュー担当による再判定と、必要なユーザー判断を得る。
- 抽出、移設、削除、名称変更を計画する場合は、旧シンボル・旧パス・直接呼出しだけでなく、ソース文字列assert、`app.js`等の部分評価fixture、PowerShell静的契約、必須ファイル一覧、技術資料の経路表を`rg`等で事前に探索する。判明したファイルは条件付き扱いにせず既知の変更予定ファイルへ加える。
- 既知パスの列挙後、`ゲーム本体/node-server`で`npm run test:affected -- --list --planned-path <リポジトリ相対パス>`を各パスに指定し、適用規則・選択範囲・完全フォールバックを検査計画へ記録する。未知パス、想定外の完全フォールバック、影響拡大があれば承認前に範囲または分割を見直す。これは試験の選択だけであり、依存ファイルの探索も最終候補の完了検査も代用しない。

### 自動試験を追加・維持する基準

- 自動試験を追加・変更する場合は、守る契約・不変条件、通す責務境界、検出するはずの現実的な誤実装を説明できることを条件とする。終了コード、件数、関数名、ソース文字列だけを観測し、利用先へ渡る状態や結果を確認しない試験は、補助的な構造検査を除き完了条件の主な根拠にしない。
- 同じ契約を複数層で検査する場合は、純粋な値・境界、実装間の接続、HTTP契約、画面到達性など、各層が固有に保証する責務を分ける。同じ責務境界と入力分類を既存試験が直接確認している場合は、その試験を拡張し、固有の保証を説明できない重複試験を追加しない。
- 高リスク変更では、主要な失敗モードから見落としやすい誤実装を一つ選び、どの観測で検出できるか確認する。検出力を判断しにくい場合は故障注入や一時変異を使えるが、その確認を恒久試験として残すのは、重要で再発しやすい誤実装を継続検出する必要がある場合だけとする。
- 試験数や実行時間だけを理由に試験を削除しない。同じ契約をより直接に保証する試験が別にあると確認できた場合だけ、統合または削除する。

- エンディングの責務検査は、設定正規化・編集を`browser-adventure-configuration`／`browser-adventure-settings`、確定値判定・総括後の明示開始・連打・旧応答・再試行／省略を`browser-story-choices`、厳格入力と応答・共有再送・取消を`api-gameplay`、実HTTPモックと使用量を`gameplay-api-integration`、実ブラウザ出力の各安定状態からv24保存・再読込・同一要求再送を`persistence-integration`が担当する。3択のシステム向け文脈と場面確定後の人物経験の境界は`api-gameplay`、`browser-chat-request`、`chat-prompt`で直接観測する。実Grokの確率的描写は保証対象外。

### 横断契約の計画と観測

- データの作成・受理・変換・適用条件を変える場合は、影響する受渡しで前段の出力と後段の受理条件（文字・長さ・件数・順序・重複）を照合する。編集中と確定時などの意図した差は一律に揃えず、必要な変換・拒否の責務を確認する。同じ条件は責務境界を崩さない範囲で共用し、共用が不適切な場合は同じ代表データで実装間の整合を検査する。
- 接続を保証する試験では、対象となる実処理の出力を次の実処理へ渡して結果を確認し、途中を手作りの正常値へ差し替えて接続保証の代わりにしない。外部APIは従来どおりモックを使い、未確認の境界は保証に含めない。
- 上記は変更の影響範囲に適用し、該当する送信・反映・保存・再読込の観測を既存の検査計画・対応表へ組み込む。毎回の全体調査・全経路試験・新しい帳票は求めず、既存試験が直接保証していれば追加不要とする。完了検査の選択は「変更リスクと完了検査」に従う。
- 高リスク・横断・未知変更の計画では、重要な状態・データ・不変条件ごとに、正本、作成・変更入口、読取・送信・表示・保存先、取消・失敗・競合時の扱い、期待結果と直接の観測方法を追跡できるように記載する。試験名だけでなく判定する状態・引数・順序等を示し、非該当と未検討を区別する。表、箇条書き、既存の受入シナリオから適切な形式を選び、同じ対応関係を別表へ重複させない。
- 保存形式、API必須項目、共通状態を変更する場合は、全送信元、受信・検証先、実行時利用先、保存・一覧、試験fixture、PowerShell実HTTP試験、ユーザー向け資料を同じ契約の連動先として扱う。
- 純粋なモジュール試験は状態変換、アプリ接続試験は`app.js`等の配線、実HTTP試験は直列化後の要求とサーバー契約、保存試験は再読込、実機手順は画面到達性と利用者が観察できる結果を受け持つ。一つの層の合格を別の層の接続保証として代用しない。試験名や合格件数だけでなく、期待結果を直接判定するassertまたは観測箇所を確認する。
- 取消、検証失敗、競合、再読込、部分適用防止の受入シナリオは、開始状態、操作順、観察対象、保持すべき状態、変化すべき状態を具体的に記載し、操作前後で保持すべき全状態を比較する。実機項目は現在の画面から到達できる操作だけで再現できることを条件とする。
- 状態制御は成功・途中失敗・取消・旧処理の遅延完了などの順序を、自然言語判定は肯定・拒否・混在などの代表入力と期待判定を、必要に応じて状態遷移表・入力分類表で整理する。対象とリスクに応じて既存の対応表やシナリオで十分なら別表は不要であり、全作業へ一律に義務化しない。回帰用の個別例は対象の自動試験へ残し、恒久資料へ大量に複製しない。

- 時刻付き状態・非同期・外部副作用を変更または指摘する場合は、状態の作成・更新・失効時刻、待機・時計変更の処理位置を具体化する。複数の期限・世代・再送キャッシュ・保留結果では、一方だけが失効し他方が有効な組合せも確認する。外部処理の所要時間は、要求前だけでなく模擬外部処理の内部など実際に起点が分かれる位置で時計を進めて再現する。課金・外部副作用では成功、同一本文・異なる本文、期限ずれについて、外部呼出回数、保存回数、結果ID、エラーコード、元状態の維持をassertする。
- 指摘の再現条件には、開始状態、操作順、修正前の観測値、修正後の期待結果を示す。非同期・時刻境界の指摘では、該当する各状態の期限がずれる順序と維持・拒否すべき対照ケースも示し、「境界を越える」「期限内」だけにしない。再現試験を追加できる場合は修正前の原因経路で失敗する条件を保って修正後の合格を確認する。指定された時刻・非同期段階の簡略化で再現条件が変わる場合、実装担当は独自に置き換えず計画・差分レビュー担当へ戻す。

### 最終候補と検査結果の同一性

- レビュー候補の識別子は、基準HEADと、候補を個別ステージした状態で`git write-tree`が返すGitインデックスのtree IDの組とする。状態が有効な`作業用/実装計画.md`、`作業用/進行中の作業.md`、`作業用/大規模作業計画.md`、`作業用/相談・事前調査.md`は候補外のため、この識別子に含めない。運用文書自体を改修する作業では、状態「なし」の空テンプレートだけを最終候補へ含められる。
- 実装担当は候補一覧を更新し、その一覧のファイルだけを個別ステージし、候補定型検査に合格してから基準HEADとtree IDを記録する。その固定候補へ変更リスクに応じた完了検査を実行し、検査後に候補定型検査とtree IDを再取得して、候補一覧、部分ステージ、差分空白、tree IDが変わっていないことを確認する。
- 検査結果は記録した候補識別子にだけ帰属する。候補ファイルを変更・再ステージしてtree IDが変わった場合、以前の合格を新候補の合格として扱わず、通常変更、高リスク、増分検査の規則に従って必要な結果を取り直す。
- 合格は対象コマンドの終了コード0を取得できた場合だけ記録する。時間切れ、中断、出力の途中までしか取得できない実行は、失敗表示がなくても未確認とする。`作業用/進行中の作業.md`には現在候補へ有効な結果だけを残し、新しい全体検査を取得したら古い候補と失敗履歴を削除する。増分検査では承認根拠となる直前候補一件と現在候補だけを保持する。
- 基準HEADとtree IDが同じで、合格結果が有効な候補には、同じ完了検査を再実行しない。候補が変わった場合、前回結果が未確認・失敗・対象不足の場合、または検査後に関係する実行条件が変わった場合だけ再判定する。

### 調整文書を閉じた後の最終化

- 通常の候補レビューと完了検査は、`作業用/進行中の作業.md`が有効で候補一覧を保持している間に通常モードで完了させる。必要な実機・外部確認後に候補が変わっていないことを確認し、すべての完了条件を満たした場合だけ調整文書を状態「なし」の空テンプレートへ戻す。
- 通常の製品変更では調整文書がレビュー候補に含まれないため、閉鎖前に承認したGitインデックスtree IDを最終化モードへ渡す。閉鎖後のtree IDが一致し、現在フェーズの`実装計画.md`と`進行中の作業.md`が状態「なし」であることを確認してからコミットする。大規模作業の途中では、`大規模作業計画.md`と必要な事前調査を有効なまま候補外に残せる。
- 大規模作業全体の終了時、または四つの調整文書自体を改訂する作業では、`-RequireAllCoordinationClosed`も指定して全調整文書の状態「なし」を要求する。調整文書自体の改訂では、閉じた空テンプレートを含む最終ステージ差分を独立してレビューし、そのGitインデックスtree IDを承認済み最終候補として記録する。そのIDを最終化モードへ渡し、通常モードの候補一覧を空テンプレートへ残さない。
- 最終化モードは候補内容を承認する手段ではなく、承認後の同一性検査である。指定IDと現在のインデックスが違う場合、閉鎖必須の調整文書が有効・欠損・不正である場合、空のステージ、部分ステージ、差分空白、PowerShellの文字コード・改行に問題がある場合は失敗する。

### レビュー指摘後の増分検査

レビュー指摘への修正では、次の条件をすべて満たす場合、直前のレビュー候補に対する完了検査を合格済み基準とし、今回の修正差分に必要な検査を追加する「増分検査」を優先する。これは検査省略ではなく、変更されていない候補へ直前の合格結果を継続適用し、修正した部分だけ新しい検査結果へ置き換える運用である。

- 直前の候補一覧、基準HEAD、実行コマンド、選択範囲、合格結果が`作業用/進行中の作業.md`に記録され、その候補に説明できない差分や試験失敗がない。
- 修正が番号付きレビュー指摘の解消だけであり、変更ファイルと変更内容を直前候補から区別できる。指摘を保証する試験・資料は追加できるが、指摘と無関係な修正や候補、仕様変更を混ぜない。
- 修正の影響を対象試験、静的契約試験、必要な非`all`領域、構文・設定検査などへ安全に限定でき、選んだ検査と限定理由を記録する。
- 修正後も候補定型検査、`git diff --cached --check`、未追跡・部分ステージ確認に合格する。

上記を満たす局所修正では、変更されていない`app.js`などがステージ済み候補に残っているという理由だけで、候補全体の`test:affected --staged`や全領域試験を機械的に再実行しない。計画・差分レビュー担当は、直前候補の完了検査と修正差分の増分検査を合わせて再レビューの根拠にでき、最終承認前の候補全体再実行も必須としない。

ただし、共通入口・共通制御・複数領域で使う挙動、高リスク条件、影響規則・試験基盤を修正した場合、候補構成が指摘対応を越えて変わった場合、限定検査の失敗から他領域への影響が疑われる場合、または修正差分を安全に分離できない場合は増分検査を使わない。候補全体を再分類し、通常変更なら`test:affected`、高リスクなら`test-game.ps1 -Area all`を1回再実行する。レビュー承認後の実機確認でコード・設定・素材・試験が変わらなければ、コミット前に同じ自動検査を繰り返さない。

### 変更後の基本確認

1. 計画時は作業規模・調査必要性と変更リスクを分け、[計画範囲と条件付き随伴ファイル](#計画範囲と条件付き随伴ファイル)に従って参照探索と予定パス判定を行う。結果を検査計画へ記録する。
2. 実装中と候補固定後の検査は[変更リスクと完了検査](#変更リスクと完了検査)で選ぶ。内部文書だけの場合は意味・参照・差分確認を行い、アプリ検査は原則不要。Node試験を低速試験以外まで広めに確認したい場合だけ`npm run test:fast`を使う。
3. 高リスク・横断・未知変更は、固定した初回の最終候補について、関係する場合にプロジェクトルートで`powershell.exe -NoProfile -ExecutionPolicy Bypass -File ".\ゲーム本体\validate-project.ps1"`を実行し、標準全体検査として`powershell.exe -NoProfile -ExecutionPolicy Bypass -File ".\ゲーム本体\test-game.ps1" -Area all`を1回実行する。`-Area all`はNode全件を内包するため、別途`npm test`を重ねない。
4. Node試験の並列入口・資源隔離を変更する場合、または並列時の不安定性を調査する場合だけ、追加で4ファイルの並列数2連続10回、`npm run test:serial`、`npm run test:slow`を実行する。
5. UI変更時は`作業用/実機確認チェックリスト.md`から該当IDと必要な端末を選ぶ。実通信が必要な場合もGrok・NovelAIの許可は作業ごとのユーザー指示に従う。
6. 引継ぎ前は[最終候補と検査結果の同一性](#最終候補と検査結果の同一性)に従って固定・検査・同一性再確認を行う。指摘修正時は[増分検査](#レビュー指摘後の増分検査)の適用条件を確認し、同じ候補の有効な完了検査を繰り返さない。

### 試験の構成・保証範囲

#### 機能別Node試験

| 機能・境界 | 担当Node試験（いずれも`.test.js`）と整理判断 |
| --- | --- |
| 永続化・正副復旧・書込み故障・Windowsロック | `persistence-integration`。実ストアとHTTP、再起動読戻し。`api-updates`のハンドラー代役試験とは層が異なるため両方維持 |
| Grokクライアント・再送・ゲート・使用量・取消 | `grok-client-integration`。クライアント単体と実ローカルGrokモック。API側の購読/要求構築とは別境界なので維持 |
| 会話・物語・要約・診断のHTTP接続 | `gameplay-api-integration`。実runtime/サービスとデモ・ローカルGrokモック。含まれる人物UI純粋処理も既存保証として維持し、他browser試験への移植はしない |
| 画像生成・アルバム・付随JSON | `scene-image-api-integration`。実parser／要求受理→ローカルGrok・NovelAI→実HTTP／ストア／付随JSON再検証、生成前拒否の外部呼出回数と保存後再送を観測する。`api-scene-images`は生成済み結果の実metadata検証を通した保存I/O失敗→同一PNG・seed・metadataの保存だけ再試行を担当する。`repository-boundaries`はversion 4の厳格な文字受理と旧facade・旧形式を維持し、`browser-scene-images`は400後の下書き再編集と成功時だけの履歴確定を確認する |
| 応答性・同時要求・終了・再起動 | `runtime-concurrency-restart`。同じ隔離保存先を複数runtimeへ引継ぎ、最終runtime停止後に削除。上記の形式別詳細assertと重なっても横断永続化として維持 |
| APIハンドラーと公開拒否 | `api-chat`、`api-gameplay`、`api-scene-images`、`api-updates`、`read-only-api`。実入口/ストアまたは限定代役の接続。対応統合試験へまとめず、各保証は以下の詳細表を参照 |
| 入力・視覚遷移・応答・プロンプト・定義・範囲 | `visual-transitions`、`chat-validation`、`chat-response`、`chat-demo`、`chat-prompt`、`grok-response-validation`、`character-definition`、`domain-validation`、`domain-scope-contracts`。純粋処理/実サービス接続の詳細境界を維持 |
| ブラウザ状態・要求・送信・復元 | `browser-character-sessions`、`browser-state-lifecycle`、`browser-chat-request`、`browser-chat-flow`、`browser-grok-settings`、`browser-checkpoint-restore`、`browser-participant-change-flow`、`browser-save-data`、`browser-save-load`、`browser-save-reset`。DOM/通信代役を含む実app接続であり、ゲーム開始・ホーム復帰・セーブ読込の音声ライフサイクルもここで確認し、HTTP側の試験と統合しない |
| ブラウザ物語・記憶・画像・音声 | `browser-adventure-configuration`、`browser-asset-restrictions`、`browser-story-choices`、`browser-story-encounter`、`browser-worldline`、`browser-medium-memories`、`browser-important-memory-state`、`browser-scene-images`、`browser-audio`。使用素材の実行中反映は公開フロー入口、画面とappの接続はそれぞれの責務境界で確認する。ブラウザVM基盤は共通化しない |
| 起動・HTTP・終了・設定・診断・画像処理・検査器 | `bootstrap`、`cli`、`interactive-startup`、`http`、`shutdown`、`runtime-settings`、`diagnostics`、`local-image-processor`、`scene-image-storage-inspector`、`project-validation`、`source-contracts`。`shutdown`は実`main.js`・実終了調停・隔離デモruntime・実loopback HTTPで、準備中、待受け取得中、起動診断中、READY後の停止、同一ポート再bind、終了失敗後の全件試行を確認する。異なるプロセス/純粋処理/静的検査境界を維持 |
| 検証・保存・起動の責務境界 | `repository-boundaries`の公開export同一性・検証値/所有・依存グラフ。`persistence-integration`の保存確定前後/削除故障・予備復旧後上書き・実bootstrap共有排他・非同期画像参照、`scene-image-api-integration`のmetadata確定・お気に入り復旧/停止・thumbnail再生成・競合後所属。依存グラフ検査は静的な構造保証、状態とファイルのassertは動作保証 |
| 支援の契約 | `test-support`。実loopback要求と予約ポートの解放、8保存先引数、非同期停止→削除、停止失敗の伝播・保持、実test afterによる作成途中/起動/listen/本体失敗の後始末、import無副作用 |

共通支援は2ファイルに限定する。`test-support/local-http.js`はloopbackのポート取得とOrigin・JSON/生本文送信だけを担当し、応答を消費・JSON化しない。各統合試験にJSON必須、空本文、画像bytes・Content-Typeの解釈を残す。`test-support/isolated-resources.js`は8永続パス引数、runtime停止の登録、試験単位の後始末を担当する。mode、delay、environment、外部モック、要求fixtureは個別試験の正本で、共通支援では既定値を追加しない。

後始末は単一の実`after`で登録資源を逆順にawaitし、その後だけ専用ディレクトリを削除する。所有登録はmkdirより前、runtime停止登録は起動成功直後であり、HTTP起動失敗でも停止する。停止失敗は他の停止も試してAggregateErrorを返し、保存物を保持する（成功扱いにしない）。削除時も絶対パスが`data/test-runs`の子孫であることを再検証する。再起動時の明示的停止は個別試験に残す。全体検査は下記の全領域入口を使い、Node試験だけでPowerShell領域を代替しない。

- 強制デモモードと隔離データを使用し、主要API、全キャラクター、3モード、2人シーン、`/api/chat`の完全な人物一覧・人物別状態と旧1人要求の拒否、アドベンチャーモードのカタログCRUD・1～10ブロック編集・行動候補・指定／自動遭遇・3択・終了結果・日替わり・設定スナップショット、共有ワールドラインの人物別選別、固定世界観・モード区分別の中期・重要記憶、世界線共通の世間の出来事、5往復要約・共同要約・失敗再送、プレイヤープロフィール、未設定関係性、20歳境界、方向付きキャラクター間関係性、全人物の短い話題参照一覧、`@`候補の一意名・非参加・最大2人解決、選択外人物の基本設定・趣味／関心だけの限定話題参照と不正指定拒否、現実時間連動、主・追加人物の交代、再送、最新1往復、現行v24セーブの通常／アドベンチャー分離・行動選択・結果状態・現行v24受理とv23以下拒否、単一世界観検証、通常・追加要望つきシーン画像モック、アルバムの新旧順・お気に入り保存／復旧・絞り込み・削除保護・安全停止、生成画像の完全削除、HTTP防御を課金なしで検査する。
- 視覚遷移の純粋処理は`node-server/test/visual-transitions.test.js`で、設定版・ID・表示名由来語彙・追加別名の検証、直接依頼と質問・引用・否定・仮定・予定・移動途中の区別、1人／2人の対象解決、複数候補、未登録・使用不可・細部変更、服装と背景の独立判定、自然文食い違いの高確度検出を確認する。サーバー会話入力検証の分離は`node-server/test/chat-validation.test.js`で、`chat.js`とのexport同一性、代表要求の主要な正規化結果、サーバー生成計画のfreeze、ブラウザ指定計画の拒否、JSON直列化後のrequestId、入力非破壊、エラー分類・原因・検証順を確認する。実`POST /api/chat`との接続と公開400コードは`gameplay-api-integration.test.js`で確認する。
- サーバー会話応答処理の分離は`node-server/test/chat-response.test.js`で、`chat.js`とのexport同一性、代表Schemaの人物数・視覚遷移許可集合・背景・記憶操作・物語項目、解析時の許可集合再検証、受理・補正・拒否、主要freeze対象、入力非破壊、書記素単位の文字数制限、実`createGrokGameplayService.chat`から実builder・parserまでの接続、自然文食い違い診断の安全項目と応答不変、接続確認マークの更新順を確認する。デモ応答の分離は`node-server/test/chat-demo.test.js`で、固定乱数による通常・自由対話・1人／2人scene、実Grok経路と共通の視覚遷移計画、表情規則適用と許可素材への復帰、表示名・ユーザー名、物語境界、乱数呼出し回数、入力非破壊を確認する。恒久試験の保証範囲は各assertの観測点とする。
- サーバー会話プロンプト構築の分離は`node-server/test/chat-prompt.test.js`で、`chat.js`とのexport同一性、通常・自由対話・1人／2人sceneと物語の代表分岐、人物・関係性・記憶・出来事・話題参照・現実時間・中期記憶・視覚遷移制約の所属と節順、先頭3 systemメッセージのバイト単位安定性、要求全体の縮小、返却プロパティとSchema、入力非破壊、履歴上限・順序・場面時刻境界、世界観・モデル・最大トークン数の次要求への反映、実`createGrokGameplayService.chat`との接続を確認する。恒久試験の保証範囲は各assertの観測点とする。実`POST /api/chat`から入力検証・サービス・ローカルGrokモック・解析・安全な診断・再試行までの接続は`gameplay-api-integration.test.js`を再利用する。
- 記憶Schemaの人物別既存ID・分類・上限到達時の削除後追加は`chat-response.test.js`、実Grok要求body内のモード別候補は`chat-prompt.test.js`で確認する。`browser-important-memory-state.test.js`は実サーバー検証値と共有・単独操作の配列順、途中拒否、ID・時計の副作用を比較する。`browser-chat-flow.test.js`は実メモリ部品と実`chat-request.js`を接続し、会話の一括確定・保持要求の再送・最新往復のやり直しから次のPOST本文までを観測する。`gameplay-api-integration.test.js`はローカルGrokモックへの現在記憶Schema、正規化済み共有更新のブラウザ確定とv24保存読込後の要求接続、記憶更新不正時の502・診断1件・秘密情報不在・診断保存失敗時の元エラー維持を観測する。実APIのSchema受理と確率的出力は自動試験の保証範囲外とする。
- 会話API入口の分離は`node-server/test/api-chat.test.js`で、実`createGameApiHandler`から分離ハンドラー・入力検証・デモ処理・実再送キャッシュへの接続、対象外経路、複数不正条件と再送参照を含む公開エラーの優先順、失敗時の原因・詳細、要求IDあり／なし、生本文指紋、完了再送・同時共有・競合・失敗後再試行・容量超過、購読者と共有処理の取消信号、既存`getGrokFailureCode` exportの同一性を確認する。実サービスとローカルHTTPのGrokモック接続は`gameplay-api-integration.test.js`、再送キャッシュ単体の境界は`grok-client-integration.test.js`を併用する。
- 物語・中期記憶・プロンプト診断API入口の分離は`node-server/test/api-gameplay.test.js`で、実`createGameApiHandler`と実入力検証・実再送キャッシュへの接続、対象外経路、遭遇の非再送、候補・要約・診断の完了再送・同時共有・全購読者取消・失敗後再操作・容量超過、生本文または正規化本文による競合判定、検証優先順、経路固有の失敗原因・詳細、診断時点の世界観と人物カスタマイズ反映を確認する。実サービスとローカルHTTPのGrokモック接続は`gameplay-api-integration.test.js`を併用する。
- 画像API入口の分離は`node-server/test/api-scene-images.test.js`で、実`createGameApiHandler`と実画像入力検証・実再送キャッシュへの接続、読取先行・対象外経路、生成の検証順・生本文指紋・二段再送キー・成功時のプロンプト再送削除順、完了再送・同時共有・全購読者取消・失敗後再操作・容量超過、画像固有の失敗分類、お気に入り・完全削除の引数・完了待ち・ストア失敗を確認する。実生成サービス・ストアとローカルHTTP画像モックの接続は`scene-image-api-integration.test.js`を併用する。
- 設定・世界観・セーブ・クライアント診断API入口の分離は`node-server/test/api-updates.test.js`で、実`createGameApiHandler`から各ハンドラーへの接続、対象外経路、メソッド・JSON・引数・応答状態、設定ごとに異なる例外境界、世界観とセーブの末尾405、スロット数値化、実診断検証・安全化・重複抑制・204を確認する。読取先行と実ストアの保存・復旧・再起動後再読込は`read-only-api.test.js`、`persistence-integration.test.js`、`runtime-concurrency-restart.test.js`を併用する。

#### API経路対応表

`game-api.js`は表の上からではなく、読取→会話→物語→中期記憶→プロンプト診断→画像→設定→世界観→アドベンチャー設定→通常チャット用カスタマイズ設定→セーブ→クライアント診断の所有順で接続する。表の「拒否」は各経路の代表的な公開状態／コードであり、入力ごとの詳細な400分類と外部サービス失敗は対応試験を正本とする。

| 経路パターン | 許可メソッド／成功状態 | 代表拒否・不在 | 担当ファイル | 対応する恒久試験・assert所在 |
| --- | --- | --- | --- | --- |
| `/api/status` | GET／200 | 405 `status_method` | `api/read-only.js` | `read-only-api.test.js`「stage 4 read-only catalogs and status expose current validated data」 |
| `/api/character-personalities` | GET／200 | 405 `character_personality_method` | `api/read-only.js` | 同上（人物一覧・年齢・人格Schema） |
| `/api/worlds`（読取） | GET／200 | 更新側へ移譲 | `api/read-only.js` | `read-only-api.test.js`の同試験、`api-updates.test.js`「the real game handler keeps read-only routes first...」 |
| `/api/worlds`（更新） | POST／201 | その他405 `world_method` | `api/worlds.js` | `api-updates.test.js`「world updates preserve status...」 |
| `/api/worlds/<worldId>`（編集可否） | GET／200 | 参照あり409 `world_edit_referenced`、検査不能409 `world_edit_reference_inspection_failed`、対象不在404 | `api/worlds.js` | `api-updates.test.js`の接続と`persistence-integration.test.js`の正副参照検査 |
| `/api/worlds/<worldId>`（編集） | PATCH／200 | revision競合409、参照あり・検査不能409、不正入力400、対象不在404 | `api/worlds.js` | 同試験の同一ID・主予備・再起動・競合・書込失敗 |
| `/api/worlds/<worldId>`（削除） | DELETE／200 | その他405 `world_method`、セーブ参照409 | `api/worlds.js` | 同試験（従来の削除境界） |
| `/api/adventure-settings`（読取） | GET／200 | 非GETは更新側へ移譲 | `api/read-only.js` | `adventure-settings.test.js`「adventure settings catalog keeps standard read-only and custom CRUD conflict-safe」（標準設定一覧・revision） |
| `/api/adventure-settings`（新規保存） | POST／201 | 競合409 `adventure_settings_revision_conflict`、件数上限409 `adventure_settings_limit`。GET・POST以外は未処理となり404 | `api/adventure-settings.js` | 同カタログ試験（新規保存・競合）、同ファイル「adventure settings serialize concurrent creates and enforce the ten-setting limit」 |
| `/api/adventure-settings/<settingId>` | PUT・DELETE／200 | その他405 `adventure_settings_method`、対象不在404 `adventure_settings_not_found`、不正設定422 `adventure_settings_configuration_invalid` | `api/adventure-settings.js` | 同カタログ試験（PUTの不正設定拒否、DELETE成功・revision） |
| `/api/adventure-settings/<settingId>/name` | PATCH／200 | その他405 `adventure_settings_method`、対象不在404 `adventure_settings_not_found` | `api/adventure-settings.js` | 同カタログ試験（名称変更・revision・主ファイルと内部予備の保存） |
| `/api/chat-customization-settings`（読取） | GET／200 | 非GETは更新側へ移譲。永続カタログとrevisionを変えず、先頭へ読み取り専用の標準設定を合成 | `api/read-only.js` | `read-only-api.test.js`「stage 4 read-only catalogs and status expose current validated data」、`chat-customization-settings.test.js`の標準設定・再取得・正副不変 |
| `/api/chat-customization-settings`（新規保存） | POST／201 | 競合409 `chat_customization_settings_revision_conflict`、件数上限409 `chat_customization_settings_limit`。GET・POST以外は未処理となり404 | `api/chat-customization-settings.js` | `chat-customization-settings.test.js`のCRUD・同時作成・上限試験 |
| `/api/chat-customization-settings/<settingId>` | PUT・DELETE／200 | その他405 `chat_customization_settings_method`、対象不在404 `chat_customization_settings_not_found`、不正設定422 `chat_customization_settings_configuration_invalid`。`settingId=standard`は400 `chat_customization_settings_standard_readonly` | `api/chat-customization-settings.js` | 同試験の内容上書き・削除・標準設定拒否・不正設定・無変更確認 |
| `/api/chat-customization-settings/<settingId>/name` | PATCH／200 | その他405 `chat_customization_settings_method`、対象不在404 `chat_customization_settings_not_found`。`settingId=standard`は400 `chat_customization_settings_standard_readonly` | `api/chat-customization-settings.js` | 同試験の名称変更・標準設定拒否・正本／内部予備確認 |
| `/api/saves` | GET／200 | 405 `save_method` | `api/read-only.js` | `read-only-api.test.js`「stage 4 save and album endpoints are read-only and bounded」、`api-updates.test.js`の読取先行試験 |
| `/api/saves/<1～3桁slot>`（読取） | GET／200 | 404 `save_not_found` | `api/read-only.js` | `read-only-api.test.js`の同試験、`persistence-integration.test.js` |
| `/api/saves/<1～3桁slot>`（更新） | POST・DELETE／200 | その他405 `save_method` | `api/saves.js` | `api-updates.test.js`「save updates preserve numeric slot conversion...」、`persistence-integration.test.js` |
| `/api/saves/<1～3桁slot>/thumbnail` | GET／200 | 404 `save_thumbnail_not_found`、非GETは405 `save_method` | `api/read-only.js` | `read-only-api.test.js`の同試験 |
| `/api/scene-images/album` | GET／200 | 400 `scene_image_album_invalid`、非GETは405 `scene_image_album_method` | `api/read-only.js` | `read-only-api.test.js`の同試験、`api-scene-images.test.js`「read-only image routes stay ahead...」 |
| `/api/scene-images/<sceneId>/image` | GET／200 | 404 `scene_image_not_found`、非GETは405 `scene_image_method` | `api/read-only.js` | `read-only-api.test.js`の同試験、`api-scene-images.test.js`の読取先行試験 |
| `/api/scene-images/<sceneId>/thumbnail` | GET／200 | 404 `scene_image_not_found`、非GETは405 `scene_image_thumbnail_method` | `api/read-only.js` | 同上 |
| `/api/grok-usage` | GET／200 | 405 `grok_usage_method` | `api/read-only.js` | `read-only-api.test.js`のカタログ・状態試験 |
| `/api/grok-models` | GET／200 | 405 `grok_model_catalog_method` | `api/read-only.js` | 同上（候補応答全体） |
| `/api/prompt-diagnostics/sources` | GET／200 | 405 `diagnostics_method` | `api/read-only.js` | 同上（選択元一覧） |
| `/api/chat` | POST／200 | 405 `chat_method`、入力400 | `api/chat.js` | `api-chat.test.js`「the real game handler returns...」「chat method, JSON...」 |
| `/api/story/encounter` | POST／200 | 405 `story_method`、入力400 | `api/story.js` | `api-gameplay.test.js`「the real game handler connects encounter...」「gameplay routes preserve validation order...」 |
| `/api/story/options` | POST／200 | 405 `story_method`、入力400 | `api/story.js` | 同上、同ファイルの再送・取消・容量試験 |
| `/api/story/ending` | POST／200 | 405 `story_method`、入力400、不正Grok応答502、異本文再送409 | `api/story.js` | `api-gameplay`の固定入力・応答・共有再送・取消・容量、`gameplay-api-integration`の実HTTP・使用量 |
| `/api/medium-memories/summarize` | POST／200 | 405 `medium_memory_method`、入力400 | `api/medium-memory.js` | `api-gameplay.test.js`の実入口、拒否、再送各試験 |
| `/api/prompt-diagnostics/review` | POST／200 | 405 `diagnostics_method`、Grokなし409 `diagnostics_grok_required` | `api/prompt-diagnostics.js` | `api-gameplay.test.js`「diagnostic validation keeps...」「diagnostics reads the current world registry...」 |
| `/api/scene-images/generate` | POST／200 | 405 `scene_image_method`、未設定409 `scene_image_not_configured` | `api/scene-images.js` | `api-scene-images.test.js`の生成・拒否・失敗・再送試験 |
| `/api/scene-images/<sceneId>/favorite` | PATCH／200 | 405 `scene_image_favorite_method`、入力400 | `api/scene-images.js` | `api-scene-images.test.js`「favorite and permanent-delete routes validate...」 |
| `/api/scene-images/<sceneId>` | DELETE／200（有効な未知ID・消去済みIDも残存なし確認後200） | 405 `scene_image_delete_method`、保護409、保護情報読取不能503、消去／確認失敗500 `scene_image_delete_failed` | `api/scene-images.js`、`storage/scene-image-deletion.js` | `api-scene-images.test.js`、`scene-image-api-integration.test.js`の再起動・応答喪失試験、`scene-image-deletion.test.js` |
| `/api/real-time-setting` | POST／200 | 405 `real_time_setting_method`、入力400 | `api/settings.js` | `api-updates.test.js`「settings preserve validation order...」「representative update operations wait...」 |
| `/api/grok-model` | POST／200 | 405 `grok_model_selection_method`、Grokなし409 `grok_model_selection_disabled` | `api/settings.js` | 同上（元model文字列、固有例外、応答失敗） |
| `/api/diagnostics/client-error` | POST／204 | 405 `client_diagnostic_method`、入力400 | `api/client-diagnostics.js` | `api-updates.test.js`「client diagnostics use real validation...」「representative update operations wait...」 |
| 未知の`/api/*` | なし | HTTP 404 `{message: "Not found."}` | 全APIが`false`、`http/server.js` | `api-updates.test.js`の実入口未知経路assert、`http.test.js`「static files, HEAD, errors...」 |

世界観一覧・アドベンチャー設定一覧・通常チャット用カスタマイズ設定一覧・セーブ・画像のGETは`game-api.js`の先頭にある`read-only.js`が更新ハンドラーより先に処理し、世界観1件の編集可否GETは参照検査を行う`api/worlds.js`が処理する。`api-updates.test.js`は実`createGameApiHandler`で読取先行、世界観編集可否・更新、カスタマイズ設定更新の応答待機、未知経路の未処理を確認する。読取ハンドラーは更新側の`try`外にあるため、その例外は同一のまま伝播する一方、世界観編集可否と更新側の`OperationError`だけを`game-api.js`が`HttpError`へ変換する。アドベンチャー設定は`adventure-settings.test.js`、通常チャット用設定は`chat-customization-settings.test.js`で、実`createGameApiHandler`を経由する一覧取得・CRUD・競合・不正設定拒否と保存復旧を確認する。

`/api/chat`と`/api/story/options`は`secretProfile`を必須として共通domainで検証し、不正値を外部通信前に400で拒否する。`/api/adventure-settings`の更新は設定v3の秘密を検証し、不正設定を422で拒否する。`/api/saves`更新・読込はv24の秘密を含む正本を扱い、旧v23は読込不可とする。各経路の入口試験に加え、`secret-profile.test.js`、`chat-prompt.test.js`、`persistence-integration.test.js`が人物別投影・永続化を直接確認する。

アドベンチャー設定の`<settingId>`は、生成形式`adventure-setting-<14桁数字>-<8桁の小文字16進数>`に一致するIDだけを経路で受理する。`standard`や形式不正なIDはこの経路へ一致せず404となる。

- 検査用データは`data/test-runs`だけに作成し、本番セーブを変更しない。

#### PowerShell試験・ソース契約の構成

- 起動時の黒い画面には使用中の`ゲーム本体`絶対パスを表示し、ウィンドウタイトルには親フォルダを含む識別名を出す。起動元の絶対パスはHTTP APIやiPhone画面へ返さない。
- `test-game.ps1`は一括実行用の進行役であり、共通準備は`tests/test-support.ps1`、領域別試験は`tests/areas`配下へ分割している。先頭の`01-source-contracts.ps1`は、次表の責務別ファイルがすべて存在し、PowerShell構文とUTF-8 BOMが正常なことを先に確認してから、表の順に同一スクリプトスコープへdot-sourceする。分離先は`ProjectRoot`を再計算しない。

| 順序 | `tests/source-contracts`のファイル | 責務と共有値 |
| --- | --- | --- |
| 1 | `01-runtime-http.ps1` | 隔離サーバー、status・index、Host・Origin、本文上限、診断APIを実HTTPで確認。`process`、`BaseUri`、`indexContent`を後続へ共有 |
| 2 | `02-screen-layout.ps1` | 画面骨格、CSS、ホーム素材、JavaScript読込順を静的確認。`styleContent`と`appContent`を後続および03領域へ共有 |
| 3 | `03-settings-story.ps1` | ホーム、設定、場面画像、記憶、物語モードのモジュール接続を静的確認 |
| 4 | `04-character-customization.ps1` | 主人公・人物設定、関係性、呼称、素材制約を静的確認 |
| 5 | `05-save-chat.ps1` | 保存画面、ロード入口、会話要求とAPI状態の接続を静的確認 |
| 6 | `06-memory-dom.ps1` | 記憶操作、人物セッション、必須DOM、場面画像履歴の接続を静的確認 |
| 7 | `07-state-visuals.ps1` | 状態保存・初期化、画面操作、再生成、表示、背景先読みを静的確認 |
| 8 | `08-memory-scene-image.ps1` | 中期記憶、場面画像要求・表示、画面幅対応を静的確認 |

- Node試験は、固定並列数2の完全入口`npm test`（および同じ入口へ接続する`npm run test:full`）、低速2件だけの`npm run test:slow`、残る通常試験を決定的順序で実行する`npm run test:fast`に分ける。低速2件は`source-contracts.test.js`と`project-validation.test.js`であり、fastとslowの和集合はfullと一致する。fastとslowはそれぞれ複数ファイルを並列数2で実行する。`npm run test:fast`は低速試験が必要な変更の代替にせず、全件直列の`npm run test:serial`は並列失敗の切分け専用とする。
- `npm run test:affected`は、影響範囲が明確な通常変更の固定した最終候補に対する完了検査に使用する。開発中は`--list`の判定を参考に、直接対象試験、構文・設定検査、必要な非`all`領域を個別に実行する。既定はHEADに対するステージ済み・未ステージの追跡変更と、無視されていない未追跡ファイル、`--staged`はステージ済み差分だけ、`--list`は実行せずに判定根拠とコマンドだけを表示する。反復可能な`--planned-path <リポジトリ相対パス>`は`--list`専用の計画前判定で、Git差分を収集せず同じ影響規則を適用する。`--staged`との併用、`--list`なし、危険なパスは拒否する。`scripts/test-impact-map.js`の明示規則は直接変更試験、UI・人物・設定素材、会話・記憶、物語、セーブ、シーン画像、Grok・HTTP・起動、文書をNode試験・設定素材検査・PowerShell累積領域へ和集合で接続する。共有の`domain/validation.js`単独変更は、今回の構造化応答用コードポイント支援の利用先である`domain-validation`、会話応答、物語・中期記憶API、ローカルGrokモック、物語・記憶のブラウザ状態、実`save-flow.js`の構築・読込・再構築を通す保存往復試験を選ぶ。`checkpoint-restore.js`単独変更では復元・会話・物語・ロードと総括の接続試験を選ぶ。`save-flow.js`単独変更では保存・ロード・初期化置換・会話・物語・総括の接続試験を選ぶ。`worldline-reset-flow.js`単独変更では要約部品を含む初期化・設定ボタン・物語取消・ロード置換の接続試験を選ぶ。`medium-memory-summary-flow.js`単独変更では要約実行、会話、編集UI、復元・ロード・全体初期化の接続試験を選ぶ。`story-flow.js`単独変更では物語開始・遭遇・会話・復元・ロード・総括の接続試験を選ぶ。四つの調整文書と内部文書はアプリ検査対象外、ユーザー向けHTMLは設定・素材検査だけとし、製品固有の文書規則を維持する。未知の現役パス、package・lock、選択器・共通支援、標準入口、検査進行役の変更は完全Node試験・設定素材検査・`grok-network`までの領域へ安全にフォールバックする。実行順は変更JavaScriptの構文、変更PowerShellのParser、選択Node試験（1件は並列数1、複数は固定2）、必要な設定素材検査、累積PowerShell領域である。改名・削除元の構文対象は`ENOENT`だけを不存在として省略し、その他の読取失敗は終了1で停止する。変更に対する実行対象が空になる場合も成功扱いにしない。
- 影響計画の`characterLifecycleRequired`は、関連規則が一つでもあれば`true`、明示的な無関係規則だけなら`false`、未指定・広い規則を含み関連規則がなければ`null`とする。内部文書は合成から除き、完全フォールバックは`true`とする。`false`、完全フォールバックなし、最終領域が`chat-memories`以後の三条件が揃う場合だけ、表示・実行で共通のPowerShell引数へ`-SkipCharacterLifecycleTests`を付ける。欠損した要否値を`false`と推定しない。
- `config/visual-transitions.json`、`config/demo-rules.json`、`domain/visual-transitions.js`の変更は、`visual-transitions`と会話入力・応答・デモ・プロンプト・実HTTP接続試験、設定素材検査、会話領域へ明示接続する。視覚遷移設定だけの変更を未知パス扱いにせず、設定検証と利用側の両方を選ぶ。
- `world-settings.js`の変更では、`browser-world-settings.test.js`、`browser-adventure-settings.test.js`、`browser-save-reset.test.js`、`browser-story-choices.test.js`を含む`browser-world-settings`規則を選ぶ。`adventure-settings.js`単独の変更では物語・記憶・セーブの既存試験集合を選ぶ`browser-story`規則を使い、`browser-world-settings.test.js`は選ばない。開始候補を接続する`app.js`の変更は`browser-app-cross-cutting`規則により完全Node試験・設定素材検査・`grok-network`までへフォールバックする。世界観削除の共有操作権、削除失敗時の不変、開始設定カタログの無効化・再取得、画像待機中に失われた開始候補、物語開始入口の拒否は、それぞれの規則で選ばれる実部品接続試験で確認する。
- `chat-customization-draft.js`、`chat-customization-settings.js`と三文脈を接続する既存カスタマイズ各controllerの変更は`browser-chat-customization`規則で、直接試験に加えて人物セッション、人物確定・初期化、ロード、世界観連携、静的契約を選ぶ。直接試験は、利用可能項目の反映後も利用不能な人物・背景・立ち絵参照と不足記憶が保持され、明示修復時だけ除去・初期化されること、実行中射影が全人物・固定世界観の両記憶区分を副作用なく複製すること、プレイ中に読込を出さず保存済み編集を実行中世界線から分離することも確認する。`character-visuals.js`では同直接試験も選び、下書きの使用素材に対する厳格画像準備を確認する。`chat-start-flow.js`単独変更は専用`browser-chat-start-flow`規則で、公開入口、保存・ロード、既存カスタマイズ、世界観、静的契約の6試験と`saves`までを選ぶ。初期下書き・編集済み下書きからの開始、厳格画像、失敗復元と取消は新フローの直接試験、v24投影は`browser-save-reset.test.js`が観測する。
- `chat-validation.test.js`、`chat-response.test.js`、`chat-prompt.test.js`、`chat-demo.test.js`のruntime fixtureは、各テストケースで`data/test-runs`配下の一意所有ルート、`unusedPort()`のloopbackポート、`persistenceArguments()`の8保存先を使い、`bootstrapOwnedRuntime()`へ接続する。外部API終了をawaitしてから所有ルートだけを削除し、本番保存先と固定8788へ接続しない。これら4ファイルを並列数2で実行しても試験単位の資源が干渉しないことを標準契約とする。
- 通常の領域別ブラックボックス試験は`test-game.ps1 -Area <領域名>`で行う。隔離データ、デモ応答、画像モックだけを使用し、本番データと実APIへ接続しない。`test-game.ps1`は先頭領域の見出し直後にNode全件を固定並列数2で1回実行してから、指定領域までを従来順に確認する。開発中に非`all`領域だけを反復する場合は`-SkipNodeUnitTests`を指定できるが、Node全件を省略した結果は完全検査として扱わない。`-Area all -SkipNodeUnitTests`は試験開始前に終了1で拒否する。
- 軽量な`03-configuration-assets.ps1`は人物・サムネイル・人格の実サーバー確認と、設定、世界観、背景、BGMの検査を所有し、後続へ共有する設定・人物・世界観・背景の値を維持する。`03-character-lifecycle.ps1`は同じPowerShellスコープと隔離データで人物パッケージ、反映、登録解除を確認し、後続へ状態を渡さない。進行役は軽量03の直後、同じ領域の時間計測内で補助検査を一度だけ呼び、失敗時も既存の`finally`清掃を行う。有効な省略時は`[SKIP-CHARACTER-LIFECYCLE]`を表示する。
- `test-game.ps1`はNode.js専用であり、Node.jsの現在契約、再起動後の再読込、主・内部予備、同時実行を合格条件とする。

#### ブラウザ動作試験とソース契約の保証範囲

`browser-app-dialogs.test.js`は実共通部品と実dialogFocusで未解決待機・結果一回・4取消経路・Abort・親終了／再表示・通知FIFO／待ち失効・古いクリック／close／画像イベント・表示失敗・有効な復帰先を観測する。実appの組立てから同じserviceを3つの実controllerへ渡し、ゲーム内削除の通信まで通す。`browser-save-data`は実部品からスロット操作の副作用・revision・取消／失効・保存読戻しへ、`browser-save-load`は実app配線から実save-flow・画像準備・成功／失敗・予備通知の所有権解放順へ接続する。`browser-image-deletion`は4入口の確定前DELETE0・承認ID・取消・対象／一覧／選択失効と既存の完全削除応答・再試行・混合結果を観測する。

`browser-prompt-diagnostics`は実appの注入・formイベントから実controllerと共通dialogへ接続し、未確定POST／ID準備0、対象・画面・カタログ変更の失効、結果不明後の同一bodyText再試行、送信後の再表示排他、表示失敗後の保留維持を観測する。`browser-story-choices`と`browser-save-reset`は実app配線を通し、確認取消・遅延・対象変更で進行／初期化／入力を保つこと、確定の一回性と無通信を確認する。`browser-chat-start-flow`と`browser-participant-change-flow`は巻戻し・候補セッション消去が通知より先であること、通知待ち中の排他、親取消と旧完了が後発操作を変更しないことを観測する。`browser-app-dialogs`の実行用JS／HTML残存検索は標準関数呼出し・別名取得・旧復旧シンボル禁止の補助検査とし、利用先の状態assertの代用にしない。影響規則は関連製品パスの単独変更でも直接接続試験を選ぶ。

`browser-audio`はユーザー操作／表示復帰でinterruptedからrunningへ戻る条件と拒否時OFFを維持し、実共通部品の確認・通知の開閉中もON/OFF、希望曲、実曲、再生位置、play/pause/resume回数が不変であることを模擬Audio上で確認する。実音、端末のTab閉じ込め、iPhoneキーボード、狭幅レイアウトは代役試験で保証せず、実機チェックリストA-12/B-03/B-04/E-06/F-13/G-09で別に観測する。`app-dialogs.js`単独変更は専用影響規則で全Node・設定素材・全領域を選び、未知ブラウザ規則と重複しない。

- DOMに依存しないブラウザモジュールの状態変換は`node-server/test`から実際に読み込んで挙動を検査する。秘密の純粋検証は`secret-profile.test.js`、編集操作と下書き確定は`browser-secret-profile.test.js`が担当し、チャット要求・プロンプト、候補要求、v24保存、設定v3、登録解除は各責務試験で接続する。中期要約の実行・結果キャッシュは`browser-medium-memory-summary-flow.test.js`が通信回数、requestId、状態確定、手動排他、キャッシュ寿命を担当する。実app配線は会話・編集UI・復元・ロード・初期化の各ブラウザ試験で観測する。中期記憶の編集・順位は`browser-medium-memories.test.js`が実保存イベント、禁止制御文字の無変更、元会話時刻の安定選別、古い失敗再試行後の60往復を担当し、`browser-chat-request.test.js`が次要求の短期履歴と要約順、`browser-save-reset.test.js`が実`save-flow.js`の保存構築、`gameplay-api-integration.test.js`が正規化済み要求のPC側受理、`persistence-integration.test.js`がv24保存・読込・再保存を担当する。会話要求構築は`browser-chat-request.test.js`で実`app.js`の`buildChatRequestPayload()`を抽出し、実`chat-request.js`のbuilderへ接続して次表を確認する。対象関数内部のローカル変数名、オブジェクト組立て順、直接returnか変数経由かは合格条件にしない。
- `browser-world-settings.test.js`は実`world-settings.js`と実`state-lifecycle.js`を接続し、削除確定から非同期の後処理完了まで`world-delete`だけが共有操作権を持つこと、競合操作と失敗DELETEがカタログ・開始候補を変えないことを確認する。実`app.js`の組立ても同試験で通し、削除後のチャット候補、開始準備の世界観・世間の出来事、保存済み開始設定の再評価を観測する。`browser-adventure-settings.test.js`は古い一覧を無効化したまま再取得失敗・再試行・明示修正読込を、`browser-chat-start-flow.test.js`は画像準備中に削除された通常チャット開始候補を、`browser-story-choices.test.js`は共有操作権中の物語開始拒否を担当する。
- `browser-settings-confirmations.test.js`は実appの共有メモリ3controllerと実共通ダイアログの接続で、確認前の通信・dirty・最新1往復無効化0、取消保持、対象改変・文脈変更・親再開始・種類往復の失効、最新別項目と下書き保持、入力10分類、失敗バッチの元会話だけの除去、再要約の確定直後の再照合を確認する。各設定の既存browser試験は編集5種、実appの独立編集親終了、カタログの固定対象・revision、dialog外の開始設定確認、実appの素材確認と操作所有者を担当する。test-impact-mapは移行対象13パスの単独変更でも新接続試験を選ぶ。可聴音と物理iPhoneのキーボード・表示は実機確認へ残す。
- `browser-chat-customization-settings.test.js`は初期下書き、開始・保存済み編集下書きに共通する秘密本文の正規化後UTF-16境界と他項目のコードポイント境界、実行中設定v1射影の全人物・両記憶区分と無副作用、利用不能参照の保持と明示修正、F1と同じ入力検証、空入力の開始・保存拒否、厳格画像準備、標準設定を含む一覧選択と明示読込・上書き対象の分離、標準設定のカスタム件数外・変更不可・別名新規保存、プレイ中の読込非表示・標準編集不可・カスタム独立編集、409後の下書き保持と古いPUT停止、取消確認、終了後の遅延GET無視、共通カスタマイズ親画面への配置、人物選択の警告だけの状態表示を担当する。実`app.js`の人物取得・カードでは世界線と開始下書きの値、登録定義不変も確認する。初期背景・立ち絵の専用子画面については、開始下書きと保存カタログからの一時状態分離、複数人物の入力保持、開始背景と全人物見た目の原子的反映、利用不能な既存参照の保持、新たに利用不能となった変更の反映拒否、差分時だけの取消確認を実`app.js`から抽出して確認する。`browser-customization-action-state.test.js`は有効人物投影の4項目、静的素材の保持、入力非変更を確認する。`browser-secret-profile.test.js`は秘密本文の編集履歴が子画面から利用不能参照マージへ渡り、変更後に本文と利用可能人物のチェックを元へ戻しても、編集開始時の利用不能認識を解除する反映が有効になることを担当する。取消では未反映編集を破棄し、利用不能認識がない項目を全て元へ戻した場合は変更なし、本文未編集の認識変更では利用不能ID保持となる対照経路も確認する。`browser-chat-start-flow.test.js`は実フローの公開入口で開始下書きの検証・全項目確定・失敗復元・取消・共有操作権・古い完了と実`app.js`の接続を確認する。`browser-save-reset.test.js`は新フローの成功結果からv24保存投影への接続を、`browser-save-load.test.js`はロード失敗復元後にホーム人物選択で初期下書きを作る開始を確認する。カタログAPIの構造・正副保存・CRUD・仮想標準設定は`chat-customization-settings.test.js`を正本とし、ブラウザ試験では本番保存先を使わない。
- P1の手入力確定では、`browser-important-memory-state.test.js`が実追加・編集イベントから記憶のコードポイント境界と拒否時のdraft／正本を、`browser-customization-action-state.test.js`が出来事のUTF-16境界と人物8欄の全人物検証を観測する。`browser-chat-customization-settings.test.js`は共用画面の反映先、`gameplay-api-integration.test.js`は確定値が実要求・デモAPI・v24保存読込・設定カタログへ届く接続を観測する。これらは手入力の確定境界の保証であり、自動記憶更新や既存データの一括修復は対象にしない。
- `browser-asset-restrictions.test.js`は実`asset-restriction-flow.js`の公開`applyChanges()`で検証・取消・中心画像失敗時復元・追加画像だけの部分成功・二重開始・失効を確認し、画面controllerの入力保持と実`app.js`の生成・同一操作調整器・実行中入口への配線を別に確認する。人物選択肢は実`app.js`の有効人物取得とcontroller配線を使い、実行中世界線・開始下書き・保存済み編集下書きの表示名、登録IDと登録名の不変を確認する。`persistence-integration.test.js`は同じ公開フローから開始設定修復後の物語開始・v24保存への接続を確認する。`test-impact-map.js`は`asset-restrictions.js`と`asset-restriction-flow.js`を同じ人物・保存状態領域へ分類し、直接試験を選ぶ。
- `browser-participant-change-flow.test.js`は実`participant-change-flow.js`の公開入口で中心人物変更、主・追加人物交代、追加・変更・明示退場、準備・画像適用失敗の復元、部分成功、共通操作権、取消・遅延完了、成功時だけの最新1往復無効化と未保存化を確認する。実`index.html`と`app.js`の読込順、controller生成時の初期化順、同一操作調整器、プレイ中入口とイベントも別に確認する。`browser-save-load.test.js`は実フローから追加人物変更を開始して保存ロードの共有操作権を確認し、`browser-save-reset.test.js`は新規開始後の保存投影を確認する。`participant-change-flow.js`単独変更の影響規則はこの三試験を選び、未知パスの完全フォールバックへ分類しない。

| 会話要求の契約 | 恒久動作assert |
| --- | --- |
| 主・副人物IDと人物別状態の所属、既存／欠損セッション、人物差分、両方向の関係性、空関係性・空人物間関係の省略、人物別重要記憶、旧トップレベル重要記憶の不在 | `app connection resolves ...`、`app connection uses both directions ...` |
| 世界観ON/OFF、ゲーム／自由対話区分、短期履歴・中期記憶・要約待ち元履歴と実`selectHistoryContext`引数 | `history, medium memories ...`、`two-person scene history ...`、各`app connection resolves ...` |
| プレイヤー設定、世間の出来事、登録人物の短い参照、`@`話題人物、使用可能素材、現実時間、物語状態 | 各`app connection resolves ...`とbuilder出力全体assert |
| 内部の無害な記述変更への耐性 | `app connection behavior tolerates harmless local rewrites` |
| 主人物、人物別記憶、世界観、履歴区分、話題人物、素材人物、現実時間の誤配線検出 | 各`app connection contract rejects incorrect ...`と`app connection tests reject incorrectly wired world inputs` |

ロード接続は`browser-save-load.test.js`で実`save-data.js`の公開`open()`から最小DOM代役に描画されたロードボタンを操作し、実`worldline-reset-flow.js`の背景待機中にロードが初期化を置換する結果も含め、実`app.js`で組み立てた`save-flow.js`の`applyLoadedSave()`へ接続して検査する。05から外した`applyLoadedSave()`内の解決・状態適用・主画像待ち・副画像待ち・app側確定の5条件は、`load applies every saved area ...`と`real save-data load waits ...`の状態・中間順序assertへ置換した。07から外したコントローラー側の適用呼出しと確定順序の2条件は、同じ接続試験のコントローラー側確定・ダイアログ終了・busy解除の順序assertへ置換した。空スロット、busy、古い一覧は表示済みボタンの登録済みイベントから各内部ガードへ到達し、確認取消、HTTP不正、save欠損、要求例外、主・副画像例外も成功確定しないことを確認する。主・副画像の`await`除去、適用待ち除去、完了前倒し、固定スロット化と各拒否ガード除去は、構文正常な変異でも該当する中間状態または入力値のassertで不合格にする。これは実モジュール間の接続をDOM・通信代役上で確認する自動試験であり、実ブラウザ操作や実API通信ではない。

保存確認は`browser-save-data.test.js`で実`save-data.js`全体を読み込み、公開`open()`で描画した保存／上書きボタンの登録済みイベントから検証する。DOM・requestJson・保存本文builder・サムネイル・外部stateは合成代役で、実appで組み立てた`save-flow.js`の保存構築接続は`browser-save-reset.test.js`が担当する。本文・thumbnail・期待revisionの出所、POSTから必要時だけ1回読戻す要求順、確認済みと未確認の状態差、競合、一覧失敗、独立した拒否ガードと4段階の待機を確認する。07から置換した9条件と恒久assertの対応は次のとおり。

| 対象条件（3＋2＋4） | `browser-save-data.test.js`の動作assert |
| --- | --- |
| 確認関数：slot一致 | `POST wrong slot ...`、`readback wrong slot ...`で読戻し要否・参照保持を確認 |
| 確認関数：safe integer | fractional／unsafe revisionと`safe integer boundary ...`で、次revision一致とは独立して拒否を確認 |
| 確認関数：expectedRevision＋1 | old／skipped revision、正常POSTのrevision出所、数値文字列のNumber変換後の受入れ |
| 読戻し：response／payload／parseErrorの取扱い | `readback ...`各結果の未確認状態・通知・再保存抑止 |
| 読戻し：parseError／HTTP不正拒否 | `readback parseError ...`、`readback HTTP failure ...` |
| 保存：response／payload／parseErrorの取扱い | `POST ...`各不正応答とHTTP失敗・競合の要求順・状態差 |
| 保存：必要時の読戻し呼出し | `POST ... needs one valid readback ...`の要求先・回数、`save waits for readback ...` |
| 保存：未確認時のstale／dirty／例外 | `readback ... keeps unconfirmed state ...`の参照維持・dirty=true・通知・登録済みイベントからの再保存拒否 |
| 保存：確認後の参照確定／dirty解除／一覧待機 | `save POST preserves ...`、`confirmed save survives list failure ...`、各`save waits for ...` |

無害な局所変数・分解順・変数経由awaitの変更は正常保存と読戻し保存の同じassertで受け入れる。slot／revision確認欠落、safe integer判定欠落、読戻し・一覧待機除去、未確認時dirty解除、一覧失敗時の参照消去は、構文正常を確認した変異を具体的な状態・順序assertで検出する。

削除も`browser-save-data.test.js`の実コントローラー・公開open・削除ボタンの登録済みイベントで確認する。DELETEはPOST・読戻しGETと区別し、一覧slotのrevisionを使う要求、現在slotだけの参照解除・dirty変更、破損slot削除、独立した拒否・HTTP/通信失敗、削除後の一覧反映と失敗通知を検証する。DOM・要求応答・外部stateはメモリ内代役であり、実appやサーバー保存ストアへの接続・実保存物の削除ではない。07の対象4条件は次のように扱う。

| 旧静的条件 | 現在の保証 |
| --- | --- |
| 共有一覧更新の取得待機 | `save waits for list ...`と`delete waits for list`で、一覧未完了時のbusy維持・完了通知前・確定状態を確認 |
| 一覧更新失敗の通知 | `confirmed save survives list failure ...`と`deleted slot survives ...`で操作成功と一覧失敗の通知、状態維持、登録済みイベントからの再操作抑止を確認 |
| 共有一覧更新のreturn false | 保存・削除の全2呼出しが戻り値を使わないため保証不要。戻り値の形は内部記述として検査しない |
| 削除後の参照解除→dirty変更→一覧待機 | `delete event completes ...`と`delete waits for ...`で現在/別/破損slotの要求・状態・一覧反映と待機を確認 |

削除・共有一覧更新の局所名変更と変数経由awaitを動作試験・静的区分の両方が許容する。誤slot/revision、別slotの参照消去、HTTP失敗後の成功処理、一覧待機除去、一覧失敗時の参照巻戻しは構文正常な変異を対応する要求・状態・中間順序assertで検出する。

状態・会話系の6群は次表の動作試験で保証する。条件数は旧PSの個別match/notmatch単位（複合正規表現は1条件）で、計43条件を動作へ置換、内部変数名禁止1条件を不要廃止した。

| 群／旧条件 | 恒久試験と観測するassert |
| --- | --- |
| A 保存構築12条件：07のbuildSave、recentTurns入力、profile、人物serialize、画像ID、latest/checkpoint不在、recentMessages不在、画像URL/prompt/composition不在、recentTurns重複確認、一時副人物非保存、08の中期記憶normalize・画像要望/ドラフト非保存 | `browser-save-reset.test.js`の`buildCurrentSaveState connects ...`。実app builder・state-lifecycle・人物セッション・worldline partitionを接続し、主副IDと状態所属、人物別記憶、両方向関係性、profile、recentTurns、入力由来の中期記憶とsceneImageIds、独立複製、返却JSONの非保存キー不在を確認 |
| B 初期化2条件：会話と世界線の段階接続 | 会話開始は`browser-chat-start-flow.test.js`の公開`start()`で準備待機中の無変更、画像失敗・取消時の全状態復元、成功時の初期化順を確認する。`browser-save-reset.test.js`は`full worldline reset ...`、`worldline reset guards ...`、`return-home click ...`で世界線全体初期化、背景待機、configなし・人物なし・busy・確認取消を確認する |
| C モード9条件：free/scene分岐、track変化、履歴再描画、自由/ゲーム通知、track変更時の最新1往復無効化、副人物記憶・復帰 | 同ファイルの`mode transitions preserve ...`。実setMode・記憶補助・人物セッションで同一game内の最新1往復保持、free切替時の無効化・履歴/記憶再描画回数・通知、1人化、元の副人物復帰、古い画像からは復帰しないこと、人物状態保持を確認 |
| C 不要廃止1条件：modeChangedという内部変数名の禁止 | 変数名自体に契約はない。track変更時のみ無効化する結果は上記動作assertで保証 |
| D 通常送信4条件：送信拒否、入力抑止、要求builder接続 | `browser-chat-flow.test.js`の`blocked send ...`、`busy and another failed request ...`、`send commits once ...`、`app form and latest regeneration ...`。公開入口で拒否時の入力・要求保持と許可時の要求ID・発言・音声・POST各1回を確認し、実`app.js`の組立て・フォーム登録からも送信を実行する。ボタンと入力の表示上の抑止は既存のapp・静的契約も併用 |
| E 応答確定7条件：画像準備、ターン、記憶、物語、最新登録 | 同ファイルの`public send records ...`、`two-person partial visual failure ...`、`memory rejection ...`、`visuals use current participants ...`、`story history ...`、`commit waits ...`、`empty reply ...`。公開入口から通常・自由対話・シーン・物語の履歴区分と参加者、2人表示の部分失敗、事前拒否、画像待機、falseと例外、履歴・記憶・要約・受信音の順序、実適用背景だけの記録を確認 |
| F 再生成と中止：最新ターン委譲とチェックポイント復元 | 同ファイルの`app redo uses the real checkpoint ...`、`app redo waits for the real checkpoint image ...`、`app redo and edit commit ...`、`real memory failures ...`、`real story cancellation ...`、`app form and latest regeneration ...`、`app form failure retry ...`、`real latest-turn edit and regenerate ...`、`regeneration waits ...`、`canceling a failed story send ...`。実`app.js`の組立てから実`checkpoint-restore.js`、`memory-scopes.js`、人物セッション、重要記憶状態・画面部品へ接続し、返信前チェックポイントと元返信後の現在記憶を分岐した追加・更新・削除×再生成・編集、無効応答／通信失敗後の中止、保持中の同一要求オブジェクトの手動再送（同一`requestId`・`bodyText`、通信1回）、中心人物画像の成功・`false`・例外時の物語状態・人物状態・最新操作権を確認する。物語状態は実`validateStorySaveState()`も通す。復元内部の状態・画像の詳細は`browser-checkpoint-restore`が担当 |

これらは最小DOM・画像処理・通信応答の代役上の接続試験であり、実ブラウザの描画やiPhone操作、実APIの保証ではない。保存側の中期記憶/物語/出来事normalizerと多くの応答経路は合成代役だが、再生成・編集の重要記憶更新は上表Fで実際の記憶部品を接続する。その範囲を各部品全体の保証と混同しない。`source-contracts.test.js`は隔離ソースの無害書換えを静的区分と`browser-chat-start-flow`・`browser-save-reset`・`browser-chat-flow`へ通し、人物ID誤所属・新規開始時の出来事確定欠落・失敗時のprofile復元欠落・track無効化欠落・送信保留拒否欠落・画像await除去・復元接続の迂回を動作assertで検出する。子試験は試験専用のソースパスを受け取り、正常終了だけでなくassertの実行件数も確認する。

残す条件の責任境界は次のとおり。混在Assert-Test全体を動作へ置換したとは扱わない。

| 残す静的条件 | 理由／担当範囲 |
| --- | --- |
| 07の関数抽出scope probe2条件、画像履歴復元関数存在、旧resetConversation・state.latestTurn/turnEdit不在、必須DOMとホーム表示/イベント/確認文言 | 抽出器の範囲限定、公開入口、所有権、旧分岐禁止という構造契約 |
| 07の世界線初期化内のbusy/failed複合禁止とrequestJson/settings/album依存禁止 | 独立した外部設定・永続保存物へ初期化を広げない依存境界。挙動側でも設定保持を確認 |
| 05の参加者フロー登録・API非依存・app生成／追加人物入口・旧`setSecondaryCharacter()`不在・保留／表示更新／共通操作調整器配線、07の一時副人物宣言・明示退場時の記憶消去／登録時の記憶設定、`setMode()`の画像revision無効化、08の画像履歴破棄禁止 | 非同期画像選択とrevision競合制御の責任。送信pending代役やモード結果試験だけで実画像競合全体を置換しない |
| 07のgetContextTrack、selectForApiのSet/公平最小/上限、createTurn接続、selectForDisplayのtrack/world、renderWorldlineConversationのselect/track/world、trimのpartition/candidates/enqueue、手動人物選択の入替3条件 | 世界線の純粋選別・押出し・手動選択の別責任。既存worldline単体試験と共存し、今回の保存結果試験をそれら全体の代替としない |
| 07の記憶保存/削除→手動更新、手動更新→最新無効化/dirty、ロード確定callback、06の記憶UI/人物状態、08の中期記憶通信/cache/UIと画像要求 | 状態・会話の段階接続に隣接するが、編集・課金防止・画像生成という別責任。共有抽出変数を維持し、未参照になった抽出だけ除去。物語の保証は次表を参照 |
| 08のbuilder生成/登録、再生成builder配線、state.mediumMemory入力、純粋モジュールのDOM/通信禁止、03～08の読込順とモジュール登録 | 公開接続と依存禁止。通常送信の関数内部呼出しとは分けて維持 |

物語系は33条件を動作へ置換し、再送状態の初期化を特定のオブジェクト記述に限定する1条件を廃止した。個別条件は次表の列挙で追跡する（match/notmatch単位）。再送状態は試験用の固定値ではなく、実appの宣言を読み込んで初期化する。

| 旧条件／判断 | 恒久assertと保証境界 |
| --- | --- |
| 03 prepareStoryChoicesのwaiting・background・request・commit（4）、waitingのsetMode（1）：置換 | `browser-story-choices.test.js`の`prepare choices exposes ...`、`morning background ...`、`real story controller, setMode ...`。背景/候補待機中のphase・busy・dirty・空候補、完了後の候補と確定順、実setModeのDOM属性、人物セッションを確認 |
| 03 beginStorySceneFromActionのprepare・request・apply・commit（4）、prepareStorySceneFromActionの人物/背景解決（2）：置換 | `browser-story-encounter.test.js`の`real request, sessions ...`と`begin action passes ...`。実入口から実APIクライアントまでの指定/名前解決/未指定の要求項目、現在人物・主副状態、位置、物語確定順を確認 |
| 03 applyStoryEncounterの準備/適用（2）、applyPreparedStoryEncounterのhide（1）、07のprepareVisuals待機・遭遇準備待機・遭遇適用待機（3）：置換 | 同ファイルの`each delayed visual stage ...`、`visual preparation failure ...`、`primary and secondary apply failures ...`、`prepare, primary, and secondary visual exceptions ...`、`real request, sessions ...`。準備・主・副の待機中に後段へ進まないこと、例外位置、画像を非表示にしても履歴IDは保持することを確認 |
| 03 retainWorldScopedStateのworldKey・game/free・記憶・対人関係・人物間関係の代入（6）：置換 | `browser-story-choices.test.js`の`fixed world retention ...`。実character-sessionsとmemory-scopesでON/OFFの各worldについてgame/free双方と両人物を入力由来値で比較。他領域を除外し、人物ID・服装・方向付き関係性を維持。公開export確認は静的に残す |
| 03 開始前世界観変更の人物スコープ移動・出来事維持・同一／利用不能／処理中の不変・gameId／保存設定由来の無効化、story UIの返値取得／選択欄反映：置換 | `browser-character-sessions.test.js`の`setup world changes ...`と`setup world scope move ...`、`browser-story-choices.test.js`の`actual app wiring ...`、`browser-world-settings.test.js`の実app接続で、全人物の両記憶区分・両関係性、A→B→A、途中失敗時の全体不変、出来事と入力途中の維持、新規作成・選択中削除・非選択削除、開始失敗再試行を確認する。保存設定の明示読込による別世界の出来事消去・同一世界の維持・人物再構築は`browser-adventure-configuration.test.js`が担当する。静的検査は世界観削除確認に消去文言がなく同じ状態移動入口を使うことを維持する |
| 03 再送のID取得・要求準備・応答正規化（3）：置換。再送オブジェクト宣言の記述形（1）：不要廃止 | 同ファイルの`story option request keeps ...`、`real api client preserves replay ...`、`story option validation ...`、`actual app wiring ...`。要求時世界・背景・本文、同本文のID再利用、変更時の新ID、失敗後の開始ボタン再操作の同一本文、応答の3件/一意/非空/許可背景を確認 |

進行は`browser-story-choices`の`story block progression ...`、`advance caller ...`、`advance cancellation ...`で標準5ブロック・翌日・日付上限・元state非変更・取消と復元呼出し順を確認する。実画像を含む復元処理の成功/失敗は既存`browser-checkpoint-restore.test.js`の実app復元接続が担当し、choices側の復元代役だけで実復元を保証しない。`browser-story-encounter`の`real save flow preserves code-point-boundary story and memory data ...`は、実`save-flow.js`の構築→ロード適用→再構築で、候補・選択済み候補、中期記憶3本文、重要記憶の上限内コードポイント列、ID、配列順が一致することを確認する。`real save and load preserve three story phases ...`は選択待ち・1人・2人の実保存構築→実ロード適用→実要求builderで、履歴・人物別記憶・中期記憶・物語位置・次要求の一致を確認する。`real send waits ...`／`real send keeps input ...`では場面開始の待機/失敗中の入力保持とチャット未送信を確認する。

`browser-story-encounter.test.js`の物語保存・ロード往復は実`save-flow.js`の`buildCurrentSaveState()`と`applyLoadedSave()`を通し、保存投影の変異を`source-contracts.test.js`で検出する。`browser-summary-disclosure.test.js`は実`story-flow.js`の`prepareNextStoryBlock()`から候補取得・背景失敗後の復元を通し、成功ロードは実`save-flow.js`の`applyLoadedSave()`から結果一覧の再展開を確認する。これらは部品間の動作を保証する試験であり、`app.js`の組立ては各機能の接続試験で別途確認する。

`browser-checkpoint-restore.test.js`の次ループ失敗・操作置換試験は実`storyFlow.createController().prepareNextStoryBlock()`から実チェックポイント復元を通し、総括状態・再試行・`busy`所有権を確認する。`browser-story-choices.test.js`の公開次ブロック入口はJSON/HTTP異常、候補待機中の未確定状態、要求時点の背景候補、翌朝背景失敗時の確定抑止を確認する。開始時の朝背景失敗による候補要求抑止は実`app.js`組立てから開始ボタンの登録済みイベントを操作して確認する。関数本文抽出を使う旧試験は局所補助として残す。

物語試験のDOM、候補/遭遇のfetch応答、画像読込/適用、画面更新の一部は合成代役であり、実API・実ブラウザ・iPhone操作を実施した保証ではない。`story-flow.js`の候補/開始/遭遇段階関数は実コードを使い、全deferredはfinallyで解決と後続回収を行う。`source-contracts.test.js`では無害な局所名・等価awaitを実静的区分と同じ動作試験へ通す。世界入力・再送ID・候補欠落/確定前倒し・人物解決・主副待機・画像履歴破棄・翌朝日付・保持世界の10変異は構文正常を確認し、各試験の`P09-08`付き状態/要求/順序assert、失敗1件・取消0件まで対応付けて検出する。

全8区分の残存分類は次のとおり。列挙した群は維持と判断済みであり、未検討の置換予定ではない。静的条件の残存と実動作の保証を区別し、先行段階で置換済みの詳細は上表群を参照する。

| 区分／残る機能群 | 判断理由・保証先 |
| --- | --- |
| 01：Node内部試験起動、隔離デモ/画像モック、Host/Origin/同一Origin事前確認、JSON/HTML/CSP防御ヘッダー、1MiB/16KiB上限、診断受信・起動識別・位置・秘密除去 | 維持。ここは既に実ローカルHTTP/ログの動作保証であり、内部ソース条件の置換対象ではない。`test-game.ps1 -Area all`、http/diagnostics等のNode試験 |
| 02：表情/クレジット/メニュー/アルバム/診断、旧表示不在、モード/2人/ホーム5入口、背景とロゴの配信、回転案内/舞台・入力16px・選択一覧/縦横幅・人物サイズ/3列、エラー日本語/機械情報非表示、選択サムネイル | 維持。DOM・文言・素材配信・CSS規約は静的/HTTP契約。PC関数試験では実端末レイアウトを再現しない |
| 03：起動失敗通知/診断、中期失敗バッチ分離/他バッチ継続、世界観複製入口/未保存確認/外タップ、アルバム/診断/ホーム配線、入力300文字/submit、設定項目順/カスタマイズ導線、現実時間/v19、物語DOM/CSS/登録/API入口/placeholder/無人thumbnail/一覧文言/旧lock禁止、素材制約UIと初期復帰 | 維持。登録・依存・UI/定数規約と中期通信/編集画面の制御。中期データ単体試験はappの要約ループ・再送cacheの代替ではない。物語内部33条件等のみ上表で置換 |
| 04：4編集画面の破棄確認、profile/関係性方向/一括適用/画像要求からの分離、記憶分類説明、人物設定の年齢/表示名/説明/人格順/差分/空欄、@候補/人数/除外/IME/キー操作、折返し/スクロール、料金文言/モデルUI | 維持。公開文言・フォーム/イベント・禁止依存と編集ドラフト責任。既存人物/重要記憶のデータ試験だけでは複数編集DOMとIMEを横断保証しない |
| 05：保存画面open/描画/ボタン、ホーム/メニュー/コントローラー入口、手動人物追加のAPI分離と状態存在、pending開始/refresh/解除 | 維持。画面配線と画像選択側の状態供給。内部ロード・保存・通常送信の動作保証は先行表 |
| 06：viewport/拡大防止/旧モバイル禁止/HTTPコピーfallback、記憶scope正本/旧互換禁止/純粋モジュール分離、人物とlifecycle接続、開始世界選択/プレイ中固定、重要/中期/出来事の編集・上限・ドラフト破棄/切替、DOM一意/latest UI、画像/アルバムUI・お気に入り・story HUD通知・無通信再表示・重複/上限/前後移動・一意所有・操作領域/CSS | 維持。DOM・分離・禁止依存と編集/画像コントローラー内部条件。browser-important-memory-state/medium-memories/scene-imagesはデータや公開操作を補完するが、全app配線/端末操作の置換ではない |
| 07：旧入口/固定セリフ不在、抽出scope/記憶更新/load callback、ロード拒否、必須DOM/ホーム確認/初期化の依存禁止、手動画像の無通信/無言/dirty、画像mode制限/latest所有、世界線track/公平選別/render/trim/人物入替、一時副人物記憶、画像revision/選択lock/1回再試行/状態確定/false処理 | 維持。構造・別責任の手動選択と画像競合。worldlineやstate接続試験を競合DOM全体の代替にしない。物語の重複待機3条件のみ上表へ移行 |
| 08：中期読込順/登録/builder純粋性/文脈、押出し/手動再要約/失敗元削除/成功失敗cache、画像履歴維持・生成成功/失敗・追加要望/同一本文再送、人物選択取消、フォーカス/blur・viewport時間差回復・dialog/pageshow/visibility | 維持。課金防止cache・画像要求・端末focus/viewportの責任。時間制御/編集DOM基盤と各モジュール/全領域試験を併用する |

`tests/source-contracts/03`～`08`は上記の静的構造・残存内部条件を守る。05の保存画面とホーム入口、07のロードHTTP不正/save欠損から例外まで・古い一覧禁止は従来どおり維持する。保存確認・削除一覧更新・ロード適用の先行段階の保証は上記各表に従う。`buildChatRequestPayload()`内部、保存構築、2初期化・応答確定・上記物語段階接続について具体的な内部記述を再要求しない。
- `node-server/test/source-contracts.test.js`は、実際の責務別ファイルをWindows PowerShell 5.1で順に読み、正常な隔離ソース、会話要求・ロード接続・保存確認の無害な内部書換え、各静的区分の代表変異が合否へ正しく反映されることを確認する。さらに実`test-game.ps1`の隔離コピーへ制御確認専用の領域・支援を与え、Node全件の先頭1回実行、非`all`の省略、`all`併用拒否、先頭だけ、前3領域、全6領域の順序、途中失敗後の停止・終了1・`finally`後始末を確認する。これは静的構造と進行制御の保証であり、実HTTP・実検査全体の合格根拠は`test-game.ps1 -Area all`と分ける。

#### 設定・素材検査の責務と実行順

`validate-project.ps1`は引数なしの正規入口であり、`ProjectRoot`、各正本パス、`Errors`、`Warnings`、画像・音声件数、`ReferencedAssetPaths`を初期化する。入口は`tests/validation`の全ファイルについて存在・PowerShell構文・UTF-8 BOMを実行前に確認した後、次表の順に同じスクリプトスコープへdot-sourceする。分離先は`ProjectRoot`を`PSScriptRoot`から再計算せず、表記した共有値だけを参照・更新する。

| 順序 | ファイル | 責務と共有状態 |
| --- | --- | --- |
| 1 | `validation-support.ps1` | JSON、安全な相対パス、構文、画像、ハッシュ、Node委譲などの共通関数だけを定義。検査全体や`exit`は実行しない |
| 2 | `character-tools.ps1` | キャラクター登録・解除入口の存在を確認し、`Errors`を更新 |
| 3 | `image-runtime.ps1` | Windows標準画像機能を準備し、失敗時は`Errors`を更新 |
| 4 | `files-and-documents.ps1` | 必須ファイルと全ユーザー向けHTMLの相対リンクを確認し、`Errors`を更新 |
| 5 | `runtime.ps1` | PowerShell／Node.js、sharp固定版、全Node構文、アルバム保存状態、既存PS1のBOMを確認。`Errors`／`Warnings`を更新し`nodeCommand`を後続へ渡す |
| 6 | `browser-and-prompts.ps1` | ブラウザ構造・読込順・分離契約とプロンプトを確認し、プロンプト読取値を後続へ渡す |
| 7 | `configuration-assets.ps1` | JSON設定、世界観、孤立セーブサムネイル、画像・音声、人物表示を確認。`Errors`／`Warnings`、件数、参照素材集合と設定値を更新 |
| 8 | `character-packages.ps1` | 実行設定と登録済み／解除済み人物パッケージ、人格・デモの整合を確認 |
| 9 | `asset-references.ps1` | `ReferencedAssetPaths`と実素材を照合し、未参照素材を`Warnings`へ追加 |

入口は最後に対象件数、順序付き警告・エラーを一度だけ出力し、エラーなしを0、エラーありを1で終了する。Node構文違反など従来から子コマンドのネイティブエラーで即時終了する経路は集約終了へ変更しない。`runtime.ps1`の全JavaScript構文確認は`node-server/scripts/check-js-syntax.js`へ1回委譲し、`src`・`scripts`・`test`の現行`*.js`をNode.js 24の`node --check`で同時最大4件検査して全子プロセスを回収する。Node試験ランナーの固定並列数は2のままとする。Node.js 24系、依存固定版とsharpの実読込み、Node.js必須ファイル、全JavaScript構文、設定・素材、全ユーザー向けHTMLと相対リンク、孤立セーブサムネイル、アルバム正本の片割れ・破損・孤立サムネイルを、旧サーバーモジュールなしで読み取り専用検査する。

恒久回帰は`node-server/test/project-validation.test.js`から実入口をWindows PowerShell 5.1の子プロセスで起動する。警告なし正常、現用人数から独立して合成した有効な1人・2人構成とその画像件数、警告だけの非破壊、JSON不正、Node構文の即時終了、異なる責務を跨ぐ複合不正の診断順、分離ファイルの欠損・BOM・構文違反、プロジェクト外CWD、BAT・人物管理からの入口接続を固定assertで確認する。対象件数の期待値は検査出力ではなくfixtureへ与えた設定・素材構成から算出する。fixtureは`data/test-runs/p09-01-*`へ作り、カスタム世界観の正副JSONと保存用フォルダは合成し、現用の保存データをコピーしない。変更対象はfixture内のコピーだけとし、共有するNode実装・依存は読取り専用junctionに限定して終了時に削除する。恒久保証は前記assertの観測点を正本とする。Node.js固有の単体・同時実行・保存契約試験は`ゲーム本体/node-server`で`npm test`、同じ全領域試験は`npm run test:blackbox`または`test-game.ps1 -Area all`で実行する。
- JavaScriptの関数内処理を静的確認する場合は、結合済み全ソースへ無制限の`[\s\S]*?`を適用せず、`Get-TestJavaScriptFunctionSource`または開始・終了を限定した`Get-TestJavaScriptSegment`で対象範囲を切り出す。後続関数の同名処理による見逃しを防ぐためである。

CSSの読込順異常は実入口で拒否させ、CSSファイル欠落と空本文はfixture専用runnerから実検査関数を呼んで診断と他ファイルの不変を確認する。検査規則は試験側へ複製しない。

## Gitによるローカル履歴管理

- リポジトリルートはプロジェクト直下、標準ブランチは`main`。`user.name`は`Sato0`、`user.email`は外部アカウントと結び付かない`sato0@local.invalid`をプロジェクトローカルに設定し、`core.autocrlf=false`、`core.longpaths=true`とする。外部remoteは持たない。
- Codex隔離環境が作成した`.git`をWindowsユーザー側のGitからも扱えるよう、ユーザーのグローバルGit設定にはこのプロジェクトの絶対パスだけを`safe.directory`として登録する。ユーザーフォルダ全体やワイルドカードは登録しない。
- 追跡対象は`ゲーム本体`の実行用コード・設定・正式素材・ライセンス、`作業用`の現役資料、ルートの保守ファイルとする。正規素材は完全な基準状態を復元できるよう、画像・音声を含めて追跡する。
- `【ユーザー作業&バックアップ用】`、`ゲーム本体/data`、`node_modules`、coverage・cache・log、`.env`、OS・エディター一時ファイルは`.gitignore`で再帰的な追加対象から除外する。`public/data`、`config`、`character-packages/installed`は除外しない。
- `.gitattributes`はPowerShell・BAT・CMDをCRLF、JavaScript・JSON・CSS・HTML・Markdown等をLF、画像・音声・書庫をbinaryとして扱う。属性はGitによる変換だけを管理し、PowerShellのUTF-8 BOMは設定・素材検査とレビュー候補の定型検査で確認する。
- 変更前後は`git -C <project-root> status --short --branch`で対象リポジトリと差分を確認する。役割分担を使う変更では、検査済みの実装と恒久資料だけをレビュー候補として個別にステージし、`git diff --cached`をレビュー対象の正本とする。承認と必要な実機・外部確認後に調整文書を閉じ、承認済みtree IDを使う最終化検査に合格してから、結果の分かる日本語の要約で1作業1コミットを作成する。未完了、調査だけ、実機確認だけが残る作業はコミットしない。担当の責任と状態遷移は`作業用/担当別指示/計画・差分レビュー担当.md`と`作業用/担当別指示/実装担当.md`を正本とする。
- Git導入後の時系列的な変更記録はコミットを正本とする。現役資料には現在の仕様だけを置き、旧値や日付付き経緯を追記しない。導入前の経緯は`作業用/記録/Git導入前の主要変更履歴.md`に凍結し、必要な場合だけ対象パスを限定した`git log`、`git show`、`git blame`または同資料で確認する。
- `git reset --hard`、`git clean`、既存差分への`checkout --`・`restore`は禁止し、必要な場合は対象と回復不能性を説明してユーザーの明示承認を得る。remote追加、fetch、pull、push、公開サービス連携も明示承認が必要。
- Gitはローカル変更履歴であり、PCの故障・紛失からデータを保護するものではない。除外済みのセーブ、生成画像、診断ログ等はGitから復元できない。

### レビュー候補の定型検査

- プロジェクト直下を実行フォルダとし、通常レビューはWindows PowerShell 5.1で`powershell.exe -NoProfile -ExecutionPolicy Bypass -File ".\tools\check-review-candidate.ps1"`を実行する。調整文書を閉じた後は、閉鎖前に承認したtree ID、または調整文書自体の最終差分を独立レビューして承認したtree IDを使い、`powershell.exe -NoProfile -ExecutionPolicy Bypass -File ".\tools\check-review-candidate.ps1" -FinalizationTreeId "<承認済みtree ID>"`を実行する。大規模作業全体の終了または調整文書自体の改訂では、末尾へ`-RequireAllCoordinationClosed`を加える。サブフォルダから実行する場合は`-File`へ正しい相対パスまたは絶対パスを指定する。成功は終了コード0、不合格または検査不能は1を返す。
- 作業中の`作業用/進行中の作業.md`にある「ステージ済みレビュー候補」へ、リポジトリ相対パスを一ファイル一行の箇条書きで記録する。検査は記録と実際のステージ対象が完全一致すること、記録の重複がないこと、同じファイルにステージ済み・未ステージ変更が併存しないこと、`git diff --cached --check`が成功することを確認する。未追跡ファイルは一覧表示するが、それだけでは不合格にしない。
- 通常モードは進行記録の候補一覧と実際のステージ対象を完全一致させる。最終化モードは進行記録の候補一覧を読まず、指定した承認済みtree IDと現在のGitインデックスを一致させ、現在フェーズの二つの調整文書を状態「なし」とする。`-RequireAllCoordinationClosed`指定時は四つすべてへ広げる。両モードとも、同じファイルの部分ステージ、`git diff --cached --check`、未追跡ファイルの表示、保護領域、現役PowerShellの厳密なUTF-8・CRLF・日本語を含む場合のBOMを同じ基準で確認し、作業ツリー、ステージ領域、Git設定を変更しない。
- 状態が有効な四つの調整文書、および`.gitignore`で保護するユーザー退避領域・入力資料・`ゲーム本体/data`はレビュー候補へ含めない。運用文書自体を変更する作業では、UTF-8で一意の`状態：なし`を持つ空テンプレートだけを最終候補にできる。
- 検査本体の回帰試験は、プロジェクト直下で`powershell.exe -NoProfile -ExecutionPolicy Bypass -File ".\tools\tests\check-review-candidate.tests.ps1"`を実行する。試験は専用の一時Gitリポジトリだけを作成し、通常モードの正常系・候補不一致・文字コード等に加え、最終化モードの閉じた進行テンプレート、候補変更、未閉鎖の現在フェーズ文書、大規模計画を残すフェーズ終了と全体終了の差を確認して終了時に削除する。
