// Copyright: Ankitects Pty Ltd and contributors
// License: GNU AGPL, version 3 or later; http://www.gnu.org/licenses/agpl.html

import { expect, test } from "./fixtures";

test("sync page exposes the sync action without internal proof content", async ({ page }) => {
    await page.goto("/ankountant-sync");

    await expect(page.getByTestId("sync")).toBeVisible();
    await expect(page.getByRole("button", { name: "Sync now" })).toBeVisible();
    await expect(page.getByTestId("sync-conflict-rule")).toHaveCount(0);
    await expect(page.getByTestId("sync-proof")).toHaveCount(0);
    await expect(page.getByText("Proof Run")).toHaveCount(0);
    await expect(page.getByText("Speedrun 7b")).toHaveCount(0);
});
