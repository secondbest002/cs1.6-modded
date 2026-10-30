/**
 * modules/library.js - Built-in Asset & Sticker Library Drawer
 * CS 1.6 Asset Studio Pro Modular Architecture
 */

import { state, eventBus } from "../core/state.js";
import { apiGet, apiPost, showToast, showLoader, hideLoader } from "../core/api.js";
import { refreshSlotPreview } from "./slots.js";

const els = {
  get libraryModal() { return document.getElementById("libraryModal"); },
  get modalTitle() { return document.getElementById("modalTitle"); },
  get modalCloseBtn() { return document.getElementById("modalCloseBtn"); },
  get modalLibraryGrid() { return document.getElementById("modalLibraryGrid"); },
  get libraryGrid() { return document.getElementById("libraryGrid"); },
  get librarySearchInput() { return document.getElementById("librarySearchInput"); },
  get libraryCategoryTabs() { return document.getElementById("libraryCategoryTabs"); },
  get knifeSubcatFilters() { return document.getElementById("knifeSubcatFilters"); },
  get libraryCatFilters() { return document.getElementById("libraryCatFilters"); },

  // Custom asset upload & edit elements
  get libraryUploadBtn() { return document.getElementById("libraryUploadBtn"); },
  get libraryBatchFilesBtn() { return document.getElementById("libraryBatchFilesBtn"); },
  get libraryBatchFolderBtn() { return document.getElementById("libraryBatchFolderBtn"); },
  get libraryDropZone() { return document.getElementById("libraryDropZone"); },
  get libraryFileInput() { return document.getElementById("libraryFileInput"); },
  get libraryFolderInput() { return document.getElementById("libraryFolderInput"); },
  get libraryUploadProgress() { return document.getElementById("libraryUploadProgress"); },
  get libraryUploadProgressText() { return document.getElementById("libraryUploadProgressText"); },
  get libraryUploadProgressPercent() { return document.getElementById("libraryUploadProgressPercent"); },
  get libraryUploadProgressBar() { return document.getElementById("libraryUploadProgressBar"); },

  get stickerEditModal() { return document.getElementById("stickerEditModal"); },
  get stickerEditModalTitle() { return document.getElementById("stickerEditModalTitle"); },
  get stickerEditModalCloseBtn() { return document.getElementById("stickerEditModalCloseBtn"); },
  get stickerEditFilename() { return document.getElementById("stickerEditFilename"); },
  get stickerEditNameInput() { return document.getElementById("stickerEditNameInput"); },
  get stickerEditCatInput() { return document.getElementById("stickerEditCatInput"); },
  get stickerUploadAlphaRow() { return document.getElementById("stickerUploadAlphaRow"); },
  get stickerUploadAutoAlpha() { return document.getElementById("stickerUploadAutoAlpha"); },
  get stickerEditSaveBtn() { return document.getElementById("stickerEditSaveBtn"); },
  get stickerEditCancelBtn() { return document.getElementById("stickerEditCancelBtn"); },
  get libraryRestoreDefaultsBtn() { return document.getElementById("libraryRestoreDefaultsBtn"); },
  get drawerViewLibrary() { return document.getElementById("drawerViewLibrary"); },
};

let pendingUploadBase64 = null;

function escapeHtml(str) {
  if (!str) return "";
  return String(str)
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;");
}

export function initLibraryModule() {
  setupEventListeners();

  eventBus.on("library:openForSlot", (tex) => {
    openLibraryModalForSlot(tex);
  });

  eventBus.on("library:openGeneral", (destination) => {
    state.modalTargetDestination = destination;
    if (els.modalTitle) {
      els.modalTitle.textContent =
        destination === "bake" ? "Choose Sticker for Bake Surface" : "Choose Sticker for Slot Fine-Tuner";
    }
    openLibraryModalGeneral();
  });

  fetchLibraryData();
}

function setupEventListeners() {
  if (els.modalCloseBtn) {
    els.modalCloseBtn.addEventListener("click", () => {
      if (els.libraryModal) els.libraryModal.classList.add("hidden");
    });
  }

  // Category Tabs switching [All | Stickers | Weapons | Knives | Gloves]
  if (els.libraryCategoryTabs) {
    els.libraryCategoryTabs.querySelectorAll(".filter-pill").forEach((pill) => {
      pill.addEventListener("click", () => {
        els.libraryCategoryTabs.querySelectorAll(".filter-pill").forEach((p) => p.classList.remove("active"));
        pill.classList.add("active");
        state.activeLibraryTab = pill.dataset.tab || "all";

        if (state.activeLibraryTab === "knives") {
          if (els.knifeSubcatFilters) els.knifeSubcatFilters.classList.remove("hidden");
          if (els.libraryCatFilters) els.libraryCatFilters.classList.add("hidden");
        } else if (state.activeLibraryTab === "stickers" || state.activeLibraryTab === "all") {
          if (els.knifeSubcatFilters) els.knifeSubcatFilters.classList.add("hidden");
          if (els.libraryCatFilters) els.libraryCatFilters.classList.remove("hidden");
        } else {
          if (els.knifeSubcatFilters) els.knifeSubcatFilters.classList.add("hidden");
          if (els.libraryCatFilters) els.libraryCatFilters.classList.add("hidden");
        }
        renderLibraryGrid();
      });
    });
  }

  // Knife Subcategory Filter Pills
  if (els.knifeSubcatFilters) {
    els.knifeSubcatFilters.querySelectorAll(".filter-pill").forEach((pill) => {
      pill.addEventListener("click", () => {
        els.knifeSubcatFilters.querySelectorAll(".filter-pill").forEach((p) => p.classList.remove("active"));
        pill.classList.add("active");
        state.activeKnifeType = pill.dataset.knifeType || "all";
        renderLibraryGrid();
      });
    });
  }

  // Style / Sticker Subcategory Filter Pills
  if (els.libraryCatFilters) {
    els.libraryCatFilters.querySelectorAll(".filter-pill").forEach((pill) => {
      pill.addEventListener("click", () => {
        els.libraryCatFilters.querySelectorAll(".filter-pill").forEach((p) => p.classList.remove("active"));
        pill.classList.add("active");
        state.activeLibraryCat = pill.dataset.cat || "all";
        renderLibraryGrid();
      });
    });
  }

  if (els.librarySearchInput) {
    els.librarySearchInput.addEventListener("input", (e) => {
      state.librarySearch = e.target.value.toLowerCase().trim();
      renderLibraryGrid();
    });
  }

  // Batch Files button
  if (els.libraryBatchFilesBtn) {
    els.libraryBatchFilesBtn.addEventListener("click", () => {
      if (els.libraryFileInput) els.libraryFileInput.click();
    });
  }

  // Batch Folder button
  if (els.libraryBatchFolderBtn) {
    els.libraryBatchFolderBtn.addEventListener("click", () => {
      if (els.libraryFolderInput) els.libraryFolderInput.click();
    });
  }

  // Upload trigger button (legacy / fallback)
  if (els.libraryUploadBtn) {
    els.libraryUploadBtn.addEventListener("click", () => {
      if (els.libraryFileInput) els.libraryFileInput.click();
    });
  }

  // Restore Default Stickers button
  if (els.libraryRestoreDefaultsBtn) {
    els.libraryRestoreDefaultsBtn.addEventListener("click", async () => {
      if (!confirm("Restore default tournament stickers? Existing custom stickers will not be touched.")) return;
      showLoader("Restoring default tournament stickers...");
      try {
        const res = await apiPost("/api/library/stickers/restore_defaults", {});
        showToast(res.message || "Default tournament stickers restored!", "success");
        await fetchLibraryData();
      } catch (err) {
        showToast(`Restore failed: ${err.message}`, "error");
      } finally {
        hideLoader();
      }
    });
  }

  // Hidden file inputs
  if (els.libraryFileInput) {
    els.libraryFileInput.addEventListener("change", (e) => {
      if (e.target.files && e.target.files.length > 0) {
        if (e.target.files.length === 1) {
          handleFileSelection(e.target.files[0]);
        } else {
          handleBatchFiles(e.target.files);
        }
        e.target.value = "";
      }
    });
  }

  if (els.libraryFolderInput) {
    els.libraryFolderInput.addEventListener("change", (e) => {
      if (e.target.files && e.target.files.length > 0) {
        handleBatchFiles(e.target.files);
        e.target.value = "";
      }
    });
  }

  // Drop zone click & drag-and-drop
  if (els.libraryDropZone) {
    els.libraryDropZone.addEventListener("click", () => {
      if (els.libraryFileInput) els.libraryFileInput.click();
    });

    els.libraryDropZone.addEventListener("dragover", (e) => {
      e.preventDefault();
      e.stopPropagation();
      els.libraryDropZone.classList.add("drag-over");
    });

    els.libraryDropZone.addEventListener("dragleave", (e) => {
      e.preventDefault();
      e.stopPropagation();
      els.libraryDropZone.classList.remove("drag-over");
    });

    els.libraryDropZone.addEventListener("drop", (e) => {
      e.preventDefault();
      e.stopPropagation();
      els.libraryDropZone.classList.remove("drag-over");
      if (e.dataTransfer && e.dataTransfer.files && e.dataTransfer.files.length > 0) {
        if (e.dataTransfer.files.length === 1) {
          handleFileSelection(e.dataTransfer.files[0]);
        } else {
          handleBatchFiles(e.dataTransfer.files);
        }
      }
    });
  }

  // Drag onto entire library drawer view
  if (els.drawerViewLibrary) {
    els.drawerViewLibrary.addEventListener("dragover", (e) => {
      e.preventDefault();
    });
    els.drawerViewLibrary.addEventListener("drop", (e) => {
      if (e.target.closest("#libraryDropZone")) return;
      e.preventDefault();
      if (e.dataTransfer && e.dataTransfer.files && e.dataTransfer.files.length > 0) {
        if (e.dataTransfer.files.length === 1) {
          handleFileSelection(e.dataTransfer.files[0]);
        } else {
          handleBatchFiles(e.dataTransfer.files);
        }
      }
    });
  }

  // Sticker edit modal buttons
  if (els.stickerEditModalCloseBtn) {
    els.stickerEditModalCloseBtn.addEventListener("click", closeStickerModal);
  }
  if (els.stickerEditCancelBtn) {
    els.stickerEditCancelBtn.addEventListener("click", closeStickerModal);
  }

  if (els.stickerEditSaveBtn) {
    els.stickerEditSaveBtn.addEventListener("click", async () => {
      const name = els.stickerEditNameInput ? els.stickerEditNameInput.value.trim() : "";
      if (!name) {
        showToast("Please enter a name.", "error");
        return;
      }
      const category = els.stickerEditCatInput ? els.stickerEditCatInput.value.trim() || "Custom / User" : "Custom / User";

      if (pendingUploadBase64) {
        const autoAlpha = Boolean(els.stickerUploadAutoAlpha && els.stickerUploadAutoAlpha.checked);
        showLoader(`Uploading custom asset "${name}"...`);
        try {
          const res = await apiPost("/api/library/stickers/upload", {
            name,
            category,
            image_base64: pendingUploadBase64,
            auto_alpha: autoAlpha,
          });
          showToast(res.message || "Custom asset uploaded!", "success");
          closeStickerModal();
          await fetchLibraryData();
        } catch (err) {
          showToast(`Upload failed: ${err.message}`, "error");
        } finally {
          hideLoader();
        }
      } else {
        const filename = els.stickerEditFilename ? els.stickerEditFilename.value : "";
        if (!filename) {
          showToast("Missing asset filename.", "error");
          return;
        }
        showLoader(`Updating "${name}"...`);
        try {
          const res = await apiPost("/api/library/stickers/edit", {
            filename,
            name,
            category,
          });
          showToast(res.message || "Asset updated!", "success");
          closeStickerModal();
          await fetchLibraryData();
        } catch (err) {
          showToast(`Update failed: ${err.message}`, "error");
        } finally {
          hideLoader();
        }
      }
    });
  }
}

async function handleBatchFiles(fileList) {
  if (!fileList || fileList.length === 0) return;
  const files = Array.from(fileList).filter((f) => /\.(png|jpe?g|bmp|webp)$/i.test(f.name));
  if (files.length === 0) {
    showToast("No supported image files found (PNG, JPG, BMP, WEBP).", "error");
    return;
  }

  if (els.libraryUploadProgress) {
    els.libraryUploadProgress.classList.remove("hidden");
    if (els.libraryUploadProgressText) els.libraryUploadProgressText.textContent = `Reading 0 / ${files.length} files...`;
    if (els.libraryUploadProgressPercent) els.libraryUploadProgressPercent.textContent = "0%";
    if (els.libraryUploadProgressBar) els.libraryUploadProgressBar.style.width = "0%";
  }

  const encodedFiles = [];
  for (let i = 0; i < files.length; i++) {
    const file = files[i];
    const dataUri = await readFileAsDataUri(file);
    encodedFiles.push({
      name: file.name,
      data: dataUri,
      relative_path: file.webkitRelativePath || file.name,
    });
    const pct = Math.round(((i + 1) / files.length) * 40);
    if (els.libraryUploadProgressText) els.libraryUploadProgressText.textContent = `Reading ${i + 1} / ${files.length} files...`;
    if (els.libraryUploadProgressPercent) els.libraryUploadProgressPercent.textContent = `${pct}%`;
    if (els.libraryUploadProgressBar) els.libraryUploadProgressBar.style.width = `${pct}%`;
  }

  const chunkSize = 15;
  const uploadCategory = state.activeLibraryTab !== "all" ? state.activeLibraryTab : "stickers";
  let totalUploaded = 0;
  const batchTotal = Math.ceil(encodedFiles.length / chunkSize);

  for (let chunkIdx = 0; chunkIdx < batchTotal; chunkIdx++) {
    const chunk = encodedFiles.slice(chunkIdx * chunkSize, (chunkIdx + 1) * chunkSize);
    if (els.libraryUploadProgressText) {
      els.libraryUploadProgressText.textContent = `Ingesting batch ${chunkIdx + 1} / ${batchTotal} (${totalUploaded} / ${encodedFiles.length})...`;
    }
    try {
      const res = await apiPost("/api/library/batch_upload", {
        category: uploadCategory,
        files: chunk,
        auto_remove_bg: true,
      });
      if (res && res.success) {
        totalUploaded += (res.count || chunk.length);
      }
    } catch (err) {
      console.error("Batch upload error:", err);
    }
    const pct = 40 + Math.round(((chunkIdx + 1) / batchTotal) * 60);
    if (els.libraryUploadProgressPercent) els.libraryUploadProgressPercent.textContent = `${pct}%`;
    if (els.libraryUploadProgressBar) els.libraryUploadProgressBar.style.width = `${pct}%`;
  }

  if (els.libraryUploadProgress) {
    els.libraryUploadProgress.classList.add("hidden");
  }
  showToast(`Successfully ingested ${totalUploaded} asset(s) into ${uploadCategory}!`, "success");
  await fetchLibraryData();
}

function readFileAsDataUri(file) {
  return new Promise((resolve) => {
    const reader = new FileReader();
    reader.onload = (e) => resolve(e.target.result);
    reader.onerror = () => resolve("");
    reader.readAsDataURL(file);
  });
}

function handleFileSelection(file) {
  if (!file) return;
  const validTypes = ["image/png", "image/jpeg", "image/bmp", "image/webp"];
  if (!validTypes.includes(file.type) && !/\.(png|jpe?g|bmp|webp)$/i.test(file.name)) {
    showToast("Unsupported image type. Use PNG, JPG, BMP, or WEBP.", "error");
    return;
  }

  const reader = new FileReader();
  reader.onload = (e) => {
    pendingUploadBase64 = e.target.result;
    openStickerModalForUpload(file.name);
  };
  reader.readAsDataURL(file);
}

function openStickerModalForUpload(originalFilename) {
  if (!els.stickerEditModal) return;
  const cleanName = originalFilename.replace(/\.[^/.]+$/, "").replace(/[-_]/g, " ");

  if (els.stickerEditModalTitle) {
    els.stickerEditModalTitle.innerHTML = '<svg class="glyph glyph-md"><use href="#glyph-sparkle"></use></svg> Upload Custom Sticker';
  }
  if (els.stickerEditFilename) els.stickerEditFilename.value = "";
  if (els.stickerEditNameInput) els.stickerEditNameInput.value = cleanName;
  if (els.stickerEditCatInput) els.stickerEditCatInput.value = "Custom / User";
  if (els.stickerUploadAlphaRow) els.stickerUploadAlphaRow.style.display = "block";
  if (els.stickerUploadAutoAlpha) els.stickerUploadAutoAlpha.checked = true;

  els.stickerEditModal.classList.remove("hidden");
  if (els.stickerEditNameInput) els.stickerEditNameInput.focus();
}

function openStickerModalForEdit(item) {
  if (!els.stickerEditModal) return;
  pendingUploadBase64 = null;

  if (els.stickerEditModalTitle) {
    els.stickerEditModalTitle.innerHTML = '<svg class="glyph glyph-md"><use href="#glyph-tune"></use></svg> Edit Sticker Details';
  }
  if (els.stickerEditFilename) els.stickerEditFilename.value = item.filename || "";
  if (els.stickerEditNameInput) els.stickerEditNameInput.value = item.name || "";
  if (els.stickerEditCatInput) els.stickerEditCatInput.value = item.category || "Custom / User";
  if (els.stickerUploadAlphaRow) els.stickerUploadAlphaRow.style.display = "none";

  els.stickerEditModal.classList.remove("hidden");
  if (els.stickerEditNameInput) els.stickerEditNameInput.focus();
}

function closeStickerModal() {
  if (els.stickerEditModal) els.stickerEditModal.classList.add("hidden");
  pendingUploadBase64 = null;
  if (els.stickerEditFilename) els.stickerEditFilename.value = "";
  if (els.stickerEditNameInput) els.stickerEditNameInput.value = "";
}

export async function fetchLibraryData() {
  try {
    const [stickersRes, skinsRes] = await Promise.all([
      apiGet("/api/library/stickers"),
      apiGet("/api/library/skins"),
    ]);

    const stickers = (stickersRes.stickers || []).map((s) => ({ ...s, asset_type: "stickers" }));
    const skins = (skinsRes.skins || []).map((sk) => ({ ...sk, asset_type: "weapons" }));
    state.libraryItems = [...stickers, ...skins];
    renderLibraryGrid();
  } catch (err) {
    console.warn("Failed to load asset library:", err);
  }
}

export function renderLibraryGrid() {
  if (!els.libraryGrid) return;
  els.libraryGrid.innerHTML = "";

  const filtered = (state.libraryItems || []).filter((item) => {
    // 1. Primary Category Tab filter
    if (state.activeLibraryTab && state.activeLibraryTab !== "all") {
      if (item.asset_type !== state.activeLibraryTab) return false;
    }
    // 2. Knife archetype filter
    if (state.activeLibraryTab === "knives" && state.activeKnifeType && state.activeKnifeType !== "all") {
      if (item.knife_type !== state.activeKnifeType) return false;
    }
    // 3. Subcategory / style filter (for stickers or all)
    if ((state.activeLibraryTab === "stickers" || state.activeLibraryTab === "all") && state.activeLibraryCat && state.activeLibraryCat !== "all") {
      if (item.category !== state.activeLibraryCat) return false;
    }
    // 4. Search query matching name, category, knife_type, or tags (#tag search support)
    if (state.librarySearch) {
      const q = state.librarySearch.toLowerCase().trim();
      if (q.startsWith("#")) {
        const tagQ = q.slice(1).trim();
        const tagMatch = (item.tags || []).some((t) => t.toLowerCase().includes(tagQ));
        if (!tagMatch) return false;
      } else {
        const nameMatch = (item.name || "").toLowerCase().includes(q);
        const catMatch = (item.category || "").toLowerCase().includes(q);
        const knifeMatch = (item.knife_type || "").toLowerCase().includes(q);
        const tagMatch = (item.tags || []).some((t) => t.toLowerCase().includes(q));
        if (!nameMatch && !catMatch && !knifeMatch && !tagMatch) return false;
      }
    }
    return true;
  });

  if (filtered.length === 0) {
    els.libraryGrid.innerHTML = `
      <div style="grid-column: 1/-1; text-align: center; padding: 40px; color: var(--text-dim);">
        No asset library items found matching your filter criteria.
      </div>
    `;
    return;
  }

  filtered.forEach((item) => {
    const card = document.createElement("div");
    card.className = "library-card";
    const previewUri = item.preview || item.thumbnail || "";

    let tagsHtml = "";
    if (item.tags && item.tags.length > 0) {
      tagsHtml = `<div class="library-tags-list">` +
        item.tags.slice(0, 5).map((tag) => `<span class="library-tag-chip" data-tag="${escapeHtml(tag)}">#${escapeHtml(tag)}</span>`).join("") +
        `</div>`;
    }

    let actionsTopHtml = "";
    const isSticker = (item.category !== "Custom Weapon Skins");
    if (isSticker) {
      actionsTopHtml = `
        <div class="library-card-actions-top">
          <button type="button" class="library-action-icon-btn btn-edit" title="Edit sticker details">
            <svg class="glyph glyph-xs"><use href="#glyph-tune"></use></svg>
          </button>
          <button type="button" class="library-action-icon-btn btn-del" title="Delete sticker">
            <svg class="glyph glyph-xs"><use href="#glyph-trash"></use></svg>
          </button>
        </div>
      `;
    }

    card.innerHTML = `
      ${actionsTopHtml}
      <div class="library-thumb-wrap">
        <img src="${previewUri}" alt="${escapeHtml(item.name)}">
      </div>
      <div class="library-card-info">
        <span class="library-card-title">${escapeHtml(item.name)}</span>
        <span class="library-card-cat">${escapeHtml(item.category || "")}</span>
        ${tagsHtml}
      </div>
      <div class="library-quick-actions">
        <button type="button" class="action-pill apply-slot-1-btn"><svg class="glyph glyph-xs"><use href="#glyph-bolt"></use></svg> Slot 1</button>
        <button type="button" class="action-pill apply-bake-btn"><svg class="glyph glyph-xs"><use href="#glyph-target"></use></svg> Bake</button>
      </div>
    `;

    if (isSticker) {
      const editBtn = card.querySelector(".btn-edit");
      if (editBtn) {
        editBtn.addEventListener("click", (e) => {
          e.stopPropagation();
          openStickerModalForEdit(item);
        });
      }

      const delBtn = card.querySelector(".btn-del");
      if (delBtn) {
        delBtn.addEventListener("click", async (e) => {
          e.stopPropagation();
          if (!confirm(`Delete sticker "${item.name}"? This cannot be undone.`)) return;
          showLoader(`Deleting sticker "${item.name}"...`);
          try {
            const res = await apiPost("/api/library/stickers/delete", { filename: item.filename });
            showToast(res.message || "Sticker deleted.", "success");
            await fetchLibraryData();
          } catch (err) {
            showToast(`Delete failed: ${err.message}`, "error");
          } finally {
            hideLoader();
          }
        });
      }
    }

    const slot1Btn = card.querySelector(".apply-slot-1-btn");
    if (slot1Btn) {
      slot1Btn.addEventListener("click", () => {
        applyLibraryItemToSlot(item, 1);
      });
    }

    const bakeBtn = card.querySelector(".apply-bake-btn");
    if (bakeBtn) {
      bakeBtn.addEventListener("click", () => {
        eventBus.emit("bake:loadSticker", { previewUri: item.preview || item.thumbnail, path: item.path });
        const bakeTab = document.querySelector('.nav-tab[data-tab="bake"]');
        if (bakeTab) bakeTab.click();
      });
    }

    // Tag chip quick filter click handler
    card.querySelectorAll(".library-tag-chip").forEach((chip) => {
      chip.addEventListener("click", (e) => {
        e.stopPropagation();
        const tag = chip.dataset.tag;
        if (tag) {
          const query = `#${tag}`;
          if (els.librarySearchInput) els.librarySearchInput.value = query;
          state.librarySearch = query;
          renderLibraryGrid();
        }
      });
    });

    els.libraryGrid.appendChild(card);
  });
}

export function openLibraryModalForSlot(tex) {
  state.targetModalSlot = tex;
  state.modalTargetDestination = "slot";
  if (els.modalTitle) {
    els.modalTitle.textContent = `Choose Sticker for ${tex.name}`;
  }
  openLibraryModalGeneral();
}

export function openLibraryModalGeneral() {
  if (!els.modalLibraryGrid || !els.libraryModal) return;
  els.modalLibraryGrid.innerHTML = "";

  state.libraryItems.forEach((item) => {
    const card = document.createElement("div");
    card.className = "library-card";
    card.style.padding = "10px";
    const previewUri = item.preview || item.thumbnail || "";
    card.innerHTML = `
      <div class="library-thumb-wrap" style="height: 100px;">
        <img src="${previewUri}" alt="${escapeHtml(item.name)}">
      </div>
      <div class="library-card-info">
        <span class="library-card-title" style="font-size: 0.85rem;">${escapeHtml(item.name)}</span>
        <span class="library-card-cat" style="font-size: 0.7rem;">${escapeHtml(item.category || "")}</span>
      </div>
    `;

    card.style.cursor = "pointer";
    card.addEventListener("click", () => {
      els.libraryModal.classList.add("hidden");

      if (state.modalTargetDestination === "bake") {
        eventBus.emit("bake:loadSticker", { previewUri: item.preview || item.thumbnail, path: item.path });
      } else if (state.modalTargetDestination === "slotTune") {
        state.slotTune.stickerDataUri = item.preview || item.thumbnail;
        const img = new Image();
        img.onload = () => {
          state.slotTune.stickerImg = img;
          const canvas = document.getElementById("slotTuneCanvas");
          if (canvas) {
            import("./slots.js").then((m) => m.renderSlotTuneCanvas());
          }
        };
        img.src = item.preview || item.thumbnail;
      } else if (state.modalTargetDestination === "slot" && state.targetModalSlot) {
        state.pendingSlotUpdates[state.targetModalSlot.index] = {
          image_path: item.path,
          base64: item.preview || item.thumbnail,
          previewUri: item.preview || item.thumbnail,
          mode: state.targetModalSlot.is_masked ? "fit" : "stretch",
          scale: 1.0,
        };
        refreshSlotPreview(state.targetModalSlot);
      }
    });

    els.modalLibraryGrid.appendChild(card);
  });

  els.libraryModal.classList.remove("hidden");
}

function applyLibraryItemToSlot(item, slotNumber) {
  if (!state.modelData) return;
  const stickers = state.modelData.textures.filter((t) => t.role === "sticker");
  if (stickers.length === 0) {
    showToast("No sticker slots in active model.", "error");
    return;
  }

  const target = stickers[Math.min(slotNumber - 1, stickers.length - 1)];
  const uri = item.preview || item.thumbnail || "";
  state.pendingSlotUpdates[target.index] = {
    image_path: item.path,
    base64: uri,
    previewUri: uri,
    mode: "fit",
    scale: 1.0,
  };
  refreshSlotPreview(target);

  const slotsTab = document.querySelector('.nav-tab[data-tab="slots"]');
  if (slotsTab) slotsTab.click();
  showToast(`Sticker staged for slot ${target.name}. Click 'Inject Texture' to commit.`, "info");
}
