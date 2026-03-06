# 可用智能體清單

## site-analyst（網站分析師）
- 職責：分析目標 URL 的網站類型、是否需要登入、建議抓取方式
- 何時呼叫：收到新的書本 URL，抓取前必須先呼叫
- 通訊方式：sessions_send（同步，需等回覆）

## auth-agent（登入管家）
- 職責：處理 Kobo Google OAuth 登入，管理 session cookie
- 何時呼叫：site-analyst 回報 login_required: true
- 通訊方式：sessions_send（同步，等登入完成）

## book-fetcher（書本搬運工）
- 職責：使用 session cookie 抓取 Kobo 電子書章節
- 何時呼叫：auth-agent 確認 session 有效後
- 通訊方式：sessions_spawn（非同步，可並行多本）

## summarizer（知識提煉師）
- 職責：將原始章節內容用 Claude API 生成學習摘要
- 何時呼叫：book-fetcher 完成所有章節後
- 通訊方式：sessions_spawn（非同步）

## publisher（網站發布師）
- 職責：整合摘要 MD，生成並發布 MkDocs 學習網站
- 何時呼叫：summarizer 完成摘要後
- 通訊方式：sessions_spawn（非同步）

---

## 循環防止規則
- 不把任務傳回給發起任務的智能體
- 最大 sessions_spawn 深度：2 層
- 智能體互傳訊息最多 5 來回（maxPingPongTurns: 5）
