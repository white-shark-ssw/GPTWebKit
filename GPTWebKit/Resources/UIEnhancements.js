(() => {
  'use strict';
  if (window.__GPTWebKitUIEnhancements) return;
  window.__GPTWebKitUIEnhancements = true;

  const STYLE_ID = 'gptwebkit-ui-enhancements-style';
  const HISTORY_ID = 'gptwebkit-inline-history';
  const LIMIT_ID = 'gptwebkit-conversation-limit';
  const LIMIT_RE = /(you(?:’|'|\s)?ve reached the maximum length|maximum length for this conversation|this conversation is too long|conversation is too long|please start a new (?:one|chat)|conversation[_ -]?(?:length|limit).*exceed|context[_ -]?length[_ -]?exceed|已达到.{0,16}(?:最大|上限)|(?:对话|会话).{0,16}(?:太长|上限)|请.{0,10}(?:新建|开始).{0,10}(?:对话|会话))/i;
  let routeId = '';
  let touchStartY = 0;
  let uploadResumeTimer = 0;
  let sidebarInterceptUntil = 0;
  let sidebarFetchBusy = false;
  let rebaseBusy = false;
  let rebaseTimer = 0;
  let limitTimer = 0;
  let limitProbeId = '';
  let lastLimitText = '';
  let mainObserver = null;
  let observedMain = null;

  const installStyle = () => {
    let style = document.getElementById(STYLE_ID);
    if (!style) {
      style = document.createElement('style');
      style.id = STYLE_ID;
      (document.head || document.documentElement).appendChild(style);
    }
    style.textContent = `
      #gptwebkit-opt-card { color-scheme:light dark !important; }
      #gptwebkit-opt-card input[type="number"] { box-sizing:border-box !important; width:72px !important; min-width:72px !important; min-height:36px !important; padding:5px 8px !important; border:1px solid rgba(127,127,127,.5) !important; border-radius:8px !important; background:rgba(127,127,127,.18) !important; color:CanvasText !important; -webkit-text-fill-color:CanvasText !important; caret-color:CanvasText !important; outline:none !important; }
      #gptwebkit-opt-card input[type="number"]:focus { border-color:rgba(90,150,255,.95) !important; box-shadow:0 0 0 2px rgba(90,150,255,.2) !important; }
      #gptwebkit-opt-card button { background:rgba(127,127,127,.16) !important; color:CanvasText !important; border:1px solid rgba(127,127,127,.22) !important; }
      aside, nav[aria-label], [data-testid="history-list"], [data-testid="conversation-history"] { will-change:auto !important; }
      [data-testid="history-list"], [data-testid="conversation-history"] { contain:none !important; }
      #${HISTORY_ID} { position:fixed; z-index:2147483500; top:calc(env(safe-area-inset-top, 0px) + 66px); left:50%; transform:translateX(-50%); min-height:34px; padding:6px 12px; border:1px solid rgba(127,127,127,.28); border-radius:999px; background:rgba(30,30,30,.9); color:#fff; box-shadow:0 4px 16px rgba(0,0,0,.16); -webkit-backdrop-filter:blur(14px); backdrop-filter:blur(14px); font:13px -apple-system,BlinkMacSystemFont,sans-serif; white-space:nowrap; }
      @media (prefers-color-scheme: light) { #${HISTORY_ID} { background:rgba(250,250,250,.96); color:#111; } }
      #${LIMIT_ID} { position:fixed; z-index:2147483490; left:16px; right:16px; bottom:calc(env(safe-area-inset-bottom, 0px) + 104px); display:none; padding:10px 13px; border:1px solid rgba(255,80,80,.72); border-radius:12px; background:rgba(120,22,22,.96); color:#fff; box-shadow:0 6px 24px rgba(0,0,0,.2); font:13px/1.45 -apple-system,BlinkMacSystemFont,sans-serif; pointer-events:none; }
      #${LIMIT_ID}[data-visible="1"] { display:block; }
      @media (prefers-color-scheme: light) { #${LIMIT_ID} { background:rgba(255,236,236,.98); color:#8e1d1d; border-color:rgba(210,45,45,.55); } }
    `;
  };

  const getProxy = () => window.GPTWebKitTailProxy;
  const getLongConversation = () => window.GPTWebKitLongConversation;
  const conversationId = () => getProxy()?.currentConversationId?.() || location.pathname.match(/\/c\/([^/?#]+)/)?.[1] || '';

  const visibleMessageNodes = () => {
    const main = document.querySelector('main');
    if (!main) return [];
    const turns = Array.from(main.querySelectorAll('[data-testid^="conversation-turn-"]'));
    const nodes = turns.length ? turns : Array.from(main.querySelectorAll('[data-message-author-role]')).filter((node) => !node.parentElement?.closest?.('[data-message-author-role]'));
    return nodes.filter((node) => {
      if (node.classList.contains('gptwebkit-tail-hidden')) return false;
      const style = getComputedStyle(node);
      return style.display !== 'none' && style.visibility !== 'hidden' && node.getBoundingClientRect().height > 0;
    });
  };

  const atLoadedHistoryTop = () => {
    const first = visibleMessageNodes()[0];
    if (!first) return false;
    const rect = first.getBoundingClientRect();
    return rect.bottom > 48 && rect.top >= 24 && rect.top <= 260;
  };

  const hasEarlierHistory = () => {
    const proxy = getProxy();
    const status = proxy?.getStatus?.() || {};
    const currentRounds = Number(status.currentRounds || proxy?.currentRounds?.() || 0);
    const totalRounds = Number(status.lastTotalRounds || 0);
    return !!conversationId() && totalRounds > 0 && currentRounds > 0 && totalRounds > currentRounds;
  };

  const removeHistoryButton = () => document.getElementById(HISTORY_ID)?.remove();
  const revealHistoryButton = () => {
    if (!hasEarlierHistory() || !atLoadedHistoryTop()) { removeHistoryButton(); return; }
    removeHistoryButton();
    const button = document.createElement('button');
    button.id = HISTORY_ID;
    button.type = 'button';
    button.textContent = '加载更早 1 轮';
    button.addEventListener('click', () => {
      button.disabled = true;
      button.textContent = '正在加载…';
      const ok = getLongConversation()?.loadEarlier?.() ?? getProxy()?.expandHistory?.();
      if (!ok) removeHistoryButton();
    }, { once:true });
    document.body?.appendChild(button);
    setTimeout(() => { if (document.getElementById(HISTORY_ID) === button) button.remove(); }, 2300);
  };

  const ensureLimitBanner = () => {
    let banner = document.getElementById(LIMIT_ID);
    if (!banner) {
      banner = document.createElement('div');
      banner.id = LIMIT_ID;
      banner.setAttribute('role', 'status');
      banner.dataset.visible = '0';
      document.body?.appendChild(banner);
    }
    return banner;
  };

  const cleanText = (text) => String(text || '').replace(/\s+/g, ' ').trim();
  const findLimitTextInPage = () => {
    const candidates = document.querySelectorAll('[role="alert"], [aria-live="assertive"], [aria-live="polite"], [data-testid*="error" i], [data-testid*="warning" i], [class*="error" i], [class*="warning" i], [class*="danger" i]');
    for (const node of candidates) {
      if (node.id === LIMIT_ID || node.closest?.(`#${LIMIT_ID}`)) continue;
      const text = cleanText(node.textContent);
      if (text && text.length < 900 && LIMIT_RE.test(text)) return text;
    }
    const own = cleanText(document.getElementById(LIMIT_ID)?.textContent);
    let bodyText = cleanText(document.body?.innerText);
    if (own && bodyText.includes(own)) bodyText = bodyText.replace(own, '');
    if (!bodyText || !LIMIT_RE.test(bodyText)) return '';
    const match = bodyText.match(/.{0,100}(?:you(?:’|'|\s)?ve reached the maximum length|maximum length for this conversation|this conversation is too long|conversation is too long|please start a new (?:one|chat)|已达到.{0,16}(?:最大|上限)|(?:对话|会话).{0,16}(?:太长|上限)|请.{0,10}(?:新建|开始).{0,10}(?:对话|会话)).{0,140}/i);
    return cleanText(match?.[0] || '此对话已达到长度上限，请新建聊天继续。');
  };

  const metadataLimitHint = (data) => {
    const container = data?.mapping ? data : data?.conversation;
    if (!container || typeof container !== 'object') return '';
    const top = { ...container };
    delete top.mapping;
    const topText = cleanText(JSON.stringify(top));
    if (LIMIT_RE.test(topText)) return '此对话已达到长度上限，请新建聊天继续。';
    const mapping = container.mapping || {};
    const visited = new Set();
    let id = container.current_node;
    let hops = 0;
    while (id && mapping[id] && !visited.has(id) && hops++ < 18) {
      visited.add(id);
      const message = mapping[id]?.message;
      const metaText = cleanText(JSON.stringify({ status: message?.status, end_turn: message?.end_turn, metadata: message?.metadata, author: message?.author, contentType: message?.content?.content_type }));
      if (LIMIT_RE.test(metaText)) return '此对话已达到长度上限，请新建聊天继续。';
      if (message?.author?.role === 'system') {
        const systemText = cleanText(JSON.stringify(message?.content || {}));
        if (LIMIT_RE.test(systemText)) return '此对话已达到长度上限，请新建聊天继续。';
      }
      id = mapping[id]?.parent || '';
    }
    return '';
  };

  const showLimitBanner = (text) => {
    if (!text) return;
    lastLimitText = cleanText(text) || '此对话已达到长度上限，请新建聊天继续。';
    const banner = ensureLimitBanner();
    banner.textContent = lastLimitText;
    banner.dataset.visible = '1';
  };

  const hideLimitBanner = () => {
    lastLimitText = '';
    const banner = document.getElementById(LIMIT_ID);
    if (banner) banner.dataset.visible = '0';
  };

  const updateLimitBanner = () => {
    if (!conversationId()) { hideLimitBanner(); return; }
    const found = findLimitTextInPage();
    if (found) showLimitBanner(found);
    else if (lastLimitText) showLimitBanner(lastLimitText);
  };

  const scheduleLimitScan = (delay = 260) => {
    if (limitTimer) clearTimeout(limitTimer);
    limitTimer = setTimeout(() => { limitTimer = 0; updateLimitBanner(); }, delay);
  };

  const probeFullConversationLimit = async () => {
    const id = conversationId();
    if (!id || limitProbeId === id) return;
    limitProbeId = id;
    try {
      const data = await getProxy()?.fetchFullConversation?.(id);
      if (id !== conversationId()) return;
      const hint = metadataLimitHint(data);
      if (hint) showLimitBanner(hint);
    } catch (_) {}
  };

  const composerUtilityButton = (target) => {
    const button = target?.closest?.('button');
    if (!(button instanceof HTMLElement)) return null;
    const prompt = document.querySelector('#prompt-textarea, textarea, [contenteditable="true"][data-placeholder]');
    const composer = prompt?.closest('form') || prompt?.parentElement?.parentElement;
    if (!composer?.contains(button)) return null;
    const label = `${button.getAttribute('aria-label') || ''} ${button.getAttribute('title') || ''} ${button.getAttribute('data-testid') || ''} ${button.textContent || ''}`;
    return /添加|附件|照片|文件|上传|attach|upload|photo|file|add/i.test(label) ? button : null;
  };

  const suspendForUploadMenu = (event) => {
    if (!event.isTrusted || !composerUtilityButton(event.target)) return;
    getLongConversation()?.suspend?.();
    if (uploadResumeTimer) clearTimeout(uploadResumeTimer);
    uploadResumeTimer = setTimeout(() => { uploadResumeTimer = 0; getLongConversation()?.resume?.(); }, 900);
  };

  const sidebarButtonForTarget = (target) => {
    const button = target?.closest?.('button');
    if (!(button instanceof HTMLElement)) return null;
    if (button.matches('button[data-testid="open-sidebar-button"], button[data-testid*="sidebar" i], button[aria-label*="sidebar" i], button[title*="sidebar" i]')) return button;
    const rect = button.getBoundingClientRect();
    if (rect.top > 120 || rect.left > innerWidth * 0.32) return null;
    const label = `${button.getAttribute('aria-label') || ''} ${button.getAttribute('title') || ''} ${button.getAttribute('data-testid') || ''} ${button.textContent || ''}`;
    return /侧边栏|侧栏|打开菜单|open menu|menu/i.test(label) ? button : null;
  };

  const interceptSidebar = (event) => {
    const handler = window.webkit?.messageHandlers?.nativeSidebar;
    if (!handler || !event.isTrusted || !sidebarButtonForTarget(event.target)) return false;
    event.preventDefault();
    event.stopPropagation();
    event.stopImmediatePropagation();
    sidebarInterceptUntil = performance.now() + 700;
    try { handler.postMessage({ href: location.href }); } catch (_) {}
    setTimeout(pushSidebarData, 0);
    return true;
  };

  const normalizeSidebarItems = (data) => {
    const raw = Array.isArray(data?.items) ? data.items : (Array.isArray(data?.conversations) ? data.conversations : (Array.isArray(data) ? data : []));
    return raw.map((item) => ({ id:String(item?.id || item?.conversation_id || '').trim(), title:String(item?.title || item?.name || '新对话').trim() || '新对话', updatedAt:Number(item?.update_time || item?.updated_at || item?.create_time || 0) || 0 })).filter((item) => item.id).slice(0, 60);
  };

  const pushSidebarData = async () => {
    const handler = window.webkit?.messageHandlers?.sidebarData;
    if (!handler || sidebarFetchBusy || document.visibilityState !== 'visible') return false;
    sidebarFetchBusy = true;
    try {
      const response = await fetch('/backend-api/conversations?offset=0&limit=28&order=updated&is_archived=false&is_starred=false', { method:'GET', credentials:'include' });
      if (!response.ok) return false;
      const items = normalizeSidebarItems(await response.json());
      handler.postMessage({ items, at:Date.now() });
      return true;
    } catch (_) { return false; }
    finally { sidebarFetchBusy = false; }
  };

  const checkNativeRebase = async () => {
    const handler = window.webkit?.messageHandlers?.rebaseRequest;
    if (!handler || rebaseBusy || document.visibilityState !== 'visible') return;
    const state = getLongConversation()?.getRebaseState?.();
    if (!state?.safe || Number(state.count || 0) < 6 || state.historyMode || state.generating || state.draft) return;
    const id = String(state.conversationId || conversationId());
    if (!id) return;
    rebaseBusy = true;
    try {
      const data = await getProxy()?.fetchFullConversation?.(id);
      const container = data?.mapping ? data : data?.conversation;
      const currentNode = String(container?.current_node || '');
      if (!currentNode || id !== conversationId()) { rebaseBusy = false; return; }
      handler.postMessage({ conversationId:id, currentNode, href:location.href, count:Number(state.count || 0), lastMessageId:String(state.lastMessageId || '') });
      setTimeout(() => { rebaseBusy = false; }, 9000);
    } catch (_) { rebaseBusy = false; }
  };

  const scheduleRebaseCheck = () => {
    if (rebaseTimer) clearTimeout(rebaseTimer);
    rebaseTimer = setTimeout(() => { rebaseTimer = 0; checkNativeRebase(); }, 1150);
  };

  const syncRoute = () => {
    const id = conversationId();
    if (id === routeId) return;
    routeId = id;
    limitProbeId = '';
    removeHistoryButton();
    hideLimitBanner();
    setTimeout(() => { scheduleLimitScan(0); probeFullConversationLimit(); pushSidebarData(); }, 180);
  };

  const observeMain = () => {
    const main = document.querySelector('main');
    if (main === observedMain) return;
    mainObserver?.disconnect();
    observedMain = main;
    if (!main) return;
    mainObserver = new MutationObserver(() => {
      syncRoute();
      scheduleLimitScan();
      scheduleRebaseCheck();
      if (document.getElementById(HISTORY_ID) && !atLoadedHistoryTop()) removeHistoryButton();
    });
    mainObserver.observe(main, { childList:true, subtree:true, characterData:true });
  };

  const start = () => {
    installStyle();
    ensureLimitBanner();
    syncRoute();
    observeMain();
    scheduleLimitScan(400);
    setTimeout(probeFullConversationLimit, 900);
    setTimeout(pushSidebarData, 500);

    document.addEventListener('scroll', () => {
      syncRoute();
      if (document.getElementById(HISTORY_ID) && !atLoadedHistoryTop()) removeHistoryButton();
    }, { capture:true, passive:true });
    document.addEventListener('touchstart', (event) => {
      touchStartY = event.touches?.[0]?.clientY || 0;
      suspendForUploadMenu(event);
    }, { capture:true, passive:true });
    document.addEventListener('touchmove', (event) => {
      const y = event.touches?.[0]?.clientY || 0;
      if (touchStartY && y - touchStartY > 28 && atLoadedHistoryTop()) revealHistoryButton();
    }, { capture:true, passive:true });
    document.addEventListener('touchend', () => { touchStartY = 0; }, { capture:true, passive:true });
    document.addEventListener('pointerdown', (event) => {
      if (interceptSidebar(event)) return;
      suspendForUploadMenu(event);
    }, true);
    document.addEventListener('click', (event) => {
      const sidebar = sidebarButtonForTarget(event.target);
      if (performance.now() < sidebarInterceptUntil || sidebar) {
        const handler = window.webkit?.messageHandlers?.nativeSidebar;
        if (handler && sidebar) {
          event.preventDefault();
          event.stopPropagation();
          event.stopImmediatePropagation();
        }
      }
    }, true);
    document.addEventListener('wheel', (event) => { if (event.deltaY < -4 && atLoadedHistoryTop()) revealHistoryButton(); }, { capture:true, passive:true });
    window.addEventListener('popstate', () => setTimeout(() => { syncRoute(); observeMain(); }, 0));
    document.addEventListener('visibilitychange', () => {
      if (document.visibilityState === 'visible') setTimeout(() => { syncRoute(); observeMain(); scheduleLimitScan(0); pushSidebarData(); }, 200);
      else { removeHistoryButton(); if (rebaseTimer) { clearTimeout(rebaseTimer); rebaseTimer = 0; } }
    });
    window.addEventListener('gptwebkit:rebase-ready', scheduleRebaseCheck);
    window.addEventListener('gptwebkit:conversation-update', () => { syncRoute(); observeMain(); scheduleLimitScan(); scheduleRebaseCheck(); });
  };

  window.GPTWebKitNativeUI = { pushSidebarData, checkNativeRebase, updateLimitBanner, revealHistoryButton, probeFullConversationLimit };
  if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', start, { once:true }); else start();
})();