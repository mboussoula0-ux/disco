// 8ubah No Blocked — built-in plugin for the 8ubah (Kettu) bundle. Original code.
// REVEALS messages from users you blocked/ignored (Discord normally collapses them into "N blocked messages").
// While ON, the blocked check returns false so their messages render inline. Turn it OFF to restore normal blocking.
import { defineCorePlugin } from "..";
import { findByStoreName } from "@metro";
import { instead } from "@lib/api/patcher";

export const preenabled = false;

const unpatches: Array<() => void> = [];
const Rel = findByStoreName("RelationshipStore");

export default defineCorePlugin({
    manifest: {
        id: "8ubah.noblocked", version: "1.1.0", type: "plugin", spec: 3, main: "",
        display: { name: "8ubah No Blocked", description: "Show messages from blocked users", authors: [{ name: "rayan" }] },
    },
    start() {
        if (!Rel) return;
        // Reveal their messages by reporting "not blocked / not ignored" to the message list.
        for (const fn of ["isBlocked", "isIgnored", "isBlockedOrIgnored", "isBlockedForMessage"]) {
            if (typeof Rel[fn] === "function") {
                unpatches.push(instead(fn, Rel, () => false));
            }
        }
    },
    stop() { while (unpatches.length) { try { unpatches.pop()!(); } catch { /* ignore */ } } },
});
