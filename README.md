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
[agent-board](https://github.com/jmarrero-forge/agent-board)'s pass and
promotion for jmarrero-forge: cgwalters-forge/tracker's controller,
retargeted (see Resync). Nothing here writes to the board or to other
repositories until the variables below are set (tracker#42).

| Workflow | What it does | Status |
| --- | --- | --- |
| [dispatch](.github/workflows/dispatch.yml) | One agent run (`implement`, `triage`, `research`, `review` or `fix`) on an item of a repository in the bounds ([dispatch.toml](.github/agentic-job/dispatch.toml), comment-only kinds [comment.toml](.github/agentic-job/comment.toml), PR recovery [recovery.toml](.github/agentic-job/recovery.toml), fixes [fix.toml](.github/agentic-job/fix.toml), the forge's forks with the `bot-midstream` topic [midstream.toml](.github/agentic-job/midstream.toml) and [midstream-fix.toml](.github/agentic-job/midstream-fix.toml)), through jmarrero-forge/actions' `cgwalters-agentic-job.yml`; the kind's [profile](.github/agentic-job/profiles) goes before the task | By hand, and by the pass once it applies |
| [trial](.github/workflows/trial.yml) | The same path with agentic-job's scripted agent, against this repository: no model, broker or tailnet | By hand |
| [poll](.github/workflows/poll.yml) | `agent-board pass` on [pass.json](.github/pass.json) every 10 minutes: pull request follow-up and board Status | Applies while the variable `PASS_APPLY` is `enabled`; otherwise each run's summary says what it would have done |
| [promote](.github/workflows/promote.yml) | `agent-board promote`: an approved draft in a midstream fork goes upstream, with jmarrero's `Signed-off-by` | Off until the variable `PROMOTE` is `enabled` |
| [review](.github/workflows/review.yml) | An agent's review of every pull request here, through `cgwalters-review.yml` | Off until the variable `AGENT_REVIEW` is set |
| [ci-health](.github/workflows/ci-health.yml) | Daily at 06:43 UTC, `agent-board ci-health` over the upstreams' CI ([config.json](.github/ci-health/config.json)): a 30-day report of pass rates and failure groups, read-only (see [CI health](#ci-health)) | Report only: [publication.json](.github/ci-health/publication.json) is `publish: false` and no status issue is named |
| [ci](.github/workflows/ci.yml) | `just test` (agent-board's installer, the config tests, `pass --check-config`, the poll's checks), actionlint and zizmor, that the bounds parse, and that scripts only shrink | On |

The pass follows the bot's pull requests here and in
jmarrero-forge/actions, and in the forge's forks with the `bot-midstream`
topic (never merging there), and derives every board item's Status, with
upstream's caps (`--max-dispatch 20 --max-writes 60
--max-status-changes 50`). It starts board work as upstream's does,
within pass.json's `wip` and the `claude` pool; a lane left off
(`sessions`, `mix`) is a pull request of its own. From 09:00 UTC each
day it also plans the maintainer digest (`maintain`, agent-board's
docs/pass.md, "Maintain"): one `research` run, reserving a fifth of the
pool's allowance while it is due, that sorts the incoming pull requests
of ostreedev/ostree and coreos/rpm-ostree into one comment on
[tracker#117](https://github.com/jmarrero-forge/tracker/issues/117) and
writes nothing upstream. `--apply` is passed
only while the variable `PASS_APPLY` is `enabled`, whether the pass is
scheduled or started by hand (upstream lets a manual `apply=true`
through without it), so unsetting `PASS_APPLY` stops every write and
ends the chain of `next` passes.

Promotion is upstream's: once `PROMOTE` is `enabled`, every 15 minutes
`promote.yml` runs `agent-board promote --apply --max-writes 4` with
`JMARRERO_BOT_PAT`. A candidate is a draft pull request of
jmarrero-bot's on a `bot/` or `dispatch/` branch of a jmarrero-forge fork
with the `bot-midstream` topic and the `origin=fork` custom property. It
publishes when jmarrero's (pass.json's `operator`) latest deciding review
approves the draft's current head, submitted after its last push; his
`/promote` comment marks it too, but publishing still needs that
approval. It then rebases the branch on the upstream's default branch,
adds `Signed-off-by: Joseph Marrero Corchado <jmarrero@redhat.com>`
(pass.json's `promote.signoff`) to every commit that lacks it, whether or
not the upstream requires DCO, and opens the upstream pull request as a
draft from a new `bot/promote/` branch. It holds unless the upstream's
record in [upstream-policy/](upstream-policy) is `bot-ok` (or
`human-text` with `/promote --human-text`), current with the upstream's
files, and loosened by no one but jmarrero; a new record counts as its
own baseline. The records are homegit's, ported, and need his review
here through [CODEOWNERS](.github/CODEOWNERS) once the ruleset on `main`
requires code-owner review. `PROMOTE` guards against turning it on by
accident, not against the bot, whose token can set variables; his
approval is what agent-board checks.

Third-party actions are pinned by commit. The wrappers' pin in
`dispatch.yml` and `review.yml` is one commit on jmarrero-forge/actions
main, the one the broker's policy names (jmarrero/atomic-setup
`bot/praxis-broker`), and those wrappers pin their own actions at a
commit too. They run agentic-job v0.6.15. agent-board is the attested
CI binary of the commit `AGENT_BOARD_REV` pins in every workflow, moved
only by a reviewed change here. It comes from our fork,
jmarrero-forge/agent-board, rather than cgwalters-forge/agent-board, so
fixes merged there (such as the pass signing with its own `generatedBy`)
reach the pass without waiting on upstream (tracker#108): the pin is a
commit on the fork's main, and the installer accepts only an attestation
from the fork's `ci.yml` on main. A CI artifact expires after 90 days, so
the pin moves, or the fork releases that commit, before its artifact
does.

The bot's write token is `JMARRERO_BOT_PAT`, an organization secret
available to this repository, as upstream's is `CGWALTERS_BOT_PAT`: any
job here can read it. Promotion, and the pass when it applies, read and
write with it; a preview reads with `JMARRERO_BOT_READ_TOKEN`.
`dispatch.yml` passes it to the wrapper as `SAFE_OUTPUTS_PAT`, which
hands it to apply, in the protected `agent-apply` environment, and to
status comments on items of other repositories; `trial.yml` passes it
for `implement` alone. Apply pushes a run's branch to jmarrero-bot's fork of the
target (jmarrero-bot/NAME, which apply creates if missing, with its
Actions turned off) and opens the pull request. A merged change to `.github/`, `workflow/`,
`upstream-policy/` or the `Justfile` needs jmarrero's review ([CODEOWNERS](.github/CODEOWNERS));
the agent's approval is enough elsewhere
([merge.toml](.github/agentic-job/merge.toml)).

### Resync

The controller files are cgwalters-forge/tracker's, copied verbatim in
one commit, then our diff in the next: identities, bounds (our own
repositories by name, since all but this one are GitHub forks; the
midstream forks by upstream's topic rule), the Claude-only
[pools.json](.github/agentic-job/pools.json) (tracker#43), our wrappers
and secrets, the `PASS_APPLY` and `PROMOTE` gates, the policy records,
and the config tests and Justfile recipes for what we run. Our diff
also installs agent-board from jmarrero-forge/agent-board (the
Justfile's `agent_board_repo`, the installer fixtures in
[agent-board-install](.github/agent-board-install) and their test): a
resync keeps that, and moves `AGENT_BOARD_REV` only to a commit on the
fork's main, merging upstream's agent-board there first. A resync
copies the same files from upstream's main and applies that diff again.
Upstream's auxiliary callers and their files are left out: the
supervisor and sessions, the release train, the retro, soak, weekly
blog, eval and comparison, the CI-health retention rehearsal, the review
corpus and refresh, maintain-shadow, midstream-sync, forge-sync,
ruleset-check, the broker probe, the agent-board pin bump,
review-send, the tailnet test, the misctool secondary bounds and the
recorded-incident replay.

### CI health

`ci-health.yml` is upstream's, retargeted: once a day it collects 30 days
of the default-branch push and pull-request runs of ostreedev/ostree's
`tests.yml`, `rust.yml` and `bootc.yaml` and coreos/rpm-ostree's `ci.yaml`
with the job token, then renders the saved JSON into the run's summary
and dated artifacts. It reads the upstreams' public Actions history only:
it checks out none of their code and writes nothing there, and an empty
or incomplete population is reported as such, never as passing. The
collector is the pass's agent-board pin, so it moves with
`AGENT_BOARD_REV`. Upstream also keeps a status comment on an issue;
ours names no issue yet, so the renderer refuses to publish even if
`publication.json` is turned on, until one is named in the workflow.
ci.yml's test job runs upstream's offline tests of the renderer
(`just test-ci-health`).

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
   a fork"); the pass and promotion read the board and the forks with it
   and make their writes as it, which needs `project` and `read:org`, and
   `workflow` too, since GitHub refuses to merge a pull request that
   changes `.github/workflows` without it.
3. The organization secret `JMARRERO_BOT_READ_TOKEN`, available to this
   repository only: a classic token of jmarrero-bot with `read:project`
   and `read:org`, which a pass that doesn't apply reads with.
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
7. When cutting over (tracker#42), the repository variable
   `PASS_APPLY=enabled`. For promotion, in this order: turn on "Require
   review from Code Owners" (and dismissal of stale approvals) in the
   ruleset on `main`; stop homegit's promotions (`bot-watch --apply` and
   `bot-promote-due`), which would act on the same approval; give each
   midstream fork the `bot-midstream` topic and, in the organization's
   settings, a custom property `origin` with the value `fork`
   (agent-board publishes only from a fork with both); run
   `promote.yml`'s command once without `--apply` to preview; then set
   `PROMOTE=enabled`.

Then `gh workflow run trial.yml -R jmarrero-forge/tracker -f repo=jmarrero-forge/tracker -f kind=implement -f item=20`
tries the whole path with the scripted agent (after 1 and 2). It creates
jmarrero-bot/tracker, the bot's fork of this repository, if missing, turns
its Actions off and pushes the trial branch there.
