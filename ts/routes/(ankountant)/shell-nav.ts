export interface ShellNavItem {
    id: string;
    href?: string;
}

export function activeShellNavId(
    nav: ShellNavItem[],
    currentPath: string,
    currentSearch: string,
): string | undefined {
    let bestMatch: ShellNavItem | undefined;
    let bestScore = -1;

    for (const item of nav) {
        if (!item.href?.includes("?") || !hrefMatchesCurrentLocation(item.href, currentPath, currentSearch)) {
            continue;
        }

        const score = hrefSearchParamCount(item.href);
        if (score > bestScore) {
            bestMatch = item;
            bestScore = score;
        }
    }

    if (bestMatch) {
        return bestMatch.id;
    }

    return nav.find((item) => item.href && !item.href.includes("?") && hrefPath(item.href) === currentPath)
        ?.id;
}

function hrefMatchesCurrentLocation(
    href: string,
    currentPath: string,
    currentSearch: string,
): boolean {
    if (hrefPath(href) !== currentPath) {
        return false;
    }

    const expected = hrefSearchParams(href);
    const actual = new URLSearchParams(currentSearch.startsWith("?") ? currentSearch.slice(1) : currentSearch);

    for (const [key, value] of expected) {
        if (actual.get(key) !== value) {
            return false;
        }
    }

    return true;
}

function hrefPath(href: string): string {
    return href.split("?")[0];
}

function hrefSearchParams(href: string): URLSearchParams {
    return new URLSearchParams(href.split("?")[1] ?? "");
}

function hrefSearchParamCount(href: string): number {
    return Array.from(hrefSearchParams(href)).length;
}
