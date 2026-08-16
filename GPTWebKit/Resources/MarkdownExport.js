(() => {
  'use strict';
  if (window.GPTWebKitMarkdown) return;

  let exportBusy = false;
  const titleOfPage = () => document.title.replace(/\s*[-–|]\s*ChatGPT.*$/i, '').trim() || document.querySelector('header h1')?.textContent?.trim() || 'ChatGPT Conversation';
  const normalize = (text) => String(text || '').replace(/\r\n/g, '\n').replace(/[ \t]+\n/g, '\n').replace(/\n[ \t]+/g, '\n').replace(/\n{3,}/g, '\n\n').trim();

  const messageNodes = () => {
    const tracked = window.GPTWebKitLongConversation?.getAllMessageNodes?.() || [];
    if (tracked.length) return tracked;
    const turns = Array.from(document.querySelectorAll('main [data-testid^="conversation-turn-"]'));
    if (turns.length) return turns;
    return Array.from(document.querySelectorAll('main [data-message-author-role]')).filter((node) => !node.parentElement?.closest?.('[data-message-author-role]'));
  };

  const roleOfNode = (node, index) => node.getAttribute('data-message-author-role') || node.querySelector?.('[data-message-author-role]')?.getAttribute('data-message-author-role') || (index % 2 === 0 ? 'user' : 'assistant');
  const cleanClone = (node) => {
    const clone = node.cloneNode(true);
    clone.querySelectorAll('script,style,noscript,button,svg,[aria-hidden="true"],[data-testid*="copy" i],[data-testid*="feedback" i]').forEach((item) => item.remove());
    return clone;
  };
  const escapePipes = (text) => text.replace(/\|/g, '\\|').replace(/\n+/g, ' ').trim();
  const children = (node) => Array.from(node.childNodes).map(renderNode).join('');

  const renderTable = (table) => {
    const rows = Array.from(table.querySelectorAll('tr')).map((row) => Array.from(row.querySelectorAll(':scope > th, :scope > td')).map((cell) => escapePipes(normalize(children(cell))))).filter((row) => row.length);
    if (!rows.length) return '';
    const width = Math.max(...rows.map((row) => row.length));
    const pad = (row) => Array.from({ length: width }, (_, i) => row[i] || '');
    const header = pad(rows[0]);
    const body = rows.slice(1).map(pad);
    return `\n\n| ${header.join(' | ')} |\n| ${header.map(() => '---').join(' | ')} |${body.length ? `\n${body.map((row) => `| ${row.join(' | ')} |`).join('\n')}` : ''}\n\n`;
  };

  const renderList = (list) => {
    const ordered = list.tagName === 'OL';
    let index = Number(list.getAttribute('start') || 1);
    const lines = [];
    for (const li of Array.from(list.children).filter((item) => item.tagName === 'LI')) {
      const clone = li.cloneNode(true);
      clone.querySelectorAll(':scope > ul, :scope > ol').forEach((item) => item.remove());
      const prefix = ordered ? `${index++}. ` : '- ';
      const main = normalize(children(clone)).replace(/\n/g, '\n  ');
      lines.push(prefix + main);
      for (const nested of Array.from(li.children).filter((item) => item.tagName === 'UL' || item.tagName === 'OL')) {
        const nestedText = renderList(nested).trim().split('\n').map((line) => `  ${line}`).join('\n');
        if (nestedText) lines.push(nestedText);
      }
    }
    return `\n${lines.join('\n')}\n`;
  };

  const mathSource = (element) => {
    const annotation = element.querySelector?.('annotation[encoding="application/x-tex"]');
    return element.getAttribute?.('data-latex') || annotation?.textContent || '';
  };

  function renderNode(node) {
    if (!node) return '';
    if (node.nodeType === Node.TEXT_NODE) return node.nodeValue || '';
    if (node.nodeType !== Node.ELEMENT_NODE) return '';
    const el = node;
    const tag = el.tagName;
    if (tag === 'BR') return '\n';
    if (/^H[1-6]$/.test(tag)) return `\n\n${'#'.repeat(Number(tag[1]))} ${normalize(children(el))}\n\n`;
    if (tag === 'P') return `\n\n${children(el)}\n\n`;
    if (tag === 'STRONG' || tag === 'B') return `**${children(el)}**`;
    if (tag === 'EM' || tag === 'I') return `*${children(el)}*`;
    if (tag === 'DEL' || tag === 'S') return `~~${children(el)}~~`;
    if (tag === 'BLOCKQUOTE') return `\n\n${normalize(children(el)).split('\n').map((line) => `> ${line}`).join('\n')}\n\n`;
    if (tag === 'HR') return '\n\n---\n\n';
    if (tag === 'UL' || tag === 'OL') return renderList(el);
    if (tag === 'TABLE') return renderTable(el);
    if (tag === 'PRE') {
      const code = el.querySelector('code') || el;
      const language = code.getAttribute('data-language') || Array.from(code.classList || []).map((item) => item.match(/^language-(.+)$/)?.[1]).find(Boolean) || '';
      const value = (code.textContent || '').replace(/\n$/, '');
      const longest = Math.max(3, ...Array.from(value.matchAll(/`+/g), (match) => match[0].length + 1));
      const fence = '`'.repeat(longest);
      return `\n\n${fence}${language}\n${value}\n${fence}\n\n`;
    }
    if (tag === 'CODE') {
      const value = el.textContent || '';
      const fence = value.includes('`') ? '``' : '`';
      return `${fence}${value}${fence}`;
    }
    if (tag === 'A') {
      const href = el.getAttribute('href') || '';
      const text = normalize(children(el)) || href;
      if (!href || href.startsWith('javascript:')) return text;
      return `[${text}](${href})`;
    }
    if (tag === 'IMG') {
      const src = el.getAttribute('src') || '';
      if (!src) return '';
      return `![${el.getAttribute('alt') || ''}](${src})`;
    }
    if (tag === 'SUP') return children(el);
    if (tag === 'DETAILS') {
      const summary = el.querySelector(':scope > summary')?.textContent?.trim();
      const clone = el.cloneNode(true);
      clone.querySelector(':scope > summary')?.remove();
      const body = normalize(children(clone));
      return `\n\n${summary ? `**${summary}**\n\n` : ''}${body}\n\n`;
    }
    if (el.matches?.('.katex, .katex-display, [data-latex]')) {
      const tex = mathSource(el);
      if (tex) return el.matches('.katex-display') || el.closest('.katex-display') === el ? `\n\n$$\n${tex}\n$$\n\n` : `$${tex}$`;
    }
    return children(el);
  }

  const renderDOMMessage = (node, index) => {
    const clone = cleanClone(node);
    const content = clone.querySelector('.markdown, [class*="markdown"], [data-message-author-role]') || clone;
    const role = roleOfNode(node, index) === 'user' ? 'User' : 'Assistant';
    return `## ${role}\n\n${normalize(renderNode(content))}`;
  };

  const currentConversationFromDOM = () => {
    const nodes = messageNodes();
    const title = titleOfPage();
    const body = nodes.map(renderDOMMessage).filter((item) => item.trim()).join('\n\n---\n\n');
    return { title, markdown: `# ${title}\n\n${body}\n`, count: nodes.length, source: 'dom' };
  };

  const containerOf = (data) => {
    if (data?.mapping && typeof data.mapping === 'object') return data;
    if (data?.conversation?.mapping && typeof data.conversation.mapping === 'object') return data.conversation;
    return null;
  };

  const currentPath = (mapping, currentNode) => {
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

  const partToText = (part) => {
    if (typeof part === 'string') return part;
    if (!part || typeof part !== 'object') return '';
    if (typeof part.text === 'string') return part.text;
    if (typeof part.content === 'string') return part.content;
    if (typeof part.transcript === 'string') return part.transcript;
    if (part.content_type === 'image_asset_pointer' || part.asset_pointer) return '[图片]';
    return '';
  };

  const messageText = (message) => {
    const content = message?.content || {};
    const parts = Array.isArray(content.parts) ? content.parts : [];
    let text = parts.map(partToText).filter(Boolean).join('\n');
    if (!text && typeof content.text === 'string') text = content.text;
    text = normalize(text);
    return text.replace(/cite[^]+/g, '').replace(/[^]+/g, '').trim();
  };

  const sourceEntries = (message) => {
    const metadata = message?.metadata || {};
    const candidates = [];
    if (Array.isArray(metadata.content_references)) candidates.push(...metadata.content_references);
    if (Array.isArray(metadata.citations)) candidates.push(...metadata.citations);
    const seen = new Set();
    const out = [];
    const scan = (value, depth = 0) => {
      if (!value || depth > 3) return;
      if (Array.isArray(value)) { value.forEach((item) => scan(item, depth + 1)); return; }
      if (typeof value !== 'object') return;
      const url = typeof value.url === 'string' && /^https?:\/\//i.test(value.url) ? value.url : '';
      const title = typeof value.title === 'string' ? value.title.trim() : '';
      if (url && !seen.has(url)) { seen.add(url); out.push({ title: title || url, url }); }
      for (const key of ['metadata', 'source', 'sources', 'attribution', 'items']) if (value[key]) scan(value[key], depth + 1);
    };
    candidates.forEach((item) => scan(item));
    return out;
  };

  const renderJSONMessage = (node) => {
    const message = node?.message;
    const role = message?.author?.role;
    if (role !== 'user' && role !== 'assistant') return '';
    const text = messageText(message);
    if (!text) return '';
    const heading = role === 'user' ? 'User' : 'Assistant';
    const sources = sourceEntries(message);
    const sourceText = sources.length ? `\n\n### Sources\n\n${sources.map((item) => `- [${item.title.replace(/\]/g, '\\]')}](${item.url})`).join('\n')}` : '';
    return `## ${heading}\n\n${text}${sourceText}`;
  };

  const fullConversation = async () => {
    const proxy = window.GPTWebKitTailProxy;
    const id = proxy?.currentConversationId?.() || '';
    if (!proxy?.fetchFullConversation || !id) return currentConversationFromDOM();
    const data = await proxy.fetchFullConversation(id);
    const container = containerOf(data);
    if (!container?.mapping || !container?.current_node) throw new Error('完整会话结构无法识别');
    const path = currentPath(container.mapping, container.current_node);
    const rendered = path.map((nodeId) => renderJSONMessage(container.mapping[nodeId])).filter(Boolean);
    if (!rendered.length) throw new Error('完整会话中没有可导出的用户/助手消息');
    const title = normalize(container.title || data?.title || titleOfPage()) || 'ChatGPT Conversation';
    return { title, markdown: `# ${title}\n\n${rendered.join('\n\n---\n\n')}\n`, count: rendered.length, source: 'full-json', conversationId: id, currentNode: container.current_node };
  };

  const shareResult = (result) => {
    try {
      if (window.webkit?.messageHandlers?.markdownExport) {
        window.webkit.messageHandlers.markdownExport.postMessage(result);
        return;
      }
    } catch (_) {}
    const blob = new Blob([result.markdown], { type: 'text/markdown;charset=utf-8' });
    const url = URL.createObjectURL(blob);
    const a = document.createElement('a');
    a.href = url;
    a.download = `${result.title.replace(/[\\/:*?"<>|]/g, '_')}.md`;
    a.click();
    setTimeout(() => URL.revokeObjectURL(url), 1000);
  };

  const exportCurrent = async () => {
    if (exportBusy) return;
    exportBusy = true;
    try {
      const result = await fullConversation();
      shareResult(result);
    } catch (error) {
      alert(`导出失败：${error?.message || error}`);
    } finally {
      setTimeout(() => { exportBusy = false; }, 1200);
    }
  };

  window.GPTWebKitMarkdown = { currentConversation: currentConversationFromDOM, fullConversation, exportCurrent };
})();

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
      #gptwebkit-opt-card input[type="number"] { box-sizing:border-box !important; min-width:72px !important; min-height:36px !important; padding:5px 8px !important; border:1px solid rgba(127,127,127,.45) !important; border-radius:8px !important; background:rgba(127,127,127,.16) !important; color:inherit !important; -webkit-text-fill-color:currentColor !important; caret-color:currentColor !important; outline:none !important; }
      #gptwebkit-opt-card input[type="number"]:focus { border-color:rgba(90,150,255,.95) !important; box-shadow:0 0 0 2px rgba(90,150,255,.2) !important; }
      #gptwebkit-opt-card button { background:rgba(127,127,127,.16) !important; color:inherit !important; border:1px solid rgba(127,127,127,.22) !important; }
      #${HISTORY_ID} { position:fixed; z-index:2147483500; top:calc(env(safe-area-inset-top, 0px) + 68px); left:50%; transform:translateX(-50%); display:none; align-items:center; gap:6px; min-height:34px; padding:6px 12px; border:1px solid rgba(127,127,127,.28); border-radius:999px; background:rgba(30,30,30,.82); color:#fff; box-shadow:0 4px 16px rgba(0,0,0,.18); -webkit-backdrop-filter:blur(14px); backdrop-filter:blur(14px); font:13px -apple-system,BlinkMacSystemFont,sans-serif; white-space:nowrap; }
      @media (prefers-color-scheme: light) { #${HISTORY_ID} { background:rgba(250,250,250,.9); color:#111; } }
      #${HISTORY_ID}[data-visible="1"] { display:flex; }
      #${HISTORY_ID}:disabled { opacity:.55; }
      html.${WARM_CLASS} aside, html.${WARM_CLASS} [data-testid*="sidebar" i], html.${WARM_CLASS} [class*="sidebar" i][role="dialog"] { animation:none !important; transition:none !important; opacity:0 !important; pointer-events:none !important; }
      aside, nav[aria-label], [data-testid="history-list"], [data-testid="conversation-history"] { will-change:auto !important; }
      [data-testid="history-list"], [data-testid="conversation-history"] { contain:none !important; }
    `;
  };

  const getProxy = () => window.GPTWebKitTailProxy;
  const getLongConversation = () => window.GPTWebKitLongConversation;

  const ensureHistoryButton = () => {
    let button = document.getElementById(HISTORY_ID);
    if (!button && document.body) {
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
      document.body.appendChild(button);
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
    const candidates = [...document.querySelectorAll('aside'), ...document.querySelectorAll('[data-testid*="sidebar" i]'), ...document.querySelectorAll('[class*="sidebar" i][role="dialog"]')];
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
      if (sidebarElement()) { setTimeout(() => finishSidebarWarmup(false), 140); return; }
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