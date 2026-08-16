(() => {
  'use strict';
  if (window.__GPTWebKitUIEnhancements) return;
  window.__GPTWebKitUIEnhancements = true;

  const STYLE_ID = 'gptwebkit-ui-enhancements-style';
  const HISTORY_ID = 'gptwebkit-inline-history';
  let lastConversationId = '';
  let historyGestureSeen = false;
  let touchStartY = 0;
  let historyUpdateRAF = 0;
  let uploadResumeTimer = 0;
  let sidebarInterceptUntil = 0;
  let sidebarFetchBusy = false;
  let rebaseBusy = false;

  const installStyle = () => {
    let style = document.getElementById(STYLE_ID);
    if (!style) {
      style = document.createElement('style');
      style.id = STYLE_ID;
      (document.head || document.documentElement).appendChild(style);
    }
    style.textContent = `
      #gptwebkit-opt-card { color-scheme:light dark !important; }
      #gptwebkit-opt-card input[type="number"] {
        box-sizing:border-box !important;
        width:72px !important;
        min-width:72px !important;
        min-height:36px !important;
        padding:5px 8px !important;
        border:1px solid rgba(127,127,127,.5) !important;
        border-radius:8px !important;
        background:rgba(127,127,127,.18) !important;
        color:CanvasText !important;
        -webkit-text-fill-color:CanvasText !important;
        caret-color:CanvasText !important;
        outline:none !important;
      }
      #gptwebkit-opt-card input[type="number"]:focus { border-color:rgba(90,150,255,.95) !important; box-shadow:0 0 0 2px rgba(90,150,255,.2) !important; }
      #gptwebkit-opt-card button { background:rgba(127,127,127,.16) !important; color:CanvasText !important; border:1px solid rgba(127,127,127,.22) !important; }
      aside, nav[aria-label], [data-testid="history-list"], [data-testid="conversation-history"] { will-change:auto !important; }
      [data-testid="history-list"], [data-testid="conversation-history"] { contain:none !important; }
      #${HISTORY_ID} {
        position:fixed;
        z-index:2147483500;
        top:calc(env(safe-area-inset-top, 0px) + 66px);
        left:50%;
        transform:translateX(-50%);
        display:none;
        align-items:center;
        min-height:34px;
        padding:6px 12px;
        border:1px solid rgba(127,127,127,.28);
        border-radius:999px;
        background:rgba(30,30,30,.84);
        color:#fff;
        box-shadow:0 4px 16px rgba(0,0,0,.16);
        -webkit-backdrop-filter:blur(14px);
        backdrop-filter:blur(14px);
        font:13px -apple-system,BlinkMacSystemFont,sans-serif;
        white-space:nowrap;
      }
      @media (prefers-color-scheme: light) { #${HISTORY_ID} { background:rgba(250,250,250,.92); color:#111; } }
      #${HISTORY_ID}[data-visible="1"] { display:flex; }
      #${HISTORY_ID}:disabled { opacity:.55; }
    `;
  };

  const getProxy = () => window.GPTWebKitTailProxy;
  const getLongConversation = () => window.GPTWebKitLongConversation;

  const ensureHistoryButton = () => {
    let button = document.getElementById(HISTORY_ID);
    if (!button) {
      button = document.createElement('button');
      button.id = HISTORY_ID;
      button.type = 'button';
      button.textContent = '加载更早 1 轮';
      button.addEventListener('click', () => {
        if (button.disabled) return;
        button.disabled = true;
        button.textContent = '正在加载…';
        const ok = getLongConversation()?.loadEarlier?.() ?? getProxy()?.expandHistory?.();
        if (!ok) {
          button.disabled = false;
          button.textContent = '加载更早 1 轮';
        }
      });
      document.body?.appendChild(button);
    }
    return button;
  };

  const findScrollRoot = () => {
    const main = document.querySelector('main');
    const last = main ? Array.from(main.querySelectorAll('[data-testid^="conversation-turn-"], [data-message-author-role]')).pop() : null;
    const prompt = document.querySelector('#prompt-textarea, textarea, [contenteditable="true"][data-placeholder]');
    const find = (node) => {
      for (let el = node?.parentElement; el && el !== document.body; el = el.parentElement) {
        const style = getComputedStyle(el);
        if (/(auto|scroll|overlay)/.test(style.overflowY) && el.scrollHeight > el.clientHeight + 24) return el;
      }
      return null;
    };
    return find(last) || find(prompt) || document.scrollingElement || document.documentElement;
  };

  const updateHistoryButton = () => {
    const button = ensureHistoryButton();
    if (!button) return;
    const proxy = getProxy();
    const id = proxy?.currentConversationId?.() || '';
    if (id !== lastConversationId) {
      lastConversationId = id;
      historyGestureSeen = false;
    }
    const status = proxy?.getStatus?.() || {};
    const currentRounds = Number(status.currentRounds || proxy?.currentRounds?.() || 0);
    const totalRounds = Number(status.lastTotalRounds || 0);
    const hasMore = !!id && totalRounds > 0 && currentRounds > 0 && totalRounds > currentRounds;
    const root = findScrollRoot();
    const atTop = !!root && Number(root.scrollTop || 0) <= 24;
    const scrollable = !!root && Number(root.scrollHeight || 0) > Number(root.clientHeight || 0) + 40;
    const historyMode = !!proxy?.isHistoryMode?.();
    const shouldShow = hasMore && atTop && (scrollable || historyGestureSeen || historyMode);
    button.dataset.visible = shouldShow ? '1' : '0';
    if (!button.disabled) button.textContent = '加载更早 1 轮';
  };

  const scheduleHistoryUpdate = () => {
    if (historyUpdateRAF) return;
    historyUpdateRAF = requestAnimationFrame(() => {
      historyUpdateRAF = 0;
      updateHistoryButton();
    });
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
    const longConversation = getLongConversation();
    longConversation?.suspend?.();
    if (uploadResumeTimer) clearTimeout(uploadResumeTimer);
    uploadResumeTimer = setTimeout(() => {
      uploadResumeTimer = 0;
      longConversation?.resume?.();
    }, 900);
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
    return raw.map((item) => ({
      id: String(item?.id || item?.conversation_id || '').trim(),
      title: String(item?.title || item?.name || '新对话').trim() || '新对话',
      updatedAt: Number(item?.update_time || item?.updated_at || item?.create_time || 0) || 0
    })).filter((item) => item.id).slice(0, 60);
  };

  const pushSidebarData = async () => {
    const handler = window.webkit?.messageHandlers?.sidebarData;
    if (!handler || sidebarFetchBusy || document.visibilityState !== 'visible') return false;
    sidebarFetchBusy = true;
    try {
      const response = await fetch('/backend-api/conversations?offset=0&limit=28&order=updated&is_archived=false&is_starred=false', { method:'GET', credentials:'include' });
      if (!response.ok) return false;
      const data = await response.json();
      const items = normalizeSidebarItems(data);
      handler.postMessage({ items, at: Date.now() });
      return true;
    } catch (_) {
      return false;
    } finally {
      sidebarFetchBusy = false;
    }
  };

  const lockLegacyRebase = () => {
    if (!window.webkit?.messageHandlers?.rebaseRequest) return;
    const id = getProxy()?.currentConversationId?.() || '';
    if (!id) return;
    try { sessionStorage.setItem(`gptwebkit.tail.rebase.${id}`, String(Date.now())); } catch (_) {}
  };

  const checkNativeRebase = async () => {
    const handler = window.webkit?.messageHandlers?.rebaseRequest;
    if (!handler || rebaseBusy || document.visibilityState !== 'visible') return;
    lockLegacyRebase();
    const state = getLongConversation()?.getRebaseState?.();
    if (!state?.safe || Number(state.count || 0) < 6 || state.historyMode || state.generating || state.draft) return;
    const id = String(state.conversationId || getProxy()?.currentConversationId?.() || '');
    if (!id) return;
    rebaseBusy = true;
    try {
      const data = await getProxy()?.fetchFullConversation?.(id);
      const container = data?.mapping ? data : data?.conversation;
      const currentNode = String(container?.current_node || '');
      if (!currentNode || id !== (getProxy()?.currentConversationId?.() || '')) { rebaseBusy = false; return; }
      handler.postMessage({ conversationId:id, currentNode, href:location.href, count:Number(state.count || 0) });
      setTimeout(() => { rebaseBusy = false; }, 9000);
    } catch (_) {
      rebaseBusy = false;
    }
  };

  const start = () => {
    installStyle();
    ensureHistoryButton();
    updateHistoryButton();
    lockLegacyRebase();

    document.addEventListener('scroll', scheduleHistoryUpdate, { capture:true, passive:true });
    document.addEventListener('touchstart', (event) => {
      touchStartY = event.touches?.[0]?.clientY || 0;
      suspendForUploadMenu(event);
    }, { capture:true, passive:true });
    document.addEventListener('touchmove', (event) => {
      const y = event.touches?.[0]?.clientY || 0;
      if (touchStartY && y - touchStartY > 18) historyGestureSeen = true;
      scheduleHistoryUpdate();
    }, { capture:true, passive:true });
    document.addEventListener('pointerdown', (event) => {
      if (interceptSidebar(event)) return;
      suspendForUploadMenu(event);
    }, true);
    document.addEventListener('click', (event) => {
      if (performance.now() < sidebarInterceptUntil || sidebarButtonForTarget(event.target)) {
        const handler = window.webkit?.messageHandlers?.nativeSidebar;
        if (handler && sidebarButtonForTarget(event.target)) {
          event.preventDefault();
          event.stopPropagation();
          event.stopImmediatePropagation();
        }
      }
    }, true);
    document.addEventListener('wheel', (event) => {
      if (event.deltaY < 0) historyGestureSeen = true;
      scheduleHistoryUpdate();
    }, { capture:true, passive:true });
    window.addEventListener('popstate', () => {
      setTimeout(updateHistoryButton, 80);
      setTimeout(() => { lockLegacyRebase(); pushSidebarData(); }, 250);
    });
    document.addEventListener('visibilitychange', () => {
      if (document.visibilityState === 'visible') {
        lockLegacyRebase();
        setTimeout(pushSidebarData, 500);
      }
    });

    setTimeout(updateHistoryButton, 350);
    setTimeout(updateHistoryButton, 1400);
    setTimeout(pushSidebarData, 550);
    setInterval(updateHistoryButton, 5000);
    setInterval(lockLegacyRebase, 3500);
    setInterval(checkNativeRebase, 2200);
    setInterval(pushSidebarData, 45000);
  };

  window.GPTWebKitNativeUI = { pushSidebarData, checkNativeRebase, updateHistoryButton };
  if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', start, { once:true }); else start();
})();