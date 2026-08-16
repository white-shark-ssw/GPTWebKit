(() => {
  'use strict';
  if (window.GPTWebKitLongConversation || window.__GPTWebKitTailBootstrap) return;
  window.__GPTWebKitTailBootstrap = true;

  const SETTINGS_KEY = 'gptwebkit.tail.settings.v1';
  const defaults = { enabled: true, initialVisible: 2, rebaseThreshold: 6, reduceMotion: true };
  const clampEven = (value, min = 2, max = 20) => {
    let n = Number(value);
    if (!Number.isFinite(n)) n = min;
    n = Math.max(min, Math.min(max, Math.round(n)));
    if (n % 2 !== 0) n += 1;
    return Math.max(min, Math.min(max, n));
  };
  let settings = { ...defaults };
  try {
    const stored = JSON.parse(localStorage.getItem(SETTINGS_KEY) || '{}');
    settings = { ...defaults, ...stored, initialVisible: clampEven(stored.initialVisible ?? defaults.initialVisible), rebaseThreshold: 6 };
  } catch (_) {}

  const saveSettings = () => {
    settings.initialVisible = clampEven(settings.initialVisible);
    settings.rebaseThreshold = 6;
    try { localStorage.setItem(SETTINGS_KEY, JSON.stringify(settings)); } catch (_) {}
  };

  const conversationIdFromPath = (pathname = location.pathname) => pathname.match(/\/c\/([^/?#]+)/)?.[1] || '';
  const historyKey = (id) => `gptwebkit.tail.history.${id}`;
  const rebaseKey = (id) => `gptwebkit.tail.rebase.${id}`;
  const readHistoryLimit = (id) => {
    if (!id) return settings.initialVisible;
    try {
      const value = Number(sessionStorage.getItem(historyKey(id)) || 0);
      return value >= settings.initialVisible ? clampEven(value, settings.initialVisible, 100) : settings.initialVisible;
    } catch (_) { return settings.initialVisible; }
  };
  const writeHistoryLimit = (id, value) => {
    if (!id) return;
    try {
      const limit = clampEven(value, settings.initialVisible, 100);
      if (limit <= settings.initialVisible) sessionStorage.removeItem(historyKey(id));
      else sessionStorage.setItem(historyKey(id), String(limit));
    } catch (_) {}
  };
  const clearHistoryLimit = (id) => { if (id) { try { sessionStorage.removeItem(historyKey(id)); } catch (_) {} } };
  const currentLimit = () => readHistoryLimit(conversationIdFromPath());
  const historyMode = () => currentLimit() > settings.initialVisible;

  const TailProxy = (() => {
    if (window.GPTWebKitTailProxy) return window.GPTWebKitTailProxy;
    const nativeFetch = window.fetch.bind(window);
    const requestURLs = new Map();
    const state = { lastConversationId: '', lastOriginalCurrentNode: '', lastTrimmedVisible: 0, lastTotalVisible: 0, lastProxyAt: 0, lastBypassedReason: '' };
    const visibleRole = (node) => {
      const role = node?.message?.author?.role;
      return role === 'user' || role === 'assistant' ? role : '';
    };
    const containerOf = (data) => {
      if (data?.mapping && typeof data.mapping === 'object') return data;
      if (data?.conversation?.mapping && typeof data.conversation.mapping === 'object') return data.conversation;
      return null;
    };
    const walkCurrentPath = (mapping, currentNode) => {
      const reversed = [];
      const visited = new Set();
      let id = currentNode;
      while (id && mapping[id] && !visited.has(id)) {
        visited.add(id);
        reversed.push(id);
        id = mapping[id]?.parent || null;
      }
      reversed.reverse();
      return reversed;
    };
    const turnStartsForPath = (path, mapping) => {
      const starts = [];
      let lastRole = '';
      for (let i = 0; i < path.length; i++) {
        const role = visibleRole(mapping[path[i]]);
        if (!role) continue;
        if (role !== lastRole) starts.push(i);
        lastRole = role;
      }
      return starts;
    };
    const countTurns = (path, mapping) => turnStartsForPath(path, mapping).length;
    const trimConversation = (data, limit) => {
      const container = containerOf(data);
      const mapping = container?.mapping;
      const currentNode = container?.current_node;
      if (!container || !mapping || !currentNode || !mapping[currentNode]) return { data, trimmed: false, reason: 'unrecognized' };
      const path = walkCurrentPath(mapping, currentNode);
      if (!path.length) return { data, trimmed: false, reason: 'empty-path' };
      const turnStarts = turnStartsForPath(path, mapping);
      state.lastTotalVisible = turnStarts.length;
      if (turnStarts.length <= limit) return { data, trimmed: false, reason: 'small' };

      const cutPathIndex = turnStarts[Math.max(0, turnStarts.length - limit)];
      const firstKeptId = path[cutPathIndex];
      const firstParentId = mapping[firstKeptId]?.parent;
      if (firstParentId && Array.isArray(mapping[firstParentId]?.children) && mapping[firstParentId].children.length > 1) return { data, trimmed: false, reason: 'recent-branch-parent' };
      const keptPath = path.slice(cutPathIndex);
      for (const id of keptPath) {
        const node = mapping[id];
        if (Array.isArray(node?.children) && node.children.length > 1) return { data, trimmed: false, reason: 'recent-branch' };
      }

      const originalRootId = container.root && mapping[container.root] ? container.root : path[0];
      const out = {};
      if (originalRootId && mapping[originalRootId] && originalRootId !== firstKeptId) out[originalRootId] = { ...mapping[originalRootId], parent: null, children: firstKeptId ? [firstKeptId] : [] };
      for (let i = 0; i < keptPath.length; i++) {
        const id = keptPath[i];
        const source = mapping[id];
        if (!source) return { data, trimmed: false, reason: 'missing-node' };
        const previous = i > 0 ? keptPath[i - 1] : (originalRootId !== firstKeptId ? originalRootId : null);
        const next = keptPath[i + 1] || null;
        out[id] = { ...source, parent: previous, children: next ? [next] : [] };
      }

      const copy = { ...data };
      if (container === data) {
        copy.mapping = out;
        copy.current_node = currentNode;
        if (originalRootId) copy.root = originalRootId;
      } else {
        copy.conversation = { ...data.conversation, mapping: out, current_node: currentNode };
        if (originalRootId) copy.conversation.root = originalRootId;
      }
      state.lastTrimmedVisible = countTurns(keptPath, mapping);
      return { data: copy, trimmed: true, reason: '' };
    };
    const parseRequest = (input, init) => {
      try {
        let urlString = '';
        let method = 'GET';
        if (input instanceof Request) { urlString = input.url; method = String(init?.method || input.method || 'GET').toUpperCase(); }
        else if (input instanceof URL) { urlString = input.href; method = String(init?.method || 'GET').toUpperCase(); }
        else { urlString = String(input || ''); method = String(init?.method || 'GET').toUpperCase(); }
        const url = new URL(urlString, location.href);
        const match = url.pathname.match(/^\/backend-api\/(conversation|shared_conversation)\/([^/]+)\/?$/);
        return match && method === 'GET' ? { url, id: decodeURIComponent(match[2]), type: match[1] } : null;
      } catch (_) { return null; }
    };
    const rebuildResponse = (original, text) => {
      const headers = new Headers(original.headers);
      headers.delete('content-length');
      headers.delete('content-encoding');
      headers.set('content-type', 'application/json; charset=utf-8');
      const response = new Response(text, { status: original.status, statusText: original.statusText, headers });
      try { if (original.url) Object.defineProperty(response, 'url', { value: original.url }); } catch (_) {}
      return response;
    };

    window.fetch = async (...args) => {
      const request = parseRequest(args[0], args[1]);
      if (!request || !settings.enabled) return nativeFetch(...args);
      requestURLs.set(request.id, request.url.href);
      const response = await nativeFetch(...args);
      const type = response.headers.get('content-type') || '';
      if (!/json/i.test(type)) return response;
      let text = '';
      try {
        text = await response.text();
        const data = JSON.parse(text);
        const container = containerOf(data);
        state.lastConversationId = request.id;
        state.lastOriginalCurrentNode = container?.current_node || '';
        state.lastProxyAt = Date.now();
        const result = trimConversation(data, readHistoryLimit(request.id));
        state.lastBypassedReason = result.trimmed ? '' : result.reason;
        return rebuildResponse(response, result.trimmed ? JSON.stringify(result.data) : text);
      } catch (_) {
        return text ? rebuildResponse(response, text) : response;
      }
    };

    const fetchFullConversation = async (id = conversationIdFromPath()) => {
      if (!id) throw new Error('当前页面不是会话页面');
      const url = requestURLs.get(id) || `/backend-api/conversation/${encodeURIComponent(id)}`;
      const response = await nativeFetch(url, { method: 'GET', credentials: 'include', cache: 'no-store' });
      if (!response.ok) throw new Error(`读取完整会话失败 (${response.status})`);
      const type = response.headers.get('content-type') || '';
      if (!/json/i.test(type)) throw new Error('完整会话返回内容不是 JSON');
      return response.json();
    };

    const api = {
      getSettings: () => ({ ...settings }),
      updateSettings: (patch = {}) => {
        settings = { ...settings, ...patch, initialVisible: clampEven(patch.initialVisible ?? settings.initialVisible), rebaseThreshold: 6 };
        saveSettings();
        return { ...settings };
      },
      currentConversationId: () => conversationIdFromPath(),
      currentLimit,
      isHistoryMode: historyMode,
      expandHistory: () => {
        const id = conversationIdFromPath();
        if (!id) return false;
        writeHistoryLimit(id, currentLimit() + 2);
        location.reload();
        return true;
      },
      returnLatest: () => {
        const id = conversationIdFromPath();
        if (!id) return false;
        clearHistoryLimit(id);
        location.reload();
        return true;
      },
      exitHistoryModeWithoutReload: () => clearHistoryLimit(conversationIdFromPath()),
      clearConversationHistory: clearHistoryLimit,
      fetchFullConversation,
      getStatus: () => ({ ...state, currentLimit: currentLimit(), historyMode: historyMode() })
    };
    window.GPTWebKitTailProxy = api;
    return api;
  })();

  const state = {
    paused: document.visibilityState !== 'visible',
    scheduled: false,
    timer: 0,
    routeId: conversationIdFromPath(),
    lastNodeCount: 0,
    lastMutationAt: Date.now(),
    pinUntil: Date.now() + 2600,
    stableBottomTicks: 0,
    rebasePending: false,
    userInteracted: false
  };

  const installCSS = () => {
    let style = document.getElementById('gptwebkit-tail-style');
    if (!style) {
      style = document.createElement('style');
      style.id = 'gptwebkit-tail-style';
      (document.head || document.documentElement).appendChild(style);
    }
    style.textContent = `
      .gptwebkit-tail-hidden { display:none !important; }
      ${settings.reduceMotion ? 'main [data-message-author-role] *, main [data-testid^="conversation-turn-"] * { animation-duration:0.001ms !important; animation-iteration-count:1 !important; transition-duration:0.001ms !important; scroll-behavior:auto !important; }' : ''}
      #gptwebkit-opt-panel { position:fixed; z-index:2147483640; inset:0; display:flex; align-items:center; justify-content:center; background:rgba(0,0,0,.28); padding:20px; }
      #gptwebkit-opt-card { width:min(350px,92vw); border-radius:18px; background:Canvas; color:CanvasText; box-shadow:0 12px 50px rgba(0,0,0,.28); padding:18px; font:15px -apple-system,BlinkMacSystemFont,sans-serif; }
      #gptwebkit-opt-card h3 { margin:0 0 12px; font-size:18px; }
      #gptwebkit-opt-card label { display:flex; align-items:center; justify-content:space-between; min-height:44px; gap:16px; }
      #gptwebkit-opt-card input[type="number"] { width:72px; font-size:16px; }
      #gptwebkit-opt-card .hint { margin:7px 0; color:#888; font-size:12px; line-height:1.5; }
      #gptwebkit-opt-card .history { display:flex; gap:8px; margin-top:12px; }
      #gptwebkit-opt-card .history button { flex:1; }
      #gptwebkit-opt-card .actions { display:flex; justify-content:flex-end; gap:10px; margin-top:14px; }
      #gptwebkit-opt-card button { min-height:38px; border:0; border-radius:10px; padding:8px 12px; font-size:15px; }
    `;
  };

  const messageNodes = () => {
    const turns = Array.from(document.querySelectorAll('main [data-testid^="conversation-turn-"]'));
    if (turns.length) return turns;
    return Array.from(document.querySelectorAll('main [data-message-author-role]')).filter((node) => !node.parentElement?.closest?.('[data-message-author-role]'));
  };
  const roleOf = (node) => {
    const role = node?.getAttribute?.('data-message-author-role') || node?.querySelector?.('[data-message-author-role]')?.getAttribute?.('data-message-author-role') || '';
    return role === 'user' || role === 'assistant' ? role : '';
  };
  const semanticTurnStarts = (nodes) => {
    const starts = [];
    let lastRole = '';
    for (let i = 0; i < nodes.length; i++) {
      const role = roleOf(nodes[i]);
      if (!role) continue;
      if (role !== lastRole) starts.push(i);
      lastRole = role;
    }
    return starts;
  };
  const semanticTurnCount = (nodes) => semanticTurnStarts(nodes).length;
  const lastMessageId = (nodes = messageNodes()) => {
    const node = nodes[nodes.length - 1];
    return node?.getAttribute?.('data-message-id') || node?.querySelector?.('[data-message-id]')?.getAttribute?.('data-message-id') || node?.getAttribute?.('data-testid') || '';
  };
  const isGenerating = () => !!document.querySelector('[data-testid="stop-button"], button[aria-label*="stop generating" i], button[aria-label*="停止生成" i], button[title*="stop generating" i]');
  const promptNode = () => document.querySelector('#prompt-textarea, textarea, [contenteditable="true"][data-placeholder]');
  const draftText = () => {
    const node = promptNode();
    return (node instanceof HTMLTextAreaElement ? node.value : (node?.innerText || node?.textContent || '')).trim();
  };

  const applyWindow = (nodes) => {
    if (!settings.enabled) {
      nodes.forEach((node) => node.classList.remove('gptwebkit-tail-hidden'));
      return Number.MAX_SAFE_INTEGER;
    }
    const limit = TailProxy.currentLimit();
    const starts = semanticTurnStarts(nodes);
    if (!starts.length || starts.length <= limit) {
      nodes.forEach((node) => node.classList.remove('gptwebkit-tail-hidden'));
      return limit;
    }
    let cutIndex = starts[Math.max(0, starts.length - limit)];

    // 生成中的回复可能拆成多个 assistant/reasoning DOM 节点。
    // 无论内部拆成多少块，都必须保留“本轮用户问题 + 本轮回答”的完整区域。
    if (isGenerating()) {
      for (let i = nodes.length - 1; i >= 0; i--) {
        if (roleOf(nodes[i]) === 'user') { cutIndex = Math.min(cutIndex, i); break; }
      }
    }
    nodes.forEach((node, index) => node.classList.toggle('gptwebkit-tail-hidden', index < cutIndex));
    return limit;
  };

  const pinLatest = (nodes) => {
    if (!nodes.length || Date.now() > state.pinUntil || state.paused || state.userInteracted) return;
    const last = nodes[nodes.length - 1];
    try { last.scrollIntoView({ block: 'end', inline: 'nearest', behavior: 'auto' }); } catch (_) {}
    const rect = last.getBoundingClientRect();
    if (rect.bottom <= innerHeight + 12 && rect.bottom >= innerHeight * 0.45) state.stableBottomTicks++;
    else state.stableBottomTicks = 0;
    if (state.stableBottomTicks >= 3) state.pinUntil = 0;
  };

  const canRebase = (nodes) => {
    if (state.paused || document.visibilityState !== 'visible' || !settings.enabled || TailProxy.isHistoryMode()) return false;
    if (semanticTurnCount(nodes) < settings.rebaseThreshold || isGenerating() || draftText()) return false;
    if (document.querySelector('[role="dialog"], [data-radix-portal] [role="menu"]')) return false;
    if ((window.getSelection?.()?.toString() || '').trim()) return false;
    if (Date.now() - state.lastMutationAt < 900) return false;
    return true;
  };
  const requestRebase = (nodes) => {
    const id = conversationIdFromPath();
    if (!id || state.rebasePending || !canRebase(nodes)) return;
    let last = 0;
    try { last = Number(sessionStorage.getItem(rebaseKey(id)) || 0); } catch (_) {}
    if (Date.now() - last < 8000) return;
    state.rebasePending = true;
    try { sessionStorage.setItem(rebaseKey(id), String(Date.now())); } catch (_) {}
    setTimeout(() => {
      const fresh = messageNodes();
      if (!canRebase(fresh) || conversationIdFromPath() !== id) { state.rebasePending = false; return; }
      location.reload();
    }, 180);
  };
  const handleRouteChange = () => {
    const nextId = conversationIdFromPath();
    if (nextId === state.routeId) return;
    if (state.routeId) TailProxy.clearConversationHistory(state.routeId);
    state.routeId = nextId;
    state.lastNodeCount = 0;
    state.rebasePending = false;
    state.pinUntil = Date.now() + 2600;
    state.stableBottomTicks = 0;
    state.userInteracted = false;
  };
  const update = () => {
    state.scheduled = false;
    if (state.paused) return;
    handleRouteChange();
    const nodes = messageNodes();
    if (!nodes.length) return;
    const wasHistory = TailProxy.isHistoryMode();
    const lastRole = roleOf(nodes[nodes.length - 1]);
    if (wasHistory && nodes.length > state.lastNodeCount && lastRole === 'user') TailProxy.exitHistoryModeWithoutReload();
    applyWindow(nodes);
    pinLatest(nodes);
    state.lastNodeCount = nodes.length;
    requestRebase(nodes);
  };
  const schedule = (delay = 70) => {
    if (state.paused) return;
    if (state.timer) clearTimeout(state.timer);
    state.timer = setTimeout(() => {
      state.timer = 0;
      if (state.scheduled) return;
      state.scheduled = true;
      requestAnimationFrame(update);
    }, delay);
  };

  const openSettings = () => {
    document.getElementById('gptwebkit-opt-panel')?.remove();
    const panel = document.createElement('div');
    panel.id = 'gptwebkit-opt-panel';
    const limit = TailProxy.currentLimit();
    panel.innerHTML = `<div id="gptwebkit-opt-card">
      <h3>长对话性能</h3>
      <label><span>启用 Tail Proxy</span><input data-k="enabled" type="checkbox" ${settings.enabled ? 'checked' : ''}></label>
      <label><span>初始加载消息数</span><input data-k="initialVisible" type="number" min="2" max="20" step="2" value="${settings.initialVisible}"></label>
      <label><span>减少消息区动效</span><input data-k="reduceMotion" type="checkbox" ${settings.reduceMotion ? 'checked' : ''}></label>
      <div class="hint">消息数按 User / Assistant 角色轮次计算。Thinking、Reasoning、Tool 等内部节点不占名额；默认始终保留本轮问题和本轮回答。React 累积到 6 条且安全时自动重置。</div>
      <div class="hint">当前会话可见上限：${limit} 条${TailProxy.isHistoryMode() ? '（历史浏览）' : ''}</div>
      <div class="history"><button data-a="older">加载更早 2 条</button><button data-a="latest">回到最新 ${settings.initialVisible} 条</button></div>
      <div class="actions"><button data-a="reset">恢复默认</button><button data-a="close">完成</button></div>
    </div>`;
    let needsReload = false;
    panel.querySelectorAll('[data-k]').forEach((input) => input.addEventListener('change', () => {
      const key = input.dataset.k;
      if (key === 'initialVisible') settings.initialVisible = clampEven(input.value);
      else settings[key] = input.checked;
      TailProxy.updateSettings(settings);
      installCSS();
      needsReload = true;
    }));
    panel.querySelector('[data-a="older"]').addEventListener('click', () => TailProxy.expandHistory());
    panel.querySelector('[data-a="latest"]').addEventListener('click', () => TailProxy.returnLatest());
    panel.querySelector('[data-a="reset"]').addEventListener('click', () => {
      settings = { ...defaults };
      TailProxy.updateSettings(settings);
      clearHistoryLimit(conversationIdFromPath());
      location.reload();
    });
    panel.querySelector('[data-a="close"]').addEventListener('click', () => {
      panel.remove();
      if (needsReload && conversationIdFromPath()) location.reload(); else schedule(0);
    });
    panel.addEventListener('click', (event) => { if (event.target === panel) { panel.remove(); if (needsReload && conversationIdFromPath()) location.reload(); } });
    document.body.appendChild(panel);
  };

  const prepareForBackground = () => {
    state.paused = true;
    if (state.timer) { clearTimeout(state.timer); state.timer = 0; }
  };
  const suspend = prepareForBackground;
  const resume = () => {
    state.paused = false;
    state.userInteracted = false;
    state.pinUntil = Date.now() + 900;
    schedule(0);
  };
  const restoreAll = () => messageNodes().forEach((node) => node.classList.remove('gptwebkit-tail-hidden'));
  const forceLatestVisible = () => pinLatest(messageNodes());
  const beginPinLatest = () => { state.userInteracted = false; state.pinUntil = Date.now() + 2600; state.stableBottomTicks = 0; schedule(0); };

  window.GPTWebKitLongConversation = {
    schedule,
    openSettings,
    getSettings: () => ({ ...settings }),
    getAllMessageNodes: messageNodes,
    isGenerating,
    isWaitingForCompletedReply: () => false,
    forceLatestVisible,
    beginPinLatest,
    prepareForBackground,
    suspend,
    resume,
    restoreAll,
    loadEarlier: () => TailProxy.expandHistory(),
    returnLatest: () => TailProxy.returnLatest(),
    getRebaseState: () => {
      const nodes = messageNodes();
      return { conversationId: conversationIdFromPath(), count: semanticTurnCount(nodes), visibleLimit: TailProxy.currentLimit(), historyMode: TailProxy.isHistoryMode(), generating: isGenerating(), draft: draftText(), lastMessageId: lastMessageId(nodes), safe: canRebase(nodes) };
    }
  };

  const patchHistory = () => {
    for (const method of ['pushState', 'replaceState']) {
      const original = history[method];
      if (typeof original !== 'function' || original.__gptwebkitPatched) continue;
      const wrapped = function(...args) {
        const result = original.apply(this, args);
        setTimeout(() => schedule(0), 0);
        return result;
      };
      wrapped.__gptwebkitPatched = true;
      history[method] = wrapped;
    }
    addEventListener('popstate', () => schedule(0));
  };
  const stopAutoPin = () => {
    state.userInteracted = true;
    state.pinUntil = 0;
  };
  const start = () => {
    installCSS();
    patchHistory();
    new MutationObserver(() => { state.lastMutationAt = Date.now(); schedule(); }).observe(document.documentElement, { childList: true, subtree: true });
    addEventListener('visibilitychange', () => document.visibilityState === 'visible' ? resume() : prepareForBackground());
    addEventListener('resize', () => schedule(80), { passive: true });
    addEventListener('touchstart', stopAutoPin, { passive: true, capture: true });
    addEventListener('wheel', stopAutoPin, { passive: true, capture: true });
    setInterval(() => { if (!state.paused) schedule(0); }, 1200);
    schedule(0);
  };

  if (document.documentElement) start(); else addEventListener('DOMContentLoaded', start, { once: true });
})();