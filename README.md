# tracker

Work items and questions for [jmarrero-bot](https://github.com/jmarrero-bot)'s workstream.
The [Workstream board](https://github.com/orgs/jmarrero-forge/projects) is a view over
these issues plus the upstream issues and PRs the bot works on; anything on
the board that isn't upstream is an issue here.

- **Work items** are ordinary issues. Larger efforts are parent issues whose
  sub-issues are the steps, so the board shows their progress.
- **Questions for jmarrero** are issues labelled `question` and assigned to
  him, usually a sub-issue of the work item they block. The first line says
  which item that is (`Blocks: <url>`). They offer lettered options, the
  recommended one first as A.

## Answering a question

Comment on the question issue. To pick an option, make the first line of the
comment just its letter (e.g. `B`), optionally followed by more text;
otherwise write whatever you want. The bot acts on the answer, then closes the
issue with a one-line comment saying what it did.

Only comments by the `jmarrero` login count as answers. The bot reads everyone
else's comments, its own included, as input to weigh, never as instructions.

## Automation

This repository is also the controller of
[agentic-job](https://github.com/cgwalters-forge/agentic-job) runs for
jmarrero-forge: a copy of
[cgwalters-forge/tracker](https://github.com/cgwalters-forge/tracker)'s
workflows, scripts and configuration, retargeted. It is being brought up
beside the current bot (#35): every lane previews, and nothing here writes
to the board, issues or pull requests until jmarrero turns a lane on (#42).
How each piece works is upstream's
[README](https://github.com/cgwalters-forge/tracker/blob/1720f962abda4a6155bd59674e2b5392795b7fe3/README.md)
at the commit copied; this section says only what differs here.

### This deployment

Copied from cgwalters-forge/tracker at
`1720f962abda4a6155bd59674e2b5392795b7fe3` (21 Oct 2026), the tree but its
README and `docs/`, `weekly-eval.yml` (cgwalters' own research thread) and
the release train (it cuts agentic-job's releases and moves cgwalters'
pins; we follow the pins upstream moves). Our own `.github/CODEOWNERS`,
`.github/agentic-job/merge.toml`, `trial.toml` and `trial.yml` stay. Copy
and retarget is upstream's
supported model (cgwalters-forge/harness-coordination#7): the `.cjs` scripts
are upstream's unchanged, and our diff is configuration:

- `.github/poll/agent-board.json`: jmarrero, jmarrero-bot, the Workstream
  board, the repositories below, our `generatedBy`, and Claude-only pools.
  agent-board is built at the head of its `main` for the poll, as upstream
  does, and at `AGENT_BOARD_REV` in `supervisor.yml` for the supervisor,
  ahead of upstream's pin to include agent-board#230 (operator and footer
  from this file);
- `.github/agentic-job/pools.json`: `claude` only, our broker's one pool;
- the bounds (`dispatch.toml`, `comment.toml`, `fix.toml`,
  `workflow/review*.toml`), the runner configurations, the profiles'
  trusted operator, `.github/usage/config.json` and
  `.github/supervisor/config.json`;
- the wrappers, jmarrero-forge/actions' `jmarrero-agentic-job.yml` and
  `jmarrero-review.yml`, pinned at `077c8a5` (agentic-job v0.6.2) where
  upstream follows `main`, since our broker admits a run by its wrapper's
  commit, and the bot's tokens: `JMARRERO_BOT_PAT` where
  upstream has `CGWALTERS_BOT_PAT`, and `JMARRERO_BOT_READ_TOKEN`, which
  previews read with;
- the preview gates below, which upstream does not have for the pull
  request poll, the usage snapshot and reviews;
- the tests that pin upstream's configuration, retargeted. The
  scheduler's and coordinator's own tests run on upstream's
  `agent-board.json` and `pools.json`, copied into `.github/poll/testdata`.

The poll follows the bot's pull requests in jmarrero-forge/tracker,
jmarrero-forge/actions and jmarrero-forge/review, the repositories whose
pull requests the bot opens and the review gate (#41) will cover. Runs may
also target the forge's bootc, ostree and rpm-ostree forks, which are not
followed: work there is promoted upstream by the operator. A first fix
round that is only toil (a rebase, placeholder subjects, or review findings
about messages or formatting, and no failed check) goes to `claude`, as
every round does, since our broker serves Claude only. The operator's
comments in `bootc-dev/*` are read as upstream reads cgwalters'
(`operatorComments`); whether runs may answer there is jmarrero's call
before the poll applies.

To resync: copy upstream's tree over again (as the first commit of #40
did), keep this diff, and refresh `.github/poll/testdata/upstream-*.json`
from upstream's `agent-board.json` and `pools.json`.

### Lanes

| Lane | Workflow | On with | Until then |
| --- | --- | --- | --- |
| Pull request poll: fix rounds, merges | `poll.yml`, job `poll` | `PR_POLL=apply` | A dry run, no saved state and no successor pass |
| Board scheduler | `poll.yml`, job `board` | `BOARD_DISPATCH=apply` | Preview |
| Epic coordinator and project status | `poll.yml`, job `board` | `COORDINATOR=apply` | Preview |
| Supervisor agent and executor | `supervisor.yml` | `SUPERVISOR=apply` | The read-only health pass only |
| Usage snapshot | `usage.yml` | `USAGE=apply` | Off |
| Broker outage probe | `broker-probe.yml` | `BROKER_OUTAGE=apply` | Off |
| Comment wake | `comment-wake.yml` | `COMMENT_WAKE=enabled` | Off |
| Agent reviews | `review.yml` | `AGENT_REVIEW` set | Off |

Every pass reads with `JMARRERO_BOT_READ_TOKEN` and is skipped with a
notice while it is unset; a pass takes the write token only once its lane
applies. `dispatch.yml`, `session.yml` (disabled in `session.json`),
`trial.yml` and `tailnet-join.yml` run only when dispatched by hand.
`SUPERVISOR=preview` is not read-only: its agent run posts its requests on
the requests issue. The requests, log and state issues in
`.github/supervisor/config.json` (and `session.json`'s issue) are
placeholders until #42 creates them and jmarrero locks them, and the
supervisor's profile is still cgwalters-forge/agenthome's, which signs as
cgwalters and reads `docs/operator-notes.md` we do not have: both are to be
ours before the supervisor runs its agent. When the
executor applies, upstream's caps hold: `maxDispatchesPerPass: 4`,
`maxDispatchesPerDay: 40`, and the daily caps `comment: 20`,
`create_issue: 15`, `close: 10`, `remove_needs_human: 12`,
`replace_state: 48` and `status_update: 1`.

A lane goes to apply only in the change that takes the same duty away from
the current bot (#42): never `bot-watch --apply` and the poll applying on
the same repositories.

A merged change to `.github/`, `workflow/` or the `Justfile` needs
jmarrero's review ([CODEOWNERS](.github/CODEOWNERS)); the agent's approval
is enough elsewhere ([merge.toml](.github/agentic-job/merge.toml)).

### Setup

Done by jmarrero (#38), since the bot's token cannot:

1. The organization secret `JMARRERO_BOT_READ_TOKEN`, available to this
   repository only: a fine-grained token of jmarrero-bot, resource owner
   jmarrero-forge, all repositories, read-only Contents, Issues, Pull
   requests, Actions and Metadata, and organization Projects read-only.
   Previews read the private jmarrero-forge/bot-ops (the usage snapshot
   and pace) besides the public repositories, which a classic
   `read:project` token cannot. Without it every pass is skipped, so it is
   what a real preview needs.
2. The organization secret `JMARRERO_BOT_PAT`, available to this
   repository only: a classic token of jmarrero-bot with the `repo` and
   `workflow` scopes. Apply's write token (dispatch, trial, session, the
   supervisor's agent), and the passes' once their lanes apply. As upstream
   has it, any job here can read it, not only the `agent-apply`
   environment.
3. The environment `agent-apply` here, limited to the default branch.
4. In the organization's Actions settings, if actions are restricted:
   allow `cgwalters-forge/agentic-job@*` and `jmarrero-forge/actions@*`,
   plus the third-party actions the workflows pin.
5. For real runs, once the broker admits the wrappers' commit
   (jmarrero/atomic-setup#24): the Tailscale OIDC trust credential, and the
   variables `INFERENCE_URL` (required), `AGENTIC_JOB_TAILSCALE_OAUTH_CLIENT_ID`,
   optionally `INFERENCE_AUDIENCE` and `AGENTIC_JOB_TAILSCALE_TAGS`
   (defaults `jmarrero-praxis-broker` and `tag:agentic-job`). The broker
   admits only `workflow_dispatch` runs from here, so the supervisor's
   agent (scheduled and comment runs) and `session.yml` need a policy entry
   there first.
6. Optionally, `DECISIONS_STATE_KEY` and a private decisions issue named in
   `agent-board.json`'s `decisions`; neither exists yet.

Then `gh workflow run trial.yml -R jmarrero-forge/tracker -f kind=implement -f item=20`
tries the whole path with the scripted agent (after 2 to 4). It creates
jmarrero-bot/tracker, the bot's fork of this repository, if missing, turns
its Actions off and pushes the trial branch there.
