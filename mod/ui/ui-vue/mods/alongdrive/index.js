import { lua } from "@/bridge"

const BUTTON_ID = "alongdrive-settings"

export async function onLoad() {
  await lua.extensions.ui_pause_actions.registerModButton({
    id: BUTTON_ID,
    tabId: "mods",
    label: "A Long Drive",
    icon: "road",
    componentName: "/ui/ui-vue/mods/alongdrive/Settings.vue",
  })
}

export async function onUnload() {
  await lua.extensions.ui_pause_actions.unregisterModButton(BUTTON_ID)
}
