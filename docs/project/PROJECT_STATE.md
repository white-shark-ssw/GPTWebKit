# Project State

_Last updated: 2026-08-26._

## Current accepted baseline

- **Stable/Frozen runtime baseline**: `Unknown / Unverified`.
- `feat/chatgpt-enhancer-v0.1` remains the product base at `c9602a0ccf3060f053f13b121b5c0c5bdf14aaf8`.
- `feat/conversation-recognition` is the newest recognition test branch, but no recognition candidate is accepted until real-device evidence proves both no cross-targeting and reliable exact-current identification.

## Current development candidates

### ChatGPTEnhancer `0.1.0-alpha46-conversation-identity-trace`

- Work ID `DEV-conversation-recognition`; branch `feat/conversation-recognition`; Draft PR #2 → `feat/chatgpt-enhancer-v0.1`.
- Build/test source `fc78d7d525969699fbd15a3f180e563e93e6d424`; Actions bookkeeping `a99a9b99ec9c26e3537ee5a242f0cfa7c4764f88`; post-CI cleanup head `96d845e7d750ea178ff73c12faed115dff33d14c`. Compare from tested source to current head changes only `.github/latest-enhancer-run-id` and workflow trigger cleanup; product source is unchanged.
- Alpha46 is **instrumentation-only**. It does not change current action-targeting behavior or claim a recognition fix.
- Adds persistent user-started sanitized identity tracing across process relaunch. The conversation menu exposes `开始会话识别记录` / `结束并导出识别日志`.
- Trace correlates menu/configuration/source structural evidence, exact menu candidate IDs/titles/count, current context, official conversation/share request method/path/status, explicit URL/query conversation IDs, explicit in-memory body `conversation_id` fields, and Pull/Reload/Export target IDs.
- Privacy: no Authorization/Cookie/account IDs, full headers, raw request templates, request/response bodies, or message contents are persisted. Generic accessibility strings are not dumped.
- CI passed: Actions `32950198256`, job `98119660626`.
- Artifacts: package id `9599824714`, digest `sha256:0e8a35affb33f7f1b359dfb9e62c5ddaf95e5f72e3c3b198dedf496050ba32b9`; dylib id `9599825427`, digest `sha256:61de097c001094c512d651825df2d904369911443a032787e349192c3c4e9e95`.
- Runtime/manual/real-device: **Pending**. Required evidence includes normal chats, project chat, Share flow, repeated A↔B, duplicate-title conversations and force-close/relaunch into the last conversation.
- Status: Candidate; not Stable/Frozen.

### Not accepted `0.1.0-alpha45-visible-button-guard`

- CI/artifact succeeded, but real-device project-chat testing shows Reload can still fail closed with `无法确认当前可见会话，已取消重载。`.
- In the same recording, enhancer-injected menu Rename resolves the correct title; this motivates menu-scoped investigation but does not prove exact ID.

### Rejected `0.1.0-alpha44-current-conversation-guard`

- Alpha44 addressed proven network-driven identity contamination but the floating action button disappeared when identity was unproven.
- Rejected as a usable candidate; cross-conversation stress acceptance was not completed.

### Rejected `0.1.0-alpha42-project-conversation-title`

- Extended real-device use proved Pull Latest and Reload could cross/wrong conversations.
- Source later proved generic observed conversation request IDs could overwrite foreground identity.
- Project-header title replacement also had no visible effect; cosmetic header work remains deferred.

### Parallel `0.1.0-alpha43-conversation-usage`

- Work ID `DEV-conversation-usage`; branch `feat/conversation-usage`; Draft PR #3 remains stacked on rejected alpha42 recognition.
- Its percentage-specific work remains separate. If all floating UI is later hidden, the percentage bubble must be coordinated with that task rather than silently changed here.

## Current architecture / evidence

1. `CEBootstrap` — startup owner; alpha46 starts the trace lifecycle manager through this existing startup path.
2. `CECore` / `CEConversationContext` — sole long-lived active-conversation state owner.
3. `CEContextResolver` — current visible UIKit/catalog-backed proof; generic network task resume is not foreground authority.
4. `CENetworkObserver` — passive official-network observation/template/event/catalog input plus alpha46 sanitized trace emission; observed requests still do not determine foreground identity.
5. `CEAPIClient` — sole enhancer-originated request owner.
6. `CECatalog` — conversation ID/title/project catalog.
7. `CEEnhancerUI` — host UIKit integration and menu augmentation. Alpha46 records menu evidence but leaves existing target behavior unchanged.
8. `Diagnostics/CEConversationIdentityTrace` — experimental persistent sanitized identity evidence recorder; not an active-conversation authority.
9. Features/Export consume the existing owners and emit action target evidence to the trace when recording.

## Current development direction

- Exact current-conversation targeting remains highest priority; both wrong-target execution and frequent false-negative refusal are unacceptable for the final design.
- Investigate whether the host's top-right conversation menu or Share flow provides a stronger exact action-time ID than continuously maintained global visible heuristics.
- A future menu-scoped action target, if proven, must be ephemeral immutable evidence passed to Pull/Reload/Export, not a second long-lived current-conversation authority. Exact proven IDs may synchronize the existing `CEConversationContext`.
- Duplicate-title conversations are a mandatory discriminator: title-only execution is prohibited.
- Do not move Pull/Reload, remove floating action UI, or restore network identity writes until alpha46 runtime trace proves the exact target source.
- Project-header title replacement remains deferred.

## Known issues / constraints

- ChatGPT private backend/runtime/UI surfaces can change.
- No verified automated unit/UI test suite exists; CI build success is not runtime proof.
- Top-right current-chat menu and sidebar/long-press menu may look similar while exposing different source/configuration evidence.
- Share showing the right title is high-value evidence but still does not prove where/how exact conversation ID is available.
- Current `CELastTouchedView` / title hints and title matching are heuristic and cannot be final execution authority.
- Generic/background network traffic remains correlation evidence only, not foreground authority.

## Evidence rule

Always distinguish Code written, Static/local checks passed, CI passed, Artifact produced, Runtime/manual/real-device tested, and Stable/Frozen.