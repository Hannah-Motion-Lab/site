// Hannah landing: the script behind the HUD.
// 0) OS switcher and copy button for the install command.
// 1) Captures play only while on screen; with reduced motion they never autoplay (controls instead).
// 2) Reveals: sections rise into place as they enter; the html.js class is what hides them first,
//    so without script nothing is hidden.
// 3) The progress hairline at the top, and a little parallax on the hero film.
// 4) The job, step by step: the step nearest the middle of the screen picks the capture.
// 5) The motion sequence: a canvas that draws the frame the scroll position asks for.

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
      if (!v.closest('.hero-film, .cta-film')) v.controls = true;   // the two ambient films just show their poster
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

  // 3) Progress hairline + hero parallax, one scroll handler, one frame at a time.
  const bar = document.querySelector('.progress i');
  const film = document.querySelector('.hero-film');
  const hero = document.querySelector('.hero');
  let ticking = false;
  const onScroll = () => {
    if (ticking) return;
    ticking = true;
    requestAnimationFrame(() => {
      ticking = false;
      const y = window.scrollY || 0;
      if (bar) {
        const max = document.documentElement.scrollHeight - window.innerHeight;
        bar.style.transform = `scaleX(${max > 0 ? clamp(y / max, 0, 1) : 0})`;
      }
      if (film && hero && !reduced && window.innerWidth > 960 && y < hero.offsetHeight) {
        film.style.transform = `translate3d(0, ${y * 0.16}px, 0)`;
      }
      scrub();
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

  // 5) The motion sequence. 48 WebP frames, drawn to a canvas at the scroll's position.
  //    Frames load when the section is within a screen of the viewport; until they all have,
  //    the poster under the canvas is what shows.
  const motion = document.querySelector('[data-scrub]');
  let scrub = () => {};
  if (motion && !reduced && hasIO) {
    const n = parseInt(motion.dataset.frames, 10) || 0;
    const tpl = motion.dataset.src;
    const canvas = motion.querySelector('.motion-canvas');
    const ctx = canvas && canvas.getContext('2d');
    const marks = motion.querySelectorAll('.motion-steps li');
    const frames = [];
    let loaded = 0, ready = false, started = false, cur = -1;
    const draw = (i) => {
      if (!ready || i === cur) return;
      cur = i;
      ctx.drawImage(frames[i], 0, 0, canvas.width, canvas.height);
    };
    const load = () => {
      if (started) return;
      started = true;
      for (let i = 0; i < n; i++) {
        const im = new Image();
        im.decoding = 'async';
        im.onload = im.onerror = () => {
          loaded++;
          if (loaded === n && !ready) { ready = true; canvas.classList.add('is-ready'); cur = -1; scrub(); }
        };
        im.src = tpl.replace('{i}', String(i).padStart(2, '0'));
        frames.push(im);
      }
    };
    scrub = () => {
      const r = motion.getBoundingClientRect();
      const span = r.height - window.innerHeight;
      if (r.bottom < 0 || r.top > window.innerHeight) return;
      const p = span > 0 ? clamp(-r.top / span, 0, 1) : 1;
      draw(Math.round(p * (n - 1)));
      let now = -1;
      marks.forEach((m, i) => { if (p >= parseFloat(m.dataset.at || '0')) now = i; });
      marks.forEach((m, i) => { m.classList.toggle('is-on', i <= now); m.classList.toggle('is-now', i === now); });
    };
    const near = new IntersectionObserver((entries) => {
      for (const e of entries) if (e.isIntersecting) { load(); near.disconnect(); }
    }, { rootMargin: '100% 0px' });
    near.observe(motion);
  } else if (motion) {
    for (const m of motion.querySelectorAll('.motion-steps li')) m.classList.add('is-on');
  }

  window.addEventListener('scroll', onScroll, { passive: true });
  window.addEventListener('resize', onScroll);
  onScroll();
})();
