const Auth = (() => {
  const TOKEN_KEY = "ps_token";
  const USER_KEY = "ps_user";

  function setSession(token, user) {
    localStorage.setItem(TOKEN_KEY, token);
    localStorage.setItem(USER_KEY, JSON.stringify(user));
  }

  function getToken() { return localStorage.getItem(TOKEN_KEY); }

  function getUser() {
    try { return JSON.parse(localStorage.getItem(USER_KEY)); }
    catch { return null; }
  }

  function isLoggedIn() { return !!getToken(); }

  function getRole() { return getUser()?.role || null; }

  function clear() {
    localStorage.removeItem(TOKEN_KEY);
    localStorage.removeItem(USER_KEY);
  }

  function authHeaders() {
    const t = getToken();
    return t ? { Authorization: `Bearer ${t}` } : {};
  }

  async function api(path, options = {}) {
    const url = `${API_BASE}/api/${path}`;
    const resp = await fetch(url, {
      ...options,
      headers: {
        "Content-Type": "application/json",
        ...authHeaders(),
        ...(options.headers || {}),
      },
    });
    const data = await resp.json().catch(() => ({}));
    return { ok: resp.ok, status: resp.status, data };
  }

  async function apiForm(path, formData) {
    const url = `${API_BASE}/api/${path}`;
    const resp = await fetch(url, {
      method: "POST",
      headers: authHeaders(),
      body: formData,
    });
    const data = await resp.json().catch(() => ({}));
    return { ok: resp.ok, status: resp.status, data };
  }

  function requireRole(role) {
    if (!isLoggedIn()) { window.location.href = "login.html"; return false; }
    if (role && getRole() !== role) { window.location.href = "login.html"; return false; }
    return true;
  }

  return { setSession, getToken, getUser, isLoggedIn, getRole, clear, authHeaders, api, apiForm, requireRole };
})();

function logout() {
  Auth.clear();
  window.location.href = "login.html";
}

// ── Toast helper ──────────────────────────────────────────────────────────────
function showToast(msg, type = "default") {
  let el = document.getElementById("toast");
  if (!el) {
    el = document.createElement("div");
    el.id = "toast";
    document.body.appendChild(el);
  }
  el.textContent = msg;
  el.style.background = type === "error" ? "#d13438" : type === "success" ? "#107c10" : "#1a1a2e";
  el.style.display = "block";
  clearTimeout(el._timer);
  el._timer = setTimeout(() => { el.style.display = "none"; }, 3500);
}

// ── Stars helper ──────────────────────────────────────────────────────────────
function renderStars(containerId, currentRating, onRate) {
  const el = document.getElementById(containerId);
  if (!el) return;
  el.innerHTML = "";
  for (let i = 1; i <= 5; i++) {
    const s = document.createElement("span");
    s.className = "star" + (i <= Math.round(currentRating) ? " filled" : "");
    s.textContent = "★";
    if (onRate) {
      s.addEventListener("click", () => onRate(i));
      s.addEventListener("mouseenter", () => {
        el.querySelectorAll(".star").forEach((st, idx) => {
          st.style.color = idx < i ? "#ffd700" : "#ccc";
        });
      });
      s.addEventListener("mouseleave", () => {
        el.querySelectorAll(".star").forEach((st, idx) => {
          st.style.color = idx < Math.round(currentRating) ? "#ffd700" : "#ccc";
        });
      });
    }
    el.appendChild(s);
  }
}

// ── Date formatting ────────────────────────────────────────────────────────────
function timeAgo(isoStr) {
  const diff = Date.now() - new Date(isoStr).getTime();
  const m = Math.floor(diff / 60000);
  if (m < 1) return "just now";
  if (m < 60) return `${m}m ago`;
  const h = Math.floor(m / 60);
  if (h < 24) return `${h}h ago`;
  const d = Math.floor(h / 24);
  return `${d}d ago`;
}
