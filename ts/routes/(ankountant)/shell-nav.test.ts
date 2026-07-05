import { expect, test } from "vitest";

import { activeShellNavId, type ShellNavItem } from "./shell-nav";

const nav: ShellNavItem[] = [
    { id: "dashboard", href: "/ankountant-home" },
    { id: "study", href: "/ankountant-workspace" },
    { id: "browse", href: "/ankountant-workspace?initial=browse" },
    { id: "settings", href: "/ankountant-settings" },
];

test("path-only workspace route selects Study", () => {
    expect(activeShellNavId(nav, "/ankountant-workspace", "")).toBe("study");
});

test("browse query route wins over the path-only Study route", () => {
    expect(activeShellNavId(nav, "/ankountant-workspace", "?initial=browse")).toBe("browse");
});

test("browse match tolerates extra query params", () => {
    expect(activeShellNavId(nav, "/ankountant-workspace", "?initial=browse&mode=cards&page=2")).toBe(
        "browse",
    );
});

test("settings route selects Settings", () => {
    expect(activeShellNavId(nav, "/ankountant-settings", "")).toBe("settings");
});
