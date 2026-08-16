(() => {
  'use strict';
  if (window.GPTWebKitLongConversation) return;

  const STORAGE_KEY = 'gptwebkit.longConversation.settings.v6';
  const defaults = { enabled: true, minMessages: 6, overscan: 1, keepRecent: 3, fastFollowLatest: true, autoRecoverStall: false };
  let settings = { ...defaults };
  try { settings = { ...defaults, ...JSON.parse(localStorage.getItem(STORAGE_KEY) || '{}') }; } catch (_) {}

  const isConversationRoute = () => /\/c\/[^/?#]+/.test(location.pathname);
  const state = {
    records: [],
    knownNodes: new WeakSet(),
    ticking: false,
    suspended: false,
    paused: document.visibilityState !== 'visible',
    url: location.href,
    routeStartedAt: Date.now(),
    stallSince: 0,
    lastRecoveryAt: 0,
    wasGenerating: false,
    pinLatest: settings.fastFollowLatest && isConversationRoute(),
    pinStartedAt: Date.now(),
    reachedBottom: false,
    stableKey: '',
    stableTicks: 0,
    touchStartY: 0,
    userCancelledPin: false
  };

  const installCSS = () => {
    if (document.getElementById('gptwebkit-long-conversation-style')) return;
    const style = document.createElement('style');
    style.id = 'gptwebkit-long-conversation-style';
    style.textContent = `
      main [data-message-author-role], main [data-testid^="conversation-turn-"], main article { content-visibility:auto; contain-intrinsic-size:auto 520px; }
      [data-gptwebkit-placeholder="1"] { content-visibility:auto; contain:layout style paint; }
      #gptwebkit-opt-panel { position:fixed; z-index:2147483640; inset:0; display:flex; align-items:center; justify-content:center; background:rgba(0,0,0,.28); padding:20px; }
      #gptwebkit-opt-card { width:min(340px,92vw); border-radius:18px; background:Canvas; color:CanvasText; box-shadow:0 12px 50px rgba(0,0,0,.28); padding:18px; font:15px -apple-system,BlinkMacSystemFont,sans-serif; }
      #gptwebkit-opt-card h3 { margin:0 0 14px; font-size:18px; }
      #gptwebkit-opt-card label { display:flex; align-items:center; justify-content:space-between; min-height:42px; gap:16px; }
      #gptwebkit-opt-card input[type="number"] { width:72px; font-size:16px; }
      #gptwebkit-opt-card .hint { margin:6px 0 2px; color:#888; font-size:12px; line-height:1.45; }
      #gptwebkit-opt-card .actions { display:flex; justify-content:flex-end; gap:10px; margin-top:14px; }
      #gptwebkit-opt-card button { border:0; border-radius:10px; padding:9px 14px; font-size:15px; }
    `;
    (document.head || document.documentElement).appendChild(style);
  };

  const saveSettings = () => { try { localStorage.setItem(STORAGE_KEY, JSON.stringify(settings)); } catch (_) {} };

  const isGenerating = () => {
    if (document.querySelector('[data-testid="stop-button"], button[aria-label*="Stop" i], button[title*="Stop" i]')) return true;
    for (const button of document.querySelectorAll('button')) {
      const text = `${button.getAttribute('aria-label') || ''} ${button.getAttribute('title') || ''} ${button.textContent || ''}`;
      if (/停止生成|停止回答|停止响应|stop generating|stop streaming/i.test(text)) return true;
    }
    return false;
  };

  const isWaitingForCompletedReply = () => /连接已中断[^\n]{0,40}正在等待完整回复|连接中断[^\n]{0,40}等待完整回复|connection interrupted[^\n]{0,80}waiting for (the )?(complete|full) response/i.test(document.body?.innerText || '');

  const openSettings = () => {
    document.getElementById('gptwebkit-opt-panel')?.remove();
    const panel = document.createElement('div');
    panel.id = 'gptwebkit-opt-panel';
    panel.innerHTML = `<div id="gptwebkit-opt-card">
      <h3>长对话优化</h3>
      <label><span>启用优化</span><input data-k="enabled" type="checkbox" ${settings.enabled ? 'checked' : ''}></label>
      <label><span>进入会话直接定位最新</span><input data-k="fastFollowLatest" type="checkbox" ${settings.fastFollowLatest ? 'checked' : ''}></label>
      <label><span>连接中断自动恢复</span><input data-k="autoRecoverStall" type="checkbox" ${settings.autoRecoverStall ? 'checked' : ''}></label>
      <div class="hint">进入长会话时会持续锁定最新消息，直到最新区域真正稳定；后台前会压缩旧消息以降低 WebKit 被系统回收的概率。</div>
      <label><span>始终保留最近消息</span><input data-k="keepRecent" type="number" min="2" max="12" value="${settings.keepRecent}"></label>
      <label><span>上下预留消息</span><input data-k="overscan" type="number" min="0" max="8" value="${settings.overscan}"></label>
      <div class="actions"><button data-a="reset">恢复默认</button><button data-a="close">完成</button></div>
    </div>`;
    panel.addEventListener('click', (event) => { if (event.target === panel) panel.remove(); });
    panel.querySelectorAll('[data-k]').forEach((input) => input.addEventListener('change', () => {
      const key = input.dataset.k;
      settings[key] = input.type === 'checkbox' ? input.checked : Math.max(Number(input.min || 0), Math.min(Number(input.max || 99), Number(input.value)));
      if (key === 'fastFollowLatest' && input.checked && isConversationRoute()) beginPinLatest();
      if (key === 'fastFollowLatest' && !input.checked) state.pinLatest = false;
      saveSettings();
      schedule();
    }));
    panel.querySelector('[data-a="reset"]').addEventListener('click', () => {
      settings = { ...defaults };
      saveSettings();
      panel.remove();
      restoreAll();
      if (isConversationRoute()) beginPinLatest();
      setTimeout(openSettings, 0);
    });
    panel.querySelector('[data-a="close"]').addEventListener('click', () => panel.remove());
    document.body.appendChild(panel);
  };

  const messageNodes = () => Array.from(document.querySelectorAll('main [data-message-author-role], main [data-testid^="conversation-turn-"], main article')).filter((node, index, all) => !all.some((other, i) => i !== index && other.contains(node)));

  const discoverMessages = () => {
    for (const node of messageNodes()) {
      if (state.knownNodes.has(node)) continue;
      state.knownNodes.add(node);
      state.records.push({ node, placeholder: null });
    }
    state.records = state.records.filter((record) => record.node?.isConnected || record.placeholder?.isConnected);
  };

  const scrollableAncestor = (node) => {
    for (let el = node?.parentElement; el && el !== document.body; el = el.parentElement) {
      const style = getComputedStyle(el);
      if (/(auto|scroll|overlay)/.test(style.overflowY) && el.scrollHeight > el.clientHeight + 40) return el;
    }
    return null;
  };

  const scrollRoot = () => {
    const nodes = messageNodes();
    const last = nodes[nodes.length - 1];
    const prompt = document.querySelector('#prompt-textarea, textarea, [contenteditable="true"][data-placeholder]');
    return scrollableAncestor(last) || scrollableAncestor(prompt) || document.scrollingElement || document.documentElement;
  };

  const restore = (record) => {
    if (!record.placeholder?.isConnected || !record.node) return;
    record.placeholder.replaceWith(record.node);
    record.placeholder = null;
  };

  const restoreAll = () => {
    state.suspended = true;
    state.records.forEach(restore);
    requestAnimationFrame(() => { state.suspended = false; schedule(); });
  };

  const restoreRecent = (count = 8) => {
    const start = Math.max(0, state.records.length - count);
    for (let i = start; i < state.records.length; i++) restore(state.records[i]);
  };

  const virtualize = (record) => {
    if (!record.node?.isConnected || record.placeholder) return;
    const rect = record.node.getBoundingClientRect();
    if (rect.height < 1) return;
    const placeholder = document.createElement('div');
    placeholder.dataset.gptwebkitPlaceholder = '1';
    placeholder.style.height = `${Math.ceil(rect.height)}px`;
    placeholder.style.minHeight = '1px';
    placeholder.addEventListener('click', () => { restore(record); schedule(); }, { once: true });
    record.node.replaceWith(placeholder);
    record.placeholder = placeholder;
  };

  const beginPinLatest = () => {
    state.pinLatest = settings.fastFollowLatest && isConversationRoute();
    state.pinStartedAt = Date.now();
    state.reachedBottom = false;
    state.stableKey = '';
    state.stableTicks = 0;
    state.userCancelledPin = false;
  };

  const resetForRouteChange = () => {
    if (state.url === location.href) return;
    state.records.forEach(restore);
    state.url = location.href;
    state.records = [];
    state.knownNodes = new WeakSet();
    state.routeStartedAt = Date.now();
    state.stallSince = 0;
    state.wasGenerating = false;
    beginPinLatest();
  };

  const clickScrollToBottom = () => {
    const selectors = ['button[aria-label*="bottom" i]', 'button[aria-label*="latest" i]', 'button[title*="bottom" i]', 'button[data-testid*="scroll" i]'];
    for (const selector of selectors) {
      const button = document.querySelector(selector);
      if (button instanceof HTMLElement && button.offsetParent !== null) { try { button.click(); } catch (_) {} }
    }
    for (const button of document.querySelectorAll('button')) {
      const text = `${button.getAttribute('aria-label') || ''} ${button.getAttribute('title') || ''} ${button.textContent || ''}`;
      if (/滚动到底部|回到底部|最新消息|scroll to bottom|jump to latest/i.test(text) && button.offsetParent !== null) { try { button.click(); } catch (_) {} }
    }
  };

  const forceLatestVisible = () => {
    if (state.paused || !settings.fastFollowLatest || (!state.pinLatest && !isWaitingForCompletedReply())) return;
    const nodes = messageNodes();
    const last = nodes[nodes.length - 1];
    const root = scrollRoot();
    clickScrollToBottom();
    try { last?.scrollIntoView({ block: 'end', inline: 'nearest', behavior: 'auto' }); } catch (_) {}

    const pushBottom = () => {
      if (root === document.scrollingElement || root === document.documentElement || root === document.body) {
        const height = Math.max(document.body?.scrollHeight || 0, document.documentElement?.scrollHeight || 0);
        window.scrollTo(0, height + innerHeight);
      } else {
        root.scrollTop = root.scrollHeight + root.clientHeight;
      }
    };

    pushBottom();
    requestAnimationFrame(pushBottom);

    const height = root === document.scrollingElement || root === document.documentElement || root === document.body ? Math.max(document.body?.scrollHeight || 0, document.documentElement?.scrollHeight || 0) : root.scrollHeight;
    const top = root === document.scrollingElement || root === document.documentElement || root === document.body ? Math.max(window.scrollY || 0, document.documentElement?.scrollTop || 0, document.body?.scrollTop || 0) : root.scrollTop;
    const client = root === document.scrollingElement || root === document.documentElement || root === document.body ? innerHeight : root.clientHeight;
    const distance = Math.max(0, height - (top + client));
    if (distance < 16) state.reachedBottom = true;

    const lastLength = (last?.textContent || '').length;
    const key = `${nodes.length}:${Math.round(height)}:${lastLength}`;
    if (key === state.stableKey && state.reachedBottom) state.stableTicks++; else state.stableTicks = 0;
    state.stableKey = key;

    if (state.pinLatest && state.reachedBottom && state.stableTicks >= 10 && Date.now() - state.pinStartedAt > 1800 && !isGenerating() && !isWaitingForCompletedReply()) state.pinLatest = false;
    if (state.pinLatest && Date.now() - state.pinStartedAt > 60000 && state.reachedBottom) state.pinLatest = false;
  };

  const update = () => {
    state.ticking = false;
    if (state.suspended || state.paused) return;
    resetForRouteChange();
    discoverMessages();

    const generating = isGenerating();
    const waitingCompleted = isWaitingForCompletedReply();
    if (state.pinLatest || waitingCompleted) {
      requestAnimationFrame(forceLatestVisible);
      restoreRecent(Math.max(settings.keepRecent + 5, 8));
      return;
    }

    const records = state.records;
    if (generating || waitingCompleted) {
      state.wasGenerating = true;
      state.stallSince = 0;
      restoreRecent(Math.max(settings.keepRecent + 5, 8));
      return;
    }
    if (state.wasGenerating) state.wasGenerating = false;
    if (!settings.enabled) { restoreAll(); return; }
    if (records.length < settings.minMessages) return;

    const root = scrollRoot();
    const documentRoot = root === document.scrollingElement || root === document.documentElement || root === document.body;
    const viewportTop = documentRoot ? 0 : root.getBoundingClientRect().top;
    const viewportBottom = documentRoot ? innerHeight : root.getBoundingClientRect().bottom;
    const recentStart = Math.max(0, records.length - settings.keepRecent);
    const visibleIndexes = [];

    records.forEach((record, index) => {
      const target = record.placeholder || record.node;
      if (!target?.isConnected) return;
      const rect = target.getBoundingClientRect();
      if (rect.bottom >= viewportTop && rect.top <= viewportBottom) visibleIndexes.push(index);
    });

    const firstVisible = visibleIndexes.length ? Math.min(...visibleIndexes) : recentStart;
    const lastVisible = visibleIndexes.length ? Math.max(...visibleIndexes) : records.length - 1;
    const keepStart = Math.max(0, firstVisible - settings.overscan);
    const keepEnd = Math.min(records.length - 1, lastVisible + settings.overscan);

    records.forEach((record, index) => {
      const keep = (index >= keepStart && index <= keepEnd) || index >= recentStart;
      if (keep) restore(record); else virtualize(record);
    });
  };

  const schedule = () => {
    if (state.paused || state.ticking) return;
    state.ticking = true;
    requestAnimationFrame(update);
  };

  const checkConnectionStall = () => {
    if (state.paused || !settings.autoRecoverStall || document.visibilityState !== 'visible' || isGenerating() || isWaitingForCompletedReply()) { state.stallSince = 0; return; }
    const stalled = /数据连接中断|正在等待数据传输|等待数据传输|connection interrupted|waiting for data|network connection was lost/i.test(document.body?.innerText || '');
    if (!stalled) { state.stallSince = 0; return; }
    if (!state.stallSince) state.stallSince = Date.now();
    if (Date.now() - state.stallSince > 30000 && Date.now() - state.lastRecoveryAt > 120000) {
      state.lastRecoveryAt = Date.now();
      state.stallSince = 0;
      location.reload();
    }
  };

  const prepareForBackground = () => {
    if (state.paused) return;
    resetForRouteChange();
    discoverMessages();
    if (settings.enabled && !isGenerating() && !isWaitingForCompletedReply()) {
      const keep = Math.max(2, settings.keepRecent);
      const keepStart = Math.max(0, state.records.length - keep);
      state.records.forEach((record, index) => { if (index < keepStart) virtualize(record); else restore(record); });
    }
    state.paused = true;
    state.ticking = false;
  };

  const suspend = () => { state.paused = true; state.ticking = false; };
  const resume = () => { state.paused = false; schedule(); };

  window.GPTWebKitLongConversation = {
    restoreAll,
    getAllMessageNodes: () => state.records.map((record) => record.node).filter(Boolean),
    schedule,
    openSettings,
    getSettings: () => ({ ...settings }),
    isGenerating,
    isWaitingForCompletedReply,
    forceLatestVisible,
    beginPinLatest,
    prepareForBackground,
    suspend,
    resume
  };

  addEventListener('touchstart', (event) => { state.touchStartY = event.touches?.[0]?.clientY || 0; }, { passive: true, capture: true });
  addEventListener('touchmove', (event) => {
    if (!state.pinLatest || !state.reachedBottom || state.paused) return;
    const y = event.touches?.[0]?.clientY || 0;
    if (y - state.touchStartY > 45) {
      state.pinLatest = false;
      state.userCancelledPin = true;
    }
  }, { passive: true, capture: true });
  addEventListener('wheel', (event) => {
    if (state.pinLatest && state.reachedBottom && event.deltaY < -20) {
      state.pinLatest = false;
      state.userCancelledPin = true;
    }
  }, { passive: true, capture: true });
  addEventListener('scroll', schedule, true);
  addEventListener('resize', schedule, { passive: true });
  addEventListener('popstate', () => setTimeout(schedule, 0));
  addEventListener('visibilitychange', () => { if (document.visibilityState === 'visible') resume(); else prepareForBackground(); });

  for (const method of ['pushState', 'replaceState']) {
    const original = history[method];
    if (typeof original !== 'function') continue;
    history[method] = function(...args) {
      const result = original.apply(this, args);
      setTimeout(schedule, 0);
      return result;
    };
  }

  const start = () => {
    installCSS();
    new MutationObserver(schedule).observe(document.documentElement, { childList: true, subtree: true, characterData: true });
    setInterval(() => { if (!state.paused && (state.pinLatest || isWaitingForCompletedReply())) forceLatestVisible(); }, 180);
    setInterval(checkConnectionStall, 2500);
    schedule();
  };

  if (document.documentElement) start(); else addEventListener('DOMContentLoaded', start, { once: true });
})();
