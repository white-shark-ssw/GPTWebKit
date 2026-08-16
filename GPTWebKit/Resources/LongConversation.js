(() => {
  'use strict';
  if (window.GPTWebKitLongConversation) return;

  const STORAGE_KEY = 'gptwebkit.longConversation.settings.v3';
  const defaults = { enabled: true, minMessages: 6, overscan: 1, keepRecent: 3, fastFollowLatest: true, autoRecoverStall: false };
  let settings = { ...defaults };
  try { settings = { ...defaults, ...JSON.parse(localStorage.getItem(STORAGE_KEY) || '{}') }; } catch (_) {}

  const state = { records: [], knownNodes: new WeakSet(), ticking: false, suspended: false, url: location.href, routeStartedAt: Date.now(), userInteracted: false, lastCount: 0, stallSince: 0, lastRecoveryAt: 0, wasGenerating: false };

  const installCSS = () => {
    if (document.getElementById('gptwebkit-long-conversation-style')) return;
    const style = document.createElement('style');
    style.id = 'gptwebkit-long-conversation-style';
    style.textContent = `
      main [data-message-author-role], main [data-testid^="conversation-turn-"], main article {
        content-visibility: auto;
        contain-intrinsic-size: auto 520px;
      }
      [data-gptwebkit-placeholder="1"] { content-visibility: auto; contain: layout style paint; }
      #gptwebkit-opt-button { position:fixed; right:4px; top:48%; z-index:2147483000; width:32px; height:42px; border:0; border-radius:12px 0 0 12px; background:rgba(0,0,0,.42); color:white; font-size:17px; opacity:.55; }
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

  const openSettings = () => {
    document.getElementById('gptwebkit-opt-panel')?.remove();
    const panel = document.createElement('div');
    panel.id = 'gptwebkit-opt-panel';
    panel.innerHTML = `<div id="gptwebkit-opt-card">
      <h3>长对话优化</h3>
      <label><span>启用优化</span><input data-k="enabled" type="checkbox" ${settings.enabled ? 'checked' : ''}></label>
      <label><span>快速跟随到最新消息</span><input data-k="fastFollowLatest" type="checkbox" ${settings.fastFollowLatest ? 'checked' : ''}></label>
      <label><span>连接中断自动恢复</span><input data-k="autoRecoverStall" type="checkbox" ${settings.autoRecoverStall ? 'checked' : ''}></label>
      <div class="hint">生成/思考过程中永远不会自动刷新；自动恢复默认关闭，避免误伤流式回答。</div>
      <label><span>始终保留最近消息</span><input data-k="keepRecent" type="number" min="2" max="12" value="${settings.keepRecent}"></label>
      <label><span>上下预留消息</span><input data-k="overscan" type="number" min="0" max="8" value="${settings.overscan}"></label>
      <div class="actions"><button data-a="reset">恢复默认</button><button data-a="close">完成</button></div>
    </div>`;
    panel.addEventListener('click', (event) => { if (event.target === panel) panel.remove(); });
    panel.querySelectorAll('[data-k]').forEach((input) => input.addEventListener('change', () => {
      const key = input.dataset.k;
      settings[key] = input.type === 'checkbox' ? input.checked : Math.max(Number(input.min || 0), Math.min(Number(input.max || 99), Number(input.value)));
      saveSettings(); schedule();
    }));
    panel.querySelector('[data-a="reset"]').addEventListener('click', () => { settings = { ...defaults }; saveSettings(); panel.remove(); restoreAll(); setTimeout(openSettings, 0); });
    panel.querySelector('[data-a="close"]').addEventListener('click', () => panel.remove());
    document.body.appendChild(panel);
  };

  const installSettingsButton = () => {
    if (document.getElementById('gptwebkit-opt-button') || !document.body) return;
    const button = document.createElement('button');
    button.id = 'gptwebkit-opt-button';
    button.textContent = '⚙︎';
    button.title = '长对话优化设置';
    button.addEventListener('click', openSettings);
    document.body.appendChild(button);
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

  const scrollRoot = () => {
    let root = document.scrollingElement;
    for (const candidate of document.querySelectorAll('main, main *')) {
      const style = getComputedStyle(candidate);
      if (/(auto|scroll|overlay)/.test(style.overflowY) && candidate.scrollHeight > candidate.clientHeight * 1.2) root = candidate;
    }
    return root;
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

  const resetForRouteChange = () => {
    if (state.url === location.href) return;
    restoreAll();
    state.url = location.href;
    state.records = [];
    state.knownNodes = new WeakSet();
    state.routeStartedAt = Date.now();
    state.userInteracted = false;
    state.lastCount = 0;
    state.stallSince = 0;
    state.wasGenerating = false;
  };

  const followLatestDuringInitialLoad = (root, count, generating) => {
    if (generating || !settings.fastFollowLatest || state.userInteracted || Date.now() - state.routeStartedAt > 10000 || count === state.lastCount) return;
    state.lastCount = count;
    requestAnimationFrame(() => {
      if (root === document.scrollingElement) window.scrollTo(0, document.documentElement.scrollHeight);
      else root.scrollTop = root.scrollHeight;
    });
  };

  const update = () => {
    state.ticking = false;
    if (state.suspended) return;
    resetForRouteChange();
    installSettingsButton();
    discoverMessages();
    const records = state.records;
    const root = scrollRoot();
    const generating = isGenerating();

    if (generating) {
      state.wasGenerating = true;
      state.stallSince = 0;
      restoreRecent(Math.max(settings.keepRecent + 5, 8));
      return;
    }
    if (state.wasGenerating) {
      state.wasGenerating = false;
      state.routeStartedAt = Date.now();
      state.userInteracted = true;
    }

    followLatestDuringInitialLoad(root, records.length, false);
    if (!settings.enabled) { restoreAll(); return; }
    if (records.length < settings.minMessages) return;

    const viewportTop = root === document.scrollingElement ? 0 : root.getBoundingClientRect().top;
    const viewportBottom = root === document.scrollingElement ? innerHeight : root.getBoundingClientRect().bottom;
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
    if (state.ticking) return;
    state.ticking = true;
    requestAnimationFrame(update);
  };

  const checkConnectionStall = () => {
    if (!settings.autoRecoverStall || document.visibilityState !== 'visible' || isGenerating()) { state.stallSince = 0; return; }
    const text = document.body?.innerText || '';
    const stalled = /数据连接中断|正在等待数据传输|等待数据传输|connection interrupted|waiting for data|network connection was lost/i.test(text);
    if (!stalled) { state.stallSince = 0; return; }
    if (!state.stallSince) state.stallSince = Date.now();
    if (Date.now() - state.stallSince > 30000 && Date.now() - state.lastRecoveryAt > 120000) {
      state.lastRecoveryAt = Date.now();
      state.stallSince = 0;
      location.reload();
    }
  };

  window.GPTWebKitLongConversation = { restoreAll, getAllMessageNodes: () => state.records.map((record) => record.node).filter(Boolean), schedule, openSettings, getSettings: () => ({ ...settings }), isGenerating };

  const userTouched = () => { if (Date.now() - state.routeStartedAt > 600) state.userInteracted = true; };
  addEventListener('touchstart', userTouched, { passive: true, capture: true });
  addEventListener('pointerdown', userTouched, { passive: true, capture: true });
  addEventListener('wheel', userTouched, { passive: true, capture: true });
  addEventListener('scroll', schedule, true);
  addEventListener('resize', schedule, { passive: true });

  const start = () => {
    installCSS();
    installSettingsButton();
    new MutationObserver(schedule).observe(document.documentElement, { childList: true, subtree: true });
    setInterval(checkConnectionStall, 3000);
    schedule();
  };
  if (document.documentElement) start(); else addEventListener('DOMContentLoaded', start, { once: true });
})();
