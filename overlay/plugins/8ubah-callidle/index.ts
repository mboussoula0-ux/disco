// 8ubah No Call Idle — built-in plugin for the 8ubah (Kettu) bundle. Original code.
// Stops Discord from marking you idle, so you are not auto-disconnected for being alone/idle in a call.
import { defineCorePlugin } from "..";
import { findByProps } from "@metro";
import { before } from "@lib/api/patcher";

export const preenabled = false;

let unpatch: (() => void) | undefined;
const Flux = findByProps("dispatch", "subscribe");

export default defineCorePlugin({
    manifest: {
        id: "8ubah.callidle", version: "1.1.0", type: "plugin", spec: 3, main: "",
        display: { name: "8ubah No Call Idle", description: "Stops idle auto-disconnect in voice", authors: [{ name: "rayan" }] },
    },
    start() {
        if (!Flux) return;
        // The "you've been by yourself for 3 minutes" disconnect fires once the client reports idle.
        // Rewrite the idle action to a fresh, non-idle copy (the original object may be frozen).
        unpatch = before("dispatch", Flux, (args: any[]) => {
            const a = args[0];
            if (!a || typeof a.type !== "string") return;
            try {
                if (a.type === "IDLE" && a.idle) args[0] = { ...a, idle: false };
            } catch { /* keep the dispatcher safe */ }
        });
    },
    stop() { unpatch?.(); unpatch = undefined; },
});
