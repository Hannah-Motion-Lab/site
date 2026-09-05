// Hannah landing: the script behind the HUD.
// 0) OS switcher and copy button for the install command.
// 1) Captures play only while on screen; with reduced motion they never autoplay (controls instead).
// 2) Reveals: sections rise into place as they enter; the html.js class is what hides them first,
//    so without script nothing is hidden.
// 3) The progress hairline at the top.
// 4) The job, step by step: the step nearest the middle of the screen picks the capture.

(function () {
  const html = document.documentElement;
  html.classList.add('js');
  const reduced = window.matchMedia('(prefers-reduced-motion: reduce)').matches;
  const hasIO = 'IntersectionObserver' in window;
  const clamp = (v, a, b) => Math.min(b, Math.max(a, v));

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
  if (detected) {
    const name = { linux: 'Linux', mac: 'macOS', win: 'Windows' }[detected];
    for (const a of document.querySelectorAll('.cta-install')) a.textContent = `Install for ${name}`;
  }
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

  // 1) Captures: play on screen, pause off screen. Saves battery and keeps a dozen clips from
  //    decoding at once. preload="none" means a clip only downloads when it first plays.
  const clips = document.querySelectorAll('video[data-auto]');
  if (reduced) {
    for (const v of clips) {
      v.removeAttribute('autoplay'); v.pause();
      v.controls = true;
    }
  } else if (hasIO && clips.length) {
    const io = new IntersectionObserver((entries) => {
      for (const e of entries) {
        const v = e.target;
        if (e.isIntersecting) v.play().catch(() => {});
        else if (!v.paused) v.pause();
      }
    }, { threshold: 0.2 });
    for (const v of clips) io.observe(v);
  } else {
    for (const v of clips) v.play().catch(() => {});
  }

  // 2) Reveals. Elements that enter in the same tick rise one after the other.
  const reveals = document.querySelectorAll('.reveal');
  if (reveals.length && hasIO && !reduced) {
    const io = new IntersectionObserver((entries) => {
      let i = 0;
      for (const e of entries) {
        if (!e.isIntersecting) continue;
        e.target.style.transitionDelay = `${Math.min(i, 6) * 70}ms`;
        e.target.classList.add('in');
        io.unobserve(e.target);
        i++;
      }
    }, { threshold: 0.12, rootMargin: '0px 0px -6% 0px' });
    for (const el of reveals) io.observe(el);
  } else {
    for (const el of reveals) el.classList.add('in');
  }

  // 3) Progress hairline, one frame at a time.
  const bar = document.querySelector('.progress i');
  let ticking = false;
  const onScroll = () => {
    if (!bar || ticking) return;
    ticking = true;
    requestAnimationFrame(() => {
      ticking = false;
      const max = document.documentElement.scrollHeight - window.innerHeight;
      bar.style.transform = `scaleX(${max > 0 ? clamp(window.scrollY / max, 0, 1) : 0})`;
    });
  };

  // 4) The job, step by step.
  const steps = document.querySelectorAll('.story .step');
  const shots = document.querySelectorAll('.story-sticky > video');
  const tags = document.querySelectorAll('.story-tag span');
  const setStep = (n) => {
    steps.forEach((s, i) => s.classList.toggle('is-active', i === n));
    shots.forEach((v, i) => { const on = i === n; v.classList.toggle('is-active', on); if (on && !reduced) v.play().catch(() => {}); });
    tags.forEach((t, i) => t.classList.toggle('is-on', i === n));
  };
  if (steps.length && hasIO) {
    const io = new IntersectionObserver((entries) => {
      for (const e of entries) if (e.isIntersecting) setStep(+e.target.dataset.step);
    }, { rootMargin: '-45% 0px -45% 0px', threshold: 0 });
    for (const s of steps) io.observe(s);
    setStep(0);
  }

  window.addEventListener('scroll', onScroll, { passive: true });
  window.addEventListener('resize', onScroll);
  onScroll();
})();
