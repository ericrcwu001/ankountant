// Copyright: Ankitects Pty Ltd and contributors
// License: GNU AGPL, version 3 or later; http://www.gnu.org/licenses/agpl.html

import { expect, test } from "./fixtures";

for (const route of ["/ankountant-research", "/ankountant-doc-review"]) {
    test(`${route}: reference tools start beside the prompt`, async ({ page, seed }) => {
        expect(seed.sealedItems).toBeGreaterThan(0);
        await page.setViewportSize({ width: 1600, height: 900 });
        await page.goto(route);

        const shell = page.getByTestId("exam-shell");
        const tools = page.getByTestId("exam-tools");
        const prompt = page.getByTestId("exam-prompt");

        await expect(shell).toBeVisible();
        await expect(tools).toBeVisible();
        await expect(prompt).toBeVisible();

        const shellBox = await shell.boundingBox();
        const toolsBox = await tools.boundingBox();
        const promptBox = await prompt.boundingBox();

        if (!shellBox || !toolsBox || !promptBox) {
            throw new Error("Missing exam shell layout box.");
        }

        expect(toolsBox.y).toBeGreaterThan(shellBox.y);
        expect(toolsBox.y).toBeLessThan(promptBox.y);
    });
}
