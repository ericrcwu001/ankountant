// Copyright: Ankitects Pty Ltd and contributors
// License: GNU AGPL, version 3 or later; http://www.gnu.org/licenses/agpl.html

import { expect, test } from "./fixtures";

test("workspace reports a corrupted saved layout", async ({ page }) => {
    await page.addInitScript(() => {
        localStorage.setItem("ankountant.workspace.layout.v1", "not json");
    });
    await page.goto("/ankountant-workspace?initial=literature");
    await expect(page.getByTestId("literature-pane")).toBeVisible();
    await expect(page.getByTestId("workspace-layout-error")).toContainText(
        "invalid JSON",
    );
    await page.getByRole("button", { name: "Reset saved layout" }).click();
    await expect(page.getByTestId("workspace-layout-error")).toHaveCount(0);
    await expect
        .poll(() => page.evaluate(() => localStorage.getItem("ankountant.workspace.layout.v1")))
        .toContain("\"surface\":\"dashboard\"");
});

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

test("workspace panes do not leak backend html on load failure", async ({ page }) => {
    await page.route("**/_anki/searchNotes", async (route) => {
        await route.fulfill({
            status: 403,
            contentType: "text/html",
            body: "<!doctype html><title>403 Forbidden</title><h1>Forbidden</h1><p>You don&#39;t have permission.</p>",
        });
    });

    await page.goto("/ankountant-workspace?initial=tbs");

    const paneState = page.getByTestId("pane-state");
    await expect(paneState).toContainText(
        "403 Forbidden. This workspace surface could not be loaded.",
    );
    await expect(paneState).not.toContainText("<!doctype html>");
    await expect(paneState).not.toContainText("don&#39;t");
});

test("workspace TBS pane reveals the answer key after submit", async ({ page, seed }) => {
    expect(seed.sealedTbsNoteIds.length).toBeGreaterThan(0);
    await page.goto("/ankountant-workspace?initial=tbs");
    await expect(page.getByTestId("tbs-surface")).toBeVisible();

    const rows = page.getByTestId("je-row");
    await expect(rows).toHaveCount(4);
    const fill = async (idx: number, account: string, side: string, amount: string) => {
        const row = rows.nth(idx);
        await row.getByTestId("je-account").selectOption(account);
        await row.getByTestId("je-side").selectOption(side);
        await row.getByTestId("je-amount").fill(amount);
    };
    await fill(0, "ROU Asset", "dr", "10000");
    await fill(1, "Lease Liability", "cr", "10000");
    await fill(2, "Interest Expense", "dr", "500");
    await fill(3, "Cash", "cr", "500");

    await page.getByTestId("confidence-confident").click();
    await page.getByTestId("tbs-submit").click();
    await expect(page.getByTestId("results-layer")).toBeVisible();
    await expect(page.getByTestId("reveal-correct")).toHaveCount(4);
});
