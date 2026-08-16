(() => {
  'use strict';
  if (window.GPTWebKitLongConversation || window.__GPTWebKitTailBootstrap) return;
  window.__GPTWebKitTailBootstrap = true;

  const SETTINGS_KEY = 'gptwebkit.tail.settings.v2';
  const defaults = { enabled: true, initialRounds: 2, rebaseThreshold: 6, reduceMotion: true, optimizeSidebar: true };
  const clampRounds = (value, min = 1, max = 10) => {
    let n = Number(value);
    if (!Number.isFinite(n)) n = min;
    return Math.max(min, Math.min(max, Math.round(n)));
  };
  let settings = { ...defaults };
  try {
    const stored = JSON.parse(localStorage.getItem(SETTINGS_KEY) || '{}');
    settings = { ...defaults, ...stored, initialRounds: clampRounds(stored.initialRounds ?? defaults.initialRounds), rebaseThreshold: 6 };
  } catch (_) {}
  const saveSettings = () => {
    settings.initialRounds = clampRounds(settings.initialRounds);
    settings.rebaseThreshold = 6;
    try { localStorage.setItem(SETTINGS_KEY, JSON.stringify(settings)); } catch (_) {}
  };

  const conversationIdFromPath = (pathname = location.pathname) => pathname.match(/\/c\/([^/?#]+)/)?.[1] || '';
  const historyKey = (id) => `gptwebkit.tail.historyRounds.${id}`;
  const rebaseKey = (id) => `gptwebkit.tail.rebase.${id}`;
  const readHistoryRounds = (id) => {
    if (!id) return settings.initialRounds;
    try {
      const value = Number(sessionStorage.getItem(historyKey(id)) || 0);
      return value >= settings.initialRounds ? clampRounds(value, settings.initialRounds, 50) : settings.initialRounds;
    } catch (_) { return settings.initialRounds; }
  };
  const writeHistoryRounds = (id, value) => {
    if (!id) return;
    try {
      const rounds = clampRounds(value, settings.initialRounds, 50);
      if (rounds <= settings.initialRounds) sessionStorage.removeItem(historyKey(id));
      else sessionStorage.setItem(historyKey(id), String(rounds));
    } catch (_) {}
  };
  const clearHistoryRounds = (id) => { if (id) { try { sessionStorage.removeItem(historyKey(id)); } catch (_) {} } };
  const currentRounds = () => readHistoryRounds(conversationIdFromPath());
  const historyMode = () => currentRounds() > settings.initialRounds;

  const TailProxy = (() => {
    if (window.GPTWebKitTailProxy) return window.GPTWebKitTailProxy;

    const nativeFetch = window.fetch.bind(window);
    const requestURLs = new Map();
    const state = {
      lastConversationId: '',
      lastOriginalCurrentNode: '',
      lastTrimmedRounds: 0,
      lastTotalRounds: 0,
      lastProxyAt: 0,
      lastBypassedReason: '',
      sidebarCacheAt: 0,
      sidebarCacheHits: 0
    };
    let sidebarCache = null;
    let sidebarPrewarmBusy = false;

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
    const roundStartsForPath = (path, mapping) => {
      const starts = [];
      let lastRole = '';
      for (let i = 0; i < path.length; i++) {
        const role = visibleRole(mapping[path[i]]);
        if (!role) continue;
        if (role === 'user' && lastRole !== 'user') starts.push(i);
        lastRole = role;
      }
      return starts;
    };
    const countMessageGroups = (path, mapping) => {
      let count = 0;
      let lastRole = '';
      for (const id of path) {
        const role = visibleRole(mapping[id]);
        if (!role) continue;
        if (role !== lastRole) count++;
        lastRole = role;
      }
      return count;
    };

    const trimConversation = (data, roundLimit) => {
      const container = containerOf(data);
      const mapping = container?.mapping;
      const currentNode = container?.current_node;
      if (!container || !mapping || !currentNode || !mapping[currentNode]) return { data, trimmed: false, reason: 'unrecognized' };
      const path = walkCurrentPath(mapping, currentNode);
      if (!path.length) return { data, trimmed: false, reason: 'empty-path' };

      const roundStarts = roundStartsForPath(path, mapping);
      state.lastTotalRounds = roundStarts.length;
      if (!roundStarts.length || roundStarts.length <= roundLimit) return { data, trimmed: false, reason: 'small' };

      const cutPathIndex = roundStarts[Math.max(0, roundStarts.length - roundLimit)];
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
      state.lastTrimmedRounds = Math.min(roundLimit, roundStarts.length);
      return { data: copy, trimmed: true, reason: '', messageGroups: countMessageGroups(keptPath, mapping) };
    };

    const parseRequest = (input, init) => {
      try {
        let urlString = '';
        let method = 'GET';
        if (input instanceof Request) { urlString = input.url; method = String(init?.method || input.method || 'GET').toUpperCase(); }
        else if (input instanceof URL) { urlString = input.href; method = String(init?.method || 'GET').toUpperCase(); }
        else { urlString = String(input || ''); method = String(init?.method || 'GET').toUpperCase(); }
        const url = new URL(urlString, location.href);
        const conversation = url.pathname.match(/^\/backend-api\/(conversation|shared_conversation)\/([^/]+)\/?$/);
        const history = url.pathname === '/backend-api/conversations';
        return { url, method, conversation: conversation && method === 'GET' ? { id: decodeURIComponent(conversation[2]), type: conversation[1] } : null, history: history && method === 'GET' };
      } catch (_) { return { url: null, method: 'GET', conversation: null, history: false }; }
    };
    const rebuildResponse = (original, text) => {
      const headers = new Headers(original.headers);
      headers.delete('content-length');
      headers.delete('content-encoding');
      const response = new Response(text, { status: original.status, statusText: original.statusText, headers });
      try { if (original.url) Object.defineProperty(response, 'url', { value: original.url }); } catch (_) {}
      return response;
    };
    const rebuildCachedResponse = (entry) => new Response(entry.text, { status: entry.status, statusText: entry.statusText, headers: new Headers(entry.headers) });
    const isSidebarFirstPage = (url) => {
      if (!url || url.pathname !== '/backend-api/conversations') return false;
      const offset = Number(url.searchParams.get('offset') || 0);
      const limit = Number(url.searchParams.get('limit') || 28);
      return offset === 0 && limit > 0 && limit <= 28;
    };
    const cacheSidebarResponse = async (url, response) => {
      if (!isSidebarFirstPage(url) || !response.ok) return;
      try {
        const clone = response.clone();
        const text = await clone.text();
        if (!text || text.length > 1024 * 1024) return;
        sidebarCache = { href:url.href, text, status:clone.status, statusText:clone.statusText, headers:Array.from(clone.headers.entries()), at:Date.now() };
        state.sidebarCacheAt = sidebarCache.at;
      } catch (_) {}
    };
    const prewarmSidebar = async () => {
      if (!settings.optimizeSidebar || sidebarPrewarmBusy || document.visibilityState !== 'visible') return;
      if (sidebarCache && Date.now() - sidebarCache.at < 25000) return;
      sidebarPrewarmBusy = true;
      try {
        const url = new URL('/backend-api/conversations?offset=0&limit=28&order=updated&is_archived=false&is_starred=false', location.origin);
        const response = await nativeFetch(url.href, { method:'GET', credentials:'include' });
        await cacheSidebarResponse(url, response);
      } catch (_) {} finally { sidebarPrewarmBusy = false; }
    };
    const invalidateSidebar = () => { sidebarCache = null; state.sidebarCacheAt = 0; };

    window.fetch = async (...args) => {
      const parsed = parseRequest(args[0], args[1]);
      if (parsed.method !== 'GET' && parsed.url?.pathname.startsWith('/backend-api/conversation')) {
        invalidateSidebar();
        setTimeout(prewarmSidebar, 1800);
      }
      if (parsed.history && settings.optimizeSidebar && sidebarCache && sidebarCache.href === parsed.url.href && Date.now() - sidebarCache.at < 30000) {
        state.sidebarCacheHits++;
        return rebuildCachedResponse(sidebarCache);
      }
      if (!parsed.conversation || !settings.enabled) {
        const response = await nativeFetch(...args);
        if (parsed.history && settings.optimizeSidebar) cacheSidebarResponse(parsed.url, response);
        return response;
      }

      const request = parsed.conversation;
      requestURLs.set(request.id, parsed.url.href);
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
        const result = trimConversation(data, readHistoryRounds(request.id));
        state.lastBypassedReason = result.trimmed ? '' : result.reason;
        return rebuildResponse(response, result.trimmed ? JSON.stringify(result.data) : text);
      } catch (_) {
        return text ? rebuildResponse(response, text) : response;
      }
    };

    const fetchFullConversation = async (id = conversationIdFromPath()) => {
      if (!id) throw new Error('当前页面不是会话页面');
      const url = requestURLs.get(id) || `/backend-api/conversation/${encodeURIComponent(id)}`;
      const response = await nativeFetch(url, { method:'GET', credentials:'include', cache:'no-store' });
      if (!response.ok) throw new Error(`读取完整会话失败 (${response.status})`);
      const type = response.headers.get('content-type') || '';
      if (!/json/i.test(type)) throw new Error('完整会话返回内容不是 JSON');
      return response.json();
    };

    const api = {
      getSettings: () => ({ ...settings }),
      updateSettings: (patch = {}) => {
        settings = { ...settings, ...patch, initialRounds:clampRounds(patch.initialRounds ?? settings.initialRounds), rebaseThreshold:6 };
        saveSettings();
        if (!settings.optimizeSidebar) invalidateSidebar(); else setTimeout(prewarmSidebar, 0);
        return { ...settings };
      },
      currentConversationId: () => conversationIdFromPath(),
      currentRounds,
      currentLimit: () => currentRounds() * 2,
      isHistoryMode: historyMode,
      expandHistory: () => {
        const id = conversationIdFromPath();
        if (!id) return false;
        writeHistoryRounds(id, currentRounds() + 1);
        location.reload();
        return true;
      },
      returnLatest: () => {
        const id = conversationIdFromPath();
        if (!id) return false;
        clearHistoryRounds(id);
        location.reload();
        return true;
      },
      exitHistoryModeWithoutReload: () => clearHistoryRounds(conversationIdFromPath()),
      clearConversationHistory: clearHistoryRounds,
      fetchFullConversation,
      prewarmSidebar,
      getStatus: () => ({ ...state, currentRounds:currentRounds(), historyMode:historyMode() })
    };
    window.GPTWebKitTailProxy = api;
    setTimeout(prewarmSidebar, 900);
    return api;
  })();

  const state = {
    paused: document.visibilityState !== 'visible',
    scheduled: false,
    timer: 0,
    idleTimer: 0,
    routeId: conversationIdFromPath(),
    lastNodeCount: 0,
    lastMutationAt: Date.now(),
    pinUntil: Date.now() + 2400,
    stableBottomTicks: 0,
    rebasePending: false,
    userInteracted: false,
    observedMain: null,
    mainObserver: null
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
    const main = document.querySelector('main');
    if (!main) return [];
    const turns = Array.from(main.querySelectorAll('[data-testid^="conversation-turn-"]'));
    if (turns.length) return turns;
    return Array.from(main.querySelectorAll('[data-message-author-role]')).filter((node) => !node.parentElement?.closest?.('[data-message-author-role]'));
  };
  const roleOf = (node) => {
    const role = node?.getAttribute?.('data-message-author-role') || node?.querySelector?.('[data-message-author-role]')?.getAttribute?.('data-message-author-role') || '';
    return role === 'user' || role === 'assistant' ? role : '';
  };
  const roundStartsForDOM = (nodes) => {
    const starts = [];
    let lastRole = '';
    for (let i = 0; i < nodes.length; i++) {
      const role = roleOf(nodes[i]);
      if (!role) continue;
      if (role === 'user' && lastRole !== 'user') starts.push(i);
      lastRole = role;
    }
    return starts;
  };
  const semanticMessageGroupCount = (nodes) => {
    let count = 0;
    let lastRole = '';
    for (const node of nodes) {
      const role = roleOf(node);
      if (!role) continue;
      if (role !== lastRole) count++;
      lastRole = role;
    }
    return count;
  };
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
    const rounds = TailProxy.currentRounds();
    const starts = roundStartsForDOM(nodes);
    if (!starts.length || starts.length <= rounds) {
      nodes.forEach((node) => node.classList.remove('gptwebkit-tail-hidden'));
      return rounds;
    }
    const cutIndex = starts[Math.max(0, starts.length - rounds)];
    nodes.forEach((node, index) => node.classList.toggle('gptwebkit-tail-hidden', index < cutIndex));
    return rounds;
  };

  const pinLatest = (nodes) => {
    if (!nodes.length || Date.now() > state.pinUntil || state.paused || state.userInteracted) return;
    const last = nodes[nodes.length - 1];
    try { last.scrollIntoView({ block:'end', inline:'nearest', behavior:'auto' }); } catch (_) {}
    const rect = last.getBoundingClientRect();
    if (rect.bottom <= innerHeight + 12 && rect.bottom >= innerHeight * 0.45) state.stableBottomTicks++;
    else state.stableBottomTicks = 0;
    if (state.stableBottomTicks >= 3) state.pinUntil = 0;
  };

  const canRebase = (nodes) => {
    if (state.paused || document.visibilityState !== 'visible' || !settings.enabled || TailProxy.isHistoryMode()) return false;
    if (semanticMessageGroupCount(nodes) < settings.rebaseThreshold || isGenerating() || draftText()) return false;
    if (document.querySelector('[role="dialog"], [data-radix-portal] [role="menu"]')) return false;
    if ((window.getSelection?.()?.toString() || '').trim()) return false;
    if (Date.now() - state.lastMutationAt < 900) return false;
    return true;
  };

  const requestRebase = (nodes) => {
    const id = conversationIdFromPath();
    if (!id || !canRebase(nodes)) return;
    if (window.webkit?.messageHandlers?.rebaseRequest) {
      try { window.dispatchEvent(new CustomEvent('gptwebkit:rebase-ready')); } catch (_) {}
      return;
    }
    if (state.rebasePending) return;
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

  const scheduleIdleCheck = () => {
    if (state.idleTimer) clearTimeout(state.idleTimer);
    state.idleTimer = setTimeout(() => {
      state.idleTimer = 0;
      schedule(0);
    }, 1050);
  };

  const ensureConversationObserver = () => {
    const main = document.querySelector('main');
    if (main === state.observedMain) return;
    state.mainObserver?.disconnect();
    state.observedMain = main;
    if (!main) return;
    state.mainObserver = new MutationObserver(() => {
      state.lastMutationAt = Date.now();
      schedule(isGenerating() ? 180 : 80);
      scheduleIdleCheck();
    });
    state.mainObserver.observe(main, { childList:true, subtree:true });
  };

  const handleRouteChange = () => {
    const nextId = conversationIdFromPath();
    if (nextId === state.routeId) return;
    if (state.routeId) TailProxy.clearConversationHistory(state.routeId);
    state.routeId = nextId;
    state.lastNodeCount = 0;
    state.rebasePending = false;
    state.pinUntil = Date.now() + 2400;
    state.stableBottomTicks = 0;
    state.userInteracted = false;
    ensureConversationObserver();
    setTimeout(() => TailProxy.prewarmSidebar?.(), 400);
  };

  const update = () => {
    state.scheduled = false;
    if (state.paused) return;
    handleRouteChange();
    ensureConversationObserver();
    const nodes = messageNodes();
    if (!nodes.length) return;
    const wasHistory = TailProxy.isHistoryMode();
    const lastRole = roleOf(nodes[nodes.length - 1]);
    if (wasHistory && nodes.length > state.lastNodeCount && lastRole === 'user') TailProxy.exitHistoryModeWithoutReload();
    applyWindow(nodes);
    pinLatest(nodes);
    state.lastNodeCount = nodes.length;
    requestRebase(nodes);
    try { window.dispatchEvent(new CustomEvent('gptwebkit:conversation-update')); } catch (_) {}
  };

  const schedule = (delay = 80) => {
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
    const rounds = TailProxy.currentRounds();
    panel.innerHTML = `<div id="gptwebkit-opt-card">
      <h3>长对话性能</h3>
      <label><span>启用 Tail Proxy</span><input data-k="enabled" type="checkbox" ${settings.enabled ? 'checked' : ''}></label>
      <label><span>最近保留对话轮数</span><input data-k="initialRounds" type="number" min="1" max="10" step="1" value="${settings.initialRounds}"></label>
      <label><span>优化侧边栏</span><input data-k="optimizeSidebar" type="checkbox" ${settings.optimizeSidebar ? 'checked' : ''}></label>
      <label><span>减少消息区动效</span><input data-k="reduceMotion" type="checkbox" ${settings.reduceMotion ? 'checked' : ''}></label>
      <div class="hint">默认保留最近 ${settings.initialRounds} 轮完整对话，即 User + Assistant。Thinking / Reasoning / Tool 内部节点不额外占轮数。React 累积到 6 个 User/Assistant 消息组且安全时自动重置。</div>
      <div class="hint">当前会话：最近 ${rounds} 轮${TailProxy.isHistoryMode() ? '（历史浏览）' : ''}。加载更早每次只增加 1 轮，也就是通常 2 条消息。</div>
      <div class="history"><button data-a="older">加载更早 1 轮</button><button data-a="latest">回到最新 ${settings.initialRounds} 轮</button></div>
      <div class="actions"><button data-a="reset">恢复默认</button><button data-a="close">完成</button></div>
    </div>`;
    let needsReload = false;
    panel.querySelectorAll('[data-k]').forEach((input) => input.addEventListener('change', () => {
      const key = input.dataset.k;
      if (key === 'initialRounds') settings.initialRounds = clampRounds(input.value);
      else settings[key] = input.checked;
      TailProxy.updateSettings(settings);
      installCSS();
      needsReload = key === 'initialRounds' || key === 'enabled';
    }));
    panel.querySelector('[data-a="older"]').addEventListener('click', () => TailProxy.expandHistory());
    panel.querySelector('[data-a="latest"]').addEventListener('click', () => TailProxy.returnLatest());
    panel.querySelector('[data-a="reset"]').addEventListener('click', () => {
      settings = { ...defaults };
      TailProxy.updateSettings(settings);
      clearHistoryRounds(conversationIdFromPath());
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
    if (state.idleTimer) { clearTimeout(state.idleTimer); state.idleTimer = 0; }
    state.mainObserver?.disconnect();
  };
  const suspend = prepareForBackground;
  const resume = () => {
    state.paused = false;
    state.userInteracted = false;
    state.pinUntil = Date.now() + 800;
    ensureConversationObserver();
    TailProxy.prewarmSidebar?.();
    schedule(0);
  };
  const restoreAll = () => messageNodes().forEach((node) => node.classList.remove('gptwebkit-tail-hidden'));
  const forceLatestVisible = () => pinLatest(messageNodes());
  const beginPinLatest = () => { state.userInteracted = false; state.pinUntil = Date.now() + 2400; state.stableBottomTicks = 0; schedule(0); };
  const updateSettings = (patch = {}) => {
    TailProxy.updateSettings(patch);
    installCSS();
    schedule(0);
    return { ...settings };
  };

  window.GPTWebKitLongConversation = {
    schedule,
    openSettings,
    updateSettings,
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
      return { conversationId:conversationIdFromPath(), count:semanticMessageGroupCount(nodes), rounds:TailProxy.currentRounds(), historyMode:TailProxy.isHistoryMode(), generating:isGenerating(), draft:draftText(), lastMessageId:lastMessageId(nodes), safe:canRebase(nodes) };
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
  const stopAutoPin = () => { state.userInteracted = true; state.pinUntil = 0; };
  const start = () => {
    installCSS();
    patchHistory();
    ensureConversationObserver();
    addEventListener('visibilitychange', () => document.visibilityState === 'visible' ? resume() : prepareForBackground());
    addEventListener('resize', () => schedule(100), { passive:true });
    addEventListener('touchstart', stopAutoPin, { passive:true, capture:true });
    addEventListener('wheel', stopAutoPin, { passive:true, capture:true });
    schedule(0);
    scheduleIdleCheck();
  };

  if (document.documentElement) start(); else addEventListener('DOMContentLoaded', start, { once:true });
})();