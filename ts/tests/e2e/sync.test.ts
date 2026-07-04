// Copyright: Ankitects Pty Ltd and contributors
// License: GNU AGPL, version 3 or later; http://www.gnu.org/licenses/agpl.html

import { expect, test } from "./fixtures";

test("sync page exposes the merge rule and Speedrun proof cases", async ({ page }) => {
    await page.goto("/ankountant-sync");

    await expect(page.getByTestId("sync")).toBeVisible();
    await expect(page.getByRole("button", { name: "Sync now" })).toBeVisible();

    const conflictRule = page.getByTestId("sync-conflict-rule");
    await expect(conflictRule).toContainText("Review logs merge additively");
    await expect(conflictRule).toContainText("destructive full-sync choices are explicit");

    const proof = page.getByTestId("sync-proof");
    await expect(proof).toContainText("Offline split");
    await expect(proof).toContainText("Same-card conflict");
    await expect(proof).toContainText("Mid-sync failure");
    await expect(proof).toContainText("All 20 revlog entries after sync");
    await expect(proof).toContainText("Both revlogs preserved");
});
