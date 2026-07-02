// Copyright: Ankitects Pty Ltd and contributors
// License: GNU AGPL, version 3 or later; http://www.gnu.org/licenses/agpl.html

// ! Desktop Home hub e2e — the days-until-exam countdown and the exam-date
// ! entry that drives the live deadline-anchored scheduler (A1-live). Also
// ! exercises the generic SetConfigJson POST (must be exposed in mediasrv, else
// ! the write 404s). Uses the same throwaway-collection harness as the
// ! dashboard specs.

import { expect, test } from "./fixtures";

test("home shows the countdown placeholder until an exam date is set", async ({ page, seed }) => {
    expect(seed.roteCards).toBeGreaterThan(0);
    await page.goto("/ankountant-home");
    await expect(page.getByTestId("countdown")).toBeVisible();
    await expect(page.getByTestId("countdown-days")).toHaveText("—");
    await expect(page.getByTestId("countdown")).toContainText("Set your exam date");
});

test("entering an exam date drives the countdown and persists across reloads", async ({ page }) => {
    await page.goto("/ankountant-home");

    const future = new Date();
    future.setDate(future.getDate() + 30);
    const iso = `${future.getFullYear()}-${String(future.getMonth() + 1).padStart(2, "0")}-${
        String(future.getDate()).padStart(2, "0")
    }`;

    await page.getByTestId("exam-date-input").fill(iso);
    // The write goes through SetConfigJson; a 404 here means it was never
    // exposed in mediasrv's allow-list.
    await expect(page.getByTestId("save-state")).toContainText("Saved");
    // ~30 days out (allow an off-by-one across a midnight boundary).
    await expect(page.getByTestId("countdown-days")).toHaveText(/^(29|30)$/);
    await expect(page.getByTestId("countdown")).toContainText("until exam");

    // Persisted in col config -> a reload reads the same date back.
    await page.reload();
    await expect(page.getByTestId("exam-date-input")).toHaveValue(iso);
    await expect(page.getByTestId("countdown-days")).toHaveText(/^(29|30)$/);
});
