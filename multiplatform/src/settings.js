// CATAI Settings — Tauri v2
const { invoke } = window.__TAURI__.core;

// Ollama requests go through Rust backend to avoid CORS issues

const CAT_COLORS = [
  { id: "orange", css: "#ff9933", hueRotate: 0, saturate: 1, brightness: 1,
    traits: { fr: "joueur et espiègle", en: "playful and mischievous", es: "juguetón y travieso" },
    names: { fr: "Citrouille", en: "Pumpkin", es: "Calabaza" }},
  { id: "black", css: "#2a2a2e", hueRotate: 0, saturate: 0.1, brightness: 0.4,
    traits: { fr: "mystérieux et philosophe", en: "mysterious and philosophical", es: "misterioso y filósofo" },
    names: { fr: "Ombre", en: "Shadow", es: "Sombra" }},
  { id: "white", css: "#f0f0f4", hueRotate: 0, saturate: 0.05, brightness: 1.5,
    traits: { fr: "élégant et poétique", en: "elegant and poetic", es: "elegante y poético" },
    names: { fr: "Neige", en: "Snow", es: "Nieve" }},
  { id: "grey", css: "#8c8c94", hueRotate: 0, saturate: 0, brightness: 0.75,
    traits: { fr: "sage et savant", en: "wise and scholarly", es: "sabio y erudito" },
    names: { fr: "Einstein", en: "Einstein", es: "Einstein" }},
  { id: "brown", css: "#804d26", hueRotate: -15, saturate: 0.7, brightness: 0.7,
    traits: { fr: "aventurier et conteur", en: "adventurous storyteller", es: "aventurero y cuentacuentos" },
    names: { fr: "Indiana", en: "Indiana", es: "Indiana" }},
  { id: "cream", css: "#f2e0bf", hueRotate: 10, saturate: 0.3, brightness: 1.2,
    traits: { fr: "câlin et réconfortant", en: "cuddly and comforting", es: "cariñoso y reconfortante" },
    names: { fr: "Caramel", en: "Caramel", es: "Caramelo" }},
];

const L10N = {
  lang_label: { fr: "LANGUE", en: "LANGUAGE", es: "IDIOMA" },
  cats:       { fr: "MON CHAT", en: "MY CAT", es: "MI GATO" },
  name:       { fr: "Nom :", en: "Name:", es: "Nombre:" },
  size:       { fr: "TAILLE", en: "SIZE", es: "TAMAÑO" },
  model:      { fr: "MODÈLE OLLAMA", en: "OLLAMA MODEL", es: "MODELO OLLAMA" },
  title:      { fr: ":: RÉGLAGES ::", en: ":: SETTINGS ::", es: ":: AJUSTES ::" },
  no_ollama:  { fr: "(Ollama indisponible)", en: "(Ollama unavailable)", es: "(Ollama no disponible)" },
  close:      { fr: "OK", en: "OK", es: "OK" },
};

let lang = localStorage.getItem("catLang") || "fr";
let catColorId = localStorage.getItem("catColorId") || "orange";
let catSize = parseInt(localStorage.getItem("catSize") || "96");
let catName = localStorage.getItem("catName") || "";
let ollamaModel = localStorage.getItem("ollamaModel") || "gemma4:latest";

function s(key) { return (L10N[key] || {})[lang] || (L10N[key] || {}).fr || key; }
function getColorDef(id) { return CAT_COLORS.find(c => c.id === id) || CAT_COLORS[0]; }

function notifyMainWindow() {
  invoke("notify_settings_changed").catch(() => {});
}

// --- Build UI ---
function buildColorRow() {
  const row = document.getElementById("color-row");
  row.innerHTML = "";
  for (const c of CAT_COLORS) {
    const dot = document.createElement("div");
    dot.className = "color-dot" + (c.id === catColorId ? " active" : "");
    dot.style.backgroundColor = c.css;
    dot.addEventListener("click", () => {
      catColorId = c.id;
      localStorage.setItem("catColorId", catColorId);
      const allDefaults = CAT_COLORS.flatMap(x => Object.values(x.names));
      if (!catName || allDefaults.includes(catName)) {
        catName = c.names[lang] || c.names.fr;
        localStorage.setItem("catName", catName);
      }
      notifyMainWindow();
      refresh();
    });
    row.appendChild(dot);
  }
}

function refresh() {
  const def = getColorDef(catColorId);

  document.querySelector("h1").textContent = s("title");
  document.getElementById("lang-title").textContent = s("lang_label");
  document.getElementById("cats-title").textContent = s("cats");
  document.getElementById("name-label").textContent = s("name");
  document.getElementById("size-title").textContent = s("size");
  document.getElementById("model-title").textContent = s("model");

  document.querySelectorAll(".flag-btn").forEach(btn => {
    btn.classList.toggle("active", btn.dataset.lang === lang);
  });

  buildColorRow();

  const preview = document.getElementById("cat-preview");
  preview.src = "cute_orange_cat/rotations/south.png";
  if (def.id === "orange") {
    preview.style.filter = "";
  } else {
    preview.style.filter = `hue-rotate(${def.hueRotate}deg) saturate(${def.saturate}) brightness(${def.brightness})`;
  }

  document.getElementById("trait-text").textContent =
    "✦ " + (def.traits[lang] || def.traits.fr);

  const nameInput = document.getElementById("name-input");
  if (document.activeElement !== nameInput) {
    nameInput.value = catName || def.names[lang] || def.names.fr;
  }

  document.getElementById("size-slider").value = catSize;
  document.getElementById("size-value").textContent = "x" + (catSize / 96).toFixed(1);
}

// --- Events ---
document.querySelectorAll(".flag-btn").forEach(btn => {
  btn.addEventListener("click", () => {
    lang = btn.dataset.lang;
    localStorage.setItem("catLang", lang);
    const def = getColorDef(catColorId);
    const allDefaults = CAT_COLORS.flatMap(c => Object.values(c.names));
    if (!catName || allDefaults.includes(catName)) {
      catName = def.names[lang] || def.names.fr;
      localStorage.setItem("catName", catName);
    }
    notifyMainWindow();
    refresh();
  });
});

document.getElementById("name-input").addEventListener("change", (e) => {
  catName = e.target.value.trim() || getColorDef(catColorId).names[lang];
  localStorage.setItem("catName", catName);
  notifyMainWindow();
});

let sizeDebounce = null;
document.getElementById("size-slider").addEventListener("input", (e) => {
  catSize = parseInt(e.target.value);
  document.getElementById("size-value").textContent = "x" + (catSize / 96).toFixed(1);
  localStorage.setItem("catSize", catSize.toString());
  clearTimeout(sizeDebounce);
  sizeDebounce = setTimeout(notifyMainWindow, 150);
});

document.getElementById("close-btn").addEventListener("click", () => {
  invoke("hide_settings").catch(() => {});
});

// --- Ollama models ---
async function loadModels() {
  const select = document.getElementById("model-select");
  try {
    const models = await invoke("ollama_models");
    select.innerHTML = "";
    if (models && models.length > 0) {
      for (const name of models) {
        const opt = document.createElement("option");
        opt.value = name; opt.textContent = name;
        if (name === ollamaModel) opt.selected = true;
        select.appendChild(opt);
      }
    } else {
      select.innerHTML = `<option>${s("no_ollama")}</option>`;
    }
  } catch (e) {
    select.innerHTML = `<option>${s("no_ollama")}</option>`;
  }
}

document.getElementById("model-select").addEventListener("change", (e) => {
  ollamaModel = e.target.value;
  localStorage.setItem("ollamaModel", ollamaModel);
  notifyMainWindow();
});

// --- Init ---
refresh();
loadModels();
