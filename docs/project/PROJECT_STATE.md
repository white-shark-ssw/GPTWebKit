# Project State

_Last updated: 2026-08-25._

## Current accepted baseline

- **Stable/Frozen runtime baseline**: `Unknown / Unverified` from repository evidence alone.
- The default branch `main` is **not** proof of the latest product behavior; before governance installation it contained only the initial README and placeholder file.
- The current active product track is `ChatGPTEnhancer`. `feat/chatgpt-enhancer-v0.1` remains the base product branch; `feat/conversation-recognition` is the newest test candidate branch and has not yet been accepted as a runtime baseline.
- A separate standalone native-client planning track, `DEV-native-chatgpt-client`, is Active but has no implementation baseline or runnable candidate yet.

## Current development candidates

### Standalone native ChatGPT client planning

- Work ID: `DEV-native-chatgpt-client`.
- Branch: `feat/native-chatgpt-client`, created from governance `main` commit `92e26ae5bd0dc6ee75cc7ea3aae628ee42d5c215`.
- Purpose: replace WebView/React/DOM chat rendering with native iOS conversation list/message/composer/attachment UI while using a native protocol/network adapter against real ChatGPT backend behavior.
- Current stage: architecture planning only. No product code, PR, candidate identity, CI, artifact or runtime result.
- Critical open boundary: standalone authentication/session bootstrap and send/stream/upload protocol behavior must be verified from real request evidence. Whether any browser surface is allowed solely for login bootstrap remains undecided.
- Status: Active planning task; not a Candidate and not a replacement for the current enhancer product track.

### ChatGPTEnhancer `0.1.0-alpha42-project-conversation-title`

- Work ID: `DEV-conversation-recognition`.
- Branch: `feat/conversation-recognition`; Draft PR #2 targets `feat/chatgpt-enhancer-v0.1`.
- Build/test source head for Actions run `32855687010`: `7a68a86ae5091a270aafb18b98b6a4037a1b4f0b`; CI bookkeeping commit `1494d048fe7cdf43b30b9a29ccb62e3f38644d59`; post-CI workflow-only cleanup head `51bc4a9b580d62e3cc95cc3cf95b33827d6a0a7b`.
- Purpose: keep current conversation identity synchronized across A→B navigation and, on the evidenced Chinese project-chat header (`聊天` subtitle), replace the visible project name with the verified current conversation title.
- Header behavior: an 8pt gear is shown immediately left of the title only after replacement succeeds. Ordinary/non-project headers are intentionally not targeted.
- Identity safety: the modified header is marked as enhancer-synthetic presentation. Shared visible-string collection, periodic context resolution, accessibility/touch title resolution and floating top-title resolution all exclude the synthetic header so plugin-written text cannot become current-conversation evidence or reinforce stale state.
- CI: passed, run `32855687010`, job `97826971741`.
- Artifacts produced: package id `9566065953` (`sha256:99ba0406e9e959cbf175f828ce1be181a14cf0b0dea001ec3e63e9013a8f620f`) and dylib id `9566066411` (`sha256:c272d7ccdcad893813c55f8e63de7db7d603cadad96ab8d5a15f0519a9fca162`).
- Runtime/manual/real-device result: **Pending**. Required acceptance covers project header title/gear, non-project header safety, and A→B Export/Pull/Reload targeting B.
- Status: Candidate; not Stable/Frozen.

### Superseded `0.1.0-alpha41-project-conversation-title`

- Alpha41 introduced the project-header presentation and passed Actions runs `32854457168` and `32854676896` with artifacts.
- Post-build review found synthetic header text could still feed identity-resolution paths. Alpha41 was therefore superseded before runtime testing and must not be treated as an accepted candidate.

### ChatGPTEnhancer `0.1.0-alpha40-conversation-recognition`

- Work ID: `DEV-conversation-recognition`.
- Build/test source head for Actions run `32850463066`: `a7f1aba4848899ec7e5b5cdfd711b584a45d4bdd`; CI bookkeeping `ab5d8d4a5caddfc3dd3fdc88acc065b0036aa8d1`.
- Purpose: fix stale active-conversation identity after A→B navigation. Export, pull-latest and exact-current reload ultimately consume `CEConversationContext.conversationID`, so stale identity affects real operation targets, not only labels.
- CI/artifacts: passed/produced.
- Runtime/manual/real-device result: **Pending**; alpha42 now supersedes it as the newest integrated device-test candidate.

### ChatGPTEnhancer `0.1.0-alpha39-reload-stability`

- Base branch head `feat/chatgpt-enhancer-v0.1` remains `c9602a0ccf3060f053f13b121b5c0c5bdf14aaf8`.
- Actions run `32841238704` passed and produced artifacts.
- User real-device reproduction on the base/current behavior established that after A→B the floating Export MD flow can still show A's title, proving the active-conversation path can remain stale across navigation.

### Legacy/native app branches

- `feat/initial-ios-shell` / Draft PR #1 and `feat/0.2-native-recovery-exporter` remain legacy tracks, not the active enhancer baseline.

## Current architecture

The current enhancer is a host-app injected dylib with separated state ownership:

1. `CEBootstrap` is startup owner.
2. `CECore` owns generic helpers and authoritative `CEConversationContext` active conversation state.
3. `CENetworkObserver` passively observes official networking and keeps sensitive request material only in memory.
4. `CEAPIClient` is the single enhancer-originated request path.
5. `CECatalog` owns conversation catalog/title resolution.
6. `CEEnhancerUI` owns host-app UI integration, including the project-header presentation override.
7. Export/features/diagnostics consume these owners rather than creating parallel authorities.

The standalone native-client architecture is not implemented yet. Planning direction requires separate state ownership for standalone authentication/session, transport/protocol, conversation data and native UI; exact modules remain `Unknown / Unverified` until implementation planning is finalized.

## Current development direction

- Treat `ChatGPTEnhancer` as the current active product track unless explicitly routed to another task.
- Manual reload remains exact-current-conversation only.
- For `DEV-conversation-recognition`, correct identity at `CEConversationContext` and treat plugin-generated header content as presentation only, never as identity evidence.
- `DEV-conversation-usage` remains a separate Active task restricted to percentage-specific files and its stacked alpha43 candidate.
- `DEV-native-chatgpt-client` is a parallel planning-only track. Its primary chat UI must be native iOS rather than WebView/React/DOM rendering; private backend/auth/stream behavior must be evidenced before implementation. It does not modify or supersede enhancer architecture during planning.

## Known issues / constraints

- ChatGPT private backend/runtime surfaces can change.
- No verified automated unit/UI test suite or dedicated lint/static suite exists; CI build success is not runtime validation.
- Enhancer version identity is duplicated across `CECore.mm`, `build.sh`, and `build-enhancer.yml`; candidate changes must stay synchronized.
- Duplicate conversation titles remain ambiguous and fail closed.
- Brand-new conversations not yet in `CECatalog` can temporarily lack enough evidence.
- The alpha42 header detector is currently evidenced only for the Chinese project-chat layout with exact subtitle `聊天`; other locales/layouts are `Unknown / Unverified`.
- Tiny-gear positioning and header restoration have compiled but still require real-device visual validation.
- GitHub Actions commits run IDs back to feature branches, so branch head can be a CI bookkeeping commit rather than the tested functional source.
- Standalone native client authentication/session acquisition is not yet solved; zero-WebView login, login-only browser bootstrap, and other approaches must not be treated as equivalent until verified.
- Send/stream/edit/regenerate/upload/model/project request contracts for the standalone client are currently `Unknown / Unverified` and must be derived from real current traffic rather than historical assumptions.

## Evidence rule

Always distinguish source written, checks/CI passed, artifact produced, runtime/manual tested, and Stable/Frozen acceptance.
