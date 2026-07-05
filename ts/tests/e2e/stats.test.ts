// Copyright: Ankitects Pty Ltd and contributors
// License: GNU AGPL, version 3 or later; http://www.gnu.org/licenses/agpl.html

import { expect, test } from "./fixtures";

function numericText(text: string | null): number {
    return Number((text ?? "").replace(/[^\d]/g, ""));
}

test("stats: empty analytics view points to import and collection", async ({ page, seedWithHistory }) => {
    expect(seedWithHistory.sealedItems).toBeGreaterThan(0);
    await page.goto("/ankountant-stats");
    await expect(page.getByLabel("Statistics overview")).toBeVisible();

    const search = page.getByLabel("Search");
    await search.fill("tag:__ankountant_empty_stats__");
    await search.dispatchEvent("change");

    const empty = page.getByTestId("stats-empty");
    await expect(empty).toBeVisible();
    await expect(empty).toContainText("No analytics evidence in this view");
    await expect(empty).toContainText("Show the whole collection");
    await expect(empty.getByRole("button", { name: "Show collection" })).toBeVisible();
    await expect(empty.getByRole("button", { name: "Import package" })).toBeVisible();
    await expect(page.getByLabel("Statistics overview")).toHaveCount(0);

    await empty.getByRole("button", { name: "Show collection" }).click();
    await expect(page.getByLabel("Statistics overview")).toBeVisible();
    await expect(page.getByTestId("stats-empty")).toHaveCount(0);
});

test("stats: review summary uses available history", async ({ page, seedWithHistory }) => {
    expect(seedWithHistory.sealedItems).toBeGreaterThan(0);
    await page.goto("/ankountant-stats");

    const summary = page.getByTestId("stats-review-summary");
    await expect(summary).toBeVisible();
    await expect.poll(async () => numericText(await summary.getByTestId("stats-reviewed").textContent()))
        .toBeGreaterThan(0);
    await expect(summary.getByTestId("stats-time")).not.toHaveText("0m");
    await expect(summary.getByTestId("stats-accuracy")).not.toHaveText("--");
    await expect.poll(async () => {
        const values = await Promise.all([
            summary.getByTestId("stats-new-count").textContent(),
            summary.getByTestId("stats-learning-count").textContent(),
            summary.getByTestId("stats-review-count").textContent(),
        ]);
        return values.some((value) => numericText(value) > 0);
    }).toBe(true);
});

test("stats: analytics page scrolls in the Ankountant shell body", async ({ page, seedWithHistory }) => {
    expect(seedWithHistory.sealedItems).toBeGreaterThan(0);
    await page.setViewportSize({ width: 1100, height: 560 });
    await page.goto("/ankountant-stats");
    await expect(page.getByTestId("stats")).toBeVisible();
    const shellBody = page.locator(".ank-shell-body");
    await expect
        .poll(() => shellBody.evaluate((el) => el.scrollHeight > el.clientHeight))
        .toBe(true);

    await shellBody.hover();
    await page.mouse.wheel(0, 700);
    await expect
        .poll(() => shellBody.evaluate((el) => el.scrollTop))
        .toBeGreaterThan(0);
});

test("stats: graph load failure shows an inline error state", async ({ page, seedWithHistory }) => {
    expect(seedWithHistory.sealedItems).toBeGreaterThan(0);
    let graphRequests = 0;
    await page.route("**/_anki/graphs", async (route) => {
        graphRequests += 1;
        if (graphRequests === 1) {
            await route.fulfill({
                status: 500,
                contentType: "text/html",
                body: "<html><head><title>500 Internal Server Error</title></head><body>traceback</body></html>",
            });
        } else {
            await route.continue();
        }
    });

    await page.goto("/ankountant-stats");

    const error = page.getByTestId("stats-load-error");
    await expect(error).toBeVisible();
    await expect(error).toContainText("We couldn't load this evidence.");
    await expect(error).toContainText("500 Internal Server Error. Statistics could not be loaded.");
    await expect(page.getByTestId("stats-loading")).toHaveCount(0);

    await page.getByRole("button", { name: "Retry" }).click();
    await expect.poll(() => graphRequests).toBeGreaterThan(1);
    await expect(page.getByLabel("Statistics overview")).toBeVisible();
    await expect(page.getByTestId("stats-load-error")).toHaveCount(0);
});

test("stats: preference load failure can retry without leaking backend html", async ({ page, seedWithHistory }) => {
    expect(seedWithHistory.sealedItems).toBeGreaterThan(0);
    let preferenceRequests = 0;
    await page.route("**/_anki/getGraphPreferences", async (route) => {
        preferenceRequests += 1;
        if (preferenceRequests === 1) {
            await route.fulfill({
                status: 503,
                contentType: "text/html",
                body: "<!doctype html><title>503 Preferences unavailable</title><h1>traceback</h1>",
            });
        } else {
            await route.continue();
        }
    });

    await page.goto("/ankountant-stats");

    const error = page.getByTestId("stats-load-error");
    await expect(error).toBeVisible();
    await expect(error).toContainText(
        "503 Preferences unavailable. Statistics preferences could not be loaded.",
    );
    await expect(error).not.toContainText("<!doctype html>");

    await error.getByRole("button", { name: "Retry" }).click();
    await expect.poll(() => preferenceRequests).toBeGreaterThan(1);
    await expect(page.getByLabel("Statistics overview")).toBeVisible();
    await expect(page.getByTestId("stats-load-error")).toHaveCount(0);
});
