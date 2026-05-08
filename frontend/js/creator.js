// Guard: creators only
if (!Auth.requireRole("creator")) { /* redirected */ }

const user = Auth.getUser();
document.getElementById("nav-username").textContent = `@${user.username}`;

let selectedFile = null;
let currentPhotoId = null;
let myPhotos = [];

// ── Init ──────────────────────────────────────────────────────────────────────
document.addEventListener("DOMContentLoaded", () => {
  loadMyPhotos();
  setupDropZone();
});

// ── Drop Zone ─────────────────────────────────────────────────────────────────
function setupDropZone() {
  const zone = document.getElementById("drop-zone");
  const input = document.getElementById("file-input");

  input.addEventListener("change", () => handleFile(input.files[0]));

  zone.addEventListener("dragover", (e) => { e.preventDefault(); zone.classList.add("drag-over"); });
  zone.addEventListener("dragleave", () => zone.classList.remove("drag-over"));
  zone.addEventListener("drop", (e) => {
    e.preventDefault();
    zone.classList.remove("drag-over");
    handleFile(e.dataTransfer.files[0]);
  });
}

function handleFile(file) {
  if (!file) return;
  if (!file.type.startsWith("image/")) { showToast("Please select an image file", "error"); return; }
  if (file.size > 10 * 1024 * 1024) { showToast("File too large (max 10MB)", "error"); return; }

  selectedFile = file;
  const reader = new FileReader();
  reader.onload = (e) => {
    const prev = document.getElementById("image-preview");
    prev.src = e.target.result;
    prev.style.display = "block";
  };
  reader.readAsDataURL(file);
  document.getElementById("ai-result-box").style.display = "none";
}

// ── Upload ────────────────────────────────────────────────────────────────────
document.getElementById("upload-form").addEventListener("submit", async (e) => {
  e.preventDefault();
  if (!selectedFile) { setUploadAlert("Please select an image to upload.", "danger"); return; }

  const title = document.getElementById("f-title").value.trim();
  if (!title) { setUploadAlert("Title is required.", "danger"); return; }

  const btn = document.getElementById("upload-btn");
  btn.disabled = true;
  document.getElementById("upload-btn-text").innerHTML = '<span class="spinner"></span> Uploading & Analysing...';

  // Convert to base64 for JSON transport
  const base64 = await fileToBase64(selectedFile);

  const form = new FormData();
  form.append("title", title);
  form.append("caption", document.getElementById("f-caption").value.trim());
  form.append("location", document.getElementById("f-location").value.trim());
  form.append("people", document.getElementById("f-people").value.trim());
  form.append("image_data", base64);
  form.append("filename", selectedFile.name);
  form.append("content_type", selectedFile.type);

  const { ok, data } = await Auth.apiForm("photos", form);

  btn.disabled = false;
  document.getElementById("upload-btn-text").textContent = "📤 Upload Photo";

  if (ok) {
    setUploadAlert("Photo uploaded successfully! AI analysis complete.", "success");
    // Show AI results
    if (data.ai_description || data.ai_tags?.length) {
      document.getElementById("ai-description").textContent = data.ai_description || "";
      const tagsEl = document.getElementById("ai-tags-container");
      tagsEl.innerHTML = (data.ai_tags || []).map(t => `<span class="tag ai">🤖 ${t}</span>`).join("");
      document.getElementById("ai-result-box").style.display = "block";
    }
    resetUploadFormFields();
    loadMyPhotos();
    showToast("Photo uploaded!", "success");
  } else {
    setUploadAlert(data.error || "Upload failed. Please try again.", "danger");
  }
});

function fileToBase64(file) {
  return new Promise((res) => {
    const reader = new FileReader();
    reader.onload = (e) => res(e.target.result.split(",")[1]);
    reader.readAsDataURL(file);
  });
}

function resetUploadFormFields() {
  document.getElementById("f-title").value = "";
  document.getElementById("f-caption").value = "";
  document.getElementById("f-location").value = "";
  document.getElementById("f-people").value = "";
  document.getElementById("image-preview").style.display = "none";
  selectedFile = null;
  document.getElementById("file-input").value = "";
}

function resetUploadForm() {
  resetUploadFormFields();
  document.getElementById("ai-result-box").style.display = "none";
  setUploadAlert("", "");
}

function setUploadAlert(msg, type) {
  const el = document.getElementById("alert-upload");
  el.innerHTML = msg ? `<div class="alert alert-${type}">${msg}</div>` : "";
}

// ── Load My Photos ────────────────────────────────────────────────────────────
async function loadMyPhotos() {
  const grid = document.getElementById("my-photos-grid");
  grid.innerHTML = `<div class="loading-state"><div class="big-spinner"></div><p>Loading...</p></div>`;

  const { ok, data } = await Auth.api("photos/my");
  if (!ok) { grid.innerHTML = `<div class="empty-state"><p>Failed to load photos.</p></div>`; return; }

  myPhotos = data.photos || [];
  updateStats(myPhotos);

  if (!myPhotos.length) {
    grid.innerHTML = `<div class="empty-state" style="grid-column:1/-1"><div class="empty-icon">📭</div><h3>No photos yet</h3><p>Upload your first photo above!</p></div>`;
    return;
  }

  grid.innerHTML = myPhotos.map(p => photoCardHTML(p, true)).join("");
}

function updateStats(photos) {
  const totalComments = photos.reduce((s, p) => s + (p.comment_count || 0), 0);
  const avgRating = photos.length
    ? (photos.reduce((s, p) => s + (p.average_rating || 0), 0) / photos.length).toFixed(1)
    : "—";
  document.getElementById("stat-photos").textContent = photos.length;
  document.getElementById("stat-comments").textContent = totalComments;
  document.getElementById("stat-avg-rating").textContent = avgRating;
}

function photoCardHTML(p, isOwn = false) {
  const rating = p.average_rating > 0
    ? `⭐ ${p.average_rating.toFixed(1)} (${p.rating_count})`
    : "No ratings yet";
  return `
    <div class="card photo-card" onclick="openPhotoDetail('${p.id}')">
      <img class="photo-thumb" src="${p.blob_url}" alt="${escHtml(p.title)}"
           onerror="this.src='data:image/svg+xml,%3Csvg xmlns=%22http://www.w3.org/2000/svg%22 viewBox=%220 0 400 300%22%3E%3Crect fill=%22%23e2e8f0%22 width=%22400%22 height=%22300%22/%3E%3Ctext x=%22200%22 y=%22160%22 text-anchor=%22middle%22 fill=%22%23999%22 font-size=%2240%22%3E📷%3C/text%3E%3C/svg%3E'" />
      <div class="photo-info">
        <div class="photo-title">${escHtml(p.title)}</div>
        <div class="photo-meta">
          <span>📍 ${escHtml(p.location || "Unknown")}</span>
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
  const { ok, data } = await Auth.api(`photos/${photoId}`);
  if (!ok) { showToast("Failed to load photo", "error"); return; }

  const p = data;
  document.getElementById("modal-title").textContent = p.title;
  document.getElementById("modal-photo").src = p.blob_url;

  document.getElementById("modal-meta").innerHTML = `
    <div class="meta-item">📍 ${escHtml(p.location || "Unknown")}</div>
    <div class="meta-item">📅 ${timeAgo(p.created_at)}</div>
    <div class="meta-item">⭐ ${p.average_rating > 0 ? `${p.average_rating.toFixed(1)} / 5 (${p.rating_count} ratings)` : "No ratings yet"}</div>
    <div class="meta-item">💬 ${p.comment_count || 0} comments</div>
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

  // People tags
  document.getElementById("modal-people-tags").innerHTML =
    (p.people || []).map(name => `<span class="tag">👤 ${escHtml(name)}</span>`).join("");

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

  if (!comments.length) { list.innerHTML = `<p style="color:var(--muted); font-size:0.9rem;">No comments yet.</p>`; return; }

  list.innerHTML = comments.map(c => `
    <div class="comment-item">
      <div class="comment-header">
        <span class="comment-user">@${escHtml(c.username)}</span>
        <div style="display:flex;align-items:center;gap:8px;">
          <span class="tag sentiment-${c.sentiment}">${sentimentEmoji(c.sentiment)} ${c.sentiment}</span>
          <span class="comment-time">${timeAgo(c.created_at)}</span>
        </div>
      </div>
      <div class="comment-text">${escHtml(c.text)}</div>
    </div>
  `).join("");
}

async function deleteCurrentPhoto() {
  if (!currentPhotoId) return;
  if (!confirm("Are you sure you want to delete this photo? This cannot be undone.")) return;

  const { ok, data } = await Auth.api(`photos/${currentPhotoId}`, { method: "DELETE" });
  if (ok) {
    showToast("Photo deleted", "success");
    closeDetailModal();
    loadMyPhotos();
  } else {
    showToast(data.error || "Delete failed", "error");
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
  window.location.href = "index.html";
}
