// Copyright: Ankitects Pty Ltd and contributors
// License: GNU AGPL, version 3 or later; http://www.gnu.org/licenses/agpl.html

// ! B1/B2/B3 (F011/F012/F013) desktop confusion-set mode specs — contract
// ! A41–A49. Exercises the pre-reveal confidence gate, the label-stripped
// ! which-treatment gate, and the interleaved session flow.

import { expect, test } from "./fixtures";

test("the treatment picker is blocked until a confidence is committed (A41/B1-D1)", async ({ page, seed }) => {
    expect(seed.confusionSets).toBeGreaterThanOrEqual(4);
    await page.goto("/ankountant-confusion");
    await expect(page.getByTestId("confusion-item")).toBeVisible();
    // Before committing confidence, the treatments are not shown.
    await expect(page.getByTestId("treatments")).toHaveCount(0);
    // The three levels render (A43).
    await expect(page.getByTestId("confidence-guess")).toBeVisible();
    await expect(page.getByTestId("confidence-unsure")).toBeVisible();
    await expect(page.getByTestId("confidence-confident")).toBeVisible();
});

test("the three confidence levels are keyboard-selectable (A43/B1-D3)", async ({ page }) => {
    await page.goto("/ankountant-confusion");
    await expect(page.getByTestId("confidence-gate")).toBeVisible();
    // Press "3" -> Confident.
    await page.keyboard.press("3");
    await expect(page.getByTestId("confidence-gate")).toHaveAttribute("data-committed", "Confident");
    // Only after commit do the treatments appear.
    await expect(page.getByTestId("treatments")).toBeVisible();
});

test("items are label-stripped: no category-label element (A44/B2-D1)", async ({ page }) => {
    await page.goto("/ankountant-confusion");
    await expect(page.getByTestId("confusion-item")).toBeVisible();
    await expect(page.locator("[data-testid=\"category-label\"]")).toHaveCount(0);
});

test("BAR deep link loads a section-specific confusion queue", async ({ page, seed }) => {
    expect(seed.confusionSets).toBeGreaterThanOrEqual(4);
    await page.goto("/ankountant-confusion?section=BAR");
    await expect(page.getByTestId("confusion-item")).toBeVisible();
});

test("selecting a treatment scores it and shows a verdict (A45/B2-D2)", async ({ page }) => {
    await page.goto("/ankountant-confusion");
    await page.getByTestId("confidence-confident").click();
    await page.getByTestId("treatment").first().click();
    await expect(page.getByTestId("verdict")).toBeVisible();
});

test("submit failures stay in the confusion surface", async ({ page }) => {
    await page.route("**/_anki/submitPerformanceAttempt", async (route) => {
        await route.fulfill({
            status: 500,
            contentType: "text/plain",
            body: "forced submit failure",
        });
    });
    await page.goto("/ankountant-confusion");
    await page.getByTestId("confidence-confident").click();
    await page.getByTestId("treatment").first().click();
    await expect(page.getByTestId("confusion-submit-error")).toContainText(
        "500: forced submit failure",
    );
    await expect(page.getByTestId("treatment").first()).toBeEnabled();
});

test("consecutive items are not all the same treatment set (A47/B3-D1)", async ({ page, seed }) => {
    expect(seed.confusionSets).toBeGreaterThanOrEqual(4);
    await page.goto("/ankountant-confusion");
    // Walk a few items and record their set ids from the interleaved queue.
    const setIds: string[] = [];
    for (let n = 0; n < 5; n++) {
        const item = page.getByTestId("confusion-item");
        if (await item.count() === 0) {
            break;
        }
        setIds.push((await item.getAttribute("data-set-id")) ?? "");
        await page.getByTestId("confidence-unsure").click();
        await page.getByTestId("treatment").first().click();
        await expect(page.getByTestId("verdict")).toBeVisible();
        await page.getByTestId("next-item").click();
    }
    // No 3 identical set ids in a row.
    for (let k = 2; k < setIds.length; k++) {
        expect(setIds[k] === setIds[k - 1] && setIds[k] === setIds[k - 2]).toBe(false);
    }
});
