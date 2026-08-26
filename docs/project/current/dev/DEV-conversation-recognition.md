# DEV-conversation-recognition

## Status

**Active**

- **Work ID**: `DEV-conversation-recognition`
- **Routing aliases / keywords**: `优化会话识别 / 会话识别 / 当前会话识别 / 会话切换识别 / conversation recognition`
- **Task**: 优化 ChatGPTEnhancer 当前会话识别，保证导出、拉取、重载只作用于真实当前可见会话。项目顶部标题替换暂时降为次要问题，先彻底消除串会话。
- **Acceptance invariant**: **拉取、重载、当前会话导出绝不能操作非当前可见会话；无法唯一证明当前会话时必须拒绝操作，不能沿用旧 ID 或猜测。**
- **Baseline**: `feat/chatgpt-enhancer-v0.1` at `c9602a0ccf3060f053f13b121b5c0c5bdf14aaf8`, rechecked 2026-08-26 and unchanged.
- **Working branch / PR / head**: `feat/conversation-recognition`; Draft PR #2 → `feat/chatgpt-enhancer-v0.1`; current branch head `a4414cbdd5466cd7bb3d660f43039204dfb052dd` (post-CI workflow-trigger cleanup only). Alpha44 build/test source `668540cbabf300d08c929a1daa057ea4959f2f01`; CI bookkeeping `ec8642391f40ae28a7f3dce8ddec983826ba76db`.
- **Candidate**: `ENH-0.1.0-alpha44-current-conversation-guard` / `0.1.0-alpha44-current-conversation-guard`. Alpha43 belongs to parallel `DEV-conversation-usage` and was not reused.
- **Authoritative alpha42 runtime result — 2026-08-26**: after extended real-device use, user reports both “拉取最新消息” and “重载” still cross/wrong conversations. Project-header title replacement also had no visible effect. Alpha42 is rejected runtime evidence, not a baseline.
- **Root cause proven from source + runtime evidence**: alpha42 had two independent network-driven active-ID writers. `CENetworkObserver.observeRequest:` wrote any observed conversation request ID directly to `CEConversationContext`; that observer is invoked at task creation/resume/receive/completion. `CEContextResolver` separately swizzled `NSURLSessionTask.resume` and also wrote any relevant request ID into `CEConversationContext`. Therefore an official background/detail request for conversation A could overwrite foreground B. Pull then read that polluted ID directly; manual reload captured the polluted ID and its later safety checks only ensured it stayed equal to the already-wrong captured value.
- **Alpha44 code changes**:
  - `0f0ab6d...`: export `CERefreshVisibleConversationContext()` from Core.
  - `aa7bafa...`: remove the resolver's network-task `resume` identity probe; visible UIKit evidence is now the resolver proof path. Unique catalog-backed explicit ID wins; otherwise exactly one catalog-backed title match is required; ambiguous/no evidence returns nil.
  - `9704027...`: remove `CENetworkObserver` mutation of `CEConversationContext`; observer remains passive for templates/events/catalog/project IDs.
  - `053bdee...`: floating tools no longer fall back to stale global ID and re-verify the exact captured visible record immediately before Pull/Reload/Export.
  - `149be14...`: actual alpha39 reload override now starts only from `CERefreshVisibleConversationContext()`; no visible proof means cancel.
  - `8ad6a19...`: Pull Latest itself now starts only from `CERefreshVisibleConversationContext()`; no visible proof means cancel.
  - `87efdc6...`, `99e12bd...`, `a8ac72f...`, `668540c...`: synchronize alpha44 product/package/bootstrap/CI identity.
- **CI / artifact evidence**: GitHub Actions run `32937976994`, build job `98082904535` passed. Package artifact id `9595516821`, digest `sha256:c084a7e6bce60d4df0a7378ae351b75a2de0669d898fd5f9a019e504c791eb99`; dylib artifact id `9595517523`, digest `sha256:e36cfdd0571b9ee34fb629e58f066947b231602194c2a1301b17c5ab2a28c7a9`.
- **Validation state**: alpha44 = **Code written → CI passed → Artifact produced**. Runtime/manual/real-device is **Pending**. Do not claim the cross-conversation problem solved until repeated real-device switching/use passes.
- **Parallel conflict**: `DEV-conversation-usage` remains Active on `feat/conversation-usage`, alpha43, Draft PR #3 stacked on the rejected alpha42 recognition state. Once alpha44 (or successor) is runtime accepted, that percentage branch must be re-stacked/revalidated; this task does not modify its checkpoint.
- **Header title issue**: still open and intentionally deferred. Alpha42's header replacement produced no visible effect; do not spend further scope on it before the identity invariant is accepted on device.
- **Next exact action**: install alpha44 on device and stress-test repeated A↔B switching over time. For each B visit test Pull Latest, Reload and Export; verify all three either target B or explicitly refuse with “无法确认当前可见会话” — never A. Include longer idle/background activity before actions to reproduce the alpha42 pollution window. Only after this invariant passes resume the cosmetic project-header title task.
- **Rejected / do-not-repeat**: network request observation is not foreground identity; no second conversation authority; no private Swift class hard-coding; no arbitrary visible-title→old-ID mutation; no speculative retry/fallback/watchdog; no stale-ID fallback when visible proof fails; no claim that CI/artifact equals runtime success.
- **Open risks**: project chat may expose insufficient catalog-backed visible identity and therefore alpha44 may intentionally refuse operations more often. Duplicate titles/new uncatalogued conversations remain fail-closed until stronger real evidence exists. This is preferable to cross-conversation execution under the current acceptance invariant.
