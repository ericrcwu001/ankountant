// Copyright: Ankitects Pty Ltd and contributors
// License: GNU AGPL, version 3 or later; http://www.gnu.org/licenses/agpl.html

// ! Workstream B — research surface e2e (T1/T2). Mirrors tbs.test.ts /
// ! confusion.test.ts. The fixture loads the FAR seed; the research route
// ! defaults to the first FAR research item (ASC 842-20-25-1). Not part of the
// ! gated set (no browser in `just test-ts` / `just check`).

import { expect, test } from "./fixtures";

test("research: literature search + a correct citation + time-to-cite (T1/T2)", async ({ page, seed }) => {
    expect(seed.sealedItems).toBeGreaterThan(0);
    await page.goto("/ankountant-research");
    await expect(page.getByTestId("exam-shell")).toHaveAttribute("data-shape", "research");

    // The Literature tab is the default tool for research; search is client-side.
    await page.getByTestId("lit-search").fill("lease commencement");
    await expect(page.getByTestId("lit-result").first()).toBeVisible();

    // Commit confidence, then submit the governing citation.
    await page.getByTestId("confidence-confident").click();
    await page.getByTestId("citation-input").fill("ASC 842-20-25-1");
    await page.getByTestId("research-submit").click();

    await expect(page.getByTestId("research-verdict")).toHaveClass(/correct/);
    await expect(page.getByTestId("research-time")).toBeVisible();
    // The answer key + basis are revealed only after submit.
    await expect(page.getByTestId("results-layer")).toBeVisible();
    await expect(page.getByTestId("citation-input")).toBeDisabled();
    await expect(page.getByTestId("lit-cite").first()).toBeDisabled();
});

test("research: a wrong citation is marked incorrect (T1)", async ({ page }) => {
    await page.goto("/ankountant-research");
    await page.getByTestId("confidence-unsure").click();
    await page.getByTestId("citation-input").fill("ASC 999-10-10-1");
    await page.getByTestId("research-submit").click();
    await expect(page.getByTestId("research-verdict")).toHaveClass(/incorrect/);
});

test("research: a normalized spelling still grades correct (T1 AC1)", async ({ page }) => {
    await page.goto("/ankountant-research");
    await page.getByTestId("confidence-confident").click();
    // No prefix + spaces instead of hyphens — the backend normalizes it.
    await page.getByTestId("citation-input").fill("842 20 25 1");
    await page.getByTestId("research-submit").click();
    await expect(page.getByTestId("research-verdict")).toHaveClass(/correct/);
});

test("research: submit requires a governing citation", async ({ page }) => {
    await page.goto("/ankountant-research");
    await page.getByTestId("confidence-confident").click();
    await expect(page.getByTestId("research-submit")).toBeDisabled();
    await expect(page.getByTestId("research-citation-hint")).toContainText(
        "Enter a governing citation",
    );
    await page.getByTestId("citation-input").fill("ASC 842-20-25-1");
    await expect(page.getByTestId("research-submit")).toBeEnabled();
});

test("research: submit failures stay in the surface", async ({ page }) => {
    await page.route("**/_anki/submitPerformanceAttempt", async (route) => {
        await route.fulfill({
            status: 500,
            contentType: "text/plain",
            body: "forced submit failure",
        });
    });
    await page.goto("/ankountant-research");
    await page.getByTestId("confidence-confident").click();
    await page.getByTestId("citation-input").fill("ASC 842-20-25-1");
    await page.getByTestId("research-submit").click();
    await expect(page.getByTestId("research-submit-error")).toContainText(
        "500: forced submit failure",
    );
    await expect(page.getByTestId("research-submit")).toBeEnabled();
});

test("research: exposes NO Again/Hard/Good/Easy buttons (parity with tbs.test.ts)", async ({ page }) => {
    await page.goto("/ankountant-research");
    await expect(page.getByTestId("exam-shell")).toBeVisible();
    for (const label of ["Again", "Hard", "Good", "Easy"]) {
        await expect(page.getByRole("button", { name: label, exact: true })).toHaveCount(0);
    }
});

test("research: literature citations scroll inside the tool panel", async ({ page }) => {
    await page.setViewportSize({ width: 900, height: 420 });
    await page.goto("/ankountant-research");
    const results = page.getByTestId("lit-results");
    await expect(results).toBeVisible();
    await expect
        .poll(() => results.evaluate((el) => el.scrollHeight > el.clientHeight))
        .toBe(true);

    await results.hover();
    await page.mouse.wheel(0, 500);
    await expect
        .poll(() => results.evaluate((el) => el.scrollTop))
        .toBeGreaterThan(0);
});

test("research: scratchpad formulas commit on Enter", async ({ page }) => {
    await page.goto("/ankountant-research");
    await page.getByTestId("tool-tab-scratch").click();

    await page.locator("input[data-cell=\"A1\"]").fill("10");
    await page.locator("input[data-cell=\"A2\"]").fill("15");

    const formulaCell = page.locator("input[data-cell=\"A3\"]");
    await formulaCell.fill("=SUM(A1:A2)");
    await formulaCell.press("Enter");
    await expect(formulaCell).toHaveValue("25");

    await formulaCell.focus();
    await expect(formulaCell).toHaveValue("=SUM(A1:A2)");
});
