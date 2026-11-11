# 幹事キャディ（ゴルフコンペ 組分け・出欠管理）PROJECT_NOTES

別のチャットや別の人が引き継いでも続けられるように、これまでの決定事項をまとめたメモ。

## 概要
- 持ち主：森雄介（株式会社メディコム）。複数の幹事で共有、スマホが中心（PCも使う）。8〜100人、定例も単発も。
- 構成：`index.html` 1ファイル（素のJS）を GitHub Pages で公開 ＋ Supabase（プロジェクト `golf-compe`、ref `sotrrieijxizfpbsumti`）。
- 公開URL：https://golf.medicom.co.jp/（独自ドメイン。DNSはVALUE-DOMAINのCNAME golf→yskm10.github.io.、リポジトリ直下のCNAMEファイルとGitHub Pagesのカスタムドメイン設定。旧 https://yskm10.github.io/golf/ は新URLへ自動転送される。localStorageはオリジンごとのため、切替時に幹事は管理用URL(?t=)を開き直す）／ リポジトリ：`yskm10/golf`（mainにpushすると公開される）。
- 幹事用URL：`?t=<チームの管理トークン>`（知っている人はそのチームの管理者）／ 出欠フォーム：`?f=<コンペのフォームトークン>`（ログイン不要）。

## 画面と機能（すべて index.html）
| 画面 | ルート | 内容 |
|---|---|---|
| コンペ一覧／作成・編集 | `#/events` `#/event/new` `#/event/<id>/edit` | 予約確認画面のスクショから日付・ゴルフ場・スタート枠・料金・注意事項をAIで読み取り |
| コンペ詳細 | `#/event/<id>` | 出欠集計、スタート枠の登録（貼り付け／間隔から作成）、出欠フォーム、承認待ち、LINE案内文のコピー |
| 組分け | `#/event/<id>/groups` | 自動振り分け（平均スコア＋所属＋男女比を分散。男女はティー色から自動）。選択肢：同じ所属＝わける／揃える／考えない、組の強さ＝揃える／揃えない、男女＝均等にばらける／考えない、タップ入れ替え、組内の順番（↑↓）、ロック、同じ組／別の組ルール、当日キャンセル、LINE用組表 |
| 印刷用組表 | `#/event/<id>/print` | A4、OUT／INを別表、ヘッダー・フッターなし |
| ニアピン・ドラコン | `#/event/<id>/special` | ホームは当日でも入力可、OUT組／IN組ごと、コースを回る順に並ぶ |
| 集金チェック | `#/event/<id>/collect` | 受取トグル、金額変更、2名組追加料金、未回収コピー |
| 成績・順位 | `#/event/<id>/results` | 成績表の写真から読み取り（Edge Function `read-results`）、手入力 |
| 賞・商品 | `#/event/<id>/awards` | 賞ごとに商品・金額・数量を登録、受賞者を自動割り当て（ネット順位／グロス／ブービー／ニアピン等）。商品の予算と差額も計算（`events.prize_budget`、`awards.price/qty`） |
| 名簿 | `#/players` | 追加・まとめて追加（CSV）・他チームの名簿コピー |
| チーム | `#/teams` | 端末内のチーム切り替え・作成・URLで追加。切り替えたあとは、画面上部に「← 前のチームに戻る」ボタンが出る |

## 決めていること（要件）
- ハンディキャップなし → **平均スコア**で組分け（0＝不明・初めての人。参加なら入力必須）。
- 所属は自由入力で、幹事だけが入力（参加者フォームには出さない）。ティー色は表示だけで、組分けには影響しない。
- 通常のスタート時間制。**時間は均等ではない**（例：8分・7分の交互）、IN／OUT同時スタート。組の呼び名は `OUT1…` `IN1…`（時間順）。
- 出欠フォームは**名簿の一覧を出さない**。姓・名・姓のよみ・名のよみを入力 → 名簿と名前（空白無視）が一致すれば本人として登録、なければ「承認待ち」。同じコンペへの再回答は上書き。
- 料金：プレーフィー＋コンペ費。案内文は「参加費：○円（プレーフィー＋コンペ費合計）」とし内訳の金額は出さない。「幹事がまとめて集金」を選ぶと集金方法に「受付で現金で集金」が自動で入る。1組2名の追加料金は、幹事集金のときだけ集金額に足す。
- 特記事項は「幹事用」と「LINE案内文に入れる」を分ける。
- 当日キャンセルは、その人を組から外すだけ（他の組は動かさない）。あとは手動で組み替える。人間関係があるため自動で詰めない。
- 成績表は「Wペリア・ネット順位」の表（氏名・グロス・Hdcp・Net・順位）を読み取る想定。ベスグロは男女別があるため性別が要る。性別はティーの色から自動で推定（赤＝女、白・青・金・黒＝男、ティー未設定＝不明）。成績画面で手で変えられ、手で入れた値が優先。

## データベース（Supabase）
- テーブル：teams, players, events, entries, groups, group_members, group_rules, special_records, awards, read_log。
- アクセス制御：RLS。リクエストヘッダー `x-team-token` → `current_team_id()`（security definer）でチームを判定。
- 出欠フォームは security definer のRPC：`form_get`（名簿は返さない）、`form_submit`（名前一致で本人登録／なければ承認待ち）。承認は `approve_entry`。
- トリガー：`compose_name()`（姓名から name を「姓 名」に組み立て）、`set_updated_at()`。
- Edge Function：`read-booking`（予約スクショ）、`read-results`（成績表の写真）。トークンで幹事を確認、1チーム24時間30回まで（`read_log`）。`read-booking`（案内文・予約スクショ）の既定は Haiku（`claude-haiku-4-5-20251001`、シークレット `READ_MODEL_BOOKING` で変更可）。比較テストで日付・料金・枠は十分正確、費用は標準の約1/3〜1/6。ただし「含まれるもの」を1項目落としがちなのでプロンプトで漏らさないよう指示。画面の「読み取りの設定」で「詳しく読む（標準 Sonnet）」に切替可（localStorage `golf_read_model_booking`）。`read-results`（成績表）の既定は標準のまま、Haikuは未検証（キー `golf_read_model_results`）。`read_log` に kind／model／input_tokens／output_tokens／input_type を記録（実費の見積り用）。`read-booking` は画像のほか、貼り付けた文章（`text`）も読める。`tool_choice` は auto（強制は未対応）。シークレット `ANTHROPIC_API_KEY`（Supabase側に設定済み）。
- SQLの履歴は `supabase/*.sql`（`form_noplayers.sql`、`group_rules.sql`、`special_course.sql`、`collect.sql`、`results_awards.sql`、`prize_budget.sql`、`fix_duplicates.sql`）。それ以前（姓名分割・よみ・料金など）は SQL Editor で実行済み。

## 作業の進め方（重要）
1. 機能ごとにブランチを切って実装 → 動作確認（Playwright＋模擬クライアントで画面、`execute_sql` で読み取りだけ）。
2. **データベースの変更が要るときは、SQLを書いて幹事（ユーザー）がSupabaseのSQL Editorで実行**。`apply_migration` は何度も「cancelled」になるため使わない。実行後に読み取りSQLで確認する。
3. mainへ fast-forward マージして push（GitHub Pages に公開される）。
4. コミット末尾：`Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>` と `Claude-Session: …`。
- 検証環境（クラウド上のコンテナ）からは CDN と supabase.co に届かない。画面のテストは `@supabase/supabase-js@2` を模擬クライアントに差し替えて行う。写真読み取りの実物確認は、ユーザーの実機で行う。

## まだやっていないこと／検討中
- **同順位や飛び賞の抽選・自動割り当て**（「10位ごと」など）。今は「手で決める」。
- **ルールの繰り返し適用**：同じ組・別の組のルールはコンペごと。毎回使う組み合わせ（夫婦など）を自動で効かせる案は未実装。
- **過去の同組履歴を避ける**（自動組分けの重みづけ）。
- **名簿の書き出し（CSV）**、チームをまたいだ共有名簿（今はコピーのみ）。
- **成績表の写真読み取りの実物確認**（模擬の結果でしか試していない）。
- 参加者向けの閲覧専用ページ（`events.view_token` は予約のみで未使用）。
- **アプリ化・公開**：まず自分たちで使ってみて、便利なら検討。方針は「無料＋広告、有料で広告なし・AI読み取り制限緩和」。公開するなら、ログイン（今は幹事用URLが鍵）、AI費用の上限、チーム作成の制限、プライバシーポリシー、App Store審査（Webの包みだけだと不可の恐れ）、アカウント削除機能が必要。データ量は小さい（1コンペ約30〜50KB）ので、DBは Supabase の有料プランで足りる見込み。コアサーバーへの移行は、裏側の作り直しが大きく割に合わない。

## アプリ化の進め方（段階）
- **段階1（済）ホーム画面に追加できるアプリ（PWA）**：`manifest.webmanifest`、`sw.js`（画面は常にネットから取る最小版）、`icons/`（4人と旗のアイコン。`source-1024.png` はストア用の元画像）。iPhoneはSafariの共有→「ホーム画面に追加」、Androidは「アプリをインストール」。
- **段階2 公開できる形にする**：ログイン（メール等。今は幹事用URLが鍵）、AI読み取りの費用上限と有料プランの区分、プライバシーポリシー・利用規約、アカウント削除機能、チーム作成の制限。広告を入れるならAdMob等。
- **段階3 ストア公開（目標）**：Webアプリを包む（Capacitor）→ App Store（年約99ドル）／Google Play（初回約25ドル）。Appleは「Webサイトと同じ中身」だと断ることがあるので、通知・端末保存など、アプリらしい機能を足す。アプリ内課金はAppleに15〜30%。

## 気をつけること
- 名簿を作り直すと、出欠の `player_id` が空になる（孤児）。同じ人を追加すると二重になるため、幹事画面の追加と出欠フォームは、同名の孤児があればつなぎ直す（`putEntry` / `form_submit`）。
- 画面側の鍵（`sb_publishable_…`）は公開してよい種類。管理トークンはURLに入っているので、幹事以外に渡さない。
- 名前が違う漢字（渡辺／渡邊）だと別人として承認待ちになる。幹事が承認画面で見比べる。

- コンペ詳細画面：ヘッダー右（旧「前のチームに戻る」の位置）に「← コンペ一覧」、末尾に「このコンペを削除」（確認ダイアログ・回答件数表示。編集画面にも同名ボタンあり）。関連データは外部キーのON DELETE CASCADEで消える。
- チーム切替：ヘッダーの「前のチームに戻る」は廃止（誤タップの元になるため）。チーム切替画面（ヘッダーのチーム名▾）で使用中のチームにも「このチームで続ける」を表示し、コンペ一覧へ戻れる。
- 戻るボタンはすべてヘッダー右に統一（`routeAdmin` の `back`）：コンペ詳細→「← コンペ一覧」、組分け/ニアピン/集金/成績/賞/編集→「← コンペに戻る」、印刷→「← 組分けに戻る」。画面内の戻るボタンは廃止。
- 自動組分けの「男女のばらけは」：均等にばらける／かためる（女性・男性を同じ組に集める。重み負）／考えない。入れ替え選択中の下部バーはタブバーの上に出す（bottom: calc(64px + safe-area)）。
- 結果をLINEで送る（`#/event/<id>/share`、コンペ詳細の「📨 結果をLINEで送る」）：①受賞者の文章（編集可・コピー・`line.me/R/msg/text`でLINEへ）、②画像（受賞者発表カード1枚＋成績表は30人ごとに1枚、Canvasで生成）、記念写真は端末の写真を選んで足す（アプリ・DBには保存しない）。画像は Web Share API（`navigator.share({files})`）でLINEの共有画面へ。LINEが画像と文章を同時共有すると文章が落ちることがあるので文章は別送。成績表の順位は成績表由来の `result_rank` を優先、なければネットから（同スコアは同順位、次は飛ぶ）。実機のLINE共有は未確認。
- 同スコアのときの順位の決め方（`supabase/tiebreak.sql` 実行済み）：events.tiebreak_net（既定 gross,sex,age,countback）/ tiebreak_gross（既定 sex,age,countback）/ tb_sex（F＝女性が上）/ tb_age（old＝年長が上）。共通関数 `tieCmp`・`rankBy`・`tiebreakCard`（賞・商品、成績・順位の両画面に設定カード）。データがない項目は飛ばし、決まらない同士は同順位（次は順位が飛ぶ）。生まれ年は players.birth_year（名簿）と entries.birth_year（成績画面で上書き）、カウントバックは entries.score_in（後半9ホールのスコア、小さい人が上。ホールごとのスコアは持たない）。成績表の写真に順位（result_rank）があればそれが優先、「ネットから順位を計算し直す」で設定どおりに付け直す。ブービー賞の同スコアは従来どおり幹事が選ぶ。
- 出欠フォームで性別（参加なら必須・男性/女性）と生年月日（任意・年月日の3選択）を聞く（`supabase/form_sex_birth.sql` 実行済み）。`form_submit` に `p_sex`・`p_birth_date`（既定null、旧クライアントでも動く）を追加し、entries.sex/birth_date/birth_year と、名簿（players.sex/birth_date/birth_year）の未入力分に反映。`approve_entry` も引き継ぐ。回答者の端末には `golf_me` に性別・生年月日も記憶（次回の入力を省く）。性別の優先順は entries.sex ＞ players.sex ＞ ティーの色。年齢の同スコア判定は生年月日があれば日付、なければ生まれ年で比べる。名簿の編集画面に性別と生年月日を追加（生まれ年の入力欄は廃止）。
- 注意：生年月日は個人情報。プライバシーポリシー（ストア公開の段階2）に、取得目的（同スコアの順位づけ）と幹事以外に見せないことを書く。
- ティー入力は廃止（名簿の編集・名簿にない人の追加・Excel貼り付けの7列目は「性別（男／女）」に変更。昔のティー色の列も男女に読み替え）。人名の横の丸印は性別（女＝赤、男＝白）。DBの players.tee / entries.tee 列は残す（過去データ）。既存の名簿・出欠は、ティーから性別を一括補完済み（赤＝女、他＝男。ティー未設定の13人は性別未設定のまま）。性別の優先順は entries.sex ＞ players.sex ＞ ティー（旧データのみ）。

## LINEログイン（2026-11-11）
- 方針：チームの権限は従来どおり幹事用トークン（x-team-token）。ログインは「トークンを取り戻す・引き継ぐ」層。既存のRLSは変えていない。
- Supabase Auth：Custom Provider `custom:line`（OIDC、issuer `https://access.line.me`、scopes `openid, profile`、Allow users without email=ON）。LINEチャネルID 2012549358（LINEログイン、ウェブアプリ）。コールバック `https://sotrrieijxizfpbsumti.supabase.co/auth/v1/callback`。Supabase の Site URL / Redirect URLs に `https://golf.medicom.co.jp/**` を登録する必要あり。
- DB（`supabase/auth_accounts.sql`、実行済み）：`team_members(team_id,user_id)`（RLSオン・ポリシーなし）、RPC `claim_team(p_token)` / `my_teams()` / `unclaim_team(p_token)`（authenticatedのみ実行可）。1チームに複数アカウントを紐づけ可能（幹事が複数いるため）。
- フロント：`authClient()`（persistSession、PKCE、storageKey `golf-auth`）、`syncAccount()`（起動時にmy_teamsで端末へ復元）、`accountCard()`（ウェルカム画面と設定画面）。ログイン中に開いたチームは自動で `claim_team`。「この端末から外す」は `unclaim_team` も呼ぶ。
- 方針メモ：Appleログインは、iOSのストア公開時に追加（後回し）。無料枠（同時進行コンペ1件／AI読み取り通算3回、失敗は数えない）はアカウント単位でサーバー側に実装予定（未実装）。結果画像のLINE送信は、無料は透かし入り、有料は透かしなし＋表彰カード等。
- 公開済み（2026-11-11）：`privacy.html`（プライバシーポリシー）/ `terms.html`（利用規約）。問い合わせ先はGoogleフォーム https://forms.gle/m8F1JNPeMe1TYfFD8（メール通知オン）。アプリのログイン画面・設定画面の下からリンク。有料化の前に、特定商取引法に基づく表記のページを追加する。公開前に専門家のチェックを推奨。
- 実機確認が必要：LINEログインの一連の流れ（サンドボックスでは不可）。
- 最初の画面（2026-11-11変更）：ログイン前はLINEログインのボタンだけ。ログイン後でチームがない場合に、「新しくチームを作る」「以前のチームを引き継ぐ（幹事用URLを貼る）」を表示。チーム作成はUI上ログイン必須（create_team RPCはまだサーバー側でログイン必須にしていない。無料枠の実装時に強制する）。既存の幹事用URL（?t=）でそのまま開く利用は、ログイン不要のまま。
- LINEログインの不具合メモ：SupabaseのCustom Provider（OIDC・自動読み込み）は、LINEのウェブログインがHS256で署名するため、ID token検証で失敗する（公開情報はES256）。手動設定（Issuer URLあり・JWKS URI空欄）に作り直して解消した。ログイン失敗時は、URLのerror_descriptionを最初の画面に表示する。ログイン中は、この端末のチームを全部 claim_team で紐づける。

## 無料プランの上限（2026-11-11）
- 仕様：無料＝進行中のコンペは同時に1件（開催日が今日〈日本時間〉以降、または日付なし。過去日は数えない）／AI読み取りは通算3回（成功した分だけ数える）／チーム作成はログイン必須で、1アカウントにつき無料チームは1つ。有料（`teams.plan='pro'`）は制限なし。
- DB（`supabase/free_plan.sql`、実行済み）：`teams.plan`（free/pro）、`teams.created_by`、`create_team`（ログイン必須・team_membersへ登録・anonの実行権限なし）、トリガー `events_free_limit`、RPC `team_status()`（プラン・AI使用回数・進行中コンペ数）。既存の4チームは、すべて pro（制限なし）にした。
- Edge Function（read-booking v7 / read-results v3）：無料チームで成功済みの読み取りが3回以上なら 402 `free_limit`。成功時は `quota:{used,limit}` を返す。上限の数字（3）は `FREE_AI_LIMIT`、SQLの `team_status()`、画面の文言の3か所で揃える。
- 有料への切り替え：決済の仕組みができるまでは、SQLで `update teams set plan='pro' where ...`。画面には「有料プランは準備中。お問い合わせ（Googleフォーム）」を表示。
- 画面：設定にプランカード、コンペ作成の前に上限の案内、AI読み取りボタンの下に残り回数、上限到達時の案内。
- 未実装：結果画像のLINE送信（無料は透かし入り／有料は透かしなし＋表彰カード）、決済、削除したコンペの扱いの見直し。
- 確認できていないこと：Edge Functionの402は、サンドボックスから呼べず、実機未確認。

