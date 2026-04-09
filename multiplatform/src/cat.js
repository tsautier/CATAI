// CATAI — Multiplatform Virtual Desktop Pet
// Frontend logic for Tauri v2

const { invoke } = window.__TAURI__.core;
const { listen } = window.__TAURI__.event;

// --- Constants ---
const RENDER_FPS = 100;
const BEHAVIOR_INTERVAL = 1000;
const MOUSE_POLL_INTERVAL = 33; // ~30fps
const WALK_SPEED = 4;
const CHASE_SPEED = 3;
const LOOK_RADIUS = 200;
const CHASE_RADIUS = 120;
const CHASE_GIVE_UP = 300;
// Ollama requests go through Rust backend to avoid CORS issues
const MEM_MAX = 20;
const CHAT_W = 300;
const CHAT_H = 280;
const MEOW_H = 40; // extra height for meow bubble above sprite

// --- Localization ---
const L10n = {
  lang: localStorage.getItem("catLang") || "fr",
  strings: {
    hi:       { fr: "Miaou! ~(=^..^=)~", en: "Meow! ~(=^..^=)~", es: "¡Miau! ~(=^..^=)~" },
    talk:     { fr: "Parle au chat...", en: "Talk to the cat...", es: "Habla al gato..." },
    err:      { fr: "Mrrp... pas de connexion", en: "Mrrp... no connection", es: "Mrrp... sin conexión" },
  },
  meows: {
    fr: ["Miaou~", "Mrrp!", "Prrrr...", "Miaou miaou!", "Nyaa~", "*ronron*", "Mew!", "Prrrt?"],
    en: ["Meow~", "Mrrp!", "Purrrr...", "Meow meow!", "Nyaa~", "*purr*", "Mew!", "Prrrt?"],
    es: ["¡Miau~!", "Mrrp!", "Purrrr...", "¡Miau miau!", "Nyaa~", "*ronroneo*", "Mew!", "Prrrt?"],
  },
  s(k) { return (this.strings[k] || {})[this.lang] || (this.strings[k] || {}).fr || k; },
  randomMeow() {
    const m = this.meows[this.lang] || this.meows.fr;
    return m[Math.floor(Math.random() * m.length)];
  }
};

// --- Cat Personalities ---
const CAT_COLORS = [
  { id: "orange", hueRotate: 0, saturate: 1, brightness: 1,
    prompt: { fr: "Tu es un petit chat joueur et espiègle nommé {name}. Tu adores les blagues. Réponds brièvement avec des sons de chat. Max 2-3 phrases.",
              en: "You are a playful cat named {name}. You love jokes. Respond briefly with cat sounds. Max 2-3 sentences.",
              es: "Eres un gatito juguetón llamado {name}. Adoras los chistes. Responde brevemente con sonidos de gato. Máximo 2-3 frases." }},
  { id: "black", hueRotate: 0, saturate: 0.1, brightness: 0.4,
    prompt: { fr: "Tu es un petit chat mystérieux nommé {name}. Tu poses des questions profondes. Réponds brièvement. Max 2-3 phrases.",
              en: "You are a mysterious cat named {name}. You ask deep questions. Respond briefly. Max 2-3 sentences.",
              es: "Eres un gatito misterioso llamado {name}. Haces preguntas profundas. Máximo 2-3 frases." }},
  { id: "white", hueRotate: 0, saturate: 0.05, brightness: 1.5,
    prompt: { fr: "Tu es un petit chat élégant nommé {name}. Tu adores la poésie. Réponds avec grâce. Max 2-3 phrases.",
              en: "You are an elegant cat named {name}. You love poetry. Respond gracefully. Max 2-3 sentences.",
              es: "Eres un gatito elegante llamado {name}. Adoras la poesía. Máximo 2-3 frases." }},
  { id: "grey", hueRotate: 0, saturate: 0, brightness: 0.75,
    prompt: { fr: "Tu es un petit chat savant nommé {name}. Tu expliques des faits scientifiques. Réponds brièvement. Max 2-3 phrases.",
              en: "You are a scholarly cat named {name}. You explain scientific facts. Respond briefly. Max 2-3 sentences.",
              es: "Eres un gatito erudito llamado {name}. Explicas datos científicos. Máximo 2-3 frases." }},
  { id: "brown", hueRotate: -15, saturate: 0.7, brightness: 0.7,
    prompt: { fr: "Tu es un petit chat aventurier nommé {name}. Tu racontes des aventures. Réponds brièvement. Max 2-3 phrases.",
              en: "You are an adventurous cat named {name}. You tell adventures. Respond briefly. Max 2-3 sentences.",
              es: "Eres un gatito aventurero llamado {name}. Cuentas aventuras. Máximo 2-3 frases." }},
  { id: "cream", hueRotate: 10, saturate: 0.3, brightness: 1.2,
    prompt: { fr: "Tu es un petit chat câlin nommé {name}. Tu remontes le moral avec tendresse. Réponds brièvement. Max 2-3 phrases.",
              en: "You are a cuddly cat named {name}. You comfort with tenderness. Respond briefly. Max 2-3 sentences.",
              es: "Eres un gatito cariñoso llamado {name}. Animas con ternura. Máximo 2-3 frases." }},
];

// --- State ---
let meta = null;
let state = "idle";
let direction = "south";
let frameIndex = 0;
let idleTicks = 0;
let chaseTicks = 0;
let x = 200, y = 0;
let destX = 200;
let screenW = 1440, screenH = 900;
let displaySize = 96;
let lastAppliedSize = 0; // track to avoid redundant style updates

// Current Tauri window dimensions
let winW = 200;
let winH = 200;

// Mouse tracking
let mouseX = 0, mouseY = 0;

// Drag state
let dragging = false;
let dragStartX = 0, dragStartY = 0;
let dragOffsetX = 0, dragOffsetY = 0;
let mouseMoved = false;

// Chat state
let chatVisible = false;
let ollamaMessages = [];
let ollamaModel = "gemma4:latest";
let isStreaming = false;
let catName = "";
let catColorId = "";

const animKeys = {
  walking: "running-8-frames",
  eating: "eating",
  drinking: "drinking",
  angry: "angry",
  wakingUp: "waking-getting-up",
  chasing: "running-8-frames",
};
const oneShotStates = new Set(["eating", "drinking", "angry", "wakingUp"]);

const sprite = document.getElementById("cat-sprite");
const meowBubble = document.getElementById("meow-bubble");
const chatBubble = document.getElementById("chat-bubble");
const chatResponse = document.getElementById("chat-response");
const chatInput = document.getElementById("chat-input");

// --- Persistence ---

function loadCatConfig() {
  catColorId = localStorage.getItem("catColorId") || "orange";
  const colorDef = CAT_COLORS.find(c => c.id === catColorId) || CAT_COLORS[0];
  catName = localStorage.getItem("catName") || "Citrouille";
  ollamaModel = localStorage.getItem("ollamaModel") || "gemma4:latest";
  L10n.lang = localStorage.getItem("catLang") || "fr";
  displaySize = parseInt(localStorage.getItem("catSize") || "96");
  applyCatColor();
}

function initOllamaChat() {
  const colorDef = CAT_COLORS.find(c => c.id === catColorId) || CAT_COLORS[0];
  const promptTemplate = colorDef.prompt[L10n.lang] || colorDef.prompt.fr;
  const systemPrompt = promptTemplate.replace("{name}", catName);
  ollamaMessages = [{ role: "system", content: systemPrompt }];

  try {
    const saved = localStorage.getItem("chatMemory_" + catColorId);
    if (saved) {
      const mem = JSON.parse(saved);
      if (mem.length > 1) ollamaMessages.push(...mem.slice(1));
    }
  } catch (e) {}
}

function saveChatMemory() {
  let msgs = [...ollamaMessages];
  if (msgs.length > MEM_MAX * 2 + 1) {
    msgs = [msgs[0], ...msgs.slice(-(MEM_MAX * 2))];
  }
  localStorage.setItem("chatMemory_" + catColorId, JSON.stringify(msgs));
}

// --- Apply cat color via CSS filter ---
function applyCatColor() {
  const colorDef = CAT_COLORS.find(c => c.id === catColorId) || CAT_COLORS[0];
  if (colorDef.id === "orange") {
    sprite.style.filter = "";
  } else {
    sprite.style.filter = `hue-rotate(${colorDef.hueRotate}deg) saturate(${colorDef.saturate}) brightness(${colorDef.brightness})`;
  }
}

// --- Direction from angle ---
function directionFromAngle(deg) {
  const a = ((deg % 360) + 360) % 360;
  if (a >= 337.5 || a < 22.5) return "east";
  if (a < 67.5) return "north-east";
  if (a < 112.5) return "north";
  if (a < 157.5) return "north-west";
  if (a < 202.5) return "west";
  if (a < 247.5) return "south-west";
  if (a < 292.5) return "south";
  if (a < 337.5) return "south-east";
  return "south";
}

// --- Sprite path ---
function getSpritePath() {
  if (state === "idle" || state === "sleeping" || state === "looking") {
    const rotPath = meta.frames.rotations[direction] || meta.frames.rotations["south"];
    return "cute_orange_cat/" + rotPath;
  }
  const animKey = animKeys[state];
  if (animKey && meta.frames.animations[animKey]) {
    const dirFrames = meta.frames.animations[animKey][direction]
      || meta.frames.animations[animKey]["south"];
    if (dirFrames && dirFrames.length > 0) {
      return "cute_orange_cat/" + dirFrames[frameIndex % dirFrames.length];
    }
  }
  const fallback = meta.frames.rotations[direction] || meta.frames.rotations["south"];
  return "cute_orange_cat/" + fallback;
}

function getAnimFrameCount() {
  const animKey = animKeys[state];
  if (!animKey || !meta.frames.animations[animKey]) return 1;
  const dirFrames = meta.frames.animations[animKey][direction]
    || meta.frames.animations[animKey]["south"];
  return dirFrames ? dirFrames.length : 1;
}

function updateSprite() {
  const path = getSpritePath();
  if (!sprite.src.endsWith(path)) {
    sprite.src = path;
  }
  if (displaySize !== lastAppliedSize) {
    sprite.style.width = displaySize + "px";
    sprite.style.height = displaySize + "px";
    lastAppliedSize = displaySize;
  }
}

// --- Window positioning ---
// x, y = cat feet position in bottom-left origin (y=0 is screen bottom)
// Tauri uses top-left origin (y=0 is screen top)
// Window is larger than sprite when chat/meow is visible

async function syncPosition() {
  const wx = Math.round(x - (winW - displaySize) / 2);
  const wy = Math.round(screenH - y - winH);
  try {
    await invoke("move_cat_window", { label: "main", x: wx, y: wy });
  } catch (e) {}
}

async function setWindowSize(w, h) {
  winW = w;
  winH = h;
  try {
    await invoke("resize_window", { label: "main", width: w, height: h });
  } catch (e) {}
  await syncPosition();
}

// --- Mouse distance and direction from cat ---
function mouseDistAndDir() {
  const cx = x + displaySize / 2;
  const cy = y + displaySize / 2;
  const dx = mouseX - cx;
  const dy = mouseY - cy;
  return {
    dx, dy,
    dist: Math.hypot(dx, dy),
    dir: directionFromAngle(Math.atan2(dy, dx) * 180 / Math.PI)
  };
}

async function pollMouse() {
  try {
    const [mx, my] = await invoke("get_mouse_position");
    mouseX = mx;
    mouseY = my;
  } catch (e) {}
}

// --- Render tick ---
function renderTick() {
  if (state === "chasing") {
    const { dx, dy, dist, dir } = mouseDistAndDir();
    if (dist > CHASE_GIVE_UP || chaseTicks > 80) {
      state = "idle"; frameIndex = 0; idleTicks = 0; chaseTicks = 0;
    } else if (dist < displaySize * 0.4) {
      state = "idle"; frameIndex = 0; idleTicks = 0; chaseTicks = 0;
    } else {
      direction = dir;
      x += (dx / dist) * CHASE_SPEED;
      frameIndex++;
      chaseTicks++;
    }
    x = Math.max(0, Math.min(x, screenW - displaySize));
    syncPosition();
  } else if (state === "walking") {
    const dx = destX - x;
    if (Math.abs(dx) <= WALK_SPEED) {
      x = destX; state = "idle"; frameIndex = 0; idleTicks = 0;
    } else {
      const step = dx > 0 ? WALK_SPEED : -WALK_SPEED;
      x += step;
      direction = step > 0 ? "east" : "west";
      frameIndex++;
    }
    x = Math.max(0, Math.min(x, screenW - displaySize));
    syncPosition();
  } else if (oneShotStates.has(state)) {
    const total = getAnimFrameCount();
    if (frameIndex >= total - 1) {
      state = "idle"; frameIndex = 0; idleTicks = 0;
    } else {
      frameIndex++;
    }
  }
  updateSprite();
}

// --- Behavior tick ---
function behaviorTick() {
  if (chatVisible) return;

  const { dist, dir } = mouseDistAndDir();

  if (state === "idle" || state === "looking") {
    if (dist < LOOK_RADIUS && dist > displaySize * 0.4) {
      direction = dir;
      if (state !== "looking") { state = "looking"; idleTicks = 0; }
      if (dist < CHASE_RADIUS && Math.random() < 0.15) {
        state = "chasing"; frameIndex = 0; chaseTicks = 0; hideMeow();
        return;
      }
      return;
    } else if (state === "looking") {
      state = "idle"; idleTicks = 0;
    }
  }

  if (state === "idle") {
    idleTicks++;
    const r = Math.random();
    if (idleTicks > 15 && r < 0.05) {
      state = "sleeping"; idleTicks = 0;
    } else if (r < 0.25) {
      state = "walking"; frameIndex = 0;
      destX = Math.random() * (screenW - displaySize * 2) + displaySize;
    } else if (r < 0.30) {
      state = "eating"; frameIndex = 0;
    } else if (r < 0.35) {
      state = "drinking"; frameIndex = 0;
    } else if (r < 0.38) {
      showMeow();
    }
  } else if (state === "sleeping") {
    if (dist < CHASE_RADIUS) {
      state = "wakingUp"; frameIndex = 0; idleTicks = 0;
    } else {
      idleTicks++;
      if (idleTicks > Math.floor(Math.random() * 11) + 5) {
        state = "wakingUp"; frameIndex = 0; idleTicks = 0;
      }
    }
  }
}

// --- Meow bubble ---
let meowTimeout = null;

async function showMeow() {
  if (chatVisible) return;
  meowBubble.textContent = L10n.randomMeow();
  meowBubble.style.display = "block";
  await setWindowSize(displaySize, displaySize + MEOW_H);
  clearTimeout(meowTimeout);
  meowTimeout = setTimeout(() => hideMeow(), 2500);
}

async function hideMeow() {
  clearTimeout(meowTimeout);
  meowTimeout = null;
  meowBubble.style.display = "none";
  if (!chatVisible) {
    await setWindowSize(displaySize, displaySize);
  }
}

// --- Chat Bubble ---
function toggleChat() {
  if (chatVisible) hideChat();
  else showChat();
}

async function showChat() {
  await hideMeow();
  chatVisible = true;
  chatBubble.style.display = "block";
  chatResponse.textContent = L10n.s("hi");
  chatInput.placeholder = L10n.s("talk");
  chatInput.value = "";
  await setWindowSize(CHAT_W, displaySize + CHAT_H);
  chatInput.focus();
}

async function hideChat() {
  chatVisible = false;
  chatBubble.style.display = "none";
  await setWindowSize(displaySize, displaySize);
}

// --- Ollama Chat ---
async function sendChat(text) {
  if (isStreaming || !text.trim()) return;

  ollamaMessages.push({ role: "user", content: text });
  if (ollamaMessages.length > MEM_MAX * 2 + 1) {
    ollamaMessages = [ollamaMessages[0], ...ollamaMessages.slice(-(MEM_MAX * 2))];
  }

  chatResponse.textContent = "...";
  chatInput.value = "";
  isStreaming = true;
  state = "eating"; frameIndex = 0;

  try {
    const response = await invoke("ollama_chat", {
      model: ollamaModel,
      messages: ollamaMessages
    });

    if (response) {
      chatResponse.textContent = response;
      ollamaMessages.push({ role: "assistant", content: response });
      saveChatMemory();
    } else {
      ollamaMessages.pop();
      chatResponse.textContent = L10n.s("err");
    }
  } catch (e) {
    ollamaMessages.pop();
    chatResponse.textContent = L10n.s("err");
  }

  isStreaming = false;
  state = "idle"; frameIndex = 0; idleTicks = 0;
}

// --- Drag handling ---
sprite.addEventListener("mousedown", (e) => {
  if (e.button === 2) return;
  dragging = true;
  mouseMoved = false;
  dragStartX = e.screenX;
  dragStartY = e.screenY;
  dragOffsetX = 0;
  dragOffsetY = 0;
  e.preventDefault();
});

document.addEventListener("mousemove", (e) => {
  if (!dragging) return;
  const dx = e.screenX - dragStartX;
  const dy = e.screenY - dragStartY;
  if (Math.abs(dx) > 3 || Math.abs(dy) > 3) mouseMoved = true;
  if (mouseMoved) {
    x += (e.screenX - dragStartX - dragOffsetX);
    y -= (e.screenY - dragStartY - dragOffsetY);
    dragOffsetX = dx;
    dragOffsetY = dy;
    x = Math.max(0, Math.min(x, screenW - displaySize));
    y = Math.max(0, Math.min(y, screenH - displaySize));
    syncPosition();
  }
});

document.addEventListener("mouseup", (e) => {
  if (!dragging) return;
  dragging = false;
  if (!mouseMoved && e.button === 0) {
    toggleChat();
  }
});

sprite.addEventListener("contextmenu", (e) => {
  e.preventDefault();
  if (state !== "angry") {
    state = "angry"; frameIndex = 0;
  }
});

chatInput.addEventListener("keydown", (e) => {
  if (e.key === "Enter") sendChat(chatInput.value);
  if (e.key === "Escape") hideChat();
});

// --- Listen for settings changes via Tauri event ---
async function listenForSettingsChanges() {
  await listen("settings-changed", () => {
    const oldSize = displaySize;
    const oldColorId = catColorId;
    loadCatConfig();

    // Re-init chat if personality changed
    if (catColorId !== oldColorId) {
      initOllamaChat();
    } else {
      // Update system prompt with new name/lang
      const colorDef = CAT_COLORS.find(c => c.id === catColorId) || CAT_COLORS[0];
      const promptTemplate = colorDef.prompt[L10n.lang] || colorDef.prompt.fr;
      ollamaMessages[0] = { role: "system", content: promptTemplate.replace("{name}", catName) };
    }

    if (displaySize !== oldSize && !chatVisible) {
      setWindowSize(displaySize, displaySize);
    }
  });
}

// --- Init ---
async function init() {
  try {
    loadCatConfig();
    initOllamaChat();

    const resp = await fetch("cute_orange_cat/metadata.json");
    meta = await resp.json();

    try {
      const [sw, sh] = await invoke("get_screen_size");
      screenW = sw; screenH = sh;
    } catch (e) {
      console.warn("Could not get screen size, using defaults");
    }

    let taskbarH = 70;
    try { taskbarH = await invoke("get_taskbar_height"); } catch (e) {}
    x = screenW / 2 - displaySize / 2;
    y = taskbarH;

    await setWindowSize(displaySize, displaySize);
    updateSprite();

    setInterval(renderTick, RENDER_FPS);
    setInterval(behaviorTick, BEHAVIOR_INTERVAL);
    setInterval(pollMouse, MOUSE_POLL_INTERVAL);
    listenForSettingsChanges();

    console.log("CATAI started!", { screenW, screenH, catName, catColorId });
  } catch (e) {
    console.error("CATAI init failed:", e);
  }
}

if (window.__TAURI__) {
  init();
} else {
  window.addEventListener("DOMContentLoaded", () => setTimeout(init, 100));
}
