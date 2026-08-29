# Project State

_Last updated: 2026-08-30._

## Current accepted baseline

- **Stable/Frozen runtime baseline**: `Unknown / Unverified`.
- Product base `feat/chatgpt-enhancer-v0.1` remains `c9602a0ccf3060f053f13b121b5c0c5bdf14aaf8`.
- `feat/conversation-recognition` remains the newest recognition branch. No recognition candidate is Stable/Frozen.

## Current development candidate

### ChatGPTEnhancer `0.1.0-alpha60-runtime-image-map`

- Work ID `DEV-conversation-recognition`; branch `feat/conversation-recognition`; Draft PR #2 → `feat/chatgpt-enhancer-v0.1`.
- Build/test source `8d371801c764b4a8da95e44e74c0a99fa3a0b126`; CI bookkeeping `192ad870a1fb8417d0616ff941966ad4049ab7f5`; post-CI cleanup/current PR head `c0431e83d29299d8da22d2e8089e392a0936511d`.
- CI passed: Actions `33274357066`, job `99158361042`.
- Artifacts: package id `9721043070`, Actions digest `sha256:a08284ace0c5ae8bd381ec5515d4ffc5cfda39b02a3186a4806aa29a4283ff03`; dylib artifact id `9721043178`, Actions digest `sha256:297f910d780a19e3f0212cb1c6fb9cb006144847c281f2e0ee406bf0f9c82338`.
- Extracted dylib: Mach-O 64-bit arm64, 634272 bytes, sha256 `1b227794c9133f022a26bc3a59aa60091984a06b7a31545f0fc840ce10ef0e95`.
- Status: **Code written → CI passed → Artifact produced → Runtime/manual partially tested.**
- Compare build source → cleanup head changes only `.github/latest-enhancer-run-id` and removal of the temporary recognition-branch CI trigger; product source is unchanged.

## Alpha60 runtime result — trace FE491226-23C8-4F76-8D4E-230A1840D930

The App `1.2026.202` test closes two diagnostic dead ends while preserving the existing Sync/Reload failure evidence:

- Official finished-conversation entry again emitted exact `conversation/init → f/conversation/prepare → conversation/<id>` on `session-1`; this run observed init → prepare in ~196 ms and prepare → detail in ~4 ms.
- Alpha60 enumerated 4991 runtime classes inside the ChatGPT app bundle and surfaced conversation-related Swift types such as `Conversations.DefaultConversationSummaryHandoffService`, `DefaultConversationBranchingService`, `ConversationsInterface.ConversationCoordinatorError.PendingCompletionTurn`, and `ConversationFinalStream` state/storage/recovery types.
- Those relevant Swift classes exposed no Objective-C selectors in the bounded runtime inventory. Independent IMP-base mapping found `mainIMPClasses=0` / `mainIMPMethods=0`; every old reference returned `no-main-objc-method`. Current evidence therefore rejects further private Objective-C selector guessing for this state-transition owner.
- Reconstructing old textual `ChatGPT + offset` frames as `_dyld_get_image_header(0) + offset` is also rejected. One frame textually recorded as `ChatGPT + 48186293` resolved by that arithmetic into `LiveKitWebRTC`; the remaining references were unresolved. Sanitized textual `+ offset` is not a reliable executable-address recipe in this injected runtime.
- An exact prepare occurred while the context menu controller was active, 114 ms before Reload action capture. It cannot be attributed to Reload and further demonstrates that prepare traffic is not a visible-refresh signal by itself.
- Reload then opened the exact route and emitted a same-ID detail GET ~34 ms later, with no exact init and no Reload-attributable prepare before completion. The same attached `nav-1` remained throughout all verification polls and Reload correctly failed `requestObserved=YES / uiRebuildObserved=NO`.
- Combined with alpha59, failed route shapes may be detail-only or detail→prepare, but the stable missing boundary is still the official host transition that precedes exact init.

## Current Sync/Reload interpretation

- `同步最新消息` still performs an enhancer-owned exact-ID GET and then hands off to current manual Reload when server state is finished.
- Successful server fetch remains retrieval evidence only; it does not prove visible synchronization.
- Same-current route delivery, detail delivery and prepare delivery are insufficient without host state/UI change.
- Do not replay init/prepare/detail merely because official entry emits them. The missing boundary remains the host-owned state transition / response consumer.
- Do not infer an Objective-C refresh owner from semantic Swift class names, and do not rebuild actual addresses from sanitized textual `ChatGPT + offset` values.

## Existing architecture / contracts

1. `CEBootstrap` — sole startup owner.
2. `CECore` / `CEConversationContext` — sole active-conversation identity authority.
3. `CENetworkObserver` — passive host-network observation; only validated exact `POST /backend-api/conversation/init` body ID may promote foreground identity.
4. `CEAPIClient` — sole enhancer-originated ChatGPT request owner; HTTP 429 is terminal for the current enhancer request.
5. `CECatalog` — conversation catalog/title state.
6. `CEEnhancerUI` — current exact-ID menu integration and row-scoped sidebar Rename/Export.
7. `CEConversationUIReloadEvidence` — ephemeral UI refresh/rebuild proof only; not identity/refresh authority.
8. `CEConversationIdentityTrace` / `CEHostRuntimeOwnerTrace` / navigation/network diagnostics — optional sanitized evidence only.

## Parallel task

- `DEV-conversation-usage` remains Active on `feat/conversation-usage`, candidate alpha43, PR #3 stacked on `feat/conversation-recognition`.
- Alpha60 does not modify percentage-owned UI/model source or its checkpoint. That task must reconcile the advancing recognition base before its own next final validation.

## Next evidence

If continuing recognition diagnosis, capture actual `NSThread.callStackReturnAddresses` at the event site and resolve each bounded frame with `dladdr` **before** sanitization. Persist only image name, symbol name, frame order and symbol-relative delta; raw addresses stay memory-only. Compare actual resolved official `init/prepare/detail` frames against the failed Reload detail path. If symbols remain stripped, use resolved image/module identity plus Swift runtime metadata for the next narrow diagnostic rather than returning to Objective-C selector guesses or textual `+ offset` arithmetic.

## Evidence rule

Always distinguish Code written, Static/local checks passed, CI passed, Artifact produced, Runtime/manual/real-device tested, and Stable/Frozen.