(() => {
  'use strict';
  if (window.GPTWebKitMarkdown) return;

  let exportBusy = false;
  const titleOf = () => document.title.replace(/\s*[-–|]\s*ChatGPT.*$/i, '').trim() || document.querySelector('header h1')?.textContent?.trim() || 'ChatGPT Conversation';
  const roleOf = (node, index) => node.getAttribute('data-message-author-role') || node.querySelector?.('[data-message-author-role]')?.getAttribute('data-message-author-role') || (index % 2 === 0 ? 'user' : 'assistant');
  const messageNodes = () => {
    const tracked = window.GPTWebKitLongConversation?.getAllMessageNodes?.() || [];
    if (tracked.length) return tracked;
    return Array.from(document.querySelectorAll('main [data-message-author-role], main [data-testid^="conversation-turn-"]')).filter((node, index, all) => !all.some((other, i) => i !== index && other.contains(node)));
  };

  const cleanClone = (node) => {
    const clone = node.cloneNode(true);
    clone.querySelectorAll('script,style,noscript,button,svg,[aria-hidden="true"],[data-testid*="copy" i],[data-testid*="feedback" i]').forEach((item) => item.remove());
    return clone;
  };

  const escapePipes = (text) => text.replace(/\|/g, '\\|').replace(/\n+/g, ' ').trim();
  const normalize = (text) => text.replace(/[ \t]+\n/g, '\n').replace(/\n[ \t]+/g, '\n').replace(/\n{3,}/g, '\n\n').trim();
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

  const renderMessage = (node, index) => {
    const clone = cleanClone(node);
    const content = clone.querySelector('.markdown, [class*="markdown"], [data-message-author-role]') || clone;
    const role = roleOf(node, index) === 'user' ? 'User' : 'Assistant';
    return `## ${role}\n\n${normalize(renderNode(content))}`;
  };

  const currentConversation = () => {
    const nodes = messageNodes();
    const title = titleOf();
    const body = nodes.map(renderMessage).filter((item) => item.trim()).join('\n\n---\n\n');
    return { title, markdown: `# ${title}\n\n${body}\n`, count: nodes.length };
  };

  const shareResult = (result) => {
    try {
      if (window.webkit?.messageHandlers?.markdownExport) {
        window.webkit.messageHandlers.markdownExport.postMessage(result);
        return;
      }
    } catch (_) {}
    const blob = new Blob([result.markdown], { type:'text/markdown;charset=utf-8' });
    const url = URL.createObjectURL(blob);
    const a = document.createElement('a');
    a.href = url;
    a.download = `${result.title.replace(/[\\/:*?"<>|]/g, '_')}.md`;
    a.click();
    setTimeout(() => URL.revokeObjectURL(url), 1000);
  };

  const exportCurrent = () => {
    if (exportBusy) return;
    exportBusy = true;
    try {
      const result = currentConversation();
      if (!result.count) { alert('当前页面没有可导出的对话内容。'); return; }
      shareResult(result);
    } finally {
      setTimeout(() => { exportBusy = false; }, 1800);
    }
  };

  window.GPTWebKitMarkdown = { currentConversation, exportCurrent };
})();
