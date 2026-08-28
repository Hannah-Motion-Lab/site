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
