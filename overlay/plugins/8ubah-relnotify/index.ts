// 8ubah Relationship Notifier — built-in plugin for the 8ubah (Kettu) bundle. Original code.
// Toasts you when: a friend removes you, or you are removed/kicked/banned from a server or a group DM.
// Note: Discord does NOT send any event when someone blocks you, so "blocked you" cannot be detected.
import { defineCorePlugin } from "..";
import { findByProps, findByStoreName } from "@metro";
import { before } from "@lib/api/patcher";
import { logger } from "@lib/utils/logger";

export const preenabled = false;

let unpatch: (() => void) | undefined;
const Flux = findByProps("dispatch", "subscribe");
const UserStore = findByStoreName("UserStore");
const GuildStore = findByStoreName("GuildStore");
const ChannelStore = findByStoreName("ChannelStore");

function toast(msg: string) {
    try { findByProps("showToast")?.showToast?.(msg); } catch { /* ignore */ }
    try { logger.log("[8ubah relnotify] " + msg); } catch { /* ignore */ }
}
function userName(id?: string): string {
    try { const u = UserStore?.getUser?.(id); return u?.username ? `@${u.username}` : "someone"; } catch { return "someone"; }
}

export default defineCorePlugin({
    manifest: {
        id: "8ubah.relnotify", version: "1.1.0", type: "plugin", spec: 3, main: "",
        display: { name: "8ubah Relationship Notifier", description: "Alerts when a friend removes you or you're kicked from a server/group", authors: [{ name: "rayan" }] },
    },
    start() {
        if (!Flux) return;
        unpatch = before("dispatch", Flux, (args: any[]) => {
            const a = args[0];
            if (!a || typeof a.type !== "string") return;
            try {
                // friend removed you (relationship type 1 = friend)
                if (a.type === "RELATIONSHIP_REMOVE" && a.relationship?.type === 1) {
                    toast(`${userName(a.relationship?.id)} removed you as a friend`);
                }
                // removed / kicked / banned from a server (guild becomes gone, not just unavailable)
                else if (a.type === "GUILD_DELETE" && !a.guild?.unavailable) {
                    let name = "a server";
                    try { name = GuildStore?.getGuild?.(a.guild?.id)?.name || name; } catch { /* ignore */ }
                    toast(`You were removed from ${name}`);
                }
                // removed from a group DM (channel type 3 = GROUP_DM)
                else if (a.type === "CHANNEL_DELETE") {
                    let ch: any = a.channel;
                    try { if (!ch || ch.type == null) ch = ChannelStore?.getChannel?.(a.channel?.id); } catch { /* ignore */ }
                    if (ch?.type === 3) toast(`You were removed from the group "${ch?.name || "group"}"`);
                }
            } catch { /* keep the dispatcher safe */ }
        });
    },
    stop() { unpatch?.(); unpatch = undefined; },
});
