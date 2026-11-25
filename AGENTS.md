# sec-range-kit Agent Rules & Developer Guidelines

AI Guidelines for sec-range-kit.



## 🛡️ Mandatory Authorization Gate & Safety Boundaries

This is a hard safety boundary for every agent session.

### 1. Action Classification Before Any Tool Call
Before performing any tool call, categorize the intended action into one of four tiers:

- **Tier 1 (Read-only)**:
  - Inspect files, Git status/history, build/test logs, CI status, or external state.
  - *Status*: **Allowed by default**.
- **Tier 2 (Local edit)**:
  - Modify or create files only when explicitly requested by the user.
  - *Status*: Allowed for the requested scope. **Does NOT imply permission to commit, push, or publish**.
- **Tier 3 (Branch Mutation / Remote Feature Push)**:
  - Branch creation/switching, commit, push/force-push on a feature branch, tag modification, PR creation.
  - *Status*: **Requires explicit authorization from the user** in the current conversation turn (or explicit session blanket permission for feature-branch commits and pushes).
- **Tier 4 (Core Baseline Merger - PR Merge to Main / Protected Branches)**:
  - Executing `gh pr merge`, GitHub API merge endpoints, or direct git merge into `main` / `master` / release branches.
  - *Status*: **ABSOLUTELY FORBIDDEN FOR AGENTS (Human-Only Authority)**. The agent is NEVER permitted to merge a PR. Even if all CI checks, security scans, and reviews pass 100%, the agent must only report status and wait for the human maintainer to manually review and merge.

### 2. Scope Non-Transitivity & Granularity Boundary
- Authorization for operation A never extends to operation B.
- **Commit & Push ≠ PR Merge**: A user stating *"commit/push 不用跟我確認"* (no need to confirm commits and pushes) applies **STRICTLY AND ONLY to feature-branch git commits and pushes**. It **NEVER** grants permission to merge a Pull Request into `main`!
- Merging a PR into `main` alters the production baseline and can only be executed by human decision.
- If an authorized operation fails and a different operation is needed, report the failure evidence and stop. Never expand authorization autonomously.
- If the user revokes or objects to an action, stop immediately. Never execute autonomous "cleanup" (such as deleting branches or force-pushing) without separate explicit authorization.

---

## 🧠 Problem-Solving Approach (Stop Brute Force)

When you encounter an error, test failure, build break, or unexpected state:

- **Do NOT** blindly guess or try random trial-and-error fixes. Each failed attempt without understanding the root cause is wasted effort.
- **DO** stop and observe the underlying mechanism first. Read the exact error stack trace, inspect the relevant source code, and consult documentation. Understand *why* it fails before attempting a fix.
- **DO** normalize the problem to its minimum reproducible unit. Verify the smallest possible piece first, then scale up.
- **DO** ask yourself: *"Am I diagnosing the root cause, or just hoping random edits will make it pass?"*


## 🎯 Goal-Oriented Engineering & Deliberation Gate (寬進嚴出思考協議)

This protocol enforces **Goal-Driven Problem Solving, Negative Constraints, and Architecture Trade-offs** before touching code. It prevents the "Micromanagement Trap" where overly specific implementation instructions lead to local optima, brittle workarounds, or XY problems.

---

### 1. Separate "What & Why" from "How" (目標與驗收導向)
When analyzing user requests, architectural proposals, or task prompts:
- **Focus on the Objective**: Identify the desired end-state (**What**) and the root motivation (**Why**).
- **Decouple Implementation**: Do NOT treat specific libraries, scripts, or procedural steps proposed in discussion as immutable constraints unless they are explicit business/environment requirements.
- **Formulate Acceptance Criteria**: Translate requirements into clear, testable criteria (e.g., performance budgets, resource footprint, fault-tolerance behaviors, schema integrity).

---

### 2. Negative Constraints over Positive Dictation (負面邊界取代正面指令)
Evaluate solution space against hard **Red Lines (Negative Constraints)** rather than rigid procedural lists. Unless a red line is breached, explore the cleanest, most idiomatic implementation:
- **Cost & Dependencies**: Avoid introducing heavy, runtime-onerous, or paid third-party dependencies when lightweight native or standard-library solutions suffice.
- **Backward Compatibility**: Never break existing public APIs, database schemas, or contract invariants without an explicit migration plan.
- **Resource & Latency Budgets**: Keep execution footprint bounded (CPU, memory, cold-start time, network roundtrips).

---

### 3. Deliberation Gate: Multi-Option & Trade-off Evaluation (強制前置架構發散)
For any non-trivial feature, architectural redesign, or new dependency introduction:
- **Freeze Implementation First**: Do NOT jump straight into writing code or modifying multiple files in a single turn without structural alignment.
- **Propose 2 to 3 Competing Approaches**:
  1. **Option A (Minimalist / Zero-Dependency)**: Lowest development and maintenance overhead.
  2. **Option B (Robust / Extensible)**: Best long-term maintainability, testability, and scalability.
  3. **Option C (Pragmatic / Existing Foundation)**: Leveraging existing patterns already in the codebase.
- **Explicit Trade-off Analysis**: Contrast the options across development complexity, maintenance burden, failure modes, and long-term tech debt.
- **Persist via ADR (架構決策落盤)**: Once an architectural approach is chosen with the human engineer, document the context, negative constraints, considered options, and trade-off rationale in `docs/adr/XXXX-title.md` (following `docs/adr/template.md`).
- **Await Decision**: Let the human engineer choose or refine the direction before proceeding to atomic implementation.

---

### 4. Expose Root Pain Points & Detect XY Problems (暴露真痛點，拒絕代碼繞道)
- **Beware of Workarounds**: If a user or issue description proposes an unusual, hyper-complex, or convoluted solution, investigate the *underlying environmental or structural limitation* that prompted it.
- **Solve the Root Cause**: Ask whether the requirement is solving a real business problem or merely patching around a fragile symptom. Address the root cause directly whenever safe and feasible.

---

### 5. Challenge Assumptions & Active Counter-Proposal (主動反駁權與去過度設計)
- **Constructive Pushback**: You are explicitly authorized and expected to challenge requirements that introduce:
  - Over-engineering or premature abstraction.
  - Logical contradictions or security anti-patterns.
  - Unnecessary fragility or maintenance liability.
- **How to Push Back**: Politely articulate the risk or cost, provide concrete rationale, and present a cleaner, simpler alternative path before proceeding.


## 🧠 Persistent Memory Protocol

Every agent session must maintain continuity across sessions via `MEMORY.md`:

### 1. Start of Session (CRITICAL — Execute First)
- Read `MEMORY.md` in the workspace root at the beginning of the session.
- Absorb recorded user preferences, active tasks, project architectural context, and prior decisions.
- Do not ask the user to re-explain background details already documented in `MEMORY.md`.

### 2. End of Session
- Update `MEMORY.md` before ending:
  - Record new architectural decisions and rationale.
  - Update current active tasks and blockers.
  - Append a concise session history entry.
  - Preserve critical technical lessons learned and platform pitfalls.


## 📐 Git Discipline & Conventional Commits

### 1. Atomic Commits & Revert Test
- **One purpose per commit**: Never mix functional logic updates with formatting, comment cleanups, or asset moves in a single commit.
- **The Revert Test**: If change A can be reverted without breaking change B, they represent separate purposes and must be committed in separate batches.
- Even within the same file, split logically independent hunks (e.g. using `git add -p`).

### 2. Conventional Commit Formatting
All commit messages must strictly follow the Conventional Commits format:
```
<type>(<scope>): <subject>
or
<type>: <subject>

1. <Numbered English detail line 1>
2. <Numbered English detail line 2>
```

- **Allowed Types**: `feat`, `fix`, `refactor`, `docs`, `test`, `chore`, `style`, `perf`, `security`
- **Rules**:
  - Header length: Maximum 72 characters.
  - No trailing period (`.`) at the end of the subject.
  - Avoid vague descriptions (`update`, `misc`, `fix bug`, `changes`).
  - Body must be a numbered list in English explaining technical rationale.

### 3. Safety Rules
- **NEVER** run `git push` or `git push --force` automatically. Only commit locally unless explicit push authorization is granted.

### 4. Separation of Concerns & Anti-Free-Riding Rule
- **Orthogonal Categorization, NOT Fixed Quotas**: Commits must be separated by their technical nature, but PRs are never forced into a fixed number of commits (small PRs can have 1-2 commits, larger PRs can have multiple atomic commits).
- **Four Functional Tiers**:
  - **Tier 1 (Purpose & Specifications)**: `SPECIFICATION.md`, ADRs, architecture diagrams, schemas.
  - **Tier 2 (Feature & Implementation)**: Source code, business logic, CLI scripts, test suites.
  - **Tier 3 (Context & Navigation)**: `README.md`, `index.md`, documentation catalogs, changelogs.
  - **Tier 4 (Governance & Session Memory)**: `MEMORY.md`, `docs/HANDOVER.md`, `.agent/*` rules.
- **Strict Anti-Free-Riding**: NEVER bundle Tier 4 governance/memory updates into Tier 2 feature/implementation commits. If a feature commit is reverted, project governance and session memory must remain intact.

### 5. Branch Scope & Naming Discipline
- **Single Scope Rule**: Every branch must address exactly ONE focused capability or problem.
- **No Compound or Sequence Suffixes**: Never concatenate unrelated topic words, and never use sequence suffixes such as `-pr2` or `phase-1`.
- **Strict Word & Length Limits**:
  - The branch suffix must consist of **2 to 3 words** separated by hyphens (e.g. `feat/user-auth` or `fix/jwt-expiry`).
  - The branch suffix length must **NOT exceed 25 characters** (enforced by `branch_policy.py`).

### 6. Pull Request Toolchain & Submission Protocol
- **Primary PR Toolchain (`pr_tool.py`)**: Use `python tools/pr_tool.py` (or `scripts/pr_tool.py`) as the standard PR operations entry point:
  - `prepare`: Fast preflight verifying branch naming, clean worktree, and commit messages.
  - `push`: Separately authorized branch publication running the pre-push gate.
  - `create`: Separately authorized PR creation with validation against the PR template.
  - `verify`: Combined acceptance checking CI status, SonarCloud quality gate, and open review threads.
  - `diagnose`: Automatic failure log and check run diagnostic extraction.
  - `threads`: Lists all unresolved review threads with file locations and comment summaries.
  - `resolve`: Safe GraphQL-based review thread resolution upon explicit user authorization (supports single `--thread <id>` or batch `--all`).
- **PR Content Generator (`pr_helper.py`)**: Use `python tools/pr_helper.py generate` to auto-extract and structure PR body drafts from commit history.
- **Bypass Shell String Escaping**: Never pass raw markdown text directly via CLI string arguments. Always write the PR body to a file and pass `--body-file <path>` to eliminate Windows/PowerShell escape stripping and markdown truncation.
- **Atomic Label Assignment**: Always pass `--label` during initial PR creation to avoid race conditions with GitHub Actions policy workflows triggering on the `opened` event.

### 7. PR Lifecycle Red Line & Intent Interpretation (Non-negotiable)
- **Strict Intent Interpretation**: User instructions such as "修" (fix), "改" (change), or "處理" (handle) mean strictly editing local code and fixing the reported issues. Never interpret them as authorization to close, abandon, recreate, or start a new branch/PR.
- **Never autonomously close or abandon PRs**: An active PR must NEVER be closed (`gh pr close`), abandoned, or replaced with a new branch unless the user explicitly and verbatim commands it (e.g. "關閉 PR", "close PR", "放棄此 PR"). All review findings and CI failures must be resolved by adding atomic follow-up commits to the existing branch.
- **Zero-tolerance for unauthorized PR mutation commands**: Never invoke `gh pr close`, `gh pr edit`, `gh pr merge`, `git push --delete`, or `git push --force` autonomously. Direct PR mutations require explicit, separate, per-operation authorization.

### 8. PR Review Safety & Closure Protocol (Non-negotiable)
- Never create, reply to, edit, repost, or delete GitHub PR review comments or conversation comments. Autonomous comment replies are prohibited. Do not use comments to announce a fix.
- **Mandatory Review Thread Closure Protocol**:
  - Whenever `pr_tool.py verify` reports unresolved review threads, the agent **MUST NEVER report the check as "passed" or "clean"**.
  - Review threads never resolve automatically; after pushing verified fixes and verifying CI is green, the agent **MUST immediately and proactively** list every open thread (whether active or outdated), cite the commit that fixed it, and explicitly request user authorization to resolve that thread ID via `pr_tool.py resolve`.
  - Never wait for the user to notice or remind about open threads.

### 9. Pull Request Merge Authority (Absolute Human-Only Gate)
- **STRICT AGENT BAN ON MERGES**: The AI agent must **NEVER** run `gh pr merge`, call merge APIs, or merge commits into `main` / `master` / protected branches.
- **Agent Lifecycle End**: Once a PR is opened, review feedback is resolved, and CI checks pass, the agent's work on the PR is **COMPLETE**. The agent must report the status to the user and await the user's manual merge.
- **No Blanket Exemption**: Blanket permissions for branch commits and pushes (`git commit`, `git push`) strictly exclude PR merges. Merging to `main` is an irreversible product baseline decision that exclusively belongs to the repository owner.


# Git Worktree Parallel Development Guidelines

To prevent dependency churn, build artifact conflicts, and environment cache pollution when working across multiple pull requests:

### 1. Dedicated Sibling Worktree Isolation
- Always create feature branches in dedicated sibling worktree directories rather than checking them out in the main working tree:
  ```bash
  python tools/worktree_tool.py start feat/your-feature
  ```
- This automatically creates and switches to `../<repo>-pr-<feature>` branched cleanly from the latest `origin/main`.
- The root repository directory remains permanently pinned to `main` for clean integration inspections.

### 2. Cryptographic Merge Verification Before Cleanup
- Once a PR is merged into `main`, clean up the dedicated worktree using:
  ```bash
  # Step 1: Preview cleanup and receive authorization token
  python tools/worktree_tool.py cleanup <PR_NUMBER>

  # Step 2: Execute cleanup with explicit user authorization
  python tools/worktree_tool.py cleanup <PR_NUMBER> --execute --authorize <TOKEN>
  ```
- The cleanup tool enforces fail-closed integration proof before deletion:
  - **Ancestry check**: PR merge commit reachable from remote main.
  - **Equivalence check**: Verifies squash patch or rebase cherry equivalence.
  - **Dirty state check**: Refuses to remove worktrees containing uncommitted modifications.
