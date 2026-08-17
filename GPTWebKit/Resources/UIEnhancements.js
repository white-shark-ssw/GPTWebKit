(() => {
  'use strict';

  const LEGACY_BLOCK_STYLE_ID = 'gptwebkit-legacy-control-block';
  const PREWARM_STYLE_ID = 'gptwebkit-official-sidebar-prewarm-style';
  const blockLegacyHistoryControl = () => {
    let style = document.getElementById(LEGACY_BLOCK_STYLE_ID);
    if (!style) {
      style = document.createElement('style');
      style.id = LEGACY_BLOCK_STYLE_ID;
      (document.head || document.documentElement)?.appendChild(style);
    }
    if (style) style.textContent = '#gptwebkit-inline-history{display:none!important;visibility:hidden!important;opacity:0!important;pointer-events:none!important;}';
    document.getElementById('gptwebkit-inline-history')?.remove();
  };

  blockLegacyHistoryControl();
  if (window.__GPTWebKitUIEnhancements) {
    setTimeout(blockLegacyHistoryControl, 0);
    return;
  }
  window.__GPTWebKitUIEnhancements = true;

  let uploadResumeTimer = 0;
  let lastSidebarItems = [];
  let sidebarObserver = null;
  let sidebarObserverTimer = 0;
  let officialSidebarPrewarmState = 'idle';
  let officialSidebarPrewarmCancelled = false;
  let officialSidebarPrewarmTimer = 0;

  const installPrewarmStyle = () => {
    let style = document.getElementById(PREWARM_STYLE_ID);
    if (!style) {
      style = document.createElement('style');
      style.id = PREWARM_STYLE_ID;
      (document.head || document.documentElement)?.appendChild(style);
    }
    if (style) style.textContent = `
      html.gptwebkit-sidebar-prewarming aside,
      html.gptwebkit-sidebar-prewarming [data-testid*="sidebar" i],
      html.gptwebkit-sidebar-prewarming [class*="sidebar" i] {
        opacity:0!important;
        transition:none!important;
        animation:none!important;
        pointer-events:none!important;
      }
    `;
  };

  const removeLegacyOverlays = () => {
    blockLegacyHistoryControl();
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
    removeLegacyOverlays();
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

  const visible = (el) => {
    if (!(el instanceof HTMLElement)) return false;
    const rect = el.getBoundingClientRect();
    const style = getComputedStyle(el);
    return rect.width > 8 && rect.height > 8 && rect.bottom > 0 && rect.right > 0 && rect.top < innerHeight && rect.left < innerWidth && style.display !== 'none' && style.visibility !== 'hidden';
  };

  const buttonLabel = (button) => `${button?.getAttribute?.('aria-label') || ''} ${button?.getAttribute?.('title') || ''} ${button?.getAttribute?.('data-testid') || ''} ${button?.textContent || ''}`.replace(/\s+/g, ' ').trim();
  const topLeftButton = (button) => {
    if (!(button instanceof HTMLElement) || !visible(button)) return false;
    const rect = button.getBoundingClientRect();
    return rect.top < 130 && rect.left < Math.min(180, innerWidth * 0.36);
  };

  const findOpenSidebarButton = () => {
    const exact = document.querySelector('button[data-testid="open-sidebar-button"]');
    if (topLeftButton(exact)) return exact;
    return Array.from(document.querySelectorAll('button')).find((button) => topLeftButton(button) && /open.*sidebar|打开.*侧|侧边栏|侧栏|open menu|打开菜单/i.test(buttonLabel(button))) || null;
  };

  const findCloseSidebarButton = () => {
    const exact = document.querySelector('button[data-testid="close-sidebar-button"]');
    if (visible(exact)) return exact;
    return Array.from(document.querySelectorAll('button')).find((button) => visible(button) && /close.*sidebar|关闭.*侧|收起.*侧|close menu|关闭菜单/i.test(buttonLabel(button))) || null;
  };

  const sidebarSurface = () => {
    const candidates = Array.from(document.querySelectorAll('aside,nav,[data-testid*="sidebar" i],[class*="sidebar" i]'));
    return candidates.find((node) => {
      if (!visible(node)) return false;
      const rect = node.getBoundingClientRect();
      return rect.left < 30 && rect.width > Math.min(220, innerWidth * 0.55) && rect.height > innerHeight * 0.55;
    }) || null;
  };

  const isOfficialSidebarOpen = () => !!findCloseSidebarButton() || !!sidebarSurface();

  const looksLikeSidebarButton = (target) => {
    const button = target?.closest?.('button');
    if (!(button instanceof HTMLElement)) return false;
    if (button.matches('button[data-testid="open-sidebar-button"], button[data-testid="close-sidebar-button"], button[data-testid*="sidebar" i], button[aria-label*="sidebar" i], button[title*="sidebar" i]')) return true;
    return topLeftButton(button) && /侧边栏|侧栏|打开菜单|关闭菜单|open menu|close menu|sidebar/i.test(buttonLabel(button));
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

  const closePrewarmedSidebar = async (openButton) => {
    if (officialSidebarPrewarmCancelled) return;
    const close = findCloseSidebarButton();
    if (close) close.click();
    else if (openButton && visible(openButton)) openButton.click();
    else {
      try { document.dispatchEvent(new KeyboardEvent('keydown', { key:'Escape', code:'Escape', bubbles:true, cancelable:true })); } catch (_) {}
    }
    const deadline = performance.now() + 650;
    while (!officialSidebarPrewarmCancelled && isOfficialSidebarOpen() && performance.now() < deadline) await new Promise((resolve) => setTimeout(resolve, 25));
  };

  const prewarmOfficialSidebar = async () => {
    if (officialSidebarPrewarmState !== 'idle' || officialSidebarPrewarmCancelled || document.visibilityState !== 'visible') return false;
    const openButton = findOpenSidebarButton();
    if (!openButton) return false;
    if (isOfficialSidebarOpen()) { officialSidebarPrewarmState = 'ready'; return true; }

    officialSidebarPrewarmState = 'opening';
    installPrewarmStyle();
    document.documentElement?.classList?.add('gptwebkit-sidebar-prewarming');
    try {
      openButton.click();
      const deadline = performance.now() + 1500;
      while (!officialSidebarPrewarmCancelled && !isOfficialSidebarOpen() && performance.now() < deadline) await new Promise((resolve) => setTimeout(resolve, 25));
      if (officialSidebarPrewarmCancelled) return false;
      if (!isOfficialSidebarOpen()) { officialSidebarPrewarmState = 'idle'; return false; }
      watchOfficialSidebar();
      await new Promise((resolve) => setTimeout(resolve, 90));
      await closePrewarmedSidebar(openButton);
      pushSidebarData();
      officialSidebarPrewarmState = 'ready';
      return true;
    } catch (_) {
      officialSidebarPrewarmState = 'idle';
      return false;
    } finally {
      document.documentElement?.classList?.remove('gptwebkit-sidebar-prewarming');
    }
  };

  const scheduleOfficialSidebarPrewarm = () => {
    if (officialSidebarPrewarmCancelled || officialSidebarPrewarmState === 'ready' || officialSidebarPrewarmTimer) return;
    let attempts = 0;
    const attempt = async () => {
      officialSidebarPrewarmTimer = 0;
      if (officialSidebarPrewarmCancelled || officialSidebarPrewarmState === 'ready') return;
      attempts++;
      const ok = await prewarmOfficialSidebar();
      if (!ok && !officialSidebarPrewarmCancelled && attempts < 18) officialSidebarPrewarmTimer = setTimeout(attempt, 100);
    };
    officialSidebarPrewarmTimer = setTimeout(attempt, 40);
  };

  const cancelPrewarmForUser = (event) => {
    if (!event?.isTrusted) return;
    officialSidebarPrewarmCancelled = true;
    if (officialSidebarPrewarmTimer) clearTimeout(officialSidebarPrewarmTimer);
    officialSidebarPrewarmTimer = 0;
    document.documentElement?.classList?.remove('gptwebkit-sidebar-prewarming');
  };

  const openOfficialSidebar = () => {
    officialSidebarPrewarmCancelled = true;
    document.documentElement?.classList?.remove('gptwebkit-sidebar-prewarming');
    if (isOfficialSidebarOpen()) return true;
    const button = findOpenSidebarButton();
    if (!button) return false;
    button.click();
    watchOfficialSidebar();
    return true;
  };

  const start = () => {
    removeLegacyOverlays();
    installPrewarmStyle();
    installPassiveHistoryCapture();
    document.addEventListener('touchstart', (event) => { cancelPrewarmForUser(event); suspendForUploadMenu(event); }, { capture:true, passive:true });
    document.addEventListener('pointerdown', (event) => {
      cancelPrewarmForUser(event);
      if (event.isTrusted && looksLikeSidebarButton(event.target)) watchOfficialSidebar();
      suspendForUploadMenu(event);
    }, true);
    document.addEventListener('click', (event) => {
      if (event.isTrusted && looksLikeSidebarButton(event.target)) watchOfficialSidebar();
    }, true);
    addEventListener('pageshow', removeLegacyOverlays, { passive:true });
    setTimeout(removeLegacyOverlays, 120);
    setTimeout(pushSidebarData, 180);
    scheduleOfficialSidebarPrewarm();
  };

  window.GPTWebKitNativeUI = { pushSidebarData, sidebarDOMItems, removeLegacyOverlays, openOfficialSidebar, prewarmOfficialSidebar, isOfficialSidebarOpen };
  if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', start, { once:true });
  else start();
})();
