// Copyright: Ankitects Pty Ltd and contributors
// License: GNU AGPL, version 3 or later; http://www.gnu.org/licenses/agpl.html

// ! B5 (F015) desktop dashboard specs — contract A54–A57. The FAR seed is
// ! loaded via the `seed` fixture; a subset of sealed attempts is submitted to
// ! move the readiness across / under the abstain thresholds.

import { expect, test } from "./fixtures";

test("thin data shows the abstain message + reason and NO number (A55)", async ({ page, seed }) => {
    expect(seed.confusionSets).toBeGreaterThanOrEqual(4);
    // No attempts submitted yet -> A5 abstains on insufficient volume.
    await page.goto("/ankountant-dashboard");
    const abstain = page.getByTestId("abstain");
    await expect(abstain).toBeVisible();
    await expect(abstain).toContainText("insufficient");
    // No readiness band / number rendered.
    await expect(page.getByTestId("readiness-band")).toHaveCount(0);

    const row = page.getByTestId("topic-row").first();
    await expect(row.getByTestId("performance")).toContainText("insufficient");
    await expect(row.getByTestId("performance")).not.toContainText("0%");
    await expect(row.getByTestId("gap")).toContainText("insufficient");
    await expect(row).not.toHaveClass(/gap-warning/);
});

test("empty readiness topics show an explicit dashboard table state", async ({ page }) => {
    await page.route("**/_anki/getReadiness", async (route) => {
        await route.fulfill({
            status: 200,
            contentType: "application/binary",
            body: Buffer.alloc(0),
        });
    });

    await page.goto("/ankountant-dashboard");

    await expect(page.getByTestId("topic-empty")).toContainText(
        "No topics defined for this section yet.",
    );
    await expect(page.getByTestId("topic-row")).toHaveCount(0);
});

test("sufficient data shows a readiness point, range, confidence, and topic scores (A54)", async ({ page, seedWithHistory }) => {
    expect(seedWithHistory.sealedItems).toBeGreaterThanOrEqual(24);
    await page.goto("/ankountant-dashboard");

    await expect(page.getByTestId("abstain")).toHaveCount(0);
    await expect(page.getByTestId("readiness-band")).toBeVisible();
    await expect(page.getByTestId("readiness-band")).toContainText("Projected");
    await expect(page.getByTestId("readiness-point")).toContainText(/^\d+$/);
    await expect(page.getByTestId("readiness-range")).toContainText(/Range \d+–\d+/);
    await expect(page.getByTestId("confidence")).toContainText(/confidence/i);

    const row = page.getByTestId("topic-row").first();
    await expect(row.getByTestId("memory")).toContainText(/%/);
    await expect(row.getByTestId("performance")).toContainText(/%/);
    await expect(row.getByTestId("gap")).toContainText(/%/);
});

test("readiness is labelled the exam-day projection tied to the set exam date (A57)", async ({ page, seedWithHistory }) => {
    expect(seedWithHistory.studyRecallCards).toBeGreaterThan(0);
    await page.goto("/ankountant-dashboard");
    const heading = page.locator(".readiness h2");
    await expect(heading).toContainText(/Exam-day projection \(\d{4}-\d{2}-\d{2}\)/);
    await expect(heading).not.toContainText("today");
});

test("section switcher reloads the dashboard for the selected CPA section", async ({ page, seed }) => {
    expect(seed.confusionSets).toBeGreaterThanOrEqual(4);
    await page.goto("/ankountant-dashboard");

    await expect(page.getByRole("button", { name: "FAR" })).toHaveAttribute(
        "aria-pressed",
        "true",
    );
    await page.getByRole("button", { name: "AUD" }).click();

    await expect(page).toHaveURL(/section=AUD/);
    await expect(page.locator(".page-head .eyebrow")).toHaveText(
        "Auditing and Attestation",
    );
    await expect(page.getByRole("button", { name: "AUD" })).toHaveAttribute(
        "aria-pressed",
        "true",
    );
});

test("gap >= 0.25 renders the gap row with the gap-warning class (A56)", async ({ page, seedWithHistory }) => {
    expect(seedWithHistory.confusionSets).toBeGreaterThanOrEqual(4);
    await page.goto("/ankountant-dashboard");
    const taxTiming = page.locator("[data-testid=\"topic-row\"][data-set-id=\"tax_timing\"]");
    await expect(taxTiming).toBeVisible();
    await expect(taxTiming).toHaveClass(/gap-warning/);
    await expect(taxTiming.getByTestId("memory")).toContainText("72%");
    await expect(taxTiming.getByTestId("performance")).toContainText("26%");
    await expect(taxTiming.getByTestId("gap")).toContainText("46%");
});
