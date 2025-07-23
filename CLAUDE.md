# CLAUDE.md - Development Guidelines

This file documents the established patterns, conventions, and best practices for the k0rdent Azure setup project. Use this as a reference when making changes or extending functionality.

## Important Technical Notes

### Kubeconfig Retrieval from k0rdent
When k0rdent creates managed clusters, it stores their kubeconfigs as Secrets in the `kcm-system` namespace. To retrieve:
```bash
kubectl get secret <cluster-name>-kubeconfig -n kcm-system -o jsonpath='{.data.value}' | base64 -d > ./k0sctl-config/<cluster-name>-kubeconfig
```
See `backlog/docs/doc-004 - Kubeconfig-Retrieval.md` for detailed documentation.

### macOS WireGuard Interface Naming
On macOS, WireGuard interfaces are always named utun0 through utun9 (dynamically assigned), not by the configuration name. When using `wg show` on macOS, you must use the actual utun interface name, not the configuration name like "wgk0r5jkseel". The configuration name is only used by wg-quick to track which utun interface belongs to which configuration.

# DEVELOPER DIRECTIVES

- Do NOT run tests without confirmation
- Ask before using git commit -A as frequently in this directory there are transient files we do NOT want to commit
- When planning infrastructure, follow the pets vs cattle methodology and consider most cloud instances as cattle who can be easily replaced and that is the better solution than trying to spending excessive amounts of time troubleshooting transient problems

## Task Management Transition (2025-07-20)

**IMPORTANT**: We have fully migrated to using Backlog.md (https://github.com/MrLesk/Backlog.md) for all task management and documentation.

- **Old System**: Previously used `notebooks/BACKLOG.md` and various subdirectories
- **New System**: Now using the `backlog` CLI tool with structured directories:
  - `backlog/tasks/` - All project tasks (48 migrated)
  - `backlog/docs/` - Design specs, troubleshooting guides, references
  - `backlog/decisions/` - Architecture Decision Records (ADRs)
  - `backlog/completed/` - Historical implementation plans
- **Migration Date**: 2025-07-20
- **Usage**: Use `backlog` CLI commands for all task management (see guidelines below)

## Development Environment

### Script Execution Timeouts

**Azure VM Creation Requirements**:
- When executing `create-azure-vms.sh` or any script that creates Azure VMs, use an extended timeout
- Allow at least 5 minutes per VM for creation (25-30 minutes for 5 VMs)
- Use `timeout` parameter of at least 1800000ms (30 minutes) when running these scripts
- VM provisioning on Azure can be slow and should not be prematurely terminated
- **New Async Implementation**: VMs are now created in parallel background processes with automatic failure recovery
- **Timeout Handling**: Individual VM creation timeouts are managed via `VM_CREATION_TIMEOUT_MINUTES` from YAML config
- **Monitoring Loop**: Single monitoring process checks all VM states every 30 seconds using bulk Azure API calls

**Azure VM Validation Requirements**:
- VM availability validation requires both `yq` and Azure CLI (`az`)
- Validation makes Azure API calls and can take 30-60 seconds per unique VM size
- Use `--skip-validation` flag when working offline or to speed up configuration creation
- Validation automatically runs after `configure.sh init` unless skipped

### Editor Configuration

**Always use vim editing mode** for consistency across development sessions:

```
vim
```

This ensures:
- Consistent editing experience across team members
- Familiar modal editing for efficient code manipulation
- Standardized keybindings and commands
- Better handling of shell script syntax and indentation

## Desktop Notifications (macOS)

### Overview
Desktop notifications provide real-time deployment status updates on macOS using native notifications.

### Usage
```bash
# Deploy with desktop notifications
./deploy-k0rdent.sh deploy --with-desktop-notifications
```

### Features
- **Real-time notifications**: Major deployment milestones trigger desktop alerts
- **Multi-instance support**: Separate notifiers for k0rdent, KOF, and child clusters
- **Grouped notifications**: Each deployment type has its own notification group
- **Duration tracking**: Completion notification shows total deployment time

### Architecture
- **Notifier daemon**: `bin/utils/desktop-notifier.sh` monitors event files
- **Event monitoring**: Polls YAML event files every 2 seconds
- **Instance isolation**: Each notifier has its own PID, log, and state files
- **Notification technology**: Uses `terminal-notifier` with `osascript` fallback

## KOF (K0rdent Operations Framework) Integration

### Overview
KOF is an optional component that can be installed after k0rdent deployment. The implementation follows the principle of maximum reuse - leveraging existing k0rdent infrastructure, configurations, and functions.

### Key Design Principles
1. **Configuration Reuse**: KOF configuration is part of existing k0rdent YAML files (no separate KOF config)
2. **Code Reuse**: All general functions come from `common-functions.sh` (only KOF-specific in `kof-functions.sh`)
3. **Pattern Reuse**: KOF scripts follow exact same patterns as k0rdent scripts
4. **No Duplication**: If it exists in k0rdent, reuse it

### KOF Functions (etc/kof-functions.sh)
Only KOF-specific functions are included:
- `check_kof_enabled()` - Check if KOF is enabled in configuration
- `get_kof_config()` - Get KOF configuration values from existing YAML
- `check_istio_installed()` - Check if Istio is installed
- `install_istio_for_kof()` - Install Istio for KOF
- `prepare_kof_namespace()` - Create and label KOF namespace
- `check_kof_mothership_installed()` - Check mothership installation
- `check_kof_operators_installed()` - Check operators installation

### Configuration Structure
KOF configuration is added to existing k0rdent YAML files:
```yaml
kof:
  enabled: false  # Disabled by default
  version: "1.1.0"
  istio:
    version: "1.1.0"
    namespace: "istio-system"
  # ... additional KOF settings
```

### Implementation Pattern
All KOF scripts follow the standard k0rdent pattern:
```bash
source ./etc/k0rdent-config.sh      # Loads everything including KOF config
source ./etc/common-functions.sh     # All common functionality
source ./etc/state-management.sh     # State tracking
source ./etc/kof-functions.sh        # Only KOF-specific additions
```

## Naming Conventions

### Cluster ID Pattern
- All resources use a consistent `K0RDENT_CLUSTERID` pattern (e.g., `k0rdent-abc123de`)
- The cluster ID is stored in `.clusterid` file
- WireGuard config files use pattern `wgk0${suffix}.conf` where suffix is extracted from cluster ID
- No more mixed PREFIX/SUFFIX terminology - everything is CLUSTERID now

## Documentation and Decision Management

### Documentation (backlog/docs/)
- **Design Documents**: Store all design documents and architectural plans in `backlog/docs/`
- **Troubleshooting Guides**: Create troubleshooting documents with type: troubleshooting
- **Technical References**: API documentation, integration guides, etc.
- **Format**: Use `doc-XXX - Title.md` naming convention
- **Types**: design, troubleshooting, reference, guide, other

### Decisions (backlog/decisions/)
- **Architectural Decisions**: Record all key architectural decisions as ADRs (Architecture Decision Records)
- **Format**: Use `decision-XXX - Title.md` naming convention
- **Structure**: Context, Decision, Consequences
- **Status**: proposed, accepted, rejected, superseded
- **Purpose**: Maintain a history of why certain technical choices were made

### Directory Usage Guidelines
- **Tasks**: Use `backlog task create` for all new tasks and features
- **Troubleshooting**: Create docs in `backlog/docs/` with type: troubleshooting
- **Design Documents**: Create docs in `backlog/docs/` with type: design
- **Technical References**: Create docs in `backlog/docs/` with type: reference
- **Architecture Decisions**: Create ADRs in `backlog/decisions/`
- **DEPRECATED**: The notebooks/ directory has been removed

<!-- BACKLOG.MD GUIDELINES START -->
# Instructions for the usage of Backlog.md CLI Tool

## 1. Source of Truth

- Tasks live under **`backlog/tasks/`** (drafts under **`backlog/drafts/`**).
- Every implementation decision starts with reading the corresponding Markdown task file.
- Project documentation is in **`backlog/docs/`**.
- Project decisions are in **`backlog/decisions/`**.

## 2. Defining Tasks

### **Title**

Use a clear brief title that summarizes the task.

### **Description**: (The **"why"**)

Provide a concise summary of the task purpose and its goal. Do not add implementation details here. It
should explain the purpose and context of the task. Code snippets should be avoided.

### **Acceptance Criteria**: (The **"what"**)

List specific, measurable outcomes that define what means to reach the goal from the description. Use checkboxes (`- [ ]`) for tracking.
When defining `## Acceptance Criteria` for a task, focus on **outcomes, behaviors, and verifiable requirements** rather
than step-by-step implementation details.
Acceptance Criteria (AC) define *what* conditions must be met for the task to be considered complete.
They should be testable and confirm that the core purpose of the task is achieved.
**Key Principles for Good ACs:**

- **Outcome-Oriented:** Focus on the result, not the method.
- **Testable/Verifiable:** Each criterion should be something that can be objectively tested or verified.
- **Clear and Concise:** Unambiguous language.
- **Complete:** Collectively, ACs should cover the scope of the task.
- **User-Focused (where applicable):** Frame ACs from the perspective of the end-user or the system's external behavior.

    - *Good Example:* "- [ ] User can successfully log in with valid credentials."
    - *Good Example:* "- [ ] System processes 1000 requests per second without errors."
    - *Bad Example (Implementation Step):* "- [ ] Add a new function `handleLogin()` in `auth.ts`."

### Task file

Once a task is created it will be stored in `backlog/tasks/` directory as a Markdown file with the format
`task-<id> - <title>.md` (e.g. `task-42 - Add GraphQL resolver.md`).

### Additional task requirements

- Tasks must be **atomic** and **testable**. If a task is too large, break it down into smaller subtasks.
  Each task should represent a single unit of work that can be completed in a single PR.

- **Never** reference tasks that are to be done in the future or that are not yet created. You can only reference
  previous
  tasks (id < current task id).

- When creating multiple tasks, ensure they are **independent** and they do not depend on future tasks.   
  Example of wrong tasks splitting: task 1: "Add API endpoint for user data", task 2: "Define the user model and DB
  schema".  
  Example of correct tasks splitting: task 1: "Add system for handling API requests", task 2: "Add user model and DB
  schema", task 3: "Add API endpoint for user data".

## 3. Recommended Task Anatomy

```markdown
# task‑42 - Add GraphQL resolver

## Description (the why)

Short, imperative explanation of the goal of the task and why it is needed.

## Acceptance Criteria (the what)

- [ ] Resolver returns correct data for happy path
- [ ] Error response matches REST
- [ ] P95 latency ≤ 50 ms under 100 RPS

## Implementation Plan (the how) (added after starting work on a task)

1. Research existing GraphQL resolver patterns
2. Implement basic resolver with error handling
3. Add performance monitoring
4. Write unit and integration tests
5. Benchmark performance under load

## Implementation Notes (only added after finishing work on a task)

- Approach taken
- Features implemented or modified
- Technical decisions and trade-offs
- Modified or added files
```

## 6. Implementing Tasks

Mandatory sections for every task:

- **Implementation Plan**: (The **"how"**) Outline the steps to achieve the task. Because the implementation details may
  change after the task is created, **the implementation plan must be added only after putting the task in progress**
  and before starting working on the task.
- **Implementation Notes**: Document your approach, decisions, challenges, and any deviations from the plan. This
  section is added after you are done working on the task. It should summarize what you did and why you did it. Keep it
  concise but informative.

**IMPORTANT**: Do not implement anything else that deviates from the **Acceptance Criteria**. If you need to
implement something that is not in the AC, update the AC first and then implement it or create a new task for it.

## 2. Typical Workflow

```bash
# 1 Identify work
backlog task list -s "To Do" --plain

# 2 Read details & documentation
backlog task 42 --plain
# Read also all documentation files in `backlog/docs/` directory.
# Read also all decision files in `backlog/decisions/` directory.

# 3 Start work: assign yourself & move column
backlog task edit 42 -a @{yourself} -s "In Progress"

# 4 Add implementation plan before starting
backlog task edit 42 --plan "1. Analyze current implementation\n2. Identify bottlenecks\n3. Refactor in phases"

# 5 Break work down if needed by creating subtasks or additional tasks
backlog task create "Refactor DB layer" -p 42 -a @{yourself} -d "Description" --ac "Tests pass,Performance improved"

# 6 Complete and mark Done
backlog task edit 42 -s Done --notes "Implemented GraphQL resolver with error handling and performance monitoring"
```

### 7. Final Steps Before Marking a Task as Done

Always ensure you have:

1. ✅ Marked all acceptance criteria as completed (change `- [ ]` to `- [x]`)
2. ✅ Added an `## Implementation Notes` section documenting your approach
3. ✅ Run all tests and linting checks
4. ✅ Updated relevant documentation

## 8. Definition of Done (DoD)

A task is **Done** only when **ALL** of the following are complete:

1. **Acceptance criteria** checklist in the task file is fully checked (all `- [ ]` changed to `- [x]`).
2. **Implementation plan** was followed or deviations were documented in Implementation Notes.
3. **Automated tests** (unit + integration) cover new logic.
4. **Static analysis**: linter & formatter succeed.
5. **Documentation**:
    - All relevant docs updated (any relevant README file, backlog/docs, backlog/decisions, etc.).
    - Task file **MUST** have an `## Implementation Notes` section added summarising:
        - Approach taken
        - Features implemented or modified
        - Technical decisions and trade-offs
        - Modified or added files
6. **Review**: self review code.
7. **Task hygiene**: status set to **Done** via CLI (`backlog task edit <id> -s Done`).
8. **No regressions**: performance, security and licence checks green.

⚠️ **IMPORTANT**: Never mark a task as Done without completing ALL items above.

## 9. Handy CLI Commands

| Purpose          | Command                                                                |
|------------------|------------------------------------------------------------------------|
| Create task      | `backlog task create "Add OAuth"`                                      |
| Create with desc | `backlog task create "Feature" -d "Enables users to use this feature"` |
| Create with AC   | `backlog task create "Feature" --ac "Must work,Must be tested"`        |
| Create with deps | `backlog task create "Feature" --dep task-1,task-2`                    |
| Create sub task  | `backlog task create -p 14 "Add Google auth"`                          |
| List tasks       | `backlog task list --plain`                                            |
| View detail      | `backlog task 7 --plain`                                               |
| Edit             | `backlog task edit 7 -a @{yourself} -l auth,backend`                   |
| Add plan         | `backlog task edit 7 --plan "Implementation approach"`                 |
| Add AC           | `backlog task edit 7 --ac "New criterion,Another one"`                 |
| Add deps         | `backlog task edit 7 --dep task-1,task-2`                              |
| Add notes        | `backlog task edit 7 --notes "We added this and that feature because"` |
| Mark as done     | `backlog task edit 7 -s "Done"`                                        |
| Archive          | `backlog task archive 7`                                               |
| Draft flow       | `backlog draft create "Spike GraphQL"` → `backlog draft promote 3.1`   |
| Demote to draft  | `backlog task demote <task-id>`                                        |

## 10. Tips for AI Agents

- **Always use `--plain` flag** when listing or viewing tasks for AI-friendly text output instead of using Backlog.md
  interactive UI.
- When users mention to create a task, they mean to create a task using Backlog.md CLI tool.

<!-- BACKLOG.MD GUIDELINES END -->
