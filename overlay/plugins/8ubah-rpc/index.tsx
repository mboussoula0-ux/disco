// 8ubah Custom RPC — built-in plugin for the 8ubah (Kettu) bundle. Original code.
// Sets a custom Rich Presence (status/activity) on your account that stays while Discord is open.
// Supports: name, details, state, activity type, big/small image + tooltips, two buttons, elapsed time, stream link.
// The dispatch (LOCAL_ACTIVITY_UPDATE / socketId "CustomRPC") matches how Discord itself applies a local activity.
import { defineCorePlugin } from "..";
import { findByProps } from "@metro";
import { FluxDispatcher } from "@metro/common";
import {
    Stack, TableRow, TableRowGroup, TableSwitchRow,
    TableRadioGroup, TableRadioRow, TextInput, Button, Text,
} from "@metro/common/components";
import { ScrollView } from "react-native";
import * as React from "react";
import { createStorageAsync } from "@lib/api/storage";

// --- activity types ---
const ActivityType = { PLAYING: 0, STREAMING: 1, LISTENING: 2, WATCHING: 3, COMPETING: 5 } as const;

interface RpcConfig {
    enabled: boolean;
    appID: string;
    name: string;
    details: string;
    state: string;
    type: number;
    streamLink: string;
    showTime: boolean;
    bigImage: string;   // asset key or external image URL
    bigText: string;
    smallImage: string;
    smallText: string;
    btn1Text: string; btn1URL: string;
    btn2Text: string; btn2URL: string;
}

const DEFAULTS: RpcConfig = {
    enabled: false, appID: "", name: "", details: "", state: "",
    type: ActivityType.PLAYING, streamLink: "", showTime: true,
    bigImage: "", bigText: "", smallImage: "", smallText: "",
    btn1Text: "", btn1URL: "", btn2Text: "", btn2URL: "",
};

// In-memory config (works even if disk persistence fails). Persistence is best-effort.
let cfg: RpcConfig = { ...DEFAULTS };
let storage: any = null;

async function loadConfig(): Promise<void> {
    try {
        storage = await createStorageAsync("8ubah/rpc.json", { dflt: { ...DEFAULTS } });
        cfg = { ...DEFAULTS, ...storage };
    } catch { /* keep in-memory defaults */ }
}

function saveConfig(): void {
    try { if (storage) Object.assign(storage, cfg); } catch { /* ignore */ }
}

// Resolve an image key/URL into an asset id Discord accepts. External URLs go through fetchAssetIds.
async function resolveAsset(appID: string, key: string): Promise<string | undefined> {
    if (!key) return undefined;
    try {
        const AAU = findByProps("fetchAssetIds") || findByProps("getAssetImage", "fetchAssetIds");
        if (AAU?.fetchAssetIds && appID) {
            const ids = await AAU.fetchAssetIds(appID, [key]);
            if (ids && ids[0]) return ids[0];
        }
    } catch { /* fall through */ }
    return key; // Discord may still accept a bare asset name
}

let revision = 0;

async function applyRpc(): Promise<void> {
    const rev = ++revision;
    try {
        if (!cfg.enabled || !cfg.name) {
            FluxDispatcher.dispatch({ type: "LOCAL_ACTIVITY_UPDATE", socketId: "CustomRPC", activity: null });
            return;
        }
        const appID = cfg.appID || "0";
        const activity: any = {
            application_id: appID,
            name: cfg.name,
            type: cfg.type,
            flags: 1 << 0,
        };
        if (cfg.details) activity.details = cfg.details;
        if (cfg.state) activity.state = cfg.state;
        if (cfg.type === ActivityType.STREAMING && cfg.streamLink) activity.url = cfg.streamLink;
        if (cfg.showTime) activity.timestamps = { start: Date.now() };

        if (cfg.btn1Text) {
            activity.buttons = [cfg.btn1Text, cfg.btn2Text].filter(Boolean);
            activity.metadata = { button_urls: [cfg.btn1URL, cfg.btn2URL].filter(Boolean) };
        }
        if (cfg.bigImage) {
            activity.assets = activity.assets || {};
            activity.assets.large_image = await resolveAsset(appID, cfg.bigImage);
            if (cfg.bigText) activity.assets.large_text = cfg.bigText;
        }
        if (cfg.smallImage) {
            activity.assets = activity.assets || {};
            activity.assets.small_image = await resolveAsset(appID, cfg.smallImage);
            if (cfg.smallText) activity.assets.small_text = cfg.smallText;
        }
        // drop empty fields
        for (const k of Object.keys(activity)) {
            if (k === "type" || k === "flags") continue;
            const v = activity[k];
            if (v == null || (typeof v === "string" && v.length === 0)) delete activity[k];
        }
        if (rev !== revision) return; // a newer apply ran while we awaited
        FluxDispatcher.dispatch({ type: "LOCAL_ACTIVITY_UPDATE", socketId: "CustomRPC", activity });
    } catch { /* never crash the client over presence */ }
}

// read a string out of whatever the TextInput hands onChange (string in the new design, event in legacy)
const asText = (v: any): string => (typeof v === "string" ? v : (v?.nativeEvent?.text ?? v?.target?.value ?? ""));

function RpcSettings(): any {
    const [, force] = React.useState(0);
    const [ready, setReady] = React.useState(!!storage || true);
    React.useEffect(() => { if (!storage) loadConfig().then(() => { setReady(true); force(x => x + 1); }); }, []);

    const set = (patch: Partial<RpcConfig>) => { cfg = { ...cfg, ...patch }; saveConfig(); force(x => x + 1); applyRpc(); };
    const field = (label: string, key: keyof RpcConfig, placeholder = "") =>
        React.createElement(TextInput, {
            key, label, placeholder, value: String((cfg as any)[key] ?? ""),
            onChange: (v: any) => set({ [key]: asText(v) } as any),
        });

    if (!ready) return React.createElement(Text, null, "…");

    return React.createElement(ScrollView, { style: { flex: 1 }, contentContainerStyle: { paddingBottom: 48 } },
        React.createElement(Stack, { style: { paddingVertical: 20, paddingHorizontal: 12 }, spacing: 16 },
            React.createElement(TableRowGroup, { title: "RPC" },
                React.createElement(TableSwitchRow, {
                    label: "Enabled", value: cfg.enabled,
                    onValueChange: (v: boolean) => set({ enabled: v }),
                }),
            ),
            field("App name", "name", "My Game"),
            field("Details", "details", "Line 2"),
            field("State", "state", "Line 3"),
            field("App ID", "appID", "optional — a Discord application id"),
            React.createElement(TableRadioGroup, {
                title: "Type",
                value: cfg.type,
                onChange: (v: number) => set({ type: Number(v) }),
            },
                React.createElement(TableRadioRow, { label: "Playing", value: ActivityType.PLAYING }),
                React.createElement(TableRadioRow, { label: "Streaming", value: ActivityType.STREAMING }),
                React.createElement(TableRadioRow, { label: "Listening", value: ActivityType.LISTENING }),
                React.createElement(TableRadioRow, { label: "Watching", value: ActivityType.WATCHING }),
                React.createElement(TableRadioRow, { label: "Competing", value: ActivityType.COMPETING }),
            ),
            field("Stream link", "streamLink", "https://twitch.tv/… (Streaming only)"),
            field("Large image", "bigImage", "asset name or image URL"),
            field("Large image text", "bigText"),
            field("Small image", "smallImage", "asset name or image URL"),
            field("Small image text", "smallText"),
            field("Button 1 text", "btn1Text"),
            field("Button 1 URL", "btn1URL"),
            field("Button 2 text", "btn2Text"),
            field("Button 2 URL", "btn2URL"),
            React.createElement(TableRowGroup, { title: "Time" },
                React.createElement(TableSwitchRow, {
                    label: "Show elapsed time", value: cfg.showTime,
                    onValueChange: (v: boolean) => set({ showTime: v }),
                }),
            ),
            React.createElement(Button, {
                text: "Apply now", variant: "primary",
                onPress: () => applyRpc(),
            }),
        ),
    );
}

export const preenabled = false;

export default defineCorePlugin({
    manifest: {
        id: "8ubah.rpc", version: "1.0.0", type: "plugin", spec: 3, main: "",
        display: { name: "8ubah Custom RPC", description: "Set a custom Rich Presence on your account", authors: [{ name: "rayan" }] },
    },
    SettingsComponent: RpcSettings,
    start() { loadConfig().then(() => applyRpc()); },
    stop() {
        try { FluxDispatcher.dispatch({ type: "LOCAL_ACTIVITY_UPDATE", socketId: "CustomRPC", activity: null }); } catch { /* ignore */ }
    },
});
