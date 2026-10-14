<template>
  <div ref="settingsRoot" class="ald-settings">
    <header class="ald-head">
      <h1>A Long Drive</h1>
      <p>An endless road with fuel and scrap to find. Debug controls for the prototype.</p>
    </header>

    <div v-if="error" class="ald-error">{{ error }}</div>
    <div v-else-if="state.walking" class="ald-error">You're on foot. Get back in the car to start a new game.</div>

    <section class="ald-status">
      <div>
        <div class="ald-label">Road</div>
        <div class="ald-value">{{ state.active ? "Running" : "Not running" }}</div>
      </div>
      <div>
        <div class="ald-label">Seed</div>
        <div class="ald-value">{{ state.seed ?? "-" }}</div>
      </div>
    </section>

    <section class="ald-row">
      <div class="ald-copy">
        <div class="ald-label">New game</div>
        <div class="ald-desc">
          Builds a new road from a random seed and puts your current car on it. The seed is shown above, so a run can be
          repeated from the console with <code>aLongDrive.start(seed)</code>.
        </div>
      </div>
      <BngButton accent="main" :disabled="loading || state.walking" @click="newGame">New game, random seed</BngButton>
    </section>

    <section class="ald-row">
      <div class="ald-copy">
        <div class="ald-label">Stop</div>
        <div class="ald-desc">Removes the road, terrain and pickups, and puts the level's ground back.</div>
      </div>
      <BngButton accent="outlined" :disabled="loading || !state.active" @click="stop">Stop</BngButton>
    </section>

    <section class="ald-row">
      <div class="ald-copy">
        <div class="ald-label">Frequent pickups</div>
        <div class="ald-desc">Fuel and scrap spawn far more often, for testing. Takes effect straight away.</div>
      </div>
      <BngSwitch :model-value="state.devMode" :disabled="loading" @update:model-value="setDevMode" />
    </section>

    <section class="ald-row">
      <div class="ald-copy">
        <div class="ald-label">Reload</div>
        <div class="ald-desc">
          Reload mod picks up edits to the Lua code, config and materials, and restarts a running road with the same
          seed. Reload UI is for edits to this page, and closes the menu.
        </div>
      </div>
      <div class="ald-buttons">
        <BngButton accent="outlined" :disabled="loading" @click="reloadMod">Reload mod</BngButton>
        <BngButton accent="outlined" :disabled="loading" @click="reloadUi">Reload UI</BngButton>
      </div>
    </section>
  </div>
</template>

<script setup>
import { onMounted, onUnmounted, reactive, ref } from "vue"
import { BngButton, BngSwitch } from "@/common/components/base"
import { useBridge } from "@/bridge"

const POLL_MS = 500

const { lua, api } = useBridge()
const settingsRoot = ref(null)
const loading = ref(true)
const error = ref("")
let settingsCard = null
let pollTimer = null

const state = reactive({ active: false, seed: null, devMode: false, walking: false })

function runLua(code) {
  return new Promise(resolve => api.engineLua(code, resolve))
}

function apply(next) {
  // Lua omits nil fields, so clear the optional one rather than keeping a stale value.
  if (next && typeof next === "object") Object.assign(state, { seed: null }, next)
}

async function refresh() {
  apply(await runLua("aLongDrive.getState()"))
}

async function loadState() {
  loading.value = true
  error.value = ""
  try {
    await lua.extensions.load("aLongDrive")
    await refresh()
  } catch {
    error.value = "A Long Drive could not be loaded. Reload Lua (Ctrl+L) or restart the game."
  } finally {
    loading.value = false
  }
}

async function newGame() {
  error.value = ""
  try {
    const result = await runLua("aLongDrive.newGame()")
    if (!result?.ok) error.value = result?.error || "The new game could not be started."
    await refresh()
  } catch {
    error.value = "The new game could not be started."
  }
}

async function stop() {
  error.value = ""
  try {
    await runLua("aLongDrive.stop()")
    await refresh()
  } catch {
    error.value = "Could not stop."
  }
}

async function reloadMod() {
  error.value = ""
  try {
    const result = await runLua("aLongDrive.reload()")
    if (!result?.ok) error.value = result?.error || "The reload failed."
    await refresh()
  } catch {
    error.value = "The reload failed. Check the log."
  }
}

function reloadUi() {
  runLua("reloadUI()")
}

function setDevMode(value) {
  state.devMode = value
  error.value = ""
  runLua(`aLongDrive.setDevMode(${value ? "true" : "false"})`).catch(() => {
    error.value = "That change could not be saved."
  })
}

onMounted(() => {
  settingsCard = settingsRoot.value?.closest(".menu-content-card-1") || null
  if (settingsCard) {
    settingsCard.style.setProperty("width", "clamp(34rem, 38vw, 42rem)", "important")
    settingsCard.style.setProperty("max-width", "calc(100vw - 2rem)", "important")
  }
  loadState()
  pollTimer = setInterval(() => refresh().catch(() => {}), POLL_MS)
})

onUnmounted(() => {
  clearInterval(pollTimer)
  if (settingsCard) {
    settingsCard.style.removeProperty("width")
    settingsCard.style.removeProperty("max-width")
  }
})
</script>

<style lang="scss" scoped>
.ald-settings {
  height: 100%;
  width: 100%;
  box-sizing: border-box;
  overflow-y: auto;
  padding: 0 1.25rem 2rem;
  color: var(--bng-off-white);
}

.ald-head {
  padding: 1rem 0 0.5rem;

  h1 {
    margin: 0;
    font-size: 1.5rem;
  }

  p {
    margin: 0.25rem 0 0;
    opacity: 0.7;
    font-size: 0.85rem;
  }
}

.ald-error {
  margin: 0.5rem 0;
  padding: 0.5rem 0.75rem;
  border-radius: 0.25rem;
  background: var(--bng-orange-700, #8a3d00);
  font-size: 0.85rem;
}

.ald-status {
  display: grid;
  grid-template-columns: repeat(2, 1fr);
  gap: 1rem;
  padding: 0.9rem 0;
  border-top: 1px solid rgba(255, 255, 255, 0.12);
}

.ald-value {
  margin-top: 0.15rem;
  font-size: 1.25rem;
  font-variant-numeric: tabular-nums;
}

.ald-row {
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: 1.5rem;
  padding: 0.9rem 0;
  border-top: 1px solid rgba(255, 255, 255, 0.12);
}

.ald-copy {
  flex: 1 1 auto;
  min-width: 0;
}

.ald-buttons {
  display: flex;
  gap: 0.25rem;
}

.ald-label {
  font-size: 1rem;
}

.ald-desc {
  margin-top: 0.15rem;
  opacity: 0.65;
  font-size: 0.8rem;
  line-height: 1.35;
}
</style>
