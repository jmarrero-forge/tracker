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

This repository is also the caller of
[agentic-job](https://github.com/cgwalters-forge/agentic-job) runs and of
[agent-board](https://github.com/cgwalters-forge/agent-board)'s pass for
jmarrero-forge: cgwalters-forge/tracker's controller, retargeted (see
Resync). It is being brought up beside the current bot (tracker#35):
nothing here writes to the board or to other repositories' pull requests
yet.

| Workflow | What it does | Status |
| --- | --- | --- |
| [dispatch](.github/workflows/dispatch.yml) | One agent run (`implement`, `triage`, `research`, `review` or `fix`) on an item of a repository in the bounds ([dispatch.toml](.github/agentic-job/dispatch.toml), comment-only kinds [comment.toml](.github/agentic-job/comment.toml), fixes [fix.toml](.github/agentic-job/fix.toml), the forge's forks [midstream.toml](.github/agentic-job/midstream.toml) and [midstream-fix.toml](.github/agentic-job/midstream-fix.toml)), through jmarrero-forge/actions' `cgwalters-agentic-job.yml`; the kind's [profile](.github/agentic-job/profiles) goes before the task | By hand only; waits for the setup below |
| [trial](.github/workflows/trial.yml) | The same path with agentic-job's scripted agent, against this repository: no model, broker or tailnet | Waits for the secret and environment below |
| [poll](.github/workflows/poll.yml) | `agent-board pass` on [pass.json](.github/pass.json) every 10 minutes: pull request follow-up, epics, scheduling and board Status | Preview only: each run's summary says what it would have done |
| [review](.github/workflows/review.yml) | An agent's review of every pull request here, through `cgwalters-review.yml` | Off until the variable `AGENT_REVIEW` is set |
| [ci](.github/workflows/ci.yml) | `just test` (agent-board's installer, the config tests, the poll's checks), actionlint and zizmor, that the bounds parse, and that scripts only shrink | On |

The pass is a preview in every way that would let it write: pass.json has
`wip: 0`, `triage: false` and no `follow` or `epics`, it reads with
`JMARRERO_BOT_READ_TOKEN`, which can write nothing, `--apply` is passed
only while the variable `PASS_APPLY` is `enabled`, and even then its caps
(`--max-dispatch 0 --max-writes 0`) take no board or forge step; only the
`next` job would start the following pass. Cutover (tracker#42) changes
all of these.

Third-party actions are pinned by commit. The wrappers' pin in
`dispatch.yml` and `review.yml` is a commit on jmarrero-forge/actions
main, the one the broker's policy names (upstream follows its dispatch
wrapper at main), and those wrappers pin their own actions at a commit
too. They run agentic-job v0.6.9, as `trial.yml` does, so the bounds are
upstream's `[github.*]` form. agent-board is the attested release binary of the
commit `AGENT_BOARD_REV` pins in `poll.yml`, moved only by a reviewed
change here.

The bot's write token is `JMARRERO_BOT_PAT`, an organization secret
available to this repository, as upstream's is `CGWALTERS_BOT_PAT`: any
job here can read it. `dispatch.yml` passes it to the wrapper as
`SAFE_OUTPUTS_PAT`, which hands it to apply, in the protected
`agent-apply` environment, and to status comments on items of other
repositories; `trial.yml` passes it for `implement` alone. Apply pushes a run's branch to jmarrero-bot's fork of the
target (jmarrero-bot/NAME, which apply creates if missing, with its
Actions turned off) and opens the pull request. A merged change to `.github/`, `workflow/`
or the `Justfile` needs jmarrero's review ([CODEOWNERS](.github/CODEOWNERS));
the agent's approval is enough elsewhere
([merge.toml](.github/agentic-job/merge.toml)).

### Resync

The controller files are cgwalters-forge/tracker's, copied verbatim in
one commit, then our diff in the next: identities, bounds, the Claude-only
[pools.json](.github/agentic-job/pools.json) (tracker#43), our wrappers
and secrets, and the preview gates above. A resync copies the same files
from upstream's main and applies that diff again. Upstream's auxiliary
callers are left out: the supervisor and sessions, the release train,
the weekly blog and eval, forge-sync, ruleset-check, the broker probe,
the agent-board pin bump, review-send and the tailnet test.

### Setup

Done by jmarrero, since the bot's token cannot (the bring-up walkthrough's
"Repository variables and secrets checklist"):

1. The environment `agent-apply` here, limited to the default branch
   (deployment branches: selected, `main`), with no secret: it gates
   apply, and `dispatch.yml` names it for every run.
2. The organization secret `JMARRERO_BOT_PAT`, available to selected
   repositories (this one only): a classic token of jmarrero-bot with the
   `repo`, `workflow`, `project` and `read:org` scopes. Apply needs `repo`
   and `workflow` (agentic-job docs/workflow.md, "Pull requests come from
   a fork"); the pass, once it applies (tracker#42), `project` and
   `read:org`.
3. The organization secret `JMARRERO_BOT_READ_TOKEN`, available to this
   repository only: a classic token of jmarrero-bot with `read:project`
   and `read:org`, which the preview pass reads with until cutover.
4. In the organization's Actions settings, if actions are restricted:
   allow `cgwalters-forge/agentic-job@*` and `jmarrero-forge/actions@*`,
   plus the third-party actions the workflows pin.
5. A ruleset on `main` here: require the `ci` check, one approving review
   with stale approvals dismissed on push, and review from code owners.
6. For real runs, once the broker admits the wrapper's pin
   (jmarrero/atomic-setup `bot/praxis-broker`): the Tailscale OIDC trust
   credential (Auth Keys: Write, tag `tag:agentic-job`, subject
   `repo:jmarrero-forge@336730605/tracker@1400840502:ref:refs/heads/main`),
   and two repository variables, `AGENTIC_JOB_TAILSCALE_OAUTH_CLIENT_ID`
   (its client id) and `INFERENCE_URL=http://<praxis-broker node IPv4>:8081`.
   The rest is committed: the tag in jmarrero-forge/actions'
   `tailscale/tailnets.json`, the audience `jmarrero-praxis-broker`, the
   agent `claude`, its model and configuration repository in its
   `deployment/deployment.json`. `AGENT_REVIEW` turns on the review
   workflow, once the broker admits its `pull_request_target` runs.

Then `gh workflow run trial.yml -R jmarrero-forge/tracker -f repo=jmarrero-forge/tracker -f kind=implement -f item=20`
tries the whole path with the scripted agent (after 1 and 2). It creates
jmarrero-bot/tracker, the bot's fork of this repository, if missing, turns
its Actions off and pushes the trial branch there.
