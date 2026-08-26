const copyBtn = document.getElementById('copy');
const cmdEl = document.getElementById('cmd-linux');
let resetTimer;

function legacyCopy(text) {
  const ta = document.createElement('textarea');
  ta.value = text;
  ta.setAttribute('readonly', '');
  ta.style.position = 'fixed';
  ta.style.opacity = '0';
  document.body.appendChild(ta);
  ta.select();
  document.execCommand('copy');
  ta.remove();
}

copyBtn.addEventListener('click', async () => {
  const text = cmdEl.textContent.trim();
  try {
    await navigator.clipboard.writeText(text);
  } catch {
    legacyCopy(text);
  }
  copyBtn.classList.add('done');
  copyBtn.textContent = 'Copied ✓';
  clearTimeout(resetTimer);
  resetTimer = setTimeout(() => {
    copyBtn.classList.remove('done');
    copyBtn.textContent = 'Copy';
  }, 1600);
});
