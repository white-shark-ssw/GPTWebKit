(() => {
  'use strict';
  if (window.__GPTWebKitUIEnhancements) return;
  window.__GPTWebKitUIEnhancements = true;

  const STYLE_ID = 'gptwebkit-ui-enhancements-style';
  const HISTORY_ID = 'gptwebkit-inline-history';
  const WARM_CLASS = 'gptwebkit-sidebar-warming';
  let sidebarWarmState = 'idle';
  let sidebarWarmCancelled = false;

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
        min-width:72px !important;
        min-height:36px !important;
        padding:5px 8px !important;
        border:1px solid rgba(127,127,127,.45) !important;
        border-radius:8px !important;
        background:rgba(127,127,127,.16) !important;
        color:inherit !important;
        -webkit-text-fill-color:currentColor !important;
        caret-color:currentColor !important;
        outline:none !important;
      }
      #gptwebkit-opt-card input[type="number"]:focus { border-color:rgba(90,150,255,.95) !important; box-shadow:0 0 0 2px rgba(90,150,255,.2) !important; }
      #gptwebkit-opt-card button { background:rgba(127,127,127,.16) !important; color:inherit !important; border:1px solid rgba(127,127,127,.22) !important; }
      #${HISTORY_ID} {
        position:fixed;
        z-index:2147483500;
        top:calc(env(safe-area-inset-top, 0px) + 68px);
        left:50%;
        transform:translateX(-50%);
        display:none;
        align-items:center;
        gap:6px;
        min-height:34px;
        padding:6px 12px;
        border:1px solid rgba(127,127,127,.28);
        border-radius:999px;
        background:rgba(30,30,30,.82);
        color:#fff;
        box-shadow:0 4px 16px rgba(0,0,0,.18);
        -webkit-backdrop-filter:blur(14px);
        backdrop-filter:blur(14px);
        font:13px -apple-system,BlinkMacSystemFont,sans-serif;
        white-space:nowrap;
      }
      @media (prefers-color-scheme: light) { #${HISTORY_ID} { background:rgba(250,250,250,.9); color:#111; } }
      #${HISTORY_ID}[data-visible="1"] { display:flex; }
      #${HISTORY_ID}:disabled { opacity:.55; }
      html.${WARM_CLASS} aside,
      html.${WARM_CLASS} [data-testid*="sidebar" i],
      html.${WARM_CLASS} [class*="sidebar" i][role="dialog"] {
        animation:none !important;
        transition:none !important;
        opacity:0 !important;
        pointer-events:none !important;
      }
      aside, nav[aria-label], [data-testid="history-list"], [data-testid="conversation-history"] { will-change:auto !important; }
      [data-testid="history-list"], [data-testid="conversation-history"] { contain:none !important; }
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

  const updateHistoryButton = () => {
    const button = ensureHistoryButton();
    if (!button) return;
    const proxy = getProxy();
    const id = proxy?.currentConversationId?.() || '';
    const status = proxy?.getStatus?.() || {};
    const currentRounds = Number(status.currentRounds || proxy?.currentRounds?.() || 0);
    const totalRounds = Number(status.lastTotalRounds || 0);
    const hasMore = !!id && totalRounds > 0 && currentRounds > 0 && totalRounds > currentRounds;
    button.dataset.visible = hasMore ? '1' : '0';
    if (!button.disabled) button.textContent = '加载更早 1 轮';
  };

  const visible = (element) => {
    if (!(element instanceof HTMLElement)) return false;
    const rect = element.getBoundingClientRect();
    const style = getComputedStyle(element);
    return rect.width > 160 && rect.height > 120 && style.display !== 'none' && style.visibility !== 'hidden';
  };

  const sidebarElement = () => {
    const candidates = [
      ...document.querySelectorAll('aside'),
      ...document.querySelectorAll('[data-testid*="sidebar" i]'),
      ...document.querySelectorAll('[class*="sidebar" i][role="dialog"]')
    ];
    return candidates.find(visible) || null;
  };

  const findSidebarToggle = () => {
    const direct = document.querySelector('button[data-testid*="sidebar" i], button[aria-label*="sidebar" i], button[title*="sidebar" i]');
    if (direct instanceof HTMLElement) return direct;
    for (const button of document.querySelectorAll('button')) {
      const text = `${button.getAttribute('aria-label') || ''} ${button.getAttribute('title') || ''} ${button.textContent || ''}`.trim();
      if (/侧边栏|sidebar|侧栏/i.test(text)) return button;
    }
    return null;
  };

  const finishSidebarWarmup = (leaveOpen = false) => {
    if (sidebarWarmState !== 'warming') return;
    if (!leaveOpen && sidebarElement()) {
      const toggle = findSidebarToggle();
      try { toggle?.click?.(); } catch (_) {}
    }
    document.documentElement.classList.remove(WARM_CLASS);
    sidebarWarmState = 'done';
  };

  const warmSidebarDOM = () => {
    const settings = getLongConversation()?.getSettings?.() || getProxy()?.getSettings?.() || {};
    if (!settings.optimizeSidebar || sidebarWarmState !== 'idle' || document.visibilityState !== 'visible') return;
    if (sidebarElement()) { sidebarWarmState = 'done'; return; }

    const toggle = findSidebarToggle();
    if (!toggle) return;
    sidebarWarmState = 'warming';
    sidebarWarmCancelled = false;
    document.documentElement.classList.add(WARM_CLASS);
    try { toggle.click(); } catch (_) { finishSidebarWarmup(true); return; }

    const started = performance.now();
    const poll = () => {
      if (sidebarWarmState !== 'warming') return;
      if (sidebarWarmCancelled) { finishSidebarWarmup(true); return; }
      if (sidebarElement()) {
        setTimeout(() => finishSidebarWarmup(false), 140);
        return;
      }
      if (performance.now() - started > 1600) { finishSidebarWarmup(true); return; }
      setTimeout(poll, 50);
    };
    setTimeout(poll, 50);
  };

  const cancelWarmupForUser = (event) => {
    if (sidebarWarmState !== 'warming' || !event.isTrusted) return;
    sidebarWarmCancelled = true;
    document.documentElement.classList.remove(WARM_CLASS);
  };

  const start = () => {
    installStyle();
    ensureHistoryButton();
    document.addEventListener('pointerdown', cancelWarmupForUser, true);
    document.addEventListener('touchstart', cancelWarmupForUser, { capture:true, passive:true });

    let ticks = 0;
    const startupTimer = setInterval(() => {
      installStyle();
      updateHistoryButton();
      if (sidebarWarmState === 'idle') warmSidebarDOM();
      if (++ticks >= 80 || sidebarWarmState === 'done') clearInterval(startupTimer);
    }, 100);

    setInterval(updateHistoryButton, 900);
    window.addEventListener('popstate', () => setTimeout(updateHistoryButton, 100));
  };

  if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', start, { once:true }); else start();
})();