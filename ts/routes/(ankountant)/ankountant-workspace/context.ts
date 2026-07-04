// Copyright: Ankitects Pty Ltd and contributors
// License: GNU AGPL, version 3 or later; http://www.gnu.org/licenses/agpl.html

// ! Svelte context contract between the workspace root (which owns the layout
// ! tree) and the recursively-rendered panes/resizers. Structural edits are
// ! addressed by path so the recursion never has to thread callbacks by hand.

import type { Path, Side, SplitDir, SurfaceKind } from "./workspace-layout";

export const WORKSPACE_ACTIONS = Symbol("ankountant-workspace-actions");

export interface WorkspaceActions {
    split(path: Path, dir: SplitDir, surface: SurfaceKind, side?: Side): void;
    close(path: Path): void;
    setSurface(path: Path, surface: SurfaceKind): void;
    setRatio(path: Path, ratio: number): void;
}
