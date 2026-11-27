// Applies the 8ubah overlay onto a freshly cloned Kettu checkout, at build time.
// It does NOT contain any Kettu source — it only copies our own plugin folders in, registers them,
// and renames the user-visible "Kettu" strings to "8ubah". Run:  node scripts/apply-overlay.mjs <kettuDir> <overlayDir>
import { readFileSync, writeFileSync, cpSync, existsSync } from "node:fs";
import { join } from "node:path";

const KETTU = process.argv[2] || "kettu";
const OVERLAY = process.argv[3] || "overlay";

// 1) our built-in plugins (folder name under overlay/plugins == folder name under src/core/plugins)
const PLUGINS = ["8ubah-noblocked", "8ubah-callidle", "8ubah-relnotify", "8ubah-hidden", "8ubah-questify", "8ubah-rpc"];
for (const p of PLUGINS) {
    cpSync(join(OVERLAY, "plugins", p), join(KETTU, "src/core/plugins", p), { recursive: true });
    console.log("copied plugin:", p);
}

// 2) register them inside getCorePlugins() — insert require() lines right after the object opens `=> ({`
const idxPath = join(KETTU, "src/core/plugins/index.ts");
let idx = readFileSync(idxPath, "utf8");
const entries = PLUGINS.map(p => `        "8ubah.${p.replace("8ubah-", "")}": require("./${p}"),`).join("\n");
if (!idx.includes("8ubah.")) {
    idx = idx.replace(/=>\s*\(\{/, m => `${m}\n${entries}`);
    writeFileSync(idxPath, idx);
    console.log("registered", PLUGINS.length, "plugins in getCorePlugins()");
} else {
    console.log("plugins already registered, skipping");
}

// 3) full rebrand + links. edit() safely patches a file only if it exists.
function edit(rel, fn) {
    const p = join(KETTU, rel);
    if (!existsSync(p)) { console.log("skip (not found):", rel); return; }
    const before = readFileSync(p, "utf8");
    const after = fn(before);
    if (after !== before) { writeFileSync(p, after); console.log("edited:", rel); }
    else console.log("no change:", rel);
}

// 3a) i18n display strings (page title, info-row label, debug/custom-url text)
edit("src/core/i18n/default.json", s => s
    .replace(/"Kettu"/g, '"8ubah"')
    .replace(/Kettu URL/g, "8ubah URL")
    .replace(/Send Kettu debug/g, "Send 8ubah debug")
    .replace(/Load Kettu from/g, "Load 8ubah from"));

// 3b) settings section name (hardcoded in the settings registry)
edit("src/core/ui/settings/index.ts", s => s.replace(/name:\s*"Kettu"/g, 'name: "8ubah"'));

// 3c) Discord invite -> your server
edit("src/lib/utils/constants.ts", s => s.replace(/(DISCORD_SERVER\s*=\s*)"[^"]*"/, '$1"https://discord.gg/ulp"'));

// 3d) General settings page: rename the Safe Mode subtitle, and REMOVE the Codeberg + GitHub link rows.
edit("src/core/ui/settings/pages/General/index.tsx", s => s
    .replace(/Load Kettu without loading add-ons/g, "Load 8ubah without loading add-ons")
    // each self-closing <TableRow ... CODEBERG ... /> (and GITHUB) is deleted whole
    .replace(/<TableRow\b[\s\S]*?\bCODEBERG\b[\s\S]*?\/>\s*/g, "")
    .replace(/<TableRow\b[\s\S]*?\bGITHUB\b[\s\S]*?\/>\s*/g, ""));

// 3e) startup / crash strings
edit("src/entry.ts", s => s.replace(/Failed to load Kettu/g, "Failed to load 8ubah").replace(/`Kettu: /g, "`8ubah: "));

console.log("8ubah overlay applied successfully.");
