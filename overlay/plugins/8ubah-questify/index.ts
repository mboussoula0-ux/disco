// 8ubah Quests — built-in plugin for the 8ubah (Kettu) bundle. Original code.
// Hides Discord Quests by dropping the quest-fetch events so no quests load anywhere.
import { defineCorePlugin } from "..";
import { findByProps } from "@metro";
import { before } from "@lib/api/patcher";

export const preenabled = false;

let unpatch: (() => void) | undefined;
const Flux = findByProps("dispatch", "subscribe");

export default defineCorePlugin({
    manifest: {
        id: "8ubah.quests", version: "1.0.0", type: "plugin", spec: 3, main: "",
        display: { name: "8ubah Quests Off", description: "Hide all Discord Quests", authors: [{ name: "rayan" }] },
    },
    start() {
        if (!Flux) return;
        unpatch = before("dispatch", Flux, (args: any[]) => {
            const a = args[0];
            if (a && typeof a.type === "string" && a.type.startsWith("QUESTS_FETCH_CURRENT_QUESTS")) args[0] = { ...a, type: "8UBAH_QUESTS_OFF" };
        });
    },
    stop() { unpatch?.(); unpatch = undefined; },
});
