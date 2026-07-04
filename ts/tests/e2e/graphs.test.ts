// Copyright: Ankitects Pty Ltd and contributors
// License: GNU AGPL, version 3 or later; http://www.gnu.org/licenses/agpl.html

import { expect, test } from "./fixtures";

test("graphs: graph load failure shows an inline error state", async ({ page, seedWithHistory }) => {
    expect(seedWithHistory.sealedItems).toBeGreaterThan(0);
    await page.route("**/_anki/graphs", async (route) => {
        await route.fulfill({
            status: 500,
            contentType: "text/html",
            body: "<html><head><title>500 Internal Server Error</title></head><body>traceback</body></html>",
        });
    });

    await page.goto("/graphs");

    const error = page.getByTestId("graphs-load-error");
    await expect(error).toBeVisible();
    await expect(error).toContainText("Statistics unavailable");
    await expect(error).toContainText("500 Internal Server Error. Statistics could not be loaded.");
});
