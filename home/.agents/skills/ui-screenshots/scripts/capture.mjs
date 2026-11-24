#!/usr/bin/env node
// Capture before/after/diff screenshots of a UI change and write screenshots.md.
// Usage: node capture.mjs spec.json
// See ../SKILL.md for the spec format and the table template this emits.

import { createRequire } from 'node:module';
import { execFileSync } from 'node:child_process';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';

const THEMES = {
  light: { name: 'light', colorScheme: 'light' },
  dark: { name: 'dark', colorScheme: 'dark' },
};
const VIEWPORTS = {
  desktop: { name: 'desktop', width: 1280, height: 800 },
  tablet: { name: 'tablet', width: 768, height: 1024 },
  mobile: { name: 'mobile', width: 390, height: 844 },
};
const BROWSERS = {
  chromium: { name: 'chromium', label: 'Chromium' },
  firefox: { name: 'firefox', label: 'Firefox' },
  webkit: { name: 'webkit', label: 'WebKit' },
};
const FREEZE_CSS = `*, *::before, *::after {
  animation-duration: 0s !important; animation-delay: 0s !important;
  transition-duration: 0s !important; transition-delay: 0s !important;
  scroll-behavior: auto !important; caret-color: transparent !important;
}
/* Dev-server overlays that differ between the two servers. */
astro-dev-toolbar, vite-error-overlay, nextjs-portal, #webpack-dev-server-client-overlay {
  display: none !important;
}`;
const GENERATED = /(-before|-after|-diff)\.png$|^(screenshots\.md|attach\.txt|manifest\.json)$/;
const CACHE = path.join(process.env.XDG_CACHE_HOME || path.join(os.homedir(), '.cache'), 'ui-screenshots');

// ---- spec -------------------------------------------------------------

const specPath = process.argv[2];
if (!specPath) {
  console.error('Usage: node capture.mjs spec.json');
  process.exit(2);
}
const spec = JSON.parse(fs.readFileSync(specPath, 'utf8'));
for (const key of ['before', 'after', 'shots']) {
  if (!spec[key]) throw new Error(`spec is missing "${key}"`);
}

const stamp = new Date().toISOString().replace(/[:.]/g, '-').slice(0, 19);
const out = path.resolve(spec.out || path.join(os.tmpdir(), 'ui-screenshots', `${path.basename(process.cwd())}-${stamp}`));
fs.mkdirSync(out, { recursive: true });
// Remove this script's outputs from an earlier run, so no stale image survives a rerun.
for (const f of fs.readdirSync(out)) if (GENERATED.test(f)) fs.rmSync(path.join(out, f));

// A closed pipe (e.g. `| head`) must not kill the run.
for (const stream of [process.stdout, process.stderr]) stream.on('error', () => {});

const slug = (s) => String(s).toLowerCase().replace(/[^a-z0-9]+/g, '-').replace(/^-|-$/g, '');
const title = (s) => String(s).charAt(0).toUpperCase() + String(s).slice(1);

const matrixThemes = (spec.themes || ['light']).map((t) => (typeof t === 'string' ? THEMES[t] : t));
const matrixViewports = (spec.viewports || ['desktop']).map((v) => (typeof v === 'string' ? VIEWPORTS[v] : v));

const matrixBrowsers = (spec.browsers || ['chromium']).map((b) => {
  if (!BROWSERS[b]) throw new Error(`unknown browser "${b}" (use chromium, firefox or webkit)`);
  return BROWSERS[b];
});

function pick(names, matrix, presets, kind) {
  if (!names) return matrix;
  return names.map((n) => {
    const found = matrix.find((m) => m.name === n) || presets[n];
    if (!found) throw new Error(`unknown ${kind} "${n}"`);
    return found;
  });
}

// ---- playwright -------------------------------------------------------

function resolvePlaywright() {
  for (const dir of [process.cwd(), CACHE]) {
    const req = createRequire(path.join(dir, 'package.json'));
    for (const name of ['playwright', '@playwright/test']) {
      try {
        return { require: req, path: req.resolve(name) };
      } catch {}
    }
  }
  console.error(`playwright not found; installing it into ${CACHE}`);
  fs.mkdirSync(CACHE, { recursive: true });
  execFileSync('npm', ['install', '--prefix', CACHE, '--no-audit', '--no-fund', 'playwright'], { stdio: 'inherit' });
  const req = createRequire(path.join(CACHE, 'package.json'));
  return { require: req, path: req.resolve('playwright') };
}

const pw = resolvePlaywright();
const playwright = pw.require(pw.path);
const browsers = new Map();

async function getBrowser(engine) {
  if (!browsers.has(engine)) {
    try {
      browsers.set(engine, await playwright[engine].launch());
    } catch (err) {
      const core = createRequire(pw.path).resolve('playwright-core/package.json');
      const cli = path.join(path.dirname(core), 'cli.js');
      console.error(`${err.message.split('\n')[0]}\nInstall the matching browser with:\n  node ${cli} install ${engine}`);
      process.exit(1);
    }
  }
  return browsers.get(engine);
}

// ---- capture ----------------------------------------------------------

async function shoot(browser, base, shot, theme, viewport, file) {
  const context = await browser.newContext({
    viewport: { width: viewport.width, height: viewport.height },
    deviceScaleFactor: spec.deviceScaleFactor || 1,
    colorScheme: theme.colorScheme || 'light',
    reducedMotion: 'reduce',
  });
  const storage = { ...spec.localStorage, ...theme.localStorage };
  const attributes = theme.attributes || {};
  const applyTheme = ({ storage, attributes }) => {
    try {
      for (const [k, v] of Object.entries(storage)) localStorage.setItem(k, v);
    } catch {}
    const html = document.documentElement;
    if (html) for (const [k, v] of Object.entries(attributes)) html.setAttribute(k, v);
  };
  await context.addInitScript(applyTheme, { storage, attributes });
  if (spec.initScript) await context.addInitScript({ content: spec.initScript });
  if (theme.initScript) await context.addInitScript({ content: theme.initScript });

  const page = await context.newPage();
  try {
    await page.goto(base.replace(/\/$/, '') + (shot.path || '/'), { waitUntil: 'networkidle' });
    await page.addStyleTag({ content: FREEZE_CSS });
    await page.evaluate(applyTheme, { storage: {}, attributes }); // re-apply after hydration
    await page.evaluate(() => document.fonts.ready);
    for (const action of shot.actions || []) await act(page, action);
    if (shot.waitFor) await page.locator(shot.waitFor).first().waitFor();
    if (shot.wait) await page.waitForTimeout(shot.wait);

    const options = {
      path: file,
      animations: 'disabled',
      caret: 'hide',
      mask: [...(spec.mask || []), ...(shot.mask || [])].map((s) => page.locator(s)),
    };
    if (shot.selector) await page.locator(shot.selector).first().screenshot(options);
    else await page.screenshot({ ...options, fullPage: shot.fullPage ?? spec.fullPage ?? false });
  } finally {
    await context.close();
  }
}

async function act(page, a) {
  if (a.click) return page.locator(a.click).first().click();
  if (a.hover) return page.locator(a.hover).first().hover();
  if (a.fill) return page.locator(a.fill[0]).first().fill(a.fill[1]);
  if (a.press) return page.keyboard.press(a.press);
  if (a.waitFor) return page.locator(a.waitFor).first().waitFor();
  if (a.wait) return page.waitForTimeout(a.wait);
  if (a.eval) return page.evaluate(a.eval);
  throw new Error(`unknown action ${JSON.stringify(a)}`);
}

// ---- diff (runs in the browser, so no image libraries are needed) ----

// The diff only compares PNGs, so it always runs on Chromium whatever engines were shot.
const diffPage = await (await getBrowser('chromium')).newPage();

async function diff(beforeFile, afterFile, diffFile) {
  const result = await diffPage.evaluate(
    async ({ a, b, threshold }) => {
      const load = async (b64) => {
        const img = new Image();
        img.src = `data:image/png;base64,${b64}`;
        await img.decode();
        return img;
      };
      const [ia, ib] = await Promise.all([load(a), load(b)]);
      const w = Math.max(ia.width, ib.width);
      const h = Math.max(ia.height, ib.height);
      const pixels = (img) => {
        const ctx = new OffscreenCanvas(w, h).getContext('2d');
        ctx.drawImage(img, 0, 0);
        return ctx.getImageData(0, 0, w, h).data;
      };
      const pa = pixels(ia);
      const pb = pixels(ib);
      const canvas = new OffscreenCanvas(w, h);
      const ctx = canvas.getContext('2d');
      const outImg = ctx.createImageData(w, h);
      const o = outImg.data;
      let changed = 0;
      for (let y = 0; y < h; y++) {
        for (let x = 0; x < w; x++) {
          const i = (y * w + x) * 4;
          const inA = x < ia.width && y < ia.height;
          const inB = x < ib.width && y < ib.height;
          const delta = Math.max(
            Math.abs(pa[i] - pb[i]),
            Math.abs(pa[i + 1] - pb[i + 1]),
            Math.abs(pa[i + 2] - pb[i + 2]),
            Math.abs(pa[i + 3] - pb[i + 3]),
          );
          if (inA !== inB || delta > threshold) {
            changed++;
            o.set([255, 0, 0, 255], i);
          } else {
            // Faded greyscale of the after image, so red changes stand out.
            const lum = 0.299 * pb[i] + 0.587 * pb[i + 1] + 0.114 * pb[i + 2];
            const v = Math.round(255 - (255 - lum) * 0.3);
            o.set([v, v, v, 255], i);
          }
        }
      }
      ctx.putImageData(outImg, 0, 0);
      const blob = await canvas.convertToBlob({ type: 'image/png' });
      const bytes = new Uint8Array(await blob.arrayBuffer());
      let bin = '';
      for (let i = 0; i < bytes.length; i += 0x8000) bin += String.fromCharCode(...bytes.subarray(i, i + 0x8000));
      return {
        png: btoa(bin),
        changedPixels: changed,
        totalPixels: w * h,
        sizeChanged: ia.width !== ib.width || ia.height !== ib.height,
      };
    },
    {
      a: fs.readFileSync(beforeFile, 'base64'),
      b: fs.readFileSync(afterFile, 'base64'),
      threshold: spec.threshold ?? 10,
    },
  );
  fs.writeFileSync(diffFile, Buffer.from(result.png, 'base64'));
  delete result.png;
  result.changedPercent = +((100 * result.changedPixels) / result.totalPixels).toFixed(3);
  return result;
}

// ---- run --------------------------------------------------------------

const manifest = { before: spec.before, after: spec.after, out, createdAt: new Date().toISOString(), shots: [] };
let failed = false;

for (const shot of spec.shots) {
  const themes = pick(shot.themes, matrixThemes, THEMES, 'theme');
  const engines = pick(shot.browsers, matrixBrowsers, BROWSERS, 'browser');
  const viewports = pick(shot.viewports, matrixViewports, VIEWPORTS, 'viewport');
  const entry = { name: shot.name, caption: shot.caption, path: shot.path, variants: [] };
  for (const engine of engines) {
    for (const theme of themes) {
      for (const viewport of viewports) {
        const label = [
          engines.length > 1 && engine.label,
          themes.length > 1 && title(theme.name),
          viewports.length > 1 && title(viewport.name),
        ]
          .filter(Boolean)
          .join(' · ');
        const stem = [
          slug(shot.name),
          engines.length > 1 && slug(engine.name),
          themes.length > 1 && slug(theme.name),
          viewports.length > 1 && slug(viewport.name),
        ]
          .filter(Boolean)
          .join('-');
        const files = { before: `${stem}-before.png`, after: `${stem}-after.png`, diff: `${stem}-diff.png` };
        const variant = { label, browser: engine.name, theme: theme.name, viewport: viewport.name, ...files };
        try {
          const browser = await getBrowser(engine.name);
          await shoot(browser, spec.before, shot, theme, viewport, path.join(out, files.before));
          await shoot(browser, spec.after, shot, theme, viewport, path.join(out, files.after));
          Object.assign(variant, await diff(...Object.values(files).map((f) => path.join(out, f))));
        } catch (err) {
          failed = true;
          variant.error = err.message.split('\n')[0];
        }
        entry.variants.push(variant);
        const status = variant.error ? `ERROR ${variant.error}` : `${variant.changedPercent}% changed`;
        console.error(`${shot.name}${label ? ` [${label}]` : ''}: ${status}`);
      }
    }
  }
  entry.changed = entry.variants.some((v) => v.changedPixels > 0);
  manifest.shots.push(entry);
}
for (const b of browsers.values()) await b.close();

// ---- markdown ---------------------------------------------------------

const img = (alt, file) => `![${alt}](./${file})`;
const cell = (s) => String(s).replace(/\|/g, '\\|');
const md = [];
const attach = [];

for (const shot of manifest.shots) {
  const rows = shot.variants.filter((v) => !v.error);
  if (!shot.changed || rows.length === 0) continue;
  const multi = rows.some((v) => v.label);
  md.push(`### ${shot.name}`, '');
  if (shot.caption) md.push(shot.caption, '');
  md.push(multi ? '| Variant | Before | After | Diff |' : '| Before | After | Diff |');
  md.push(multi ? '| --- | --- | --- | --- |' : '| --- | --- | --- |');
  for (const v of rows) {
    const diffCell = v.changedPixels > 0 ? img('Diff', v.diff) : '_No visual change_';
    const cells = [img('Before', v.before), img('After', v.after), diffCell];
    if (multi) cells.unshift(cell(v.label));
    md.push(`| ${cells.join(' | ')} |`);
    attach.push(v.before, v.after, ...(v.changedPixels > 0 ? [v.diff] : []));
  }
  md.push('');
}

fs.writeFileSync(path.join(out, 'screenshots.md'), md.join('\n'));
fs.writeFileSync(path.join(out, 'attach.txt'), attach.map((f) => f + '\n').join(''));
fs.writeFileSync(path.join(out, 'manifest.json'), JSON.stringify(manifest, null, 2) + '\n');

const unchanged = manifest.shots.filter((s) => !s.changed && s.variants.every((v) => !v.error));
if (unchanged.length) console.error(`No visual change (left out of screenshots.md): ${unchanged.map((s) => s.name).join(', ')}`);
console.error(`${attach.length} images referenced (gh --attach allows 50 per call)`);
console.log(out);
process.exit(failed ? 1 : 0);
