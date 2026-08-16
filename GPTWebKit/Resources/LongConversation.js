(() => {
  'use strict';
  if (window.GPTWebKitLongConversation || window.__GPTWebKitTailBootstrap) return;
  window.__GPTWebKitTailBootstrap = true;

  const SETTINGS_KEY = 'gptwebkit.tail.settings.v3';
  const defaults = { enabled: true, initialRounds: 2, rebaseThreshold: 6, reduceMotion: true, optimizeSidebar: true };
  const CACHE_DB_NAME = 'GPTWebKitConversationCache';
  const CACHE_STORE = 'conversations';
  const CACHE_DB_VERSION = 1;
  const CACHE_MAX_ITEMS = 10;
  const CACHE_MAX_ENTRY_BYTES = 4 * 1024 * 1024;
  const LIMIT_RE = /(you(?:’|'|\s)?ve reached the maximum length|maximum length for this conversation|this conversation is too long|conversation is too long|conversation[_ -]?(?:length|limit).*exceed|context[_ -]?length[_ -]?exceed|已达到.{0,16}(?:最大|上限)|(?:对话|会话).{0,16}(?:太长|上限))/i;

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
  const forceNetworkKey = (id) => `gptwebkit.tail.forceNetwork.${id}`;

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

  const clearHistoryRounds = (id) => {
    if (!id) return;
    try { sessionStorage.removeItem(historyKey(id)); } catch (_) {}
  };

  const currentRounds = () => readHistoryRounds(conversationIdFromPath());
  const historyMode = () => currentRounds() > settings.initialRounds;

  let cacheDBPromise = null;
  const openCacheDB = () => {
    if (cacheDBPromise) return cacheDBPromise;
    cacheDBPromise = new Promise((resolve, reject) => {
      if (!window.indexedDB) { reject(new Error('IndexedDB unavailable')); return; }
      const request = indexedDB.open(CACHE_DB_NAME, CACHE_DB_VERSION);
      request.onupgradeneeded = () => {
        const db = request.result;
        let store;
        if (!db.objectStoreNames.contains(CACHE_STORE)) {
          store = db.createObjectStore(CACHE_STORE, { keyPath: 'id' });
        } else {
          store = request.transaction.objectStore(CACHE_STORE);
        }
        if (!store.indexNames.contains('lastAccess')) store.createIndex('lastAccess', 'lastAccess');
      };
      request.onsuccess = () => resolve(request.result);
      request.onerror = () => reject(request.error || new Error('IndexedDB open failed'));
    }).catch((error) => {
      cacheDBPromise = null;
      throw error;
    });
    return cacheDBPromise;
  };

  const cacheGet = async (id) => {
    if (!id) return null;
    try {
      const db = await openCacheDB();
      const entry = await new Promise((resolve, reject) => {
        const tx = db.transaction(CACHE_STORE, 'readonly');
        const request = tx.objectStore(CACHE_STORE).get(id);
        request.onsuccess = () => resolve(request.result || null);
        request.onerror = () => reject(request.error);
      });
      if (!entry?.body) return null;
      entry.lastAccess = Date.now();
      try {
        const tx = db.transaction(CACHE_STORE, 'readwrite');
        tx.objectStore(CACHE_STORE).put(entry);
      } catch (_) {}
      return entry;
    } catch (_) {
      return null;
    }
  };

  const enforceCacheLimit = async (db) => {
    try {
      await new Promise((resolve, reject) => {
        const tx = db.transaction(CACHE_STORE, 'readwrite');
        const store = tx.objectStore(CACHE_STORE);
        const index = store.index('lastAccess');
        let count = 0;
        const request = index.openCursor(null, 'prev');
        request.onsuccess = () => {
          const cursor = request.result;
          if (!cursor) return;
          count++;
          if (count > CACHE_MAX_ITEMS) cursor.delete();
          cursor.continue();
        };
        tx.oncomplete = () => resolve();
        tx.onerror = () => reject(tx.error);
        tx.onabort = () => reject(tx.error);
      });
    } catch (_) {}
  };

  const cachePut = async (entry) => {
    if (!entry?.id || !entry?.body) return false;
    const size = Number(entry.size || new TextEncoder().encode(entry.body).byteLength);
    if (!Number.isFinite(size) || size <= 0 || size > CACHE_MAX_ENTRY_BYTES) return false;
    try {
      const db = await openCacheDB();
      const value = {
        id: String(entry.id),
        title: String(entry.title || '新对话'),
        currentNode: String(entry.currentNode || ''),
        body: String(entry.body),
        size,
        lastAccess: Date.now(),
        totalRounds: Number(entry.totalRounds || 0),
        fullBytes: Number(entry.fullBytes || 0),
        rawLimitSignal: !!entry.rawLimitSignal
      };
      await new Promise((resolve, reject) => {
        const tx = db.transaction(CACHE_STORE, 'readwrite');
        tx.objectStore(CACHE_STORE).put(value);
        tx.oncomplete = () => resolve();
        tx.onerror = () => reject(tx.error);
        tx.onabort = () => reject(tx.error);
      });
      await enforceCacheLimit(db);
      return true;
    } catch (_) {
      return false;
    }
  };

  const cacheRemove = async (id) => {
    if (!id) return false;
    try {
      const db = await openCacheDB();
      await new Promise((resolve, reject) => {
        const tx = db.transaction(CACHE_STORE, 'readwrite');
        tx.objectStore(CACHE_STORE).delete(id);
        tx.oncomplete = () => resolve();
        tx.onerror = () => reject(tx.error);
      });
      return true;
    } catch (_) {
      return false;
    }
  };

  const cacheClear = async () => {
    try {
      const db = await openCacheDB();
      await new Promise((resolve, reject) => {
        const tx = db.transaction(CACHE_STORE, 'readwrite');
        tx.objectStore(CACHE_STORE).clear();
        tx.oncomplete = () => resolve();
        tx.onerror = () => reject(tx.error);
      });
      return true;
    } catch (_) {
      return false;
    }
  };

  const cacheList = async () => {
    try {
      const db = await openCacheDB();
      return await new Promise((resolve, reject) => {
        const items = [];
        const tx = db.transaction(CACHE_STORE, 'readonly');
        const request = tx.objectStore(CACHE_STORE).index('lastAccess').openCursor(null, 'prev');
        request.onsuccess = () => {
          const cursor = request.result;
          if (!cursor) { resolve(items.slice(0, CACHE_MAX_ITEMS)); return; }
          const value = cursor.value || {};
          items.push({
            id: String(value.id || ''),
            title: String(value.title || '新对话'),
            size: Number(value.size || 0),
            lastAccess: Number(value.lastAccess || 0),
            currentNode: String(value.currentNode || '')
          });
          if (items.length >= CACHE_MAX_ITEMS) { resolve(items); return; }
          cursor.continue();
        };
        request.onerror = () => reject(request.error);
      });
    } catch (_) {
      return [];
    }
  };

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
      lastFullBytes: 0,
      lastRawLimitSignal: false,
      hotCacheHits: 0,
      hotCacheMisses: 0,
      sidebarCacheHits: 0
    };
    let sidebarCache = null;

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
      if (!container || !mapping || !currentNode || !mapping[currentNode]) return { data, trimmed: false, reason: 'unrecognized', totalRounds: 0 };
      const path = walkCurrentPath(mapping, currentNode);
      if (!path.length) return { data, trimmed: false, reason: 'empty-path', totalRounds: 0 };

      const roundStarts = roundStartsForPath(path, mapping);
      const totalRounds = roundStarts.length;
      state.lastTotalRounds = totalRounds;
      if (!roundStarts.length || totalRounds <= roundLimit) return { data, trimmed: false, reason: 'small', totalRounds };

      const cutPathIndex = roundStarts[Math.max(0, totalRounds - roundLimit)];
      const firstKeptId = path[cutPathIndex];
      const firstParentId = mapping[firstKeptId]?.parent;
      if (firstParentId && Array.isArray(mapping[firstParentId]?.children) && mapping[firstParentId].children.length > 1) {
        return { data, trimmed: false, reason: 'recent-branch-parent', totalRounds };
      }

      const keptPath = path.slice(cutPathIndex);
      for (const id of keptPath) {
        const node = mapping[id];
        if (Array.isArray(node?.children) && node.children.length > 1) return { data, trimmed: false, reason: 'recent-branch', totalRounds };
      }

      const originalRootId = container.root && mapping[container.root] ? container.root : path[0];
      const out = {};
      if (originalRootId && mapping[originalRootId] && originalRootId !== firstKeptId) {
        out[originalRootId] = { ...mapping[originalRootId], parent: null, children: firstKeptId ? [firstKeptId] : [] };
      }

      for (let i = 0; i < keptPath.length; i++) {
        const id = keptPath[i];
        const source = mapping[id];
        if (!source) return { data, trimmed: false, reason: 'missing-node', totalRounds };
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
      state.lastTrimmedRounds = Math.min(roundLimit, totalRounds);
      return { data: copy, trimmed: true, reason: '', totalRounds, messageGroups: countMessageGroups(keptPath, mapping) };
    };

    const parseRequest = (input, init) => {
      try {
        let urlString = '';
        let method = 'GET';
        if (input instanceof Request) {
          urlString = input.url;
          method = String(init?.method || input.method || 'GET').toUpperCase();
        } else if (input instanceof URL) {
          urlString = input.href;
          method = String(init?.method || 'GET').toUpperCase();
        } else {
          urlString = String(input || '');
          method = String(init?.method || 'GET').toUpperCase();
        }
        const url = new URL(urlString, location.href);
        const conversation = url.pathname.match(/^\/backend-api\/(conversation|shared_conversation)\/([^/]+)\/?$/);
        const conversationMutation = url.pathname.match(/^\/backend-api\/conversation(?:\/([^/]+))?(?:\/.*)?$/);
        const history = url.pathname === '/backend-api/conversations';
        const mutationConversationId = conversationMutation && method !== 'GET'
          ? (conversationMutation[1] ? decodeURIComponent(conversationMutation[1]) : conversationIdFromPath())
          : '';
        return {
          url,
          method,
          conversation: conversation && method === 'GET' ? { id: decodeURIComponent(conversation[2]), type: conversation[1] } : null,
          mutationConversationId,
          history: history && method === 'GET'
        };
      } catch (_) {
        return { url: null, method: 'GET', conversation: null, mutationConversationId: '', history: false };
      }
    };

    const rebuildResponse = (original, text) => {
      const headers = new Headers(original.headers);
      headers.delete('content-length');
      headers.delete('content-encoding');
      const response = new Response(text, { status: original.status, statusText: original.statusText, headers });
      try { if (original.url) Object.defineProperty(response, 'url', { value: original.url }); } catch (_) {}
      return response;
    };

    const cachedResponse = (entry, href) => {
      const response = new Response(entry.body, { status: 200, headers: { 'content-type': 'application/json' } });
      try { Object.defineProperty(response, 'url', { value: href || location.href }); } catch (_) {}
      return response;
    };

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
        sidebarCache = {
          href: url.href,
          text,
          status: clone.status,
          statusText: clone.statusText,
          headers: Array.from(clone.headers.entries()),
          at: Date.now()
        };
      } catch (_) {}
    };

    const rebuildSidebarResponse = (entry) => new Response(entry.text, {
      status: entry.status,
      statusText: entry.statusText,
      headers: new Headers(entry.headers)
    });

    const shouldForceNetwork = (id) => {
      if (!id) return false;
      try {
        const key = forceNetworkKey(id);
        const at = Number(localStorage.getItem(key) || 0);
        if (at && Date.now() - at < 12000) {
          localStorage.removeItem(key);
          return true;
        }
        if (at) localStorage.removeItem(key);
      } catch (_) {}
      return false;
    };

    const setStateFromCache = (entry, id) => {
      state.lastConversationId = id;
      state.lastOriginalCurrentNode = String(entry.currentNode || '');
      state.lastTotalRounds = Number(entry.totalRounds || 0);
      state.lastTrimmedRounds = Math.min(settings.initialRounds, state.lastTotalRounds || settings.initialRounds);
      state.lastFullBytes = Number(entry.fullBytes || entry.size || 0);
      state.lastRawLimitSignal = !!entry.rawLimitSignal;
      state.lastBypassedReason = '';
      state.lastProxyAt = Date.now();
    };

    const signalFreshConversation = (id, currentNode, previousCurrentNode) => {
      if (!id || !currentNode || !previousCurrentNode || currentNode === previousCurrentNode || conversationIdFromPath() !== id) return;
      try { localStorage.setItem(forceNetworkKey(id), String(Date.now())); } catch (_) {}
      setTimeout(() => {
        if (conversationIdFromPath() !== id) return;
        const longConversation = window.GPTWebKitLongConversation;
        const rebaseState = longConversation?.getRebaseState?.();
        if (!rebaseState || rebaseState.generating || rebaseState.draft || rebaseState.historyMode) return;
        const handler = window.webkit?.messageHandlers?.rebaseRequest;
        if (!handler) return;
        try {
          handler.postMessage({
            conversationId: id,
            currentNode,
            href: location.href,
            count: Number(rebaseState.count || 0),
            lastMessageId: String(rebaseState.lastMessageId || '')
          });
        } catch (_) {}
      }, 650);
    };

    const processConversationResponse = async (response, request, roundLimit, previousCurrentNode = '') => {
      const type = response.headers.get('content-type') || '';
      if (!/json/i.test(type)) return response;

      let text = '';
      try {
        text = await response.text();
        const data = JSON.parse(text);
        const container = containerOf(data);
        const currentNode = String(container?.current_node || '');
        const fullBytes = new TextEncoder().encode(text).byteLength;
        const rawLimitSignal = LIMIT_RE.test(text);

        state.lastConversationId = request.id;
        state.lastOriginalCurrentNode = currentNode;
        state.lastProxyAt = Date.now();
        state.lastFullBytes = fullBytes;
        state.lastRawLimitSignal = rawLimitSignal;

        const result = trimConversation(data, roundLimit);
        state.lastBypassedReason = result.trimmed ? '' : result.reason;
        const outputText = result.trimmed ? JSON.stringify(result.data) : text;

        const cacheable = roundLimit === settings.initialRounds && (result.trimmed || result.reason === 'small');
        if (cacheable) {
          const title = String(data?.title || data?.conversation?.title || '新对话').trim() || '新对话';
          cachePut({
            id: request.id,
            title,
            currentNode,
            body: outputText,
            size: new TextEncoder().encode(outputText).byteLength,
            totalRounds: Number(result.totalRounds || 0),
            fullBytes,
            rawLimitSignal
          });
        }

        signalFreshConversation(request.id, currentNode, previousCurrentNode);
        return rebuildResponse(response, outputText);
      } catch (_) {
        return text ? rebuildResponse(response, text) : response;
      }
    };

    window.fetch = async (...args) => {
      const parsed = parseRequest(args[0], args[1]);

      if (parsed.mutationConversationId) {
        cacheRemove(parsed.mutationConversationId);
        sidebarCache = null;
      }

      if (parsed.history && settings.optimizeSidebar && sidebarCache && sidebarCache.href === parsed.url.href && Date.now() - sidebarCache.at < 30000) {
        state.sidebarCacheHits++;
        return rebuildSidebarResponse(sidebarCache);
      }

      if (!parsed.conversation || !settings.enabled) {
        const response = await nativeFetch(...args);
        if (parsed.history && settings.optimizeSidebar) cacheSidebarResponse(parsed.url, response);
        return response;
      }

      const request = parsed.conversation;
      requestURLs.set(request.id, parsed.url.href);
      const roundLimit = readHistoryRounds(request.id);
      const forceNetwork = shouldForceNetwork(request.id) || roundLimit !== settings.initialRounds;
      const networkPromise = nativeFetch(...args);

      if (!forceNetwork) {
        const cachePromise = cacheGet(request.id);
        const cacheEntry = await Promise.race([
          cachePromise,
          new Promise((resolve) => setTimeout(() => resolve(null), 85))
        ]);
        if (cacheEntry?.body) {
          state.hotCacheHits++;
          setStateFromCache(cacheEntry, request.id);
          networkPromise
            .then((response) => processConversationResponse(response, request, roundLimit, String(cacheEntry.currentNode || '')))
            .catch(() => {});
          return cachedResponse(cacheEntry, parsed.url.href);
        }
        state.hotCacheMisses++;
      }

      const response = await networkPromise;
      return processConversationResponse(response, request, roundLimit);
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
        settings = { ...settings, ...patch, initialRounds: clampRounds(patch.initialRounds ?? settings.initialRounds), rebaseThreshold: 6 };
        saveSettings();
        if (!settings.optimizeSidebar) sidebarCache = null;
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
        try { localStorage.setItem(forceNetworkKey(id), String(Date.now())); } catch (_) {}
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
      cacheList,
      cacheRemove,
      cacheClear,
      cacheCount: async () => (await cacheList()).length,
      getStatus: () => ({
        ...state,
        currentRounds: currentRounds(),
        historyMode: historyMode(),
        cacheMaxItems: CACHE_MAX_ITEMS
      })
    };

    window.GPTWebKitTailProxy = api;
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
    try { last.scrollIntoView({ block: 'end', inline: 'nearest', behavior: 'auto' }); } catch (_) {}
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

  const requestRebase = async (nodes) => {
    const id = conversationIdFromPath();
    if (!id || state.rebasePending || !canRebase(nodes)) return;

    let last = 0;
    try { last = Number(sessionStorage.getItem(rebaseKey(id)) || 0); } catch (_) {}
    if (Date.now() - last < 8000) return;

    state.rebasePending = true;
    try { sessionStorage.setItem(rebaseKey(id), String(Date.now())); } catch (_) {}

    const handler = window.webkit?.messageHandlers?.rebaseRequest;
    if (!handler) {
      setTimeout(() => {
        const fresh = messageNodes();
        if (canRebase(fresh) && conversationIdFromPath() === id) location.reload();
        else state.rebasePending = false;
      }, 180);
      return;
    }

    try {
      const data = await TailProxy.fetchFullConversation(id);
      const container = data?.mapping ? data : data?.conversation;
      const currentNode = String(container?.current_node || '');
      if (!currentNode || conversationIdFromPath() !== id || !canRebase(messageNodes())) {
        state.rebasePending = false;
        return;
      }
      handler.postMessage({
        conversationId: id,
        currentNode,
        href: location.href,
        count: semanticMessageGroupCount(messageNodes()),
        lastMessageId: lastMessageId(messageNodes())
      });
      setTimeout(() => { state.rebasePending = false; }, 9000);
    } catch (_) {
      state.rebasePending = false;
    }
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
    state.mainObserver.observe(main, { childList: true, subtree: true });
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
      <div class="hint">默认保留最近 ${settings.initialRounds} 轮；Rebase 阈值固定为 6 个 User/Assistant 消息组。</div>
      <div class="hint">当前会话：最近 ${rounds} 轮${TailProxy.isHistoryMode() ? '（历史浏览）' : ''}。</div>
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
      needsReload = needsReload || key === 'initialRounds' || key === 'enabled';
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
      if (needsReload && conversationIdFromPath()) location.reload();
      else schedule(0);
    });
    panel.addEventListener('click', (event) => {
      if (event.target !== panel) return;
      panel.remove();
      if (needsReload && conversationIdFromPath()) location.reload();
    });

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
    schedule(0);
  };

  const restoreAll = () => messageNodes().forEach((node) => node.classList.remove('gptwebkit-tail-hidden'));
  const forceLatestVisible = () => pinLatest(messageNodes());
  const beginPinLatest = () => {
    state.userInteracted = false;
    state.pinUntil = Date.now() + 2400;
    state.stableBottomTicks = 0;
    schedule(0);
  };

  const updateSettings = (patch = {}) => {
    TailProxy.updateSettings(patch);
    settings = { ...settings, ...patch, initialRounds: clampRounds(patch.initialRounds ?? settings.initialRounds), rebaseThreshold: 6 };
    saveSettings();
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
      return {
        conversationId: conversationIdFromPath(),
        count: semanticMessageGroupCount(nodes),
        rounds: TailProxy.currentRounds(),
        historyMode: TailProxy.isHistoryMode(),
        generating: isGenerating(),
        draft: draftText(),
        lastMessageId: lastMessageId(nodes),
        safe: canRebase(nodes)
      };
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
    ensureConversationObserver();
    addEventListener('visibilitychange', () => document.visibilityState === 'visible' ? resume() : prepareForBackground());
    addEventListener('resize', () => schedule(100), { passive: true });
    addEventListener('touchstart', stopAutoPin, { passive: true, capture: true });
    addEventListener('wheel', stopAutoPin, { passive: true, capture: true });
    schedule(0);
    scheduleIdleCheck();
  };

  if (document.documentElement) start();
  else addEventListener('DOMContentLoaded', start, { once: true });
})();