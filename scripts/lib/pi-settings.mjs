// Merge the shared Pi settings (templates/pi/settings.json) into the local
// ~/.pi/agent/settings.json, which Pi owns and rewrites at runtime.
//
// Shared keys win. Every other local key is kept: Pi's own state (deviceId,
// changelog versions) and per-machine choices such as defaultModel. Packages
// merge by source, so a package added locally with `pi install` survives; a
// package removed from the shared list stays installed until removed locally.
//
// Usage: node pi-settings.mjs apply|check <shared.json> <local.json>
//   apply  Write the merged settings. Replaces a symlink (the old Stow-managed
//          link) with a regular file, keeping what the link pointed to.
//   check  Print one line per problem and exit 1, or exit 0 when up to date.

import fs from "node:fs";
import path from "node:path";
import { isDeepStrictEqual } from "node:util";

const [mode, sharedPath, localPath] = process.argv.slice(2);

const packageSource = (entry) =>
  typeof entry === "string" ? entry : entry?.source;

function readLocal() {
  let text;
  try {
    text = fs.readFileSync(localPath, "utf8");
  } catch (error) {
    // A dangling link to the old repository file counts as missing.
    if (error.code === "ENOENT") return {};
    throw error;
  }
  try {
    return JSON.parse(text);
  } catch {
    throw new Error(`${localPath} is not valid JSON; fix or remove it`);
  }
}

function isSymlink(file) {
  try {
    return fs.lstatSync(file).isSymbolicLink();
  } catch {
    return false;
  }
}

function merge(shared, local) {
  const merged = { ...local };
  for (const [key, value] of Object.entries(shared)) {
    if (key === "packages") {
      const sharedSources = new Set(value.map(packageSource));
      const localOnly = (local.packages ?? []).filter(
        (entry) => !sharedSources.has(packageSource(entry)),
      );
      merged.packages = [...value, ...localOnly];
    } else {
      merged[key] = value;
    }
  }
  return merged;
}

function apply(merged) {
  const text = `${JSON.stringify(merged, null, 2)}\n`;
  const symlink = isSymlink(localPath);
  if (!symlink && fs.existsSync(localPath)) {
    if (fs.readFileSync(localPath, "utf8") === text) return;
  }
  fs.mkdirSync(path.dirname(localPath), { recursive: true });
  const temp = `${localPath}.dot-tmp`;
  fs.writeFileSync(temp, text);
  // rename replaces a symlink itself rather than writing through it.
  fs.renameSync(temp, localPath);
}

function check(merged, local) {
  const problems = [];
  if (isSymlink(localPath)) {
    problems.push(`${localPath} is a symlink; Pi needs a local file`);
  } else if (!fs.existsSync(localPath)) {
    problems.push(`${localPath} is missing`);
  } else {
    for (const key of Object.keys(merged)) {
      if (!isDeepStrictEqual(merged[key], local[key])) {
        problems.push(`Pi setting "${key}" differs from the shared settings`);
      }
    }
  }
  for (const problem of problems) console.log(problem);
  return problems.length === 0;
}

try {
  if (mode !== "apply" && mode !== "check") {
    throw new Error("usage: pi-settings.mjs apply|check <shared> <local>");
  }
  const shared = JSON.parse(fs.readFileSync(sharedPath, "utf8"));
  const local = readLocal();
  const merged = merge(shared, local);
  if (mode === "apply") {
    apply(merged);
  } else if (!check(merged, local)) {
    process.exitCode = 1;
  }
} catch (error) {
  console.error(error.message);
  process.exitCode = 2;
}
