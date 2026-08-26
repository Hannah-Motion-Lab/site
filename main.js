// Copy the install command. Nothing else on the page needs JavaScript.
const btn = document.getElementById('copy');
const cmd = document.getElementById('cmd-linux');
let reset;

btn.addEventListener('click', async () => {
  const text = cmd.textContent.trim();
  try {
    await navigator.clipboard.writeText(text);
  } catch {
    const ta = document.createElement('textarea');
    ta.value = text; ta.setAttribute('readonly', ''); ta.style.position = 'fixed'; ta.style.opacity = '0';
    document.body.appendChild(ta); ta.select(); document.execCommand('copy'); ta.remove();
  }
  btn.classList.add('done'); btn.textContent = 'Copied';
  clearTimeout(reset);
  reset = setTimeout(() => { btn.classList.remove('done'); btn.textContent = 'Copy'; }, 1600);
});
