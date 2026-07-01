export const meta = {
    name: "agentic-loop-launch",
    description:
        "Thin launcher: normalizes a stringified args payload back into an object, then delegates to the unchanged agentic-loop skill workflow via in-process workflow().",
    phases: [
        { title: "Plan", detail: "delegated to agentic-loop (pre-seeded → skipped)" },
        { title: "Contract", detail: "delegated to agentic-loop (pre-seeded → skipped)" },
        { title: "Build", detail: "delegated to agentic-loop bounded build loop" },
    ],
};

// This runtime delivers the untyped Workflow `args` param to the script as a
// JSON STRING (a documented footgun). Parse it back to an object here so the
// {prd, clarifications, repoContext, config} shape survives, then hand the real
// object to the skill workflow. workflow(ref, args) passes args in-process (no
// re-serialization), so the child sees a genuine object.
const A = (typeof args === "string")
    ? (() => {
        try {
            return JSON.parse(args);
        } catch (e) {
            return {};
        }
    })()
    : (args || {});

log(
    "Launcher: delegating to agentic-loop (prd present: "
        + !!(A && A.prd)
        + ", targetDir: "
        + ((A && A.config && A.config.targetDir) || "(unset)")
        + ")",
);

return await workflow(
    { scriptPath: "/Users/ericwu/.claude/skills/agentic-loop/agentic-loop.workflow.js" },
    A,
);
