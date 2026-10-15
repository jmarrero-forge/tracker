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
[agentic-job](https://github.com/cgwalters-forge/agentic-job) runs for
jmarrero-forge, adapted from cgwalters-forge/tracker. It is being brought
up beside the current bot (tracker#17): nothing here writes to the board or
to other repositories' pull requests yet.

| Workflow | What it does | Status |
| --- | --- | --- |
| [dispatch](.github/workflows/dispatch.yml) | One agent run (`implement`, `triage`, `research`, `review` or `fix`) on an item of a repository in the [bounds](.github/agentic-job/dispatch.toml), through jmarrero-forge/actions' `jmarrero-agentic-job.yml`; the kind's [profile](.github/agentic-job/profiles) goes before the task | Waits for the broker (tracker#19) and the setup below |
| [trial](.github/workflows/trial.yml) | The same path with agentic-job's scripted agent, against this repository: no model, broker or tailnet | Waits for the secret and environment below |
| [poll](.github/workflows/poll.yml) | agent-board's pull request poll, the board scheduler and the epic coordinator, every 30 minutes | Preview only: each run's summary says what it would have done |
| [review](.github/workflows/review.yml) | An agent's review of every pull request here, through `jmarrero-review.yml` | Off until the variable `AGENT_REVIEW` is set |
| [ci](.github/workflows/ci.yml) | The scripts' tests (`just test`), actionlint and zizmor, and that the bounds parse | On |

Every action and reusable workflow is pinned by commit, and agent-board is
built at the commit [agent-board.json](.github/poll/agent-board.json) pins.
The wrappers' pin in `dispatch.yml` and `review.yml` is a placeholder until
jmarrero-forge/actions#1 merges, then the main commit the broker's policy
names.

The bot's write token reaches one job: apply's, which runs in the
`agent-apply` environment, the only place it is stored. There it pushes a
run's branch to jmarrero-bot's fork of the target (jmarrero-bot/NAME,
which apply creates if missing, with its Actions turned off) and opens the
pull request. Status comments write with the job token. The poll,
scheduler and coordinator read with a separate token that can write
nothing.

agent-board's poll still ends its comments with cgwalters' `Generated-by`
line, which it does not yet take from configuration; `generatedBy` there
records ours for when it does. A merged change to `.github/`, `workflow/`
or the `Justfile` needs jmarrero's review ([CODEOWNERS](.github/CODEOWNERS));
the agent's approval is enough elsewhere
([merge.toml](.github/agentic-job/merge.toml)).

### Setup

Done by jmarrero, since the bot's token cannot:

1. The environment `agent-apply` here, limited to the default branch
   (deployment branches: selected, `main`), with one environment secret,
   `SAFE_OUTPUTS_PAT`: a classic token of jmarrero-bot with the `repo` and
   `workflow` scopes. Not an organization or repository secret: only the
   apply job enters the environment.
2. The organization secret `JMARRERO_BOT_READ_TOKEN`: a classic token of
   jmarrero-bot with only the `read:project` scope, for the poll's board
   reads (every followed repository is public, which needs no scope). A
   fine-grained token also works if the organization allows them:
   resource owner jmarrero-forge, organization permission Projects
   read-only, public repositories read-only.
3. In the organization's Actions settings, if actions are restricted:
   allow `cgwalters-forge/agentic-job@*` and `jmarrero-forge/actions@*`,
   plus the third-party actions the workflows pin.
4. A ruleset on `main` here: require the `ci` check, one approving review
   with stale approvals dismissed on push, and review from code owners.
5. For real runs, once the broker is up: the Tailscale OIDC trust
   credential (Auth Keys: Write, tag `tag:agentic-job`, subject
   `repo:jmarrero-forge@336730605/tracker@1400840502:ref:refs/heads/main`),
   and the repository variables `TAILSCALE_OAUTH_CLIENT_ID` (its client
   id), `TAILSCALE_TAGS=tag:agentic-job`,
   `INFERENCE_URL=http://<praxis-broker node IPv4>:8081`,
   `INFERENCE_AUDIENCE=jmarrero-praxis-broker` and `AGENT=claude`.
   `AGENT_REVIEW` turns on the review workflow, once the broker admits its
   `pull_request_target` runs.

Then `gh workflow run trial.yml -R jmarrero-forge/tracker -f kind=implement -f item=20`
tries the whole path with the scripted agent (after 1 and 3). It creates
jmarrero-bot/tracker, the bot's fork of this repository, if missing, turns
its Actions off and pushes the trial branch there.
