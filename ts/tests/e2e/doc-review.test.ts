// Copyright: Ankitects Pty Ltd and contributors
// License: GNU AGPL, version 3 or later; http://www.gnu.org/licenses/agpl.html

// ! Workstream B — document-review surface e2e (T3). Mirrors tbs.test.ts /
// ! confusion.test.ts. The research route defaults to the first FAR doc-review
// ! item (the ASC 606 revenue-recognition footnote, 5 blanks). Not gated.

import { expect, test } from "./fixtures";

test("doc-review: document with blanks + co-visible exhibits + partial credit (T3)", async ({ page, seed }) => {
    expect(seed.sealedItems).toBeGreaterThan(0);
    await page.goto("/ankountant-doc-review");
    await expect(page.getByTestId("exam-shell")).toHaveAttribute("data-shape", "doc_review");

    const doc = page.getByTestId("dr-document");
    await expect(doc).toBeVisible();
    const blanks = page.getByTestId("dr-blank-select");
    await expect(blanks.first()).toBeVisible();
    const n = await blanks.count();
    expect(n).toBeGreaterThanOrEqual(3);

    // Exhibits are the default tool and co-visible with the document (C13).
    await expect(page.getByTestId("exhibits")).toBeVisible();

    // Label-stripped: there is no category/topic label element (T3 AC2).
    await expect(page.getByTestId("category-label")).toHaveCount(0);

    // Fill every blank (the exam forces a choice on each) with its first real
    // option, commit confidence, and submit — expect a partial-credit total.
    for (let i = 0; i < n; i++) {
        await blanks.nth(i).selectOption({ index: 1 });
    }
    await page.getByTestId("confidence-unsure").click();
    await page.getByTestId("docreview-submit").click();

    await expect(page.getByTestId("docreview-total")).toBeVisible();
    // Per-blank ✓/✗ marks + a post-submit reveal.
    await expect(page.getByTestId("results-layer")).toBeVisible();
    await expect(blanks.first()).toBeDisabled();
});

test("doc-review: each blank offers its confusion-set candidates (T3 AC2)", async ({ page }) => {
    await page.goto("/ankountant-doc-review");
    const first = page.getByTestId("dr-blank-select").first();
    await expect(first).toBeVisible();
    // A placeholder plus >= 2 candidate options.
    const optionCount = await first.locator("option").count();
    expect(optionCount).toBeGreaterThanOrEqual(3);
});

test("doc-review: submit requires an edit for every blank", async ({ page }) => {
    await page.goto("/ankountant-doc-review");
    const blanks = page.getByTestId("dr-blank-select");
    await expect(blanks.first()).toBeVisible();
    const n = await blanks.count();
    expect(n).toBeGreaterThanOrEqual(3);

    await page.getByTestId("confidence-unsure").click();
    await expect(page.getByTestId("docreview-submit")).toBeDisabled();
    await expect(page.getByTestId("docreview-answer-hint")).toContainText(
        "Select an edit for every blank",
    );

    for (let i = 0; i < n; i++) {
        await blanks.nth(i).selectOption({ index: 1 });
    }
    await expect(page.getByTestId("docreview-submit")).toBeEnabled();
});

test("doc-review: submit failures stay in the surface", async ({ page }) => {
    await page.route("**/_anki/submitPerformanceAttempt", async (route) => {
        await route.fulfill({
            status: 500,
            contentType: "text/plain",
            body: "forced submit failure",
        });
    });
    await page.goto("/ankountant-doc-review");
    const blanks = page.getByTestId("dr-blank-select");
    await expect(blanks.first()).toBeVisible();
    const n = await blanks.count();
    for (let i = 0; i < n; i++) {
        await blanks.nth(i).selectOption({ index: 1 });
    }
    await page.getByTestId("confidence-unsure").click();
    await page.getByTestId("docreview-submit").click();
    await expect(page.getByTestId("docreview-submit-error")).toContainText(
        "500: forced submit failure",
    );
    await expect(page.getByTestId("docreview-submit")).toBeEnabled();
});
