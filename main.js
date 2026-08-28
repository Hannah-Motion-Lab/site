// Hannah landing — the little that needs script.
// 1) Copy button for the install command.
// 2) "Watch 30 s": if the demo video actually loaded, scroll to it and play it with sound;
//    otherwise just scroll to the hero (the poster is what there is).
// 3) The hero video only plays while it is on screen, and never autoplays for people who
//    asked their OS for less motion.

(function () {
  // 0) OS switcher: one command box, three commands; the visitor's platform is preselected.
  const tabs = document.querySelectorAll('.os-tab');
  const prompt = document.querySelector('.cmd-prompt');
  const selectOs = (os) => {
    for (const t of tabs) { const on = t.dataset.os === os; t.classList.toggle('is-active', on); t.setAttribute('aria-selected', on ? 'true' : 'false'); }
    for (const el of document.querySelectorAll('[data-os]:not(.os-tab)')) el.hidden = el.dataset.os !== os;
    if (prompt) prompt.textContent = os === 'win' ? '>' : '$';
  };
  const ua = navigator.userAgent || '';
  const detected = /Windows/i.test(ua) ? 'win' : /Mac/i.test(ua) && !/iPhone|iPad/i.test(ua) ? 'mac' : /Linux|X11/i.test(ua) && !/Android/i.test(ua) ? 'linux' : null;
  if (tabs.length) {
    for (const t of tabs) t.addEventListener('click', () => selectOs(t.dataset.os));
    selectOs(detected || 'linux');
  }
  // The big buttons say which install they lead to, like every download page does.
  if (detected) {
    const name = { linux: 'Linux', mac: 'macOS', win: 'Windows' }[detected];
    for (const a of document.querySelectorAll('.cta-install')) a.textContent = `Install for ${name}`;
  }

  // 1) Copy: whichever command is visible.
  const btn = document.getElementById('copy');
  if (btn) {
    btn.addEventListener('click', async () => {
      const code = document.querySelector('.cmd code:not([hidden])');
      if (!code) return;
      try {
        await navigator.clipboard.writeText(code.textContent.trim());
        btn.textContent = 'Copied';
        btn.classList.add('done');
        setTimeout(() => { btn.textContent = 'Copy'; btn.classList.remove('done'); }, 1800);
      } catch {
        btn.textContent = 'Select & copy';
      }
    });
  }

  // 4) "Just the window": the raw builds as small links, resolved from the latest GitHub
  //    release (name suffix -> label, plus size and version). Without the API the line keeps
  //    its link to the releases page.
  const directs = document.querySelectorAll('.direct-links[data-assets]');
  if (directs.length && 'fetch' in window) {
    fetch('https://api.github.com/repos/Hannah-Motion-Lab/desktop/releases/latest', { headers: { accept: 'application/vnd.github+json' } })
      .then((r) => (r.ok ? r.json() : null))
      .then((rel) => {
        if (!rel || !Array.isArray(rel.assets)) return;
        const sums = rel.assets.find((x) => x.name === 'SHA256SUMS');
        for (const span of directs) {
          const links = [];
          for (const pair of span.dataset.assets.split('|')) {
            const [suffix, label] = pair.split('=');
            const asset = rel.assets.find((x) => x.name.endsWith(suffix));
            if (asset) links.push(`<a href="${asset.browser_download_url}">${label} <span class="ver">(${(asset.size / 1048576).toFixed(0)} MB)</span></a>`);
          }
          if (!links.length) continue;
          span.innerHTML = `<span class="ver">Hannah ${rel.tag_name.replace(/^v/, '')} ·</span> ${links.join('')}${sums ? ` <a href="${sums.browser_download_url}">SHA256SUMS</a>` : ''}`;
        }
      })
      .catch(() => {});
  }

  const video = document.getElementById('demo');
  const watch = document.getElementById('watch');
  const reduced = window.matchMedia('(prefers-reduced-motion: reduce)').matches;
  if (video) {
    if (reduced) { video.removeAttribute('autoplay'); video.pause(); }
    // Play only on screen: saves battery and stops the loop from running under the fold.
    if ('IntersectionObserver' in window && !reduced) {
      const io = new IntersectionObserver((entries) => {
        for (const e of entries) {
          if (e.isIntersecting) video.play().catch(() => {});
          else video.pause();
        }
      }, { threshold: 0.25 });
      io.observe(video);
    }
  }
  if (watch) {
    watch.addEventListener('click', () => {
      const hero = document.querySelector('.hero');
      (video || hero)?.scrollIntoView({ behavior: reduced ? 'auto' : 'smooth', block: 'center' });
      // readyState > 0 means a source was found and metadata loaded; without demo files the
      // element just shows its poster and there is nothing to unmute.
      if (video && video.readyState > 0 && !video.error) {
        video.muted = false;
        video.currentTime = 0;
        video.play().catch(() => { video.muted = true; });
      }
    });
  }
})();
