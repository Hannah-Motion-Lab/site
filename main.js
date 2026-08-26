// Hannah landing — the little that needs script.
// 1) Copy buttons for the install command (top and closing band).
// 2) "Watch 30 s": if the demo video actually loaded, scroll to it and play it with sound;
//    otherwise just scroll to the hero (the poster is what there is).
// 3) The hero video only plays while it is on screen, and never autoplays for people who
//    asked their OS for less motion.

(function () {
  const copyPairs = [['copy', 'cmd-linux'], ['copy-2', 'cmd-linux-2']];
  for (const [btnId, codeId] of copyPairs) {
    const btn = document.getElementById(btnId);
    const code = document.getElementById(codeId);
    if (!btn || !code) continue;
    btn.addEventListener('click', async () => {
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
