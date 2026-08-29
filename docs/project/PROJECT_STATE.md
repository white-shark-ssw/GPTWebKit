# Project State

_Last updated: 2026-08-30._

## Current accepted baseline

- **Stable/Frozen runtime baseline**: `Unknown / Unverified`.
- Product base `feat/chatgpt-enhancer-v0.1` remains `c9602a0ccf3060f053f13b121b5c0c5bdf14aaf8`.
- `feat/conversation-recognition` is the newest recognition branch. No recognition candidate is Stable/Frozen.

## Current development candidate

### ChatGPTEnhancer `0.1.0-alpha58-reentry-network-trace`

- Work ID `DEV-conversation-recognition`; branch `feat/conversation-recognition`; Draft PR #2 → `feat/chatgpt-enhancer-v0.1`.
- Build/test source `c9f9c328386e63fd409421d74d7f18c091144ad2`; CI bookkeeping `00b1aa85cb8d02d9b4e9be300a3f3c5bfa2296a2`; post-CI cleanup head `c0fa017e6bda0a4d91701e687abae3c8d51d3304`.
- CI passed: Actions `33272953771`, job `99154630406`.
- Artifacts: package id `9720640754`, Actions digest `sha256:80dcb905eb95486208a9e0a3457050f15401c0d6ed2a2b85e0ca79f8434ac369`; dylib artifact id `9720641009`, Actions digest `sha256:99deeeb00bc1cdf2779fcc349ab604ae1ddff7a957ea1d5d911adea77dd6de7a`.
- Extracted dylib: Mach-O 64-bit arm64, 615248 bytes, sha256 `df6c3f0b7e41b3386769f9df35d10dcb57bee4fee7e8c22c5190192dfd80a061`.
- Status: **Code written → CI passed → Artifact produced → Runtime/manual partially tested.**

## Alpha58 runtime result — trace E74DA953-6BB5-4A92-87DF-474142BD37C7

The controlled small-conversation test materially narrows the problem:

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
- The next diagnostic target is the missing official response/state-consumption boundary, not another URL route variant.

## Existing architecture / contracts

1. `CEBootstrap` — sole startup owner.
2. `CECore` / `CEConversationContext` — sole active-conversation identity authority.
3. `CENetworkObserver` — passive host-network observation; only validated exact `POST /backend-api/conversation/init` body ID may promote foreground identity.
4. `CEAPIClient` — sole enhancer-originated ChatGPT request owner; HTTP 429 is terminal for the current enhancer request.
5. `CECatalog` — conversation catalog/title state.
6. `CEEnhancerUI` — current exact-ID menu integration and row-scoped sidebar Rename/Export.
7. `CEConversationUIReloadEvidence` — ephemeral UI refresh/rebuild proof only; it is not identity or refresh authority.
8. `CEConversationIdentityTrace` / navigation/network diagnostics — optional sanitized runtime evidence, never identity authority.

## Parallel task

- `DEV-conversation-usage` remains Active on `feat/conversation-usage`, candidate alpha43.
- Alpha58 does not modify percentage-owned source/checkpoint.

## Next evidence

Instrument only the official detail task/session completion and public Foundation response/lifecycle surfaces needed to locate the missing host consumer. Compare one official entry with one failed Reload. Do not originate new requests or mutate navigation for this diagnostic.

## Evidence rule

Always distinguish Code written, Static/local checks passed, CI passed, Artifact produced, Runtime/manual/real-device tested, and Stable/Frozen.