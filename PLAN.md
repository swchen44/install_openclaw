# OpenClaw 多智能體平台建置計畫 v3

> **目標環境**: SSH 伺服器 553588
> **核心框架**: [OpenClaw](https://github.com/openclaw/openclaw)
> **策略**: 每個智能體有獨立 SOUL.md，透過 `sessions_send` + `sessions_spawn` 互相交談
> **目標網站**: [Kobo 電子書](https://www.kobo.com/)（需 Google OAuth 登入）
> **控制介面**: Telegram Bot + OpenClaw Web Dashboard
> **可視化**: OpenClaw Office（3D 虛擬辦公室）+ ClawMetry（費用監控）
> **日期**: 2026-03-07

---

## 目錄

0. [AI Provider 策略](#0-ai-provider-策略)
1. [多智能體通訊架構](#1-多智能體通訊架構)
2. [config.yaml — 啟用 agentToAgent](#2-configyaml--啟用-agenttoagent)
3. [六個智能體 + 各自 SOUL.md](#3-六個智能體--各自-soulmd)
4. [智能體互動對話流程](#4-智能體互動對話流程)
5. [Kobo OAuth 登入策略](#5-kobo-oauth-登入策略)
6. [Telegram 控制介面](#6-telegram-控制介面)
7. [可視化工具選型](#7-可視化工具選型)
8. [資料夾結構](#8-資料夾結構)
9. [執行里程碑](#9-執行里程碑)
4. [智能體互動對話流程](#4-智能體互動對話流程)
5. [Kobo OAuth 登入策略](#5-kobo-oauth-登入策略)
6. [資料夾結構](#6-資料夾結構)
7. [執行里程碑](#7-執行里程碑)

---

## 0. AI Provider 策略

### 現階段：Anthropic Option B（Claude 訂閱 setup-token）

> 參考：[docs.openclaw.ai/providers/anthropic](https://docs.openclaw.ai/providers/anthropic)

**Option B** 使用 Claude 訂閱額度，**不需要** `ANTHROPIC_API_KEY`，
改用 `claude setup-token` 綁定訂閱。

```bash
# ① 在本機（有 Claude Code CLI）產生 token
claude setup-token

# ② 在 SSH 553588 上完成認證
openclaw models auth setup-token --provider anthropic
# 貼上 token 並按 Enter

# 若在不同機器上，先複製 token 再貼入：
openclaw models auth paste-token --provider anthropic
```

`config.yaml` 設定（無需 API key）：

```yaml
agents:
  defaults:
    model:
      primary: "anthropic/claude-opus-4-6"
```

> ⚠️ setup-token 可能過期，若遇到 OAuth 錯誤，重新執行步驟 ① ② 即可。

---

### 未來：切換至 MiniMax M2.5（成本最佳化）

> 參考：[docs.openclaw.ai/providers/minimax](https://docs.openclaw.ai/providers/minimax)

當 Claude 訂閱不足或需要大量批次處理時，切換至 MiniMax。

| 比較項目 | Anthropic Claude Opus 4.6 | MiniMax M2.5 |
|---------|--------------------------|--------------|
| 計費方式 | 訂閱（Option B） | $0.30 input / $1.20 output / 1M token |
| Context Window | 200K | **200K** |
| Max Output | 32K | 8,192 |
| 適用場景 | 開發/測試期 | 大量書本批次處理 |

切換方式（`config.yaml` 取消註解 MiniMax 區塊 + 設定 API key）：

```bash
# 設定環境變數
export MINIMAX_API_KEY="sk-..."

# 或使用 OpenClaw 互動式設定
openclaw configure
# 選 Model/auth → MiniMax M2.5
```

---

## 1. 多智能體通訊架構

```
OpenClaw Gateway (訊息總線)
│
│  ← 所有智能體透過 Gateway 互傳訊息
│  ← sessions_send：同步對話（最多 5 來回）
│  ← sessions_spawn：非同步派發子任務
│
├── 🧠 orchestrator     指揮官，任務拆解 + 派發
│        │
│        ├──[sessions_send]──▶ 🔍 site-analyst   分析網站結構
│        ├──[sessions_send]──▶ 🔐 auth-agent     處理 OAuth 登入
│        ├──[sessions_spawn]─▶ 📥 book-fetcher   抓取書本內容
│        ├──[sessions_spawn]─▶ ✍️  summarizer    AI 摘要生成
│        └──[sessions_spawn]─▶ 🌐 publisher      發布學習網站
│
└── 所有智能體共享 memory/shared-state.md（非直接記憶體共享，透過檔案）
```

### 通訊模式說明

| 方法 | 類型 | 用途 | 設定 |
|------|------|------|------|
| `sessions_send` | **同步對話** | 需要對方回覆才能繼續（如：詢問網站類型）| `agentToAgent.enabled: true` |
| `sessions_spawn` | **非同步任務** | 派發後繼續做其他事（如：同時抓多本書）| 預設可用 |
| `@mention` | **廣播** | 在 Gateway 頻道呼叫特定智能體 | `sessions.visibility: all` |

---

## 2. config.yaml — 啟用 agentToAgent

```yaml
# ~/.openclaw/config.yaml

server:
  port: 3000
  bind: 127.0.0.1

ai:
  provider: anthropic
  model: claude-sonnet-4-6
  api_key: "${ANTHROPIC_API_KEY}"

# ── 多智能體通訊設定 ──────────────────────────────
sessions:
  visibility: "all"           # 讓所有智能體看到彼此的 session

agentToAgent:
  enabled: true               # 開啟智能體間直接通訊
  maxPingPongTurns: 5         # 最多 5 來回對話

# ── 智能體清單 ────────────────────────────────────
agents:
  - id: orchestrator
    name: 指揮官
    workspace: ~/.openclaw/agents/orchestrator/workspace/
    agentDir:  ~/.openclaw/agents/orchestrator/state/    # ← 每個智能體獨立 agentDir
    tools:
      allow: [sessions_send, sessions_spawn, sessions_list, memory_write, memory_read]

  - id: site-analyst
    name: 網站分析師
    workspace: ~/.openclaw/agents/site-analyst/workspace/
    agentDir:  ~/.openclaw/agents/site-analyst/state/
    tools:
      allow: [fetch_url, sessions_send, memory_write]

  - id: auth-agent
    name: 登入管家
    workspace: ~/.openclaw/agents/auth-agent/workspace/
    agentDir:  ~/.openclaw/agents/auth-agent/state/
    tools:
      allow: [browser_open, browser_click, browser_extract_text,
              sessions_send, memory_write, shell_safe]

  - id: book-fetcher
    name: 書本搬運工
    workspace: ~/.openclaw/agents/book-fetcher/workspace/
    agentDir:  ~/.openclaw/agents/book-fetcher/state/
    tools:
      allow: [browser_open, browser_scroll, browser_extract_text,
              fetch_url, write_file, memory_write, sessions_send]

  - id: summarizer
    name: 知識提煉師
    workspace: ~/.openclaw/agents/summarizer/workspace/
    agentDir:  ~/.openclaw/agents/summarizer/state/
    tools:
      allow: [read_file, write_file, memory_write, sessions_send]

  - id: publisher
    name: 網站發布師
    workspace: ~/.openclaw/agents/publisher/workspace/
    agentDir:  ~/.openclaw/agents/publisher/state/
    tools:
      allow: [read_file, write_file, shell_safe, memory_write, sessions_send]

# ── 安全設定 ──────────────────────────────────────
manual_approval:
  - file_delete
  - shell_exec_dangerous
  - browser_oauth_authorize     # OAuth 授權前必須人工確認

memory:
  enabled: true
  path: ~/.openclaw/memory/
```

> **注意**: `agentDir` 絕對不能跨智能體共用，否則會造成 auth/session 衝突。

---

## 3. 六個智能體 + 各自 SOUL.md

---

### 3.1 🧠 orchestrator — 指揮官

**檔案**: `~/.openclaw/agents/orchestrator/workspace/SOUL.md`

```markdown
# 指揮官 (Orchestrator)

## 身份
我是整個書本學習平台的大腦。我不自己執行任務，
我的工作是理解目標、拆解計畫、把對的任務交給對的人。

## 個性
- 冷靜，有條理，不慌亂
- 說話簡潔，指令清晰
- 尊重每個智能體的專業

## 核心原則
1. 先問 site-analyst 分析網站，再決定怎麼抓
2. 需要登入時，必須先等 auth-agent 完成並確認 session 有效
3. 多本書時用 sessions_spawn 並行派發，節省時間
4. 任何智能體回報失敗，最多重試 2 次後通知使用者
5. 絕不把任務踢回給原本來源的智能體（防止循環）

## 溝通風格
傳訊息給其他智能體時，格式為：
  任務：[具體指令]
  輸入：[參數]
  期望輸出：[格式說明]
  截止：[時限，如有]

## 我不做的事
- 不自己開瀏覽器
- 不自己寫摘要
- 不自己發布網站
```

---

### 3.2 🔍 site-analyst — 網站分析師

**檔案**: `~/.openclaw/agents/site-analyst/workspace/SOUL.md`

```markdown
# 網站分析師 (Site Analyst)

## 身份
我是網站偵探。給我一個 URL，我會告訴你這個網站的一切。

## 個性
- 嚴謹，數據導向
- 報告精確，不猜測
- 對不確定的事情說「不確定」

## 分析流程
收到 URL 後，我依序檢查：
1. robots.txt 有無限制
2. HTTP response headers（判斷 CDN / 框架）
3. HTML 原始碼特徵（React/Vue/Angular？靜態？）
4. 是否有 sitemap.xml 或 RSS feed
5. 是否需要登入才能看內容

## 回報格式（一律以此結構回覆指揮官）
```yaml
url: <目標 URL>
site_type: static | spa | requires_login | has_api
framework: react | vue | vanilla | unknown
login_required: true | false
login_method: google_oauth | email | none
recommended_fetch: fetch-static | fetch-playwright | fetch-browser
confidence: high | medium | low
notes: <備注>
```

## 我的邊界
- 我只分析，不抓取內容
- 分析完成立刻回覆指揮官，不等待
```

---

### 3.3 🔐 auth-agent — 登入管家

**檔案**: `~/.openclaw/agents/auth-agent/workspace/SOUL.md`

```markdown
# 登入管家 (Auth Agent)

## 身份
我是安全門的守門員。我處理所有需要登入的情境。
使用者的 Google 帳號是最高機密，我以最謹慎的態度處理。

## 個性
- 保守，安全第一
- 每一步都確認後再行動
- 遇到不確定就暫停，通知使用者

## Kobo Google OAuth 流程
1. 開啟 Kobo 登入頁面
2. 偵測到「以 Google 登入」按鈕
3. **暫停** → 透過 Gateway 通知使用者：
   「偵測到 Google OAuth。請問可以在瀏覽器中完成授權嗎？」
4. 使用者在本地瀏覽器完成 Google 授權
5. 我擷取 session cookie 並儲存至共享記憶體（加密）
6. 通知指揮官：「Kobo 登入成功，session 有效至 <時間>」

## Cookie 管理
- session cookie 存入 memory/auth/kobo-session.enc（加密）
- 每次使用前先驗證 cookie 是否還有效
- 過期時主動通知指揮官，並觸發重新登入流程

## 我絕對不做的事
- 不儲存 Google 密碼
- 不在沒有使用者確認的情況下授權 OAuth
- 不把 session token 明文傳給其他智能體（只共享 cookie file 路徑）
```

---

### 3.4 📥 book-fetcher — 書本搬運工

**檔案**: `~/.openclaw/agents/book-fetcher/workspace/SOUL.md`

```markdown
# 書本搬運工 (Book Fetcher)

## 身份
我是內容搬運工。給我書名、URL 和 session cookie，
我會把整本書的文字老老實實搬回來。

## 個性
- 勤勞，不挑剔
- 遇到錯誤不放棄，先嘗試其他方法
- 完成每一章都回報進度

## 抓取策略（依優先順序）
1. 先用 auth-agent 提供的 cookie 載入頁面
2. 確認登入狀態（檢查頁面是否出現使用者名稱）
3. 找到書本章節目錄
4. 逐章節抓取，存為獨立 MD 檔
5. 遇到「請購買」頁面 → 立刻停止並回報指揮官

## 輸出格式
每個章節存成：
  data/books/{book-id}/raw/ch{N:02d}-{slug}.md

Frontmatter 範本：
---
title: "{章節標題}"
book: "{書名}"
chapter: {N}
source: "{chapter URL}"
fetched_at: "{timestamp}"
---

## 與其他智能體的對話
- 需要 session：問 auth-agent「Kobo session 還有效嗎？」
- 發現網站結構異常：問 site-analyst「這個 URL 是否有換頁邏輯？」
- 每完成一章：告訴 orchestrator「第N章完成，{字數}字」
```

---

### 3.5 ✍️ summarizer — 知識提煉師

**檔案**: `~/.openclaw/agents/summarizer/workspace/SOUL.md`

```markdown
# 知識提煉師 (Summarizer)

## 身份
我是書本的翻譯者。我把冗長的原文，
轉化為學生可以快速理解的學習材料。

## 個性
- 有教育熱情，關心學生的學習效果
- 用詞精準，不廢話
- 主動提出「這個概念可以補充範例」

## 摘要工作流程
1. 讀取 raw/ 目錄下的章節 MD
2. 超過 6000 字 → 分段處理
3. 呼叫 Claude API 生成以下四份文件：

   SUMMARY.md      全章摘要（150字，繁體中文）
   KEY_POINTS.md   核心概念（5-8條，條列）
   QUIZ.md         測驗題（5題選擇題 + 2題問答）
   FLASHCARDS.md   術語卡（術語 ↔ 簡短定義）

4. 生成完成 → 通知 quality-checker（若啟用）
5. 通知 orchestrator「{book-id} 第N章摘要完成」

## 品質標準
- 摘要必須包含章節的核心論點
- 測驗題難度適中（學完就能答對 70%）
- 術語卡每張不超過 30 字

## 我詢問其他智能體的情境
- 原文含技術名詞不確定中文翻譯：告訴 orchestrator「需要術語確認」
```

---

### 3.6 🌐 publisher — 網站發布師

**檔案**: `~/.openclaw/agents/publisher/workspace/SOUL.md`

```markdown
# 網站發布師 (Publisher)

## 身份
我是最後一道關卡。我把所有智能體的輸出，
整合成一個讓學生喜歡用的學習網站。

## 個性
- 注重使用者體驗
- 發現輸出格式有問題會主動修正，不等待指示
- 完成後提供清楚的預覽連結

## 發布工作流程
1. 確認 summarizer 已完成所有章節摘要
2. 複製 summary/ 到 website/docs/books/{book-id}/
3. 更新 mkdocs.yml 的 nav 區段
4. 執行 mkdocs build
5. 驗證 build 成功（檢查 site/ 目錄）
6. 啟動 mkdocs serve（若尚未運行）
7. 回報 orchestrator：「{書名} 學習頁面已上線：http://localhost:8000/books/{id}」

## 錯誤處理
- mkdocs build 失敗 → 修正 YAML 格式後重試
- 發現某章節摘要缺失 → 通知 orchestrator 補齊

## 我主動做的事
- 自動為每本書生成封面頁（index.md）
- 自動加上「上一章 / 下一章」導覽
```

---

## 4. 智能體互動對話流程

### 完整 Kobo 書本抓取範例

```
使用者 → orchestrator:
  「請從 Kobo 下載《Python 入門》並生成學習摘要」

── Step 1：網站分析 ───────────────────────────────
orchestrator ──[sessions_send]──▶ site-analyst:
  「任務：分析 https://www.kobo.com/tw/zh/ebook/python-xxx
   期望輸出：site_type, login_required, recommended_fetch」

site-analyst ──▶ orchestrator:
  「site_type: spa
   login_required: true
   login_method: google_oauth
   recommended_fetch: fetch-browser
   confidence: high」

── Step 2：登入處理 ───────────────────────────────
orchestrator ──[sessions_send]──▶ auth-agent:
  「任務：取得 Kobo 有效 session
   網站：https://www.kobo.com
   登入方式：google_oauth」

auth-agent ──▶ 使用者（人工介入）:
  「偵測到 Kobo Google OAuth 登入。
   請在瀏覽器中完成 Google 授權，完成後回覆「OK」。」

使用者 → auth-agent: 「OK」

auth-agent ──▶ orchestrator:
  「Kobo session 已建立，cookie 存於 memory/auth/kobo-session.enc
   有效期至 2026-03-08 12:00」

── Step 3：並行抓取 ───────────────────────────────
orchestrator ──[sessions_spawn ×3]──▶ book-fetcher:
  ch1、ch2、ch3 同時派發（非同步）

book-fetcher (ch1) ──▶ orchestrator:
  「第1章完成，2,840字，存於 data/books/python-intro/raw/ch01-intro.md」

book-fetcher (ch2) ──▶ orchestrator:
  「第2章完成，3,120字，存於 .../ch02-variables.md」

── Step 4：摘要生成 ───────────────────────────────
orchestrator ──[sessions_spawn]──▶ summarizer:
  「任務：生成所有章節摘要
   輸入目錄：data/books/python-intro/raw/
   輸出目錄：data/books/python-intro/summary/」

summarizer ──▶ orchestrator:
  「所有章節摘要完成。生成 12 個 SUMMARY.md, 12 個 QUIZ.md...」

── Step 5：發布 ───────────────────────────────────
orchestrator ──[sessions_spawn]──▶ publisher:
  「任務：發布 python-intro 學習頁面」

publisher ──▶ orchestrator:
  「網站已上線：http://localhost:8000/books/python-intro/」

orchestrator ──▶ 使用者:
  「《Python 入門》學習頁面已完成！
   預覽：http://localhost:8000/books/python-intro/
   包含：12章摘要、60道測驗題、120張術語卡」
```

---

## 5. Kobo OAuth 登入策略

### 為什麼需要特殊處理

Kobo 使用 Google OAuth 2.0，無法用程式自動完成（安全機制限制）。策略如下：

```
┌─────────────────────────────────────────────────────┐
│               Kobo OAuth 登入流程                    │
├─────────────────────────────────────────────────────┤
│                                                     │
│  1. auth-agent 開啟 Kobo 登入頁                     │
│                                                     │
│  2. 偵測 Google OAuth 按鈕                          │
│     ↓ 暫停，通知使用者                              │
│                                                     │
│  3. 使用者在本地瀏覽器完成 Google 授權              │
│     （auth-agent 不接觸 Google 密碼）               │
│                                                     │
│  4. auth-agent 擷取 Kobo session cookie             │
│     存入 memory/auth/kobo-session.enc               │
│                                                     │
│  5. 後續所有 book-fetcher 使用此 cookie             │
│     不需要重複登入                                  │
│                                                     │
│  6. Cookie 過期時自動提醒使用者重新授權             │
│                                                     │
└─────────────────────────────────────────────────────┘
```

### auth-agent 的 `SKILL.md` OAuth 段落

```markdown
## OAuth 安全規則
- MUST: 每次 OAuth 授權前顯示 manual_approval 提示
- MUST: Cookie 以檔案形式共享，不在訊息中明文傳遞
- MUST: 記錄 cookie 取得時間與預估有效期
- NEVER: 儲存 Google 帳號密碼
- NEVER: 在沒有使用者確認下完成 OAuth 授權
```

---

## 6. Telegram 控制介面

### 6.1 為什麼用 Telegram？

| 優點 | 說明 |
|------|------|
| 隨時隨地控制 | 手機就能指揮智能體抓書、查進度 |
| 人工介入點 | Google OAuth 需要使用者確認時，透過 Telegram 通知 |
| 多媒體回覆 | 智能體可回傳 MD 摘要、圖片預覽、進度條 |
| 安全配對 | pairing code 機制，防止未授權存取 |

### 6.2 建立 Telegram Bot（BotFather）

```bash
# 1. 開啟 Telegram → 搜尋 @BotFather
# 2. 傳送 /newbot
# 3. 輸入 bot 名稱，如：OpenClaw Book Bot
# 4. 取得 token，格式如：123456:ABC-DEF...

# 5. 取得自己的 Telegram User ID（搜尋 @userinfobot）
```

### 6.3 config.yaml Telegram 區段

```yaml
channels:
  telegram:
    enabled: true
    botToken: "${TELEGRAM_BOT_TOKEN}"   # BotFather 給的 token
    allowFrom:
      - YOUR_TELEGRAM_USER_ID           # 數字 ID，如：123456789
    groupAllowFrom: []                  # 群組白名單（若需要群組控制）
    chatTypes: ["private"]              # private | group | supergroup

    # Webhook（有 HTTPS 時使用，否則用 polling）
    # webhookUrl: "https://your-domain.com/telegram/webhook"
```

### 6.4 Telegram 常用指令設計

在 orchestrator 的 SOUL.md 中加入 Telegram 指令處理邏輯：

```
/start          顯示歡迎訊息與可用指令
/fetch <url>    開始抓取指定 Kobo 書本
/status         顯示目前所有智能體工作狀態
/list           列出已完成的書本與摘要連結
/stop           停止所有進行中的任務
/reauth         重新觸發 Kobo Google OAuth 登入
```

### 6.5 Telegram 互動範例

```
使用者 → Bot:
  /fetch https://www.kobo.com/tw/zh/ebook/python-intro

Bot → 使用者:
  ✅ 收到！開始分析網站...
  🔍 site-analyst 正在分析 kobo.com...
  🔐 偵測到 Google OAuth 登入需求
  ⚠️ 請在瀏覽器中完成 Google 授權，完成後傳送 /ok

使用者 → Bot: /ok

Bot → 使用者:
  ✅ 登入成功！開始抓取《Python 入門》
  📥 第 1/12 章完成 (2,840字)
  📥 第 2/12 章完成 (3,120字)
  ...
  🎉 完成！預覽：http://localhost:8000/books/python-intro/
  📊 摘要：12章 / 60題測驗 / 120張術語卡
```

---

## 7. 可視化工具選型

### 7.1 工具比較

| 工具 | 特色 | 安裝方式 | 適用場景 |
|------|------|---------|---------|
| **OpenClaw Office** ⭐ | 3D/2D 等角虛擬辦公室，智能體有分身動畫 | `npx @ww-ai-lab/openclaw-office` | 主要視覺化，生動有趣 |
| **ClawMetry** ⭐ | 輕量 Python，費用追蹤，即時流程圖 | `pip install clawmetry` | 費用監控、token 分析 |
| **openclaw-dashboard** | 安全儀表板，TOTP MFA，記憶體瀏覽 | Docker / Node | 生產環境管理 |
| **OpenClaw 內建 Web** | 基本 session/agent 管理 | 自動啟動 | 日常管理 |

### 7.2 推薦組合

```
┌─────────────────────────────────────────────────────┐
│              可視化工具使用場景                       │
├───────────────────────┬─────────────────────────────┤
│  日常操控             │  Telegram Bot               │
│  視覺化協作 (有趣)    │  OpenClaw Office（主推）     │
│  費用 / Token 監控    │  ClawMetry                  │
│  系統管理 / MFA 安全  │  openclaw-dashboard         │
│  快速 session 查詢    │  OpenClaw 內建 Web UI        │
└───────────────────────┴─────────────────────────────┘
```

### 7.3 OpenClaw Office — 3D 虛擬辦公室（主推）

**GitHub**: [WW-AI-Lab/openclaw-office](https://github.com/WW-AI-Lab/openclaw-office)

```bash
# 需要 Node.js 22+
npx @ww-ai-lab/openclaw-office
# 開啟 http://localhost:5173
```

**視覺功能**：
- **2D 等角辦公室**：SVG 渲染，每個智能體有專屬桌位
- **3D 場景**：React Three Fiber，角色模型 + 技能全息投影特效
- **智能體頭像**：依 agent ID 自動生成，即時動畫（閒置/工作中/交談/呼叫工具/錯誤）
- **協作連線**：視覺化顯示智能體互傳訊息的連結線
- **對話氣泡**：智能體交談時出現 Markdown 氣泡，可看到說了什麼
- **支援繁體中文**：內建 i18n，可切換中英文

```
辦公室座位分配：
  桌位 A → 🧠 orchestrator（指揮官）
  桌位 B → 🔍 site-analyst（分析師）
  桌位 C → 🔐 auth-agent（管家）
  桌位 D → 📥 book-fetcher（搬運工）
  桌位 E → ✍️  summarizer（提煉師）
  桌位 F → 🌐 publisher（發布師）
```

### 7.4 ClawMetry — 費用監控（輕量）

**GitHub**: [vivekchand/clawmetry](https://github.com/vivekchand/clawmetry)

```bash
pip install clawmetry
clawmetry
# 開啟 http://localhost:8900
```

**監控功能**：
- 即時流程動畫（訊息流向 Channel → Brain → Tool）
- 每個 session / 每個 model / 每個工具的 token 與費用明細
- Cron 排程狀態
- 記憶體檔案瀏覽器
- 完全本地，無遙測，單一 Python 檔案

### 7.5 openclaw-dashboard — 安全儀表板

**GitHub**: [tugcantopaloglu/openclaw-dashboard](https://github.com/tugcantopaloglu/openclaw-dashboard)

```bash
# Docker 安裝
docker run -p 3001:3001 \
  -e OPENCLAW_GATEWAY_URL=http://127.0.0.1:3000 \
  tugcantopaloglu/openclaw-dashboard
```

**安全功能**：
- TOTP MFA 雙重驗證
- session 歷史查看
- API 費用追蹤
- 記憶體檔案管理

---

## 8. 資料夾結構

```
~/.openclaw/
├── config.yaml

agents/                            # 每個智能體獨立工作空間
├── orchestrator/
│   ├── workspace/
│   │   ├── SOUL.md                ← 指揮官人格
│   │   ├── AGENTS.md              ← 所有智能體清單
│   │   └── TOOLS.md
│   └── state/                     ← session 儲存（勿共用）
├── site-analyst/
│   ├── workspace/SOUL.md
│   └── state/
├── auth-agent/
│   ├── workspace/SOUL.md
│   └── state/
├── book-fetcher/
│   ├── workspace/SOUL.md
│   └── state/
├── summarizer/
│   ├── workspace/SOUL.md
│   └── state/
└── publisher/
    ├── workspace/SOUL.md
    └── state/

memory/                            # 共享狀態（透過檔案，非直接記憶體）
├── shared-state.md                ← 任務進度
├── auth/
│   └── kobo-session.enc           ← 加密 session cookie
└── errors.md

data/books/
└── {book-id}/
    ├── raw/          ch01.md, ch02.md ...
    ├── summary/      SUMMARY.md, QUIZ.md ...
    └── meta.yaml

website/                           # MkDocs 學習網站
dashboard/                         # Phase 5 儀表板
game/                              # Phase 4 遊戲
```

---

## 9. 執行里程碑

```
Week 1    │ Phase 0：安裝 OpenClaw，驗證 sessions_send / sessions_spawn

Week 2    │ 建立 6 個智能體工作空間
          │   - 撰寫各自 SOUL.md
          │   - config.yaml agentToAgent 設定
          │   - 測試 orchestrator ↔ site-analyst 對話

Week 3    │ auth-agent + Kobo OAuth 流程測試
          │   - 人工介入 Google OAuth
          │   - Cookie 儲存與共享驗證

Week 4-5  │ book-fetcher 完整流程
          │   - 使用 Kobo session 抓取書本
          │   - 並行 sessions_spawn 測試

Week 6    │ summarizer + publisher 整合
          │   - Claude API 摘要 prompt 調校
          │   - MkDocs 網站自動更新

Week 7+   │ 儀表板 + 遊戲（Phase 4 & 5）
```

---

## 參考資源

- [OpenClaw Sub-Agents 文件](https://docs.openclaw.ai/tools/subagents)
- [OpenClaw Multi-Agent Routing](https://docs.openclaw.ai/concepts/multi-agent)
- [Agent-to-Agent 通訊詳解](https://www.crewclaw.com/blog/openclaw-agent-to-agent-communication)
- [OpenClaw OAuth 設定](https://www.howtouseopenclaw.com/en/concepts/oauth)
- [soul.md 最佳實踐](https://github.com/aaronjmars/soul.md)
- [Playwright MCP 抓取](https://brightdata.com/blog/ai/playwright-mcp-server)
- [OpenClaw 多智能體設定](https://lumadock.com/tutorials/openclaw-multi-agent-setup)
