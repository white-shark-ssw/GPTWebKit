# DEV-conversation-recognition

## Status

**Active**

- **Work ID**: `DEV-conversation-recognition`
- **Routing aliases / keywords**: `优化会话识别 / 会话识别 / 当前会话识别 / 会话切换识别 / conversation recognition`
- **Task**: 优化 ChatGPTEnhancer 对当前会话的识别与上下文更新，并保证导出、拉取、重载始终使用真实当前会话。
- **User intent / acceptance criteria**: 用户真机复现：从 A 会话切换到 B，会在 B 中点击“导出 MD 文档”，重命名输入框仍显示 A 会话标题。必须判断是仅标题识别错误，还是 conversation ID / 真实功能目标也仍指向 A；同时检查“拉取最新消息”和“重载当前会话”是否存在同类错误。修复后 A→B 切换时，导出标题与导出数据、拉取目标、重载目标都必须对应 B。
- **Baseline**: current enhancer track `feat/chatgpt-enhancer-v0.1` at `c9602a0ccf3060f053f13b121b5c0c5bdf14aaf8`; current candidate `0.1.0-alpha39-reload-stability`; alpha39 runtime/manual result remains `Unknown / Unverified` except this user-reported stale-session reproduction.
- **Working branch / PR / head commit**: `feat/conversation-recognition`; PR `Not created`; initial head `c9602a0ccf3060f053f13b121b5c0c5bdf14aaf8`.
- **Candidate identity**: `Not allocated`.
- **Evidence**: `CEConversationContext` is the documented active-conversation authority. `CEContextResolver.resolveNow` immediately returns whenever `conversationID` is already non-empty, so it does not re-evaluate an established context after A→B navigation. `CEFloatingButtonController.currentRecord` takes the current `conversationID`, then may derive a visible title and write that title back to the catalog under that same ID; therefore if the ID is stale A while UI is B, it can associate B's visible title with A. Floating-tool export passes that record to `CEFeatures exportRecord`. `CEFeatures pullLatestCurrentConversation` reads `CEConversationContext.conversationID` directly. Alpha39 manual reload override also copies `CEConversationContext.conversationID` directly and routes/reloads exactly that ID. Thus stale identity is not a filename-only risk: all three current-conversation actions can target the wrong conversation if context did not switch.
- **Files / modules in scope**: `ChatGPTEnhancer/Sources/Core/CEContextResolver.mm`, `CECore.*`, `Network/CENetworkObserver.*`, `Storage/CECatalog.*`, `UI/CEEnhancerUI.mm`, `Features/CEFeatures.mm`, `Features/CEManualConversationReload.mm`; diagnostics only if needed to verify identity evidence.
- **State owner / shared dependencies**: `CEConversationContext` is the single active-conversation authority; `CENetworkObserver` owns passive official-network observation; `CECatalog` owns conversation catalog/title mapping; `CEAPIClient` is the sole enhancer-originated request path; `CEEnhancerUI` owns UI integration; `CEBootstrap` owns startup.
- **Frozen / do-not-touch**: no module is marked Frozen. Preserve single-constructor architecture, memory-only sensitive request context, sole `CEConversationContext` authority, sole network/UI owners, and exact-current-conversation-only manual reload contract. Do not patch only filename/title while leaving stale ID possible.
- **Parallel conflicts checked against**: no other Active development checkpoint existed in `docs/project/current/dev/` at task creation; no branch/candidate collision found.
- **Completed**: governance routing; current project docs read; real enhancer baseline/head verified; dedicated working branch created; user reproduction recorded; export/pull/reload entry paths inspected enough to establish shared stale-context risk.
- **Validation state**: investigation only; no product code changed; no candidate allocated; no CI/artifact/runtime validation for this task yet.
- **Pending**: inspect all active-conversation writes/clears and classify which network requests are safe evidence of active-view identity versus background/history/prefetch; inspect pull implementation; determine smallest owner-level fix that updates/invalidates context on real navigation without allowing background request pollution.
- **Next exact action**: map every `CEConversationContext` writer in active source, especially `CENetworkObserver` and UI touch/navigation paths, then implement an evidence-ranked current-session update policy and remove any title write that can mutate a record under an unverified stale ID.
- **Rejected / do-not-repeat**: do not add a second conversation state owner; do not guess private Swift class names; do not add speculative polling/retry/fallback; do not treat visible title alone as proof of conversation identity; do not merely change the export input-field title.
- **Open questions / risks**: official app may issue background conversation requests, so blindly treating every request containing a conversation ID as active could overwrite correct context. Existing left-edge delayed clear and visible-title matching are heuristic and may not reliably fire on every A→B navigation. Need source/runtime evidence before broadening request matching.
