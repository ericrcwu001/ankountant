// Copyright: Ankitects Pty Ltd and contributors
// License: GNU AGPL, version 3 or later; http://www.gnu.org/licenses/agpl.html

import { expect, test } from "./fixtures";

test("workspace find and replace blocks replace when fields fail to load", async ({ page, seed }) => {
    expect(seed.sealedItems).toBeGreaterThan(0);
    await page.route("**/_anki/fieldNamesForNotes", async (route) => {
        await route.fulfill({
            status: 500,
            contentType: "text/plain",
            body: "field list failed",
        });
    });
    await page.goto("/ankountant-workspace?initial=browse");
    await expect(page.getByTestId("browse-pane")).toBeVisible();
    await page.getByRole("button", { name: "Find and replace" }).click();
    const dialog = page.getByRole("dialog", { name: "Find and replace" });
    await dialog.getByRole("textbox", { name: "Find" }).fill("lease");
    await expect(page.getByTestId("fr-field-load-error")).toContainText(
        "500: field list failed",
    );
    await expect(page.getByTestId("fr-replace")).toBeDisabled();
});

test("workspace find and replace shows apply failures in the dialog", async ({ page, seed }) => {
    expect(seed.sealedItems).toBeGreaterThan(0);
    await page.route("**/_anki/findAndReplace", async (route) => {
        await route.fulfill({
            status: 500,
            contentType: "text/plain",
            body: "replace failed",
        });
    });
    await page.goto("/ankountant-workspace?initial=browse");
    await expect(page.getByTestId("browse-pane")).toBeVisible();
    await page.getByRole("button", { name: "Find and replace" }).click();
    const dialog = page.getByRole("dialog", { name: "Find and replace" });
    await dialog.getByRole("textbox", { name: "Find" }).fill("lease");
    await page.getByTestId("fr-replace").click();
    await expect(page.getByTestId("fr-apply-error")).toContainText(
        "500: replace failed",
    );
    await expect(dialog).toBeVisible();
});
