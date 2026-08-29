# Project State

_Last updated: 2026-08-30._

## Current accepted baseline

- **Stable/Frozen runtime baseline**: `Unknown / Unverified`.
- Product base `feat/chatgpt-enhancer-v0.1` remains `c9602a0ccf3060f053f13b121b5c0c5bdf14aaf8`.
- `feat/conversation-recognition` is the newest recognition branch. No recognition candidate is Stable/Frozen.

## Current development candidate

### ChatGPTEnhancer `0.1.0-alpha59-runtime-owner-map`

- Work ID `DEV-conversation-recognition`; branch `feat/conversation-recognition`; Draft PR #2 → `feat/chatgpt-enhancer-v0.1`.
- Build/test source `76f83fcf6a53bebd4c8067b2bde44a4edb4a0dfc`; CI bookkeeping `21d7e92443052cec1afc8aaa1576b7d773e56138`; post-CI cleanup/current PR head `e86b8670fb8de4888e76fdc41f84f4e226275136`.
- CI passed: Actions `33273831978`, job `99156971862`.
- Artifacts: package id `9720892970`, Actions digest `sha256:41838f67c629f3cf50e3d18260b304c65b57cec3dcddd1ad6df232256d471709`; dylib artifact id `9720893086`, Actions digest `sha256:3907409a25eaaa40c8dfe954bc7dc53aa4cad802ad4fe4a801d7dca7fb5d4044`.
- Extracted dylib: Mach-O 64-bit arm64, 633984 bytes, sha256 `a84a06d9ec29f2e9bdb84d7e35438939f9303d94bf01e969264ef26c0e9aa801`.
- Status: **Code written → CI passed → Artifact produced. Runtime/manual pending.**

## Alpha59 diagnostic purpose

Alpha58 runtime evidence showed that normal official entry and failed Reload can use the same low-level `__NSURLSessionLocal` transport while only the official path updates host state/UI, and the successful detail-response consumer is not visible through the currently hooked public Objective-C completion/delegate surfaces.

Alpha59 therefore changes diagnostics only:

- `CEHostRuntimeOwnerTrace` is started from the existing single `CEBootstrap` startup owner.
- When the user-started identity trace is active and an exact current conversation is established, it enumerates Objective-C classes/methods belonging to the ChatGPT main executable without invoking them.
- For exact App version `1.2026.202`, it maps alpha58's already-observed `ChatGPT + offset` frames to nearest main-image Objective-C method IMP offsets and records signed delta / `near64k` evidence.
- It also records a bounded semantic inventory of conversation/chat/thread/message/history/route/sidebar/navigation-related runtime classes and selectors.
- On a different ChatGPT app version, the numeric alpha58 offset mapping is explicitly non-comparable and is not applied.
- No private selector is called or swizzled. No request replay/navigation mutation is added. No raw pointer, request/response body, message content, Authorization, Cookie, account ID or request template is persisted.

## Alpha58 runtime result retained — trace E74DA953-6BB5-4A92-87DF-474142BD37C7

- Normal official entry into a finished conversation emitted exact `conversation/init → f/conversation/prepare → conversation/<id>` detail GET.
- Those official requests were all observed on the same opaque `session-1` (`__NSURLSessionLocal`) transport.
- Current manual Reload did **not** reproduce that sequence. Each tested Reload delivered only one exact detail GET on the same `session-1` and then failed to rebuild the UI across the full verification window.
- Therefore “re-send the detail GET” is runtime-rejected as a sufficient Reload mechanism.
- Alpha58 did not observe a completion-handler/session-delegate response-consumption callback for the successful official detail request even though its task resume was visible. The successful host response consumer/state-update path remains Unknown / Unverified.
- Same low-level NSURLSession ownership is not enough to establish UI semantics; official navigation/state transition remains materially different from failed Reload.

## Current Sync/Reload interpretation

- `同步最新消息` still performs an enhancer-owned exact-ID GET and then hands off to current manual Reload when the server result is finished.
- Because current Reload can deliver detail without a UI rebuild, successful Sync server fetch still does not imply visible synchronization.
- Do not manually replay init/prepare/detail merely because normal entry emits them. Network sequence is evidence of the official state transition, not yet a proven callable refresh recipe.
- Do not invoke a runtime selector merely because alpha59 reports it near a stack offset. Proximity is candidate-owner evidence only.

## Existing architecture / contracts

1. `CEBootstrap` — sole startup owner.
2. `CECore` / `CEConversationContext` — sole active-conversation identity authority.
3. `CENetworkObserver` — passive host-network observation; only validated exact `POST /backend-api/conversation/init` body ID may promote foreground identity.
4. `CEAPIClient` — sole enhancer-originated ChatGPT request owner; HTTP 429 is terminal for the current enhancer request.
5. `CECatalog` — conversation catalog/title state.
6. `CEEnhancerUI` — current exact-ID menu integration and row-scoped sidebar Rename/Export.
7. `CEConversationUIReloadEvidence` — ephemeral UI refresh/rebuild proof only; it is not identity or refresh authority.
8. `CEConversationIdentityTrace` / `CEHostRuntimeOwnerTrace` / navigation/network diagnostics — optional sanitized runtime evidence, never identity or refresh authority.

## Parallel task

- `DEV-conversation-usage` remains Active on `feat/conversation-usage`, candidate alpha43, PR #3 stacked on `feat/conversation-recognition`.
- Alpha59 does not modify percentage-owned UI/model source or its checkpoint. Because the stacked base advanced, that task must reconcile the new recognition head before its own next final validation.

## Next evidence

Use ChatGPT App `1.2026.202` and the exact alpha59 artifact. Start `会话识别记录` from Home or another conversation, enter one already-finished target via normal official UI, wait until fully rendered, press Reload exactly once and wait for its final status, then export the trace. Compare `RUNTIME-OWNER*` records against official navigation/refresh frames and the failed Reload path.

## Evidence rule

Always distinguish Code written, Static/local checks passed, CI passed, Artifact produced, Runtime/manual/real-device tested, and Stable/Frozen.