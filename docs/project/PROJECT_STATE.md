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
- Status: **Code written → CI passed → Artifact produced. Runtime/manual pending.**
- Compare build source → cleanup head changes only `.github/latest-enhancer-run-id` and removal of the temporary recognition-branch CI trigger; product source is unchanged.

## Alpha59 runtime result — trace 897A6818-776A-44FC-84BA-21E0501A6A9A

The controlled App `1.2026.202` test materially refines the Reload model:

- Normal official entry again emitted exact `conversation/init → f/conversation/prepare → conversation/<id>` on the same `__NSURLSessionLocal` session. Init preceded prepare by ~83 ms; detail followed prepare ~2 ms later.
- Alpha59's runtime-owner mapper emitted `hostClasses=0 hostMethods=0 semanticClasses=0`. This output is inconclusive because ownership was filtered by raw image-path string equality; equivalent `/var/...` and `/private/var/...` paths can fail that test.
- Same-current Reload opened the custom route and then emitted exact **detail first**, followed ~355 ms later by exact **prepare**, with **no exact init**.
- That `detail → prepare` sequence still produced no UI disappear/rebuild; all verification polls stayed on the same attached `nav-1`, and Reload correctly failed with `requestObserved=YES`, `uiRebuildObserved=NO`.
- Therefore the old simplified statement “failed Reload is detail-only” is superseded. The durable distinction is that successful official entry starts with exact init and rapidly runs `init → prepare → detail`; a failed same-current route can emit `detail → prepare` without init and still leave UI unchanged.
- **Prepare delivery is not Reload completion evidence.** Manually replaying prepare remains unjustified.
- No `NAV-MUTATION` appeared in this run; older UINavigationController mutation traces are not a universal recipe for current modern SwiftUI side-menu state transitions.

## Alpha60 diagnostic purpose

Alpha60 corrects alpha59's image-ownership blind spot without changing production behavior:

- canonicalizes main executable/class-image/App-bundle paths before ownership comparison;
- independently proves main-image Objective-C ownership with method IMP `dladdr(...).dli_fbase` rather than relying on path text;
- directly resolves the known App `1.2026.202` `ChatGPT + offset` addresses through `dladdr`, recording only image basename, bounded symbol name and symbol-start delta;
- emits a bounded inventory of conversation/chat/thread/message/history/route/sidebar/navigation-related runtime classes from images inside the ChatGPT App bundle;
- invokes/swizzles none of those discovered methods and originates no new host requests.

If alpha60 still reports no main-image ObjC IMPs and no direct symbol names after those two independent checks, that will be stronger evidence the relevant owner is pure Swift/non-ObjC rather than a reason to guess selectors.

## Current Sync/Reload interpretation

- `同步最新消息` still performs an enhancer-owned exact-ID GET and then hands off to current manual Reload when server state is finished.
- Successful server fetch remains retrieval evidence only; it does not prove visible synchronization.
- Same-current route delivery, detail delivery and prepare delivery are all insufficient without host state/UI change.
- Do not replay init/prepare/detail merely because official entry emits them. The missing boundary is still the host-owned state transition / response consumer.

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

Use the exact alpha60 artifact on ChatGPT App `1.2026.202`: start `会话识别记录` from Home or another conversation, enter one already-finished target through normal official UI, wait until rendered, press Reload exactly once, wait for the final result, then export the trace. Compare `RUNTIME-OWNER-DLADDR`, `RUNTIME-OWNER`, `RUNTIME-OWNER-REF`, `RUNTIME-OWNER-CLASS`, official `init → prepare → detail`, and failed Reload ordering.

## Evidence rule

Always distinguish Code written, Static/local checks passed, CI passed, Artifact produced, Runtime/manual/real-device tested, and Stable/Frozen.