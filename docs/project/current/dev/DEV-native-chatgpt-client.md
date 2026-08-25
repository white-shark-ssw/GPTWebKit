# DEV-native-chatgpt-client

## Status

**Active / Planning only**

- **Work ID**: `DEV-native-chatgpt-client`
- **Routing aliases / keywords**: `原生 ChatGPT 客户端 / iOS 原生客户端 / native chatgpt client / 新客户端规划`
- **Task**: 规划一个不再以 ChatGPT WebView 作为聊天 UI 的 iOS 原生客户端；可研究/复用 ChatGPT Web 或官方客户端真实通讯方式，但消息列表、输入、附件、导航和长会话渲染由 iOS 原生实现。
- **User intent / acceptance criteria**: 当前会话只做规划，不写产品代码。新项目应吸收旧 GPTWebKit Web 客户端的历史经验，重点避免长会话首次加载慢、滚动/输入卡顿、WebContent 后台恢复、网页 Sidebar 延迟、DOM/React 多 owner 等旧问题。聊天主 UI 目标为原生；登录是否保留一个独立 Web bootstrap 仍待真实认证链证据确认。
- **Baseline**: Planning branch `feat/native-chatgpt-client` created from repository `main` at `92e26ae5bd0dc6ee75cc7ea3aae628ee42d5c215`. This branch is for planning/checkpoint isolation only; it is not yet a product-code baseline for the new client.
- **Working branch / PR / head commit**: `feat/native-chatgpt-client`; no PR. No product code has been written. Checkpoint creation is the first planning-only branch change.
- **Candidate identity**: None. No build/version/test artifact allocated.
- **Parallel conflicts checked against**: Existing Active tasks `DEV-conversation-recognition` and `DEV-conversation-usage` belong to the `ChatGPTEnhancer` product line. This task does not modify their source/state owners/candidate identities. If implementation later reuses shared repository CI/project files, conflict preflight must be repeated before edits.
- **Historical WebView evidence consolidated**: Old Web client history includes `feat/initial-ios-shell` and `feat/0.2-native-recovery-exporter`; last located Web candidate packaging commit `5533f96a011f971e132c369becc945291ac2ee49` (`0.2.0-alpha28`). Repository then pivoted with `d4b7029baaface35651221b25b79574ce5a097fa` (`replace web client root with native exporter`) and `d2f47697e8848ba513705e1f34636782c2fd67eb` (`remove obsolete long conversation runtime`).
- **Planning artifact produced**: `ChatGPT_iOS_Native_Client_History_Pack_2026-08-25.zip` was generated in the ChatGPT session for transfer into the new repository. It contains an executive handoff, WebView timeline, problem/solution matrix, long-conversation lessons, lifecycle/auth/upload/sidebar/export lessons, native architecture handoff, do-not-repeat list, MVP acceptance checklist, repository/external evidence notes, raw WebView-era conversation extract, and user-runtime-feedback-only extract. The ZIP is a conversation artifact, not a repository build artifact.
- **Current architecture direction**: Native UIKit-centric transcript (`UICollectionView` preferred for the long-message path), native composer/attachments/navigation, one authoritative ConversationStore, a separate ChatGPT protocol/network layer, and Web only as a possible isolated authentication bootstrap if current auth evidence requires it.
- **Evidence rule**: Historical private endpoints/headers are research clues only. Before implementation, current official ChatGPT traffic must be re-observed and verified. Old CI/artifacts do not prove current protocol/runtime behavior.
- **Rejected / do-not-repeat**: no WebView chat UI as default architecture; no renewed DOM virtualization/placeholder stack; no broad MutationObserver/timer/watchdog accumulation; no Shadow WKWebView Rebase unless a new independent requirement proves it necessary; no UI-text conversation-ID guessing; no guessing private endpoints from old history; no raw auth persistence.
- **Next exact action**: User is opening a separate repository/project for the native client. Import/read the generated history ZIP there, initialize that repository under its own governance/baseline, then plan the first protocol-research/MVP slice. Do not start product implementation in this old repository unless the user explicitly reroutes back here.
