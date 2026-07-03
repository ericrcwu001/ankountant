// Best-effort fetcher for third-party CPA decks on AnkiWeb.
//
// AnkiWeb's shared-deck browser is a client-rendered SvelteKit app with no
// scriptable JSON API, and downloads are gated behind the JS "Download" button
// (a plain HTTP GET of /shared/download/<id> 404s). So we drive the real UI with
// a headless browser, politely (sequential, throttled, capped) — this is NOT a
// bulk scrape of the whole site. Whatever lands in the inbox is then ingested,
// quality-filtered, and de-duped by scripts/harvest_online.py.
//
// This step is intentionally *best-effort*: on a block/captcha/timeout it writes
// a ranked shortlist to inbox/shortlist.json and exits 0, so you can download
// those decks by hand into the inbox and the rest of the pipeline still runs.
//
// Usage:
//   cd tools/cardgen/scripts && npm install && npx playwright install chromium
//   node fetch_ankiweb.mjs --top 30 --terms "cpa,cpa reg,cpa far,cpa aud,cpa isc,cpa tcp"
//
// Flags: --top N (max decks) | --terms "a,b,c" | --out DIR | --headful | --max-per-term N

import { chromium } from "playwright";
import { mkdir, writeFile } from "node:fs/promises";
import { existsSync, readFileSync } from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const HERE = path.dirname(fileURLToPath(import.meta.url));
const DEFAULT_OUT = path.resolve(HERE, "..", "inbox");
const BASE = "https://ankiweb.net";
const UA =
  "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 " +
  "(KHTML, like Gecko) Chrome/124.0 Safari/537.36";

function parseArgs(argv) {
  const a = {
    top: 30,
    terms: ["cpa", "cpa reg", "cpa far", "cpa aud", "cpa isc", "cpa tcp", "cpa bec"],
    out: DEFAULT_OUT,
    headful: false,
    maxPerTerm: 40,
    ids: [], // when set, skip enumeration and download exactly these deck ids
  };
  for (let i = 2; i < argv.length; i++) {
    const arg = argv[i];
    if (arg === "--top") a.top = parseInt(argv[++i], 10) || a.top;
    else if (arg === "--terms") a.terms = String(argv[++i]).split(",").map((s) => s.trim()).filter(Boolean);
    else if (arg === "--out") a.out = path.resolve(argv[++i]);
    else if (arg === "--headful") a.headful = true;
    else if (arg === "--max-per-term") a.maxPerTerm = parseInt(argv[++i], 10) || a.maxPerTerm;
    else if (arg === "--ids") a.ids = String(argv[++i]).split(",").map((s) => s.trim()).filter(Boolean);
  }
  return a;
}

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

function looksBlocked(html) {
  const h = (html || "").toLowerCase();
  return (
    h.includes("just a moment") ||
    h.includes("verify you are human") ||
    h.includes("cf-challenge") ||
    h.includes("attention required")
  );
}

// Scrape the rendered result rows for one search term.
async function searchTerm(page, term, maxPerTerm) {
  const url = `${BASE}/shared/decks?search=${encodeURIComponent(term)}`;
  console.log(`[fetch] search "${term}" -> ${url}`);
  try {
    await page.goto(url, { waitUntil: "domcontentloaded", timeout: 45000 });
  } catch (e) {
    console.warn(`[fetch]   goto failed: ${e.message}`);
    return [];
  }
  if (looksBlocked(await page.content())) {
    throw new Error("blocked-by-challenge");
  }
  // The list is client-rendered; wait for deck info links, then let a couple of
  // scrolls pull in any lazily-mounted rows.
  try {
    await page.waitForSelector('a[href*="/shared/info/"]', { timeout: 25000 });
  } catch {
    console.warn(`[fetch]   no results rendered for "${term}"`);
    return [];
  }
  for (let s = 0; s < 3; s++) {
    await page.mouse.wheel(0, 4000);
    await sleep(600);
  }
  // Extract id + title from each info anchor, and best-effort rating/downloads
  // from the surrounding row text (tolerant of layout changes).
  const rows = await page.$$eval('a[href*="/shared/info/"]', (els) => {
    const seen = new Set();
    const out = [];
    for (const el of els) {
      const m = (el.getAttribute("href") || "").match(/\/shared\/info\/(\d+)/);
      if (!m) continue;
      const id = m[1];
      if (seen.has(id)) continue;
      seen.add(id);
      const title = (el.textContent || "").trim();
      if (!title) continue;
      const rowText = (el.closest("tr,li,div")?.textContent || "").replace(/\s+/g, " ").trim();
      const rating = (rowText.match(/(\d+)\s*(?:ratings?|votes?|thumbs)/i) || [])[1];
      const downloads = (rowText.match(/([\d,]+)\s*(?:downloads?)/i) || [])[1];
      out.push({
        id,
        title,
        rating: rating ? parseInt(rating, 10) : 0,
        downloads: downloads ? parseInt(downloads.replace(/,/g, ""), 10) : 0,
      });
    }
    return out;
  });
  console.log(`[fetch]   ${rows.length} decks for "${term}"`);
  return rows.slice(0, maxPerTerm);
}

// Drive the info page's Download button and capture the .apkg.
async function downloadDeck(page, deck, outDir) {
  const url = `${BASE}/shared/info/${deck.id}`;
  await page.goto(url, { waitUntil: "domcontentloaded", timeout: 45000 });
  if (looksBlocked(await page.content())) throw new Error("blocked-by-challenge");
  await page.waitForTimeout(800);
  const selectors = [
    'button:has-text("Download")',
    'a:has-text("Download")',
    'input[type="submit"][value*="Download" i]',
  ];
  let clicked = null;
  for (const sel of selectors) {
    const el = page.locator(sel).first();
    if (await el.count()) {
      clicked = el;
      break;
    }
  }
  if (!clicked) throw new Error("no-download-button");
  const dest = path.join(outDir, `${deck.id}.apkg`);
  const [download] = await Promise.all([
    page.waitForEvent("download", { timeout: 60000 }),
    clicked.click(),
  ]);
  await download.saveAs(dest);
  return dest;
}

async function main() {
  const args = parseArgs(process.argv);
  await mkdir(args.out, { recursive: true });
  console.log(`[fetch] out=${args.out} top=${args.top} terms=${JSON.stringify(args.terms)}`);

  let browser;
  try {
    browser = await chromium.launch({ headless: !args.headful });
  } catch (e) {
    console.error(
      `[fetch] could not launch Chromium (${e.message}).\n` +
        `[fetch] Install it once with:  cd tools/cardgen/scripts && npm install && npx playwright install chromium`
    );
    process.exit(0); // non-fatal: harvest_online.py still runs on whatever is in inbox/
  }

  const ctx = await browser.newContext({ userAgent: UA, acceptDownloads: true, viewport: { width: 1280, height: 900 } });
  const page = await ctx.newPage();

  // Targeted mode: download exactly the given ids (titles reused from a prior
  // shortlist.json when available), skipping enumeration entirely.
  if (args.ids.length) {
    let known = {};
    const slPath = path.join(args.out, "shortlist.json");
    if (existsSync(slPath)) {
      try {
        for (const d of JSON.parse(readFileSync(slPath, "utf8"))) known[d.id] = d;
      } catch {}
    }
    const ranked = args.ids.map((id) => known[id] || { id, title: id, rating: 0, downloads: 0 });
    const manifest = [];
    for (const deck of ranked) {
      const dest = path.join(args.out, `${deck.id}.apkg`);
      if (existsSync(dest)) {
        manifest.push({ ...deck, file: `${deck.id}.apkg`, status: "cached" });
        continue;
      }
      try {
        await downloadDeck(page, deck, args.out);
        console.log(`[fetch]   ok  ${deck.id}  ${String(deck.title).slice(0, 60)}`);
        manifest.push({ ...deck, file: `${deck.id}.apkg`, status: "downloaded" });
      } catch (e) {
        console.warn(`[fetch]   skip ${deck.id}: ${e.message}`);
        manifest.push({ ...deck, status: `failed:${e.message}` });
      }
      await sleep(2000);
    }
    // Merge into any existing manifest so repeated targeted runs accumulate.
    let prior = [];
    const mfPath = path.join(args.out, "manifest.json");
    if (existsSync(mfPath)) {
      try {
        prior = JSON.parse(readFileSync(mfPath, "utf8"));
      } catch {}
    }
    const merged = new Map(prior.map((m) => [m.id, m]));
    for (const m of manifest) merged.set(m.id, m);
    await writeFile(mfPath, JSON.stringify([...merged.values()], null, 2));
    const got = manifest.filter((m) => m.status === "downloaded" || m.status === "cached").length;
    console.log(`[fetch] targeted done: ${got}/${ranked.length} decks in ${args.out}`);
    await browser.close();
    return;
  }

  // 1) Enumerate + rank.
  const byId = new Map();
  let blocked = false;
  for (const term of args.terms) {
    try {
      for (const d of await searchTerm(page, term, args.maxPerTerm)) {
        const prev = byId.get(d.id);
        if (!prev || d.downloads > prev.downloads) byId.set(d.id, d);
      }
    } catch (e) {
      if (String(e.message).includes("blocked")) {
        blocked = true;
        console.warn(`[fetch] challenge encountered on "${term}" — stopping enumeration`);
        break;
      }
      console.warn(`[fetch] term "${term}" failed: ${e.message}`);
    }
    await sleep(1200);
  }

  const ranked = [...byId.values()]
    .filter((d) => /\bcpa\b|regulation|audit|far|reg\b|tcp|isc|bec|becker|wiley|roger|financial accounting|taxation/i.test(d.title))
    .sort((a, b) => b.downloads - a.downloads || b.rating - a.rating)
    .slice(0, args.top);

  await writeFile(path.join(args.out, "shortlist.json"), JSON.stringify(ranked, null, 2));
  console.log(`[fetch] ranked ${ranked.length} candidate decks -> inbox/shortlist.json`);

  // 2) Download politely (sequential, throttled). Skip any already present.
  const manifest = [];
  if (!blocked) {
    for (const deck of ranked) {
      const dest = path.join(args.out, `${deck.id}.apkg`);
      if (existsSync(dest)) {
        manifest.push({ ...deck, file: `${deck.id}.apkg`, status: "cached" });
        continue;
      }
      try {
        await downloadDeck(page, deck, args.out);
        console.log(`[fetch]   ok  ${deck.id}  ${deck.title.slice(0, 60)}`);
        manifest.push({ ...deck, file: `${deck.id}.apkg`, status: "downloaded" });
      } catch (e) {
        console.warn(`[fetch]   skip ${deck.id}: ${e.message}`);
        manifest.push({ ...deck, status: `failed:${e.message}` });
        if (String(e.message).includes("blocked")) break;
      }
      await sleep(2000);
    }
  }

  await writeFile(path.join(args.out, "manifest.json"), JSON.stringify(manifest, null, 2));
  const got = manifest.filter((m) => m.status === "downloaded" || m.status === "cached").length;
  console.log(`[fetch] done: ${got}/${ranked.length} decks in ${args.out}`);
  if (got === 0) {
    console.log(
      `[fetch] Nothing downloaded (site likely gated automated access). ` +
        `Open the URLs in inbox/shortlist.json, click Download, and drop the .apkg files into ${args.out}. ` +
        `Then run harvest_online.py.`
    );
  }
  await browser.close();
}

main().catch((e) => {
  console.error(`[fetch] fatal: ${e.stack || e.message}`);
  process.exit(0); // never block the pipeline on acquisition
});
