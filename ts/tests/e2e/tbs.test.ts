// Copyright: Ankitects Pty Ltd and contributors
// License: GNU AGPL, version 3 or later; http://www.gnu.org/licenses/agpl.html

// ! B4 (F014) desktop TBS surface specs — contract A50–A53. Deep-links the
// ! surface at the sealed TBS notes produced by the FAR seed.

import { expect, test } from "./fixtures";

test("a JE TBS renders an editable grid and shows per-line + partial-credit total (A50/B4-D1)", async ({ page, seed }) => {
    expect(seed.sealedJeTbs).toBeGreaterThanOrEqual(3);
    // The first sealed TBS note is a journal-entry (seed set 0).
    const jeNoteId = seed.sealedTbsNoteIds[0];
    await page.goto(`/ankountant-tbs?note=${jeNoteId}`);
    await expect(page.getByTestId("tbs-surface")).toHaveAttribute("data-shape", "journal_entry");
    const grid = page.getByTestId("je-grid");
    await expect(grid).toBeVisible();
    const rows = page.getByTestId("je-row");
    await expect(rows).toHaveCount(4);
    await expect(page.getByTestId("tbs-submit")).toBeDisabled();
    await page.getByTestId("confidence-unsure").click();
    await expect(page.getByTestId("tbs-submit")).toBeEnabled();

    // Fill three lines correctly (matching the seed's JE answer key) and one
    // wrong amount -> expect [ok,ok,ok,wrong] and 75% (reconciles with A35).
    const fill = async (idx: number, account: string, side: string, amount: string) => {
        const row = rows.nth(idx);
        // Account is now a controlled picker (agent 07), not a free-text input.
        await row.getByTestId("je-account").selectOption(account);
        await row.getByTestId("je-side").selectOption(side);
        await row.getByTestId("je-amount").fill(amount);
    };
    await fill(0, "ROU Asset", "dr", "10000");
    await fill(1, "Lease Liability", "cr", "10000");
    await fill(2, "Interest Expense", "dr", "500");
    await fill(3, "Cash", "cr", "99999"); // wrong amount only on line 4

    await page.getByTestId("tbs-submit").click();
    await expect(page.getByTestId("tbs-total")).toContainText("75%");
});

test("a numeric TBS renders input cells graded per cell (A51/B4-D2)", async ({ page, seed }) => {
    expect(seed.sealedNumericTbs).toBeGreaterThanOrEqual(2);
    // A later id in the seed is a numeric TBS; find one by shape.
    let numericId: bigint | null = null;
    for (const id of seed.sealedTbsNoteIds) {
        await page.goto(`/ankountant-tbs?note=${id}`);
        const shape = await page.getByTestId("tbs-surface").getAttribute("data-shape");
        if (shape === "numeric") {
            numericId = id;
            break;
        }
    }
    expect(numericId).not.toBeNull();
    await expect(page.getByTestId("numeric-grid")).toBeVisible();
    await page.getByTestId("confidence-confident").click();
    const cells = page.getByTestId("cell-input");
    await expect(cells.first()).toBeVisible();
    await cells.nth(0).fill("250000");
    await cells.nth(1).fill("12500");
    await page.getByTestId("tbs-submit").click();
    await expect(page.getByTestId("tbs-total")).toContainText("100%");
});

test("a TBS submit failure stays in the surface", async ({ page, seed }) => {
    await page.route("**/_anki/submitPerformanceAttempt", async (route) => {
        await route.fulfill({
            status: 500,
            contentType: "text/plain",
            body: "forced submit failure",
        });
    });
    await page.goto(`/ankountant-tbs?note=${seed.sealedTbsNoteIds[0]}`);
    await page.getByTestId("confidence-guess").click();
    await page.getByTestId("tbs-submit").click();
    await expect(page.getByTestId("tbs-submit-error")).toContainText(
        "500: forced submit failure",
    );
    await expect(page.getByTestId("tbs-submit")).toBeEnabled();
});

test("the TBS surface exposes NO Again/Hard/Good/Easy buttons (A52/B4-D3)", async ({ page, seed }) => {
    await page.goto(`/ankountant-tbs?note=${seed.sealedTbsNoteIds[0]}`);
    await expect(page.getByTestId("tbs-surface")).toBeVisible();
    for (const label of ["Again", "Hard", "Good", "Easy"]) {
        await expect(page.getByRole("button", { name: label, exact: true })).toHaveCount(0);
    }
});

test("exhibits are visible alongside the task (A53/B4-D4)", async ({ page, seed }) => {
    // The JE seed note carries a "Lease schedule" exhibit.
    await page.goto(`/ankountant-tbs?note=${seed.sealedTbsNoteIds[0]}`);
    await expect(page.getByTestId("exhibits")).toBeVisible();
    await expect(page.getByTestId("exhibit").first()).toBeVisible();
});
