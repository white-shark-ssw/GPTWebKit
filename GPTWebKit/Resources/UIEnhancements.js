(() => {
  'use strict';
  if (window.__GPTWebKitUIEnhancements) return;
  window.__GPTWebKitUIEnhancements = true;

  let uploadResumeTimer = 0;
  let lastSidebarItems = [];
  let sidebarObserver = null;
  let sidebarObserverTimer = 0;

  const removeLegacyOverlays = () => {
    document.getElementById('gptwebkit-inline-history')?.remove();
    document.getElementById('gptwebkit-conversation-limit')?.remove();
    document.getElementById('gptwebkit-ui-enhancements-style')?.remove();
    document.getElementById('gptwebkit-sidebar-hydrate-style')?.remove();
    document.documentElement?.classList?.remove('gptwebkit-sidebar-hydrating');
  };

  const getLongConversation = () => window.GPTWebKitLongConversation;

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
    uploadResumeTimer = setTimeout(() => {
      uploadResumeTimer = 0;
      getLongConversation()?.resume?.();
    }, 900);
  };

  const normalizeSidebarItems = (data) => {
    const raw = Array.isArray(data?.items) ? data.items : (Array.isArray(data?.conversations) ? data.conversations : (Array.isArray(data) ? data : []));
    const seen = new Set();
    const items = [];
    for (const item of raw) {
      const id = String(item?.id || item?.conversation_id || '').trim();
      if (!id || seen.has(id)) continue;
      seen.add(id);
      const title = String(item?.title || item?.name || '新对话').replace(/\s+/g, ' ').trim() || '新对话';
      items.push({ id, title, updatedAt:Number(item?.update_time || item?.updated_at || item?.create_time || 0) || 0 });
      if (items.length >= 60) break;
    }
    return items;
  };

  const publishSidebarItems = (items, extra = {}) => {
    const handler = window.webkit?.messageHandlers?.sidebarData;
    if (!handler || !Array.isArray(items)) return false;
    if (items.length) lastSidebarItems = items;
    try {
      handler.postMessage({ items, at:Date.now(), ...extra });
      return true;
    } catch (_) {
      return false;
    }
  };

  const sidebarDOMItems = () => {
    const seen = new Set();
    const items = [];
    for (const anchor of document.querySelectorAll('a[href*="/c/"]')) {
      let url;
      try { url = new URL(anchor.getAttribute('href') || '', location.href); } catch (_) { continue; }
      const id = url.pathname.match(/^\/c\/([^/?#]+)/)?.[1] || '';
      if (!id || seen.has(id)) continue;
      let title = String(anchor.textContent || '').replace(/\s+/g, ' ').trim();
      if (!title) title = String(anchor.getAttribute('aria-label') || anchor.getAttribute('title') || '').trim();
      if (!title || title.length > 240) continue;
      seen.add(id);
      items.push({ id, title, updatedAt:0 });
      if (items.length >= 60) break;
    }
    return items;
  };

  const pushSidebarData = () => {
    const dom = sidebarDOMItems();
    if (dom.length) return publishSidebarItems(dom, { source:'dom' });
    if (lastSidebarItems.length) return publishSidebarItems(lastSidebarItems, { source:'network-cache' });
    return false;
  };

  const parseFetch = (input, init) => {
    try {
      const method = String(init?.method || (input instanceof Request ? input.method : 'GET') || 'GET').toUpperCase();
      const href = input instanceof Request ? input.url : (input instanceof URL ? input.href : String(input || ''));
      return { url:new URL(href, location.href), method };
    } catch (_) {
      return { url:null, method:'GET' };
    }
  };

  const captureHistoryResponse = (parsed, response) => {
    if (!parsed.url || parsed.method !== 'GET' || parsed.url.pathname !== '/backend-api/conversations') return;
    if (Number(parsed.url.searchParams.get('offset') || 0) !== 0) return;
    const clone = response.clone();
    Promise.resolve().then(async () => {
      try {
        if (!clone.ok) return;
        const data = await clone.json();
        const items = normalizeSidebarItems(data);
        publishSidebarItems(items, { source:'official-fetch', confirmedEmpty:items.length === 0, status:clone.status });
      } catch (_) {}
    });
  };

  const installPassiveHistoryCapture = () => {
    const baseFetch = window.fetch;
    if (typeof baseFetch !== 'function' || baseFetch.__gptwebkitPassiveHistoryCapture) return;
    const wrapped = async function(...args) {
      const parsed = parseFetch(args[0], args[1]);
      const response = await baseFetch.apply(this, args);
      try { captureHistoryResponse(parsed, response); } catch (_) {}
      return response;
    };
    wrapped.__gptwebkitPassiveHistoryCapture = true;
    window.fetch = wrapped;
  };

  const looksLikeSidebarButton = (target) => {
    const button = target?.closest?.('button');
    if (!(button instanceof HTMLElement)) return false;
    if (button.matches('button[data-testid="open-sidebar-button"], button[data-testid="close-sidebar-button"], button[data-testid*="sidebar" i], button[aria-label*="sidebar" i], button[title*="sidebar" i]')) return true;
    const rect = button.getBoundingClientRect();
    if (rect.top > 120 || rect.left > innerWidth * 0.32) return false;
    const label = `${button.getAttribute('aria-label') || ''} ${button.getAttribute('title') || ''} ${button.getAttribute('data-testid') || ''} ${button.textContent || ''}`;
    return /侧边栏|侧栏|打开菜单|关闭菜单|open menu|close menu|sidebar/i.test(label);
  };

  const watchOfficialSidebar = () => {
    if (pushSidebarData()) return;
    sidebarObserver?.disconnect();
    if (sidebarObserverTimer) clearTimeout(sidebarObserverTimer);
    const root = document.body || document.documentElement;
    if (!root) return;
    sidebarObserver = new MutationObserver(() => {
      if (!pushSidebarData()) return;
      sidebarObserver?.disconnect();
      sidebarObserver = null;
      if (sidebarObserverTimer) clearTimeout(sidebarObserverTimer);
      sidebarObserverTimer = 0;
    });
    sidebarObserver.observe(root, { childList:true, subtree:true });
    sidebarObserverTimer = setTimeout(() => {
      pushSidebarData();
      sidebarObserver?.disconnect();
      sidebarObserver = null;
      sidebarObserverTimer = 0;
    }, 4000);
  };

  const start = () => {
    removeLegacyOverlays();
    installPassiveHistoryCapture();
    document.addEventListener('touchstart', suspendForUploadMenu, { capture:true, passive:true });
    document.addEventListener('pointerdown', (event) => {
      if (event.isTrusted && looksLikeSidebarButton(event.target)) watchOfficialSidebar();
      suspendForUploadMenu(event);
    }, true);
    document.addEventListener('click', (event) => {
      if (event.isTrusted && looksLikeSidebarButton(event.target)) watchOfficialSidebar();
    }, true);
    setTimeout(pushSidebarData, 180);
  };

  window.GPTWebKitNativeUI = { pushSidebarData, sidebarDOMItems };
  if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', start, { once:true });
  else start();
})();