// Copyright: Ankitects Pty Ltd and contributors
// License: GNU AGPL, version 3 or later; http://www.gnu.org/licenses/agpl.html

import { expect, test } from "./fixtures";

test("stats: analytics page scrolls in the Ankountant shell body", async ({ page, seedWithHistory }) => {
    expect(seedWithHistory.sealedItems).toBeGreaterThan(0);
    await page.setViewportSize({ width: 1100, height: 560 });
    await page.goto("/ankountant-stats");
    await expect(page.getByTestId("stats")).toBeVisible();
    const shellBody = page.locator(".ank-shell-body");
    await expect
        .poll(() => shellBody.evaluate((el) => el.scrollHeight > el.clientHeight))
        .toBe(true);

    await shellBody.hover();
    await page.mouse.wheel(0, 700);
    await expect
        .poll(() => shellBody.evaluate((el) => el.scrollTop))
        .toBeGreaterThan(0);
});
