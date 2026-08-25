# DEV-conversation-recognition

## Status

**Active**

- **Work ID**: `DEV-conversation-recognition`
- **Routing aliases / keywords**: `优化会话识别 / 会话识别 / 当前会话识别 / conversation recognition`
- **Task**: 优化 ChatGPTEnhancer 对当前会话的识别与上下文更新。
- **User intent / acceptance criteria**: 提高当前会话识别的准确性、及时性与稳定性；后续具体运行时验收以用户实机反馈为准。
- **Baseline**: current enhancer track `feat/chatgpt-enhancer-v0.1` at `c9602a0ccf3060f053f13b121b5c0c5bdf14aaf8`; current candidate `0.1.0-alpha39-reload-stability`; alpha39 runtime/manual result remains `Unknown / Unverified`.
- **Working branch / PR / head commit**: `feat/conversation-recognition`; PR `Not created`; initial head `c9602a0ccf3060f053f13b121b5c0c5bdf14aaf8`.
- **Candidate identity**: `Not allocated`.
- **Evidence**: `CEConversationContext` is the documented active-conversation authority. `CEContextResolver.mm` currently learns IDs from relevant NSURLSessionTask URLs and otherwise scans visible UIKit strings/titles once per second only while no conversation ID is set. It also currently declares its own constructor despite the repository architecture declaring `CEBootstrap` the single constructor/startup owner; this inconsistency must be resolved from source before product changes.
- **Files / modules in scope**: `ChatGPTEnhancer/Sources/Core/CEContextResolver.mm`, `CECore.*`; likely `Network/CENetworkObserver.*`, `Bootstrap/CEBootstrap.mm`, and diagnostics only if source evidence shows they participate in active-conversation identity.
- **State owner / shared dependencies**: `CEConversationContext` is the single active-conversation authority; `CENetworkObserver` owns passive official-network observation; `CECatalog` owns conversation catalog/title mapping; `CEBootstrap` owns startup.
- **Frozen / do-not-touch**: no module is marked Frozen. Preserve single-constructor architecture, memory-only sensitive request context, sole `CEConversationContext` authority, and sole network/UI owners.
- **Parallel conflicts checked against**: no other Active development checkpoint existed in `docs/project/current/dev/` at task creation; no branch/candidate collision found.
- **Completed**: governance routing; current project docs read; real enhancer baseline/head verified; current resolver/source owner inspected; dedicated working branch created.
- **Validation state**: investigation only; no product code changed; no candidate allocated; no CI/artifact/runtime evidence for this task yet.
- **Pending**: inspect all active-conversation write/clear call sites and network evidence paths; determine concrete misidentification/staleness failure modes; implement the smallest owner-level fix; validate build and then produce a unique test candidate only when needed.
- **Next exact action**: enumerate every `setConversationID`, `updateTitle`, and `clear` call on the enhancer baseline and inspect `CENetworkObserver`/diagnostics to map how current conversation state can become stale or incorrect.
- **Rejected / do-not-repeat**: do not add a second conversation state owner; do not guess private Swift class names; do not add speculative polling/retry/fallback before identifying the concrete failure mode.
- **Open questions / risks**: current `CEContextResolver` has a separate constructor inconsistent with documented single-bootstrap architecture; visible-title matching may be ambiguous; the early-return when a conversation ID already exists may allow stale context across navigation. These are source-level hypotheses pending call-site/runtime evidence, not yet accepted bugs.
