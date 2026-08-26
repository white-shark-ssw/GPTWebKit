# DEV-conversation-recognition

## Status

**Active**

- **Work ID**: `DEV-conversation-recognition`
- **Routing aliases / keywords**: `优化会话识别 / 会话识别 / 当前会话识别 / 会话切换识别 / conversation recognition`
- **Task**: 精确识别 ChatGPT iOS 当前会话，并确保 Sync / Reload / Export / Rename 不串会话；侧栏 Rename / Export 保持被长按行作用域；继续完善 Sync/Reload 的真实完成语义。项目顶部标题按用户要求暂停。
- **Acceptance invariant**: 当前会话动作必须使用真实 exact conversation ID。HTTP 429 不得被插件短间隔自动重试放大。服务器 GET 成功不等于页面同步；same-ID request delivery 不等于页面 Reload；只有真实 UI refresh/rebuild 才能报告可见同步/重载完成。

## Resume identity / conflict guard — 2026-08-27

- **Baseline**: `feat/chatgpt-enhancer-v0.1` = `c9602a0ccf3060f053f13b121b5c0c5bdf14aaf8`, rechecked unchanged after alpha52 runtime capture.
- **Working branch / PR**: `feat/conversation-recognition` = `90c5bb97f332b2c0c4935ad3eaea9432df3e156e`; Draft PR #2 → `feat/chatgpt-enhancer-v0.1`; PR rechecked open/draft/mergeable at the same head.
- **Parallel task**: `DEV-conversation-usage` remains Active on `feat/conversation-usage` at `ddd5829b563a9191ad2687378123d9e53fbb232d`, candidate alpha43. Recognition work does not touch percentage-owned files/checkpoint.
- **Candidate uniqueness**: recognition alpha42–52 and parallel alpha43 are allocated. New diagnostic candidate `ENH-0.1.0-alpha53-refresh-path-trace` / `0.1.0-alpha53-refresh-path-trace` is unique.
- **No Frozen conflict**: product modules remain Active. Alpha53 is diagnostic-only and must not change identity ownership or production refresh semantics.

## Previous candidate — alpha52

- **Candidate**: `ENH-0.1.0-alpha52-sync-refresh-handoff` / `0.1.0-alpha52-sync-refresh-handoff`.
- **Build/test source**: `9c06219cdee1ac00b75372f1480278169b3f6e59`.
- **Actions**: run `33004675627`, job `98295074960` — success.
- **CI bookkeeping**: `087d03884b6a4c565d126e8c90849bafa0bf28e9`; post-CI cleanup head `90c5bb97f332b2c0c4935ad3eaea9432df3e156e`.
- **Artifacts**: package id `9620028731`; dylib id `9620029383`; extracted dylib sha256 `0b19bb2ec6d2b9a5ff26210bbd8d8945cffa77bb280b38e28ef1e0f9dc7f62d5`.
- **Validation**: Code written → CI passed → Artifact produced → Runtime/manual partially tested. Nothing Stable/Frozen.

## Authoritative alpha52 A → B → A runtime evidence — 2026-08-27

Trace `conversation-identity-585B0B11-C85D-4A19-BA16-4F55D56A320A.log`, enhancer `0.1.0-alpha52-sync-refresh-handoff`, app `1.2026.202`:

- Trace starts while A is current: `6a8d8d0b-1b2c-83ec-89f4-fa5eb65138d7`.
- Normal A → B navigation produced exact B `POST /backend-api/conversation/init` with body ID `6a8efab8-8898-83ec-ab3a-555b7cb9d32e`; about 120–125 ms later the host issued two exact B `/backend-api/f/conversation/prepare` requests and one exact B `GET /backend-api/conversation/<B>`.
- While B remained visible the host continued B-scoped prepare/status activity, including `POST /backend-api/conversation/<B>/async-status`.
- Normal B → A return first emitted an ID-less `conversation/init` + ID-less prepare/project-loading sequence, then exact A `conversation/init` body ID `6a8d8d0b-1b2c-83ec-89f4-fa5eb65138d7`; about 125 ms later it issued exact A prepare + detail GET + a second exact A prepare.
- `IDENTITY-INIT` accepted B and then A exactly, so foreground identity behavior remained correct during the genuine navigation sequence.
- This directly contrasts alpha51 failed same-current custom-route Reload, which produced only same-ID detail GETs and **zero exact `conversation/init` / exact `prepare`** while the visible page did not rebuild.
- Therefore genuine host navigation/rebuild is correlated with an internal host navigation-state transition that emits `conversation/init → prepare → detail`; a detail GET alone is insufficient.
- The trace does **not** prove that manually sending `conversation/init`/`prepare` network requests would update UI. Those requests are consequences/evidence of host navigation state; enhancer-originated copies would not by themselves prove host state mutation.
- Existing alpha52 trace captures network/menu/header structure but not enough call-site/UI-lifecycle evidence to identify a safe production host refresh entry point.

## Current direction — alpha53 diagnostic candidate

- **Candidate**: `ENH-0.1.0-alpha53-refresh-path-trace` / `0.1.0-alpha53-refresh-path-trace`.
- **Goal**: gather minimum sanitized structural evidence at the exact host request creation point and around genuine navigation so the next production refresh change can target a real host pathway rather than guess.
- **Allowed instrumentation**:
  1. for exact `conversation/init` and exact `/f/conversation/prepare` host requests only, record a bounded sanitized call-site signature (symbol/class/function names only; no headers/body/message content/account/auth data);
  2. record foreground key/top view-controller class and public UIKit navigation-container state near those semantic requests;
  3. keep all persistence within the existing user-started identity trace.
- **Do not add**: production `/resume`, direct enhancer-originated init/prepare replay, watchdog, timer retry family, alternate IDs, History/sidebar navigation, UIKit pop/push fallback, private-class hard-coding, Catalog throttling, project-header work, or percentage changes.
- **Expected next capture**: with alpha53, record one normal A → B → A sequence and one `同步最新消息` attempt on A in the same trace. Compare semantic-request call-site/navigation signatures between genuine rebuild and same-current custom-route handoff.
- **Validation state**: candidate allocated; Code not yet written; CI/artifact/runtime pending.

## Architecture retained / rejected routes

- Sole active identity owner: `CEConversationContext`; only validated explicit `POST /backend-api/conversation/init` body `conversation_id` promotes foreground identity.
- Generic request recency, title-only matching and arbitrary UUIDs are not identity authority.
- Current menu freezes exact ID; sidebar Rename/Export remain row-scoped.
- `CEAPIClient` remains sole enhancer-originated request owner; 429 remains terminal for the current request.
- Do not claim GET/request/openURL success as UI Sync/Reload success.
- Do not automatically repeat same-route delivery once exact same-ID request delivery is proven but UI effect is absent.
- Genuine navigation traffic is evidence of host state transition, not authorization to replay its requests manually.
- Project-header work remains paused; percentage-owned files remain untouched.

## Next exact action

Implement alpha53 diagnostic-only instrumentation on `feat/conversation-recognition`, synchronize candidate identity, run isolated CI/artifact, then ask for one combined trace: normal A → B → A followed by a same-A `同步最新消息` attempt. Use the structural call-site/navigation comparison to decide whether a real host refresh entry point is evidenced. Do not implement a production refresh mechanism until that evidence exists.