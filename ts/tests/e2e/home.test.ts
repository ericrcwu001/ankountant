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

test("home readiness rail explains the score and links to full evidence", async ({ page, seed }) => {
    expect(seed.confusionSets).toBeGreaterThan(0);
    await page.goto("/ankountant-home");

    const brief = page.getByTestId("readiness-brief");
    await expect(brief).toBeVisible();
    await expect(brief).toContainText("Next");
    await expect(brief).toContainText("Missing");
    await expect(brief).not.toContainText("memory is 0%");

    await page.getByRole("button", { name: "See readiness evidence" }).click();
    await expect(page).toHaveURL(/ankountant-dashboard/);
    await expect(page.getByTestId("readiness-evidence")).toBeVisible();
});

test("home readiness rail shows the projected point with a likely range", async ({ page, seedWithHistory }) => {
    expect(seedWithHistory.sealedItems).toBeGreaterThanOrEqual(24);
    await page.goto("/ankountant-home");

    const readiness = page.getByTestId("readiness");
    await expect(readiness).toBeVisible();
    await expect(readiness).toContainText("projected");
    await expect(readiness).toContainText(/Range \d+–\d+/);
});

test("home section switcher reloads topic mastery and keeps evidence scoped", async ({ page, seed }) => {
    expect(seed.confusionSets).toBeGreaterThan(0);
    await page.goto("/ankountant-home");

    const aud = page.getByTestId("home-section").filter({ hasText: "AUD" });
    await aud.click();

    await expect(page).toHaveURL(/ankountant-home\?section=AUD/);
    await expect(page.getByText("AUD TOPIC MASTERY")).toBeVisible();
    await expect(aud).toHaveAttribute("aria-pressed", "true");

    await page.getByRole("button", { name: "See readiness evidence" }).click();
    await expect(page).toHaveURL(/ankountant-dashboard\?section=AUD/);
    await expect(page.getByText("Auditing and Attestation")).toBeVisible();
});

test("home load failure can retry without leaking backend html", async ({ page }) => {
    let readinessRequests = 0;
    await page.route("**/_anki/getReadiness", async (route) => {
        readinessRequests += 1;
        if (readinessRequests === 1) {
            await route.fulfill({
                status: 500,
                contentType: "text/html",
                body: "<!doctype html><title>500 Readiness failed</title><h1>Readiness failed</h1>",
            });
        } else {
            await route.continue();
        }
    });

    await page.goto("/ankountant-home");

    const error = page.getByTestId("home-load-error");
    await expect(error).toContainText(
        "500 Readiness failed. The study home could not be loaded.",
    );
    await expect(error).not.toContainText("<!doctype html>");
    await error.getByRole("button", { name: "Retry" }).click();

    await expect(page.getByTestId("home")).toBeVisible();
    await expect.poll(() => readinessRequests).toBeGreaterThan(1);
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
