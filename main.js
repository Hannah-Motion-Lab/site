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
  if (tabs.length) {
    for (const t of tabs) t.addEventListener('click', () => selectOs(t.dataset.os));
    const ua = navigator.userAgent || '';
    selectOs(/Windows/i.test(ua) ? 'win' : /Mac/i.test(ua) && !/iPhone|iPad/i.test(ua) ? 'mac' : 'linux');
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

  // 4) Desktop builds: the links point at the releases page; if the GitHub API answers, each
  //    one becomes a direct download of the matching asset (by name suffix) with its size.
  const builds = document.querySelectorAll('.builds-list a[data-asset]');
  if (builds.length && 'fetch' in window) {
    fetch('https://api.github.com/repos/Hannah-Motion-Lab/desktop/releases/latest', { headers: { accept: 'application/vnd.github+json' } })
      .then((r) => (r.ok ? r.json() : null))
      .then((rel) => {
        if (!rel || !Array.isArray(rel.assets)) return;
        for (const a of builds) {
          const asset = rel.assets.find((x) => x.name.endsWith(a.dataset.asset));
          const hint = a.querySelector('span');
          if (asset) {
            a.href = asset.browser_download_url;
            if (hint) hint.textContent = `${hint.textContent} · ${(asset.size / 1048576).toFixed(0)} MB · ${rel.tag_name}`;
          } else {
            a.classList.add('is-missing');
            if (hint) hint.textContent = `${hint.textContent} · not in ${rel.tag_name} yet`;
          }
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
