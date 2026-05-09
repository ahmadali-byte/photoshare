// Guard: authenticated users (both roles can browse)
if (!Auth.isLoggedIn()) { window.location.href = "login.html"; }

const user = Auth.getUser();
document.getElementById("nav-username").textContent = `@${user.username}`;

let currentPhotoId = null;
let currentRating = 0;
let offset = 0;
const PAGE_SIZE = 20;
let isSearchMode = false;

// ── Init ──────────────────────────────────────────────────────────────────────
document.addEventListener("DOMContentLoaded", () => {
  loadFeed();
  document.getElementById("search-input").addEventListener("keydown", (e) => {
    if (e.key === "Enter") doSearch();
  });
});

// ── Feed ──────────────────────────────────────────────────────────────────────
async function loadFeed(reset = true) {
  if (reset) { offset = 0; isSearchMode = false; }
  const grid = document.getElementById("photo-grid");
  if (reset) {
    grid.innerHTML = `<div class="loading-state" style="grid-column:1/-1"><div class="big-spinner"></div><p>Loading...</p></div>`;
    document.getElementById("feed-heading").textContent = "Discover Photos";
  }

  const { ok, data } = await Auth.api(`photos?limit=${PAGE_SIZE}&offset=${offset}`);
  if (!ok) { grid.innerHTML = `<div class="empty-state" style="grid-column:1/-1"><p>Failed to load photos.</p></div>`; return; }

  const photos = data.photos || [];
  if (reset) grid.innerHTML = "";

  if (!photos.length && offset === 0) {
    grid.innerHTML = `<div class="empty-state" style="grid-column:1/-1"><div class="empty-icon">📭</div><h3>No photos yet</h3><p>Check back soon!</p></div>`;
    document.getElementById("load-more").style.display = "none";
    return;
  }

  photos.forEach(p => {
    grid.insertAdjacentHTML("beforeend", photoCardHTML(p));
  });

  offset += photos.length;
  document.getElementById("load-more").style.display = photos.length === PAGE_SIZE ? "block" : "none";
}

async function loadMore() {
  if (isSearchMode) return;
  await loadFeed(false);
}

// ── Search ────────────────────────────────────────────────────────────────────
async function doSearch() {
  const q = document.getElementById("search-input").value.trim();
  if (!q) { clearSearch(); return; }

  const grid = document.getElementById("photo-grid");
  grid.innerHTML = `<div class="loading-state" style="grid-column:1/-1"><div class="big-spinner"></div><p>Searching...</p></div>`;
  document.getElementById("feed-heading").textContent = `Search: "${q}"`;
  document.getElementById("load-more").style.display = "none";
  isSearchMode = true;

  const { ok, data } = await Auth.api(`photos/search?q=${encodeURIComponent(q)}`);
  if (!ok) { grid.innerHTML = `<div class="empty-state" style="grid-column:1/-1"><p>Search failed.</p></div>`; return; }

  const photos = data.photos || [];
  if (!photos.length) {
    grid.innerHTML = `<div class="empty-state" style="grid-column:1/-1"><div class="empty-icon">🔍</div><h3>No results found</h3><p>Try a different search term.</p></div>`;
    return;
  }
  document.getElementById("feed-heading").textContent = `"${q}" — ${photos.length} result${photos.length !== 1 ? "s" : ""}`;
  grid.innerHTML = photos.map(p => photoCardHTML(p)).join("");
}

function clearSearch() {
  document.getElementById("search-input").value = "";
  loadFeed(true);
}

// ── Photo Card ────────────────────────────────────────────────────────────────
function photoCardHTML(p) {
  const rating = p.average_rating > 0
    ? `⭐ ${p.average_rating.toFixed(1)} (${p.rating_count})`
    : "Be first to rate";
  return `
    <div class="card photo-card" onclick="openPhotoDetail('${p.id}')">
      <img class="photo-thumb" src="${p.blob_url}" alt="${escHtml(p.title)}"
           loading="lazy"
           onerror="this.src='data:image/svg+xml,%3Csvg xmlns=%22http://www.w3.org/2000/svg%22 viewBox=%220 0 400 300%22%3E%3Crect fill=%22%23e2e8f0%22 width=%22400%22 height=%22300%22/%3E%3Ctext x=%22200%22 y=%22160%22 text-anchor=%22middle%22 fill=%22%23999%22 font-size=%2240%22%3E📷%3C/text%3E%3C/svg%3E'" />
      <div class="photo-info">
        <div class="photo-title">${escHtml(p.title)}</div>
        <div class="photo-meta">
          <span>📍 ${escHtml(p.location || "Unknown")}</span>
          <span>👤 ${escHtml(p.creator_name)}</span>
          <span>${rating}</span>
          <span>💬 ${p.comment_count || 0}</span>
        </div>
        <div class="photo-caption">${escHtml(p.caption || "")}</div>
        ${p.ai_tags?.length ? `<div class="tags">${p.ai_tags.slice(0, 3).map(t => `<span class="tag ai">🤖 ${t}</span>`).join("")}</div>` : ""}
      </div>
    </div>`;
}

// ── Photo Detail Modal ────────────────────────────────────────────────────────
async function openPhotoDetail(photoId) {
  currentPhotoId = photoId;
  currentRating = 0;

  const { ok, data } = await Auth.api(`photos/${photoId}`);
  if (!ok) { showToast("Failed to load photo", "error"); return; }

  const p = data;
  document.getElementById("modal-title").textContent = p.title;
  document.getElementById("modal-photo").src = p.blob_url;
  document.getElementById("modal-caption").textContent = p.caption || "";

  document.getElementById("modal-meta").innerHTML = `
    <div class="meta-item">📍 ${escHtml(p.location || "Unknown")}</div>
    <div class="meta-item">👤 ${escHtml(p.creator_name)}</div>
    <div class="meta-item">📅 ${timeAgo(p.created_at)}</div>
    <div class="meta-item">⭐ ${p.average_rating > 0 ? `${p.average_rating.toFixed(1)} / 5 (${p.rating_count} ratings)` : "No ratings yet"}</div>
  `;

  // AI box
  if (p.ai_description || p.ai_tags?.length) {
    document.getElementById("modal-ai-desc").textContent = p.ai_description || "";
    document.getElementById("modal-ai-tags").innerHTML =
      (p.ai_tags || []).map(t => `<span class="tag ai">🤖 ${t}</span>`).join("");
    document.getElementById("modal-ai-box").style.display = "block";
  } else {
    document.getElementById("modal-ai-box").style.display = "none";
  }

  // People
  document.getElementById("modal-people").innerHTML =
    (p.people || []).map(n => `<span class="tag">👤 ${escHtml(n)}</span>`).join("");

  // Rating stars (interactive)
  currentRating = p.average_rating || 0;
  document.getElementById("rating-display").textContent =
    p.average_rating > 0 ? `${p.average_rating.toFixed(1)} avg (${p.rating_count} votes)` : "Not rated yet";
  document.getElementById("rating-msg").textContent = "";
  renderStars("rating-stars", currentRating, async (val) => {
    const { ok, data } = await Auth.api(`photos/${photoId}/rate`, {
      method: "POST",
      body: JSON.stringify({ rating: val }),
    });
    if (ok) {
      currentRating = data.photo_average;
      document.getElementById("rating-display").textContent =
        `${data.photo_average.toFixed(1)} avg (${data.rating_count} votes)`;
      document.getElementById("rating-msg").textContent = "✅ Rating saved!";
      renderStars("rating-stars", currentRating, null);
      showToast("Rating saved!", "success");
    } else {
      showToast("Failed to save rating", "error");
    }
  });

  // Reset comment
  document.getElementById("comment-input").value = "";

  loadComments(photoId);
  document.getElementById("detail-modal").classList.add("open");
}

async function loadComments(photoId) {
  const { ok, data } = await Auth.api(`photos/${photoId}/comments`);
  const heading = document.getElementById("comments-heading");
  const list = document.getElementById("comments-list");

  if (!ok) { list.innerHTML = "<p>Failed to load comments.</p>"; return; }
  const comments = data.comments || [];
  heading.textContent = `Comments (${comments.length})`;

  if (!comments.length) {
    list.innerHTML = `<p style="color:var(--muted); font-size:0.9rem;">Be the first to comment!</p>`;
    return;
  }

  list.innerHTML = comments.map(c => `
    <div class="comment-item">
      <div class="comment-header">
        <span class="comment-user">@${escHtml(c.username)}</span>
        <div style="display:flex;align-items:center;gap:8px;">
          <span class="tag sentiment-${c.sentiment}" title="Sentiment score: ${c.sentiment_score}">
            ${sentimentEmoji(c.sentiment)} ${c.sentiment}
          </span>
          <span class="comment-time">${timeAgo(c.created_at)}</span>
        </div>
      </div>
      <div class="comment-text">${escHtml(c.text)}</div>
    </div>
  `).join("");
}

async function submitComment() {
  const text = document.getElementById("comment-input").value.trim();
  if (!text) { showToast("Please write a comment first", "error"); return; }

  const btn = document.getElementById("comment-btn");
  btn.disabled = true;
  document.getElementById("comment-btn-text").innerHTML = '<span class="spinner"></span> Analysing...';

  const { ok, data } = await Auth.api(`photos/${currentPhotoId}/comments`, {
    method: "POST",
    body: JSON.stringify({ text }),
  });

  btn.disabled = false;
  document.getElementById("comment-btn-text").textContent = "Post Comment";

  if (ok) {
    document.getElementById("comment-input").value = "";
    const sentimentMsg = `Sentiment: ${sentimentEmoji(data.sentiment)} ${data.sentiment} (${(data.sentiment_score * 100).toFixed(0)}% confidence)`;
    showToast(`Comment posted! ${sentimentMsg}`, "success");
    loadComments(currentPhotoId);
  } else {
    showToast(data.error || "Failed to post comment", "error");
  }
}

function closeDetailModal() {
  document.getElementById("detail-modal").classList.remove("open");
  currentPhotoId = null;
}

function closeModal(e) {
  if (e.target.id === "detail-modal") closeDetailModal();
}

// ── Utilities ─────────────────────────────────────────────────────────────────
function escHtml(str) {
  const d = document.createElement("div");
  d.textContent = str || "";
  return d.innerHTML;
}

function sentimentEmoji(s) {
  return s === "positive" ? "😊" : s === "negative" ? "😟" : "😐";
}

function logout() {
  Auth.clear();
  window.location.href = "login.html";
}
