// Copyright: Ankitects Pty Ltd and contributors
// License: GNU AGPL, version 3 or later; http://www.gnu.org/licenses/agpl.html

import { expect, test } from "./fixtures";

test("settings page is a first-class Ankountant route", async ({ page }) => {
    await page.goto("/ankountant-settings");

    await expect(page.getByTestId("settings")).toBeVisible();
    await expect(
        page.getByRole("heading", { level: 1, name: "Settings" }),
    ).toBeVisible();
    await expect(
        page.locator(".nav-item.active", { hasText: "Settings" }),
    ).toBeVisible();
    await expect(page.getByTestId("settings-card-study")).toContainText(
        "Study Schedule",
    );

    await page.getByTestId("settings-card-study").click();
    await expect(page).toHaveURL(/\/ankountant-settings\/study$/);
    await expect(page.getByTestId("settings-study")).toBeVisible();
    await expect(page.getByLabel("Rollover hour")).toBeVisible();
    await expect(
        page.getByRole("button", { name: "Save study settings" }),
    ).toBeVisible();

    await page.goto("/ankountant-settings/readiness");
    await expect(page.getByTestId("settings-readiness")).toBeVisible();
    await expect(page.getByLabel("CPA section")).toBeVisible();
    await expect(page.getByLabel("Exam date")).toBeVisible();

    await page.goto("/ankountant-settings/sync");
    await expect(page.getByTestId("settings-sync")).toBeVisible();
    await expect(page.getByLabel("Custom sync server URL")).toBeVisible();
    await expect(page.getByLabel("Network timeout seconds")).toBeVisible();
});
