// 8ubah Show Hidden Channels — built-in plugin for the 8ubah (Kettu) bundle. Original code.
// Lists channels you lack VIEW_CHANNEL for (opening is still blocked by the server). Scoped to that one bit.
import { defineCorePlugin } from "..";
import { findByStoreName } from "@metro";
import { instead } from "@lib/api/patcher";

export const preenabled = false;

let unpatch: (() => void) | undefined;
const PermissionStore = findByStoreName("PermissionStore");
const VIEW_CHANNEL = 1024n; // 1 << 10
const isView = (p: any) => { try { return BigInt(p) === VIEW_CHANNEL; } catch { return false; } };

export default defineCorePlugin({
    manifest: {
        id: "8ubah.hidden", version: "1.0.0", type: "plugin", spec: 3, main: "",
        display: { name: "8ubah Show Hidden Channels", description: "Reveal hidden channels in the list", authors: [{ name: "rayan" }] },
    },
    start() {
        if (!PermissionStore?.can) return;
        unpatch = instead("can", PermissionStore, (args: any[], orig: any) => {
            try { if (isView(args[0])) return true; } catch { /* fall through */ }
            return orig.apply(PermissionStore, args);
        });
    },
    stop() { unpatch?.(); unpatch = undefined; },
});
