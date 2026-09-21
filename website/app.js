/* Pastiche site: theme toggle, copy buttons, and the hero demo.
   No dependencies. Everything degrades to a static page without it. */
(() => {
  "use strict";
  const $ = (sel, root = document) => root.querySelector(sel);
  const root = document.documentElement;

  /* ---------- Theme toggle ---------- */
  const isDark = () =>
    root.dataset.theme === "dark" ||
    (root.dataset.theme === "auto" && matchMedia("(prefers-color-scheme: dark)").matches);

  $("#themeToggle")?.addEventListener("click", () => {
    const next = isDark() ? "light" : "dark";
    root.dataset.theme = next;
    try { localStorage.setItem("theme", next); } catch (e) { /* private mode: fine */ }
  });

  /* ---------- Copy buttons ---------- */
  function fallbackCopy(text) {
    const area = document.createElement("textarea");
    area.value = text;
    area.setAttribute("readonly", "");
    area.style.cssText = "position:fixed;left:-999px;top:0";
    document.body.appendChild(area);
    area.select();
    let ok = false;
    try { ok = document.execCommand("copy"); } catch (e) { ok = false; }
    area.remove();
    return ok;
  }

  document.querySelectorAll(".copy").forEach((button) => {
    button.addEventListener("click", async () => {
      const text = button.dataset.copy || "";
      let ok = false;
      try { await navigator.clipboard.writeText(text); ok = true; }
      catch (e) { ok = fallbackCopy(text); }
      const label = button.textContent;
      button.textContent = ok ? "Copied" : "Select & ⌘C";
      setTimeout(() => { button.textContent = label; }, 1400);
    });
  });

  /* ---------- Hero demo ----------
     Plays the real interaction on the mock popup: open, arrow down, Tab into
     search, type, Return. Skipped for reduced motion, paused while off-screen
     or in a background tab. */
  const mock = $("#mock");
  if (!mock || matchMedia("(prefers-reduced-motion: reduce)").matches) return;

  const rows = [...mock.querySelectorAll(".mock-row")];
  const list = $("#mockList");
  const search = $("#mockSearch");
  const queryEl = $("#mockQuery");
  const countEl = $("#mockCount");
  const keycap = $("#keycap");
  const PLACEHOLDER = "Search (⇥)";
  const QUERY = "ssh";

  let token = 0;          // bumped to cancel the running loop
  let selected = 0;
  let visible = rows.slice();

  const sleep = (ms, mine) => new Promise((resolve) => setTimeout(() => resolve(mine === token), ms));

  function cap(html) { keycap.innerHTML = html; }

  function render() {
    rows.forEach((row) => row.classList.remove("sel"));
    visible.forEach((row, i) => { row.querySelector(".num").textContent = String((i + 1) % 10); });
    if (visible[selected]) visible[selected].classList.add("sel");
    countEl.textContent = String(visible.length);
  }

  function filter(query) {
    const terms = query.toLowerCase().split(" ").filter(Boolean);
    visible = rows.filter((row) => terms.every((term) => row.dataset.q.includes(term)));
    rows.forEach((row) => { row.hidden = !visible.includes(row); });
    selected = 0;
    render();
  }

  function reset() {
    queryEl.textContent = PLACEHOLDER;
    search.classList.remove("focus");
    rows.forEach((row) => row.classList.remove("pasted"));
    filter("");
  }

  async function play(mine) {
    reset();
    cap("");
    if (!(await sleep(1400, mine))) return;

    cap("<kbd>⌘</kbd><kbd>'</kbd> opens it");
    if (!(await sleep(900, mine))) return;

    for (let i = 0; i < 2; i++) {
      cap("<kbd>↓</kbd> move down");
      selected = Math.min(selected + 1, visible.length - 1);
      render();
      if (!(await sleep(850, mine))) return;
    }

    cap("<kbd>⇥</kbd> search");
    search.classList.add("focus");
    queryEl.textContent = "";
    if (!(await sleep(700, mine))) return;

    let typed = "";
    for (const ch of QUERY) {
      typed += ch;
      queryEl.textContent = typed;
      filter(typed);
      cap("typing “" + typed + "”");
      if (!(await sleep(320, mine))) return;
    }
    if (!(await sleep(900, mine))) return;

    cap("<kbd>Return</kbd> pastes it");
    if (visible[selected]) visible[selected].classList.add("pasted");
    if (!(await sleep(1700, mine))) return;
  }

  async function loop() {
    const mine = ++token;
    while (mine === token) {
      await play(mine);
      if (mine !== token) return;
    }
  }

  function start() { if (!document.hidden) loop(); }
  function stop() { token++; reset(); cap(""); }

  // Only animate while the mock is actually on screen and the tab is in front.
  let onScreen = false;
  new IntersectionObserver((entries) => {
    onScreen = entries[0].isIntersecting;
    onScreen ? start() : stop();
  }, { threshold: 0.35 }).observe(mock);
  document.addEventListener("visibilitychange", () => {
    if (document.hidden) stop(); else if (onScreen) start();
  });
})();
