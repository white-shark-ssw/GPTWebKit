# Project State

_Last updated: 2026-08-25._

## Current accepted baseline

- **Stable/Frozen runtime baseline**: `Unknown / Unverified` from repository evidence alone.
- The default branch `main` is **not** proof of the latest product behavior; before governance installation it contained only the initial README and placeholder file.
- The current active product track is `ChatGPTEnhancer`. `feat/chatgpt-enhancer-v0.1` remains the base product branch; `feat/conversation-recognition` is the newest test candidate branch and has not yet been accepted as a runtime baseline.

## Current development candidates

### ChatGPTEnhancer `0.1.0-alpha40-conversation-recognition`

- Work ID: `DEV-conversation-recognition`.
- Branch: `feat/conversation-recognition`; Draft PR #2 targets `feat/chatgpt-enhancer-v0.1`.
- Current branch head: `5157425c3b3926ec8150486730301c7d285f24e9`.
- Build/test source head for Actions run `32850463066`: `a7f1aba4848899ec7e5b5cdfd711b584a45d4bdd`; CI bookkeeping commit: `ab5d8d4a5caddfc3dd3fdc88acc065b0036aa8d1`.
- Purpose: fix stale active-conversation identity after A → B navigation. The candidate keeps visible-context resolution active after an ID has already been established and prevents floating-tool visible titles from being written into an unverified stale conversation ID.
- Scope evidence: export, pull-latest and manual reload all ultimately consume `CEConversationContext.conversationID`; therefore stale identity can affect actual operation targets, not only the export filename.
- CI: passed.
- Artifacts produced: `ChatGPTEnhancer-0.1.0-alpha40-conversation-recognition` and `ChatGPTEnhancer-0.1.0-alpha40-conversation-recognition-dylib`.
- Runtime/manual/real-device result: **Pending**. The user-reported alpha39/base reproduction is A → B then Export MD still showing A's title. Alpha40 must still be tested for export title/data, pull target and reload target before acceptance.
- Status: Candidate; not Stable/Frozen.

### ChatGPTEnhancer `0.1.0-alpha39-reload-stability`

- Branch head: `feat/chatgpt-enhancer-v0.1` at `c9602a0ccf3060f053f13b121b5c0c5bdf14aaf8` (CI run-id bookkeeping commit).
- Build source head for Actions run `32841238704`: `70905cc5d038d41a900e626f0c6467c5d0573ef9`.
- Functional alpha39 reload change: `8e520cba370870173a5ef08392636e1ca8036308` (`fix: make exact-current conversation reload retry-safe`).
- CI: passed.
- Artifacts produced: `ChatGPTEnhancer-0.1.0-alpha39-reload-stability` and `ChatGPTEnhancer-0.1.0-alpha39-reload-stability-dylib`.
- Runtime/manual/real-device result: user has now provided a concrete stale-session reproduction on the current/base behavior: after switching A → B, the floating Export MD rename input can still show A's title. This does not by itself isolate every alpha39 behavior, but it is authoritative evidence that the current conversation identity path can remain stale across navigation.
- PR: none recorded for this branch in the scanned repository state.

### Legacy/native app branches

- `feat/initial-ios-shell` head `48c42c706def626c5ab363778fb1f4013767c79c`; open Draft PR #1 targets `main` and describes the earlier WKWebView shell.
- `feat/0.2-native-recovery-exporter` head `f1a6fac30d3b4ba8dd790679ef666debbcfc5fd5`; contains the later native utility/Markdown-export app line and unsigned IPA workflow.
- These are repository candidates/history, not the current enhancer baseline. Do not resume or modify either merely because the branch exists; development routing still requires a selected Active checkpoint.

## Current architecture

The current enhancer is a host-app injected dylib with separated state ownership:

1. `CEBootstrap` is the primary product startup owner recorded by project architecture.
2. `CECore` owns generic helpers and the authoritative `CEConversationContext` active conversation state.
3. `CENetworkObserver` observes official networking and keeps sensitive request material only in memory.
4. `CEAPIClient` is the single enhancer-originated request path.
5. `CECatalog` owns conversation catalog resolution.
6. `CEEnhancerUI` owns host UI integration.
7. Export, feature and diagnostics modules consume those owners rather than establishing parallel authorities.

## Current development direction

- Treat `ChatGPTEnhancer` as the current active product track unless a future explicitly routed development task says otherwise.
- Preserve the old native/WebView code as a separate legacy track. Do not mix its UI/recovery/upload architecture into enhancer work without explicit evidence and task scope.
- Manual reload remains exact-current-conversation only and verifies delivery through the host app's own detail/resume request behavior.
- For `DEV-conversation-recognition`, correct identity at the existing `CEConversationContext` owner rather than creating a second current-conversation cache. Do not use arbitrary visible text as proof of identity and do not broaden background network requests into active-view authority without runtime evidence.

## Known issues / constraints

- ChatGPT private backend routes and host-app runtime surfaces are undocumented and can change.
- The repository currently has no verified automated unit/UI tests or dedicated lint/static-analysis suite; CI build success is not runtime validation.
- Enhancer version identity is duplicated across `CECore.mm`, `build.sh`, and `build-enhancer.yml`; candidate changes must keep them synchronized.
- Duplicate visible conversation titles are ambiguous for title-based resolution; alpha40 intentionally fails closed instead of guessing.
- A newly created conversation not yet represented in `CECatalog` may temporarily lack enough catalog-backed visible evidence; real-device behavior remains to be measured.
- The enhancer branch still contains older `GPTWebKit` native app source and a root README describing the earlier 0.3 utility, so source-track identity must be resolved before development work.
- Existing Draft PR #1 belongs to the legacy WebView shell; Draft PR #2 belongs to the enhancer conversation-recognition candidate.
- GitHub Actions commits run IDs back to feature branches, so branch head may be a CI bookkeeping commit rather than the last functional code change.

## Evidence rule

Always distinguish source written, checks/CI passed, artifact produced, runtime/manual tested, and Stable/Frozen acceptance.
