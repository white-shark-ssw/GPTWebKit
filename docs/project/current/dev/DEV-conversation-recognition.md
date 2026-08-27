# DEV-conversation-recognition

## Status

**Active**

- **Work ID**: `DEV-conversation-recognition`
- **Routing aliases / keywords**: `优化会话识别 / 会话识别 / 当前会话识别 / 会话切换识别 / conversation recognition`
- **Task**: 精确识别 ChatGPT iOS 当前会话，并确保 Sync / Reload / Export / Rename 不串会话；侧栏 Rename / Export 保持被长按行作用域；继续完善 Sync/Reload 的真实完成语义。项目顶部标题按用户要求暂停。
- **Acceptance invariant**: 当前会话动作必须使用真实 exact conversation ID。HTTP 429 不得被插件短间隔自动重试放大。服务器 GET 成功不等于页面同步；same-ID request delivery 不等于页面 Reload；只有真实 UI refresh/rebuild 才能报告可见同步/重载完成。

## Resume identity / conflict guard — 2026-08-27

- Baseline `feat/chatgpt-enhancer-v0.1` rechecked unchanged at `c9602a0ccf3060f053f13b121b5c0c5bdf14aaf8`.
- Working branch `feat/conversation-recognition`; Draft PR #2 → `feat/chatgpt-enhancer-v0.1`; current branch/head rechecked at `aa00b1d164fd11e8f743e557b33eecd8dcb1bfd1`; PR remains open/draft/mergeable.
- Parallel `DEV-conversation-usage` remains Active on `feat/conversation-usage` at `ddd5829b563a9191ad2687378123d9e53fbb232d`, candidate alpha43. Recognition diagnostics do not touch percentage-owned sources/checkpoint.
- No product module is Frozen. Diagnostics and Network are Active. Alpha54 changed only diagnostic observation at the existing NSURLSession hook surface; request ownership and production Sync/Reload behavior remain unchanged.
- Candidate `ENH-0.1.0-alpha54-task-creation-trace` / `0.1.0-alpha54-task-creation-trace` remains unique versus recognition alpha42–53 and parallel alpha43.

## Previous evidence — alpha53

Trace `conversation-identity-E076722C-E0F0-4044-8B99-41F727B1B62B.log`, enhancer `0.1.0-alpha53-refresh-path-trace`, app `1.2026.202`:

- Genuine A → B and B → A exact navigation emitted exact `conversation/init`, then exact `prepare` + conversation detail within about 125 ms.
- Genuine exact navigation snapshots showed `SwiftUI.UIKitNavigationController navCount=3`; same-A custom-route Sync/Reload produced one detail GET only, no exact init/prepare, no UI rebuild, and `navCount=1`.
- Alpha52 delivery-aware suppression worked: no second/third route burst after the first same-ID request delivery.
- All alpha53 downstream `REFRESH-PATH` call-stack signatures were identical, so that logging point could not identify the upstream host navigation owner.

## Current candidate — alpha54 task-creation trace

- **Candidate**: `ENH-0.1.0-alpha54-task-creation-trace` / `0.1.0-alpha54-task-creation-trace`.
- **Source baseline**: alpha53 cleanup head `f2478c58fcaaf621ccfdffb5cb0a08b89be8dc53`.
- **Build/test source**: `6d0f8537cde9d1f3029e4b0a5f39c9a0aa041142`.
- **Actions**: run `33042244321`, job `98418234062` — completed **success**.
- **CI bookkeeping**: `fa5338712eea77194548e041472047e1dfe4b931`.
- **Post-CI cleanup/current branch head**: `aa00b1d164fd11e8f743e557b33eecd8dcb1bfd1`.
- **Post-CI compare**: build/test source → current head changes only `.github/latest-enhancer-run-id` and removal of the temporary recognition-branch CI trigger; tested product source is unchanged.
- **Artifacts**:
  - package `ChatGPTEnhancer-0.1.0-alpha54-task-creation-trace`, id `9634299997`, Actions archive digest `sha256:560a89c13222875effba1e15e19d7afada4228ce0b111e2269fc2ecab3957834`;
  - dylib `ChatGPTEnhancer-0.1.0-alpha54-task-creation-trace-dylib`, id `9634300301`, Actions archive digest `sha256:506f9db6c6df491a167b51fe0541bf5c7a6bec753efc5b949bdc6e159e494f2e`;
  - extracted `ChatGPTEnhancer.dylib`: arm64 Mach-O, 594752 bytes, sha256 `cad6d1e1fdcc74b4c1cc25d2d3abed53f8af79b818d04e619073f01544224237`.
- **Validation state**: **Code written → CI passed → Artifact produced → Runtime/manual/real-device partially tested.** Nothing Stable/Frozen.

## Authoritative alpha54 runtime evidence — 2026-08-27

Trace `conversation-identity-1995A79E-71DF-4EBC-BB1E-A61D48871FD2.log`, enhancer `0.1.0-alpha54-task-creation-trace`, app `1.2026.202`, 172 structured events:

- Trace starts with A exact current ID `6a8d8d0b-1b2c-83ec-89f4-fa5eb65138d7`.
- Before the first exact navigation target appears, the host emitted an ID-less `conversation/init` at `1787810013246` and two ID-less prepare requests at `1787810013469/3471`; corresponding `REFRESH-PATH` snapshots showed `navCount=2` and two `NavigationStackHostingController<AnyView>` entries.
- Exact navigation to B `6a8da245-c538-83ec-9303-da2952a46a1f` then emitted exact init at `1787810015340`; exact prepare began +118 ms and exact detail +123 ms. These exact snapshots showed `navCount=3` and three homogeneous `NavigationStackHostingController<AnyView>` entries. This proves the public navigation stack had already grown from 2 to 3 before/at exact-init observation.
- Returning to A emitted one additional ID-less prepare while `navCount=3`, then exact A init at `1787810023969`, followed by exact prepare +123 ms and detail +126 ms; exact A snapshots remained `navCount=3` with the same three-controller composition.
- After returning to A, `ACTION-SYNC` targeted the correct exact A ID. About 12.7 s later Sync entered Reload; route attempt 0 opened once and produced only one same-ID detail GET. That failed route snapshot showed `navCount=1` with one `NavigationStackHostingController<AnyView>`, no exact init/prepare and no UI rebuild. Delivery-aware suppression again stopped further route attempts and reported failure truthfully.
- **Critical alpha54 result**: the trace contains **zero `REFRESH-CREATE` records**, even though 14 refresh-relevant `REFRESH-PATH` records were captured. Therefore the official semantic init/prepare/detail requests in this runtime did not pass through any of the swizzled Objective-C `NSURLSession dataTaskWithRequest:/dataTaskWithURL:/uploadTaskWithRequest:` creation selectors where alpha54 placed `REFRESH-CREATE`. They were observed only later on the existing task/resume/delegate observation surface. The exact higher-level Foundation/Swift API remains unverified; do not name one as fact.
- All 14 downstream `REFRESH-PATH` call-stack signatures were still identical. Alpha54 therefore did **not** identify a production refresh caller; the task-creation hypothesis for these selectors is runtime-rejected.
- No HTTP 429 occurred in this trace; terminal 429 behavior remains separately unexercised by trace evidence.

## Alpha54 conclusions

1. Exact identity remains correct and one-delivery suppression remains device-confirmed.
2. Genuine navigation now has stronger structural evidence: ID-less staging at public navigation depth 2 can precede exact target navigation at depth 3; exact init/prepare/detail are consequences/evidence after the host navigation structure has changed.
3. The failed same-current custom URL path collapses/reaches a one-controller navigation state and emits detail only; it is not equivalent to genuine navigation.
4. `REFRESH-CREATE=0` rejects the specific alpha54 assumption that these host requests traverse the swizzled Objective-C NSURLSession task-creation selectors. Do not keep expanding diagnostics at those same selectors.
5. The next diagnostic should follow the newly proven state difference rather than the rejected network-creation path: observe public `UINavigationController` stack mutations (`setViewControllers` / push / pop family) without mutating them, recording before/after bounded class composition and sanitized caller evidence only while the user-started trace is active. This is diagnostic observation, not authorization to perform navigation-stack mutation.
6. Do not manually replay init/prepare, force a three-controller stack, hard-code the observed Swift controller class, use History/sidebar navigation, add `/resume`, retry/watchdog/timers, or add new route variants from this evidence.

## Architecture retained / rejected routes

- `CEConversationContext` remains sole active identity authority; only validated exact `conversation/init` body ID promotes foreground identity.
- `CEAPIClient` remains sole enhancer-originated request owner.
- Server GET/request delivery is not visible Sync/Reload completion.
- Navigation count/composition and init→prepare→detail are evidence of host state, not instructions to replay requests or mutate stacks.
- Project-header work remains paused; percentage work remains untouched.

## Next exact action

If continuing the refresh investigation, build one diagnostic-only successor that traces public `UINavigationController` stack mutation entry points during the existing user-started identity trace, with before/after stack count + bounded controller-class composition + sanitized caller symbols. Keep production Sync/Reload unchanged. Then capture the same A → B → A → Sync sequence and compare genuine stack transitions with the custom-route collapse. Do not implement a production refresh mechanism until a real host navigation entry path is evidenced.