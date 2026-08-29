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
- Status: **Code written → CI passed → Artifact produced. Runtime/manual pending.**

## Runtime evidence driving alpha58

The user reports after extended real-device use that the existing Sync and Reload are very likely to fail. This supersedes alpha57's route-proof correction as the next production direction.

Current source explains why this is plausible:

- Sync performs an enhancer-owned exact-ID GET, analyzes the returned conversation, then hands off to the same manual Reload implementation.
- Manual Reload opens the exact same conversation through a custom `com.openai.chat://chatgpt.com/c/<id>` route and observes request/UI evidence; it does not call a proven official host refresh/state-consumption owner.
- Therefore a successful enhancer GET can prove server data exists while still failing to update the host UI.

The user proposed tracing the official request/response path used when the App opens an already-finished conversation and basing the next implementation on that real path. Alpha58 implements only the evidence collection needed to test that hypothesis.

## Alpha58 scope

While the existing user-started `会话识别记录` is active, `CENetworkObserver` now adds sanitized correlation for relevant `conversation/init`, `conversation/prepare`, and exact detail traffic:

- request stage, exact conversation ID, request top-level JSON key names only;
- per-process opaque NSURLSession/task tokens and bounded public class/state/source information;
- response status, size and MIME type;
- successful detail-response structural summary (`current_node`, mapping count, latest message ID/role/status/end_turn, timestamps/content type) without message contents;
- public completion-handler versus session-delegate completion capture markers where observable.

No production Sync/Reload behavior changes in alpha58. No raw request body/header/template, Authorization, Cookie, account ID or message text is persisted.

## Current Sync/Reload behavior

- `CEConversationContext` remains the sole active conversation identity authority.
- `同步最新消息` still uses the frozen exact ID and one guarded enhancer GET. HTTP 429 remains terminal for that request; no burst retry.
- If the fetched server conversation is still generating, Sync does not force page refresh.
- If the server result is finished, current Sync still calls the existing exact-current manual Reload path; alpha58 does not claim this path is reliable.
- Server GET/init/prepare/detail or custom-route acceptance alone is not visible synchronization.
- Do not implement raw request replay until runtime evidence proves which official host path consumes the response and updates UI.

## Prior alpha56/57 evidence retained

- Alpha56 trace `62313B1B-56B2-4F4C-A1B3-A658FDE8067D` showed one visible refresh with active attached nav replacement `nav-1 → nav-2` and exact same-ID init/prepare/detail.
- Alpha57 corrected the UI rebuild detector to accept active attached navigation-controller replacement as ephemeral UI proof when exact request delivery is also present.
- Alpha57 reached **Code written → CI passed → Artifact produced** but later broad user runtime testing rejected route-based Sync/Reload as sufficiently reliable.

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

Install alpha58 and record one controlled comparison:

1. Start `会话识别记录` before opening the target.
2. Use the official ChatGPT UI/sidebar to enter an already-finished conversation and wait until the latest answer is fully visible.
3. Press `同步最新消息` once and wait for its final status.
4. Press `重载` once and wait for its final status.
5. Finish/export the trace.

Compare official-entry `NET-REENTRY-*` transport/response structure against Sync/Reload before changing production refresh behavior.

## Evidence rule

Always distinguish Code written, Static/local checks passed, CI passed, Artifact produced, Runtime/manual/real-device tested, and Stable/Frozen.