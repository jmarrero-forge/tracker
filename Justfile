# The checks and jobs of this repository's automation. Workflows call these
# recipes rather than inline scripts, so a check runs the same here and in CI.

# Recipes see their arguments as $1, $2, ...
set positional-arguments

# Every test of the files under .github.
test: test-agent-board-install test-config test-poll-bounds test-poll-next agent-board-pin

# poll must pass both of the fix bounds files dispatch selects per target.
test-poll-bounds:
    #!/usr/bin/env node
    const assert = require('node:assert/strict');
    const poll = require('node:fs').readFileSync('.github/workflows/poll.yml', 'utf8');
    const command = /"\$AGENT_BOARD" pass .*\\\n(?: {12}.*\\\n)* {12}.*\n/.exec(poll)?.[0];
    assert.ok(command, 'the agent-board pass command');
    assert.deepEqual([...command.matchAll(/--fix-bounds (\S+)/g)].map(m => m[1]),
      ['.github/agentic-job/fix.toml', '.github/agentic-job/midstream-fix.toml']);
    console.log('ok poll passes both fix bounds files to agent-board pass');

# poll's `next` step script, run with a stub agent-board that prints its
# arguments: the supervisor and release-train wakes are added only under
# their variables' gates. Every flag it passes is checked against the
# pinned CLI's help (AGENT_BOARD), which reads no token. The failure-only
# fallback uses runner tools and makes just one dispatch attempt.
test-poll-next:
    #!/usr/bin/env node
    const assert = require('node:assert/strict');
    const { execFileSync } = require('node:child_process');
    const fs = require('node:fs');
    const path = require('node:path');
    const poll = fs.readFileSync('.github/workflows/poll.yml', 'utf8');
    const step = /^ {6}- name: Start the next pass .*\n((?: {8}.*\n)+)/m.exec(poll)?.[1];
    assert.ok(step, 'the next pass step');
    assert.match(step, /^ {10}RELEASE_TRAIN: \$\{\{ vars\.RELEASE_TRAIN \}\}$/m);
    const script = /^ {8}run: \|\n((?: {10}.*\n)+)/m.exec(step)[1].replace(/^ {10}/gm, '');
    const temp = fs.mkdtempSync(path.join(require('node:os').tmpdir(), 'poll-next-'));
    const stub = path.join(temp, 'agent-board/bin/agent-board');
    fs.mkdirSync(path.dirname(stub), { recursive: true });
    fs.writeFileSync(stub, '#!/bin/sh\nprintf "%s\\n" "$@"\n', { mode: 0o755 });
    const run = (env) => execFileSync('bash', ['--noprofile', '--norc', '-eo', 'pipefail', '-c', script], {
      env: { PATH: process.env.PATH, RUNNER_TEMP: temp, DEFAULT_BRANCH: 'main', SUPERVISOR: '', RELEASE_TRAIN: '', ...env },
    }).toString().trimEnd().split('\n');
    const base = ['pass', 'next', '--workflow', 'poll.yml', '--branch', 'main', '--input', 'apply=true',
      '--apply-title', 'pass (apply)', '--wait-minutes', '10'];
    const supervisor = ['--supervisor-workflow', 'supervisor.yml', '--supervisor-stale-minutes', '30',
      '--supervisor-input', 'prompt=', '--supervisor-input', 'session=false'];
    const train = ['--train-workflow', 'release-train.yml', '--train-stale-minutes', '60'];
    for (const value of ['', 'enabled', 'Apply', ' apply', 'dry-run ', 'preview']) {
      assert.deepEqual(run({ RELEASE_TRAIN: value }), base, `RELEASE_TRAIN=${JSON.stringify(value)}`);
    }
    for (const value of ['dry-run', 'apply']) {
      assert.deepEqual(run({ RELEASE_TRAIN: value }), [...base, ...train], `RELEASE_TRAIN=${value}`);
    }
    for (const [value, enabled] of [['off', false], ['preview', true], ['apply', true]]) {
      assert.deepEqual(run({ SUPERVISOR: value }), enabled ? [...base, ...supervisor] : base, `SUPERVISOR=${value}`);
    }
    const all = run({ SUPERVISOR: 'preview', RELEASE_TRAIN: 'apply' });
    assert.deepEqual(all, [...base, ...supervisor, ...train]);
    fs.rmSync(temp, { recursive: true });
    console.log('ok poll next wakes the supervisor and release train only under their gates');
    if (process.env.AGENT_BOARD) {
      const help = execFileSync(process.env.AGENT_BOARD, ['pass', 'next', '--help']).toString();
      for (const flag of new Set(all.filter(arg => arg.startsWith('--')))) {
        assert.match(help, new RegExp(`${flag}(?![\\w-])`), `${flag} in agent-board pass next --help`);
      }
      console.log('ok the pinned agent-board pass next takes every flag poll next passes');
    } else {
      console.log('skipped: set AGENT_BOARD to check the flags against the pinned CLI');
    }
    const fallback = /^ {2}next-fallback:\n([\s\S]+)$/m.exec(poll)?.[1];
    assert.ok(fallback, 'the final fallback job');
    assert.match(fallback, /^ {4}needs: next$/m);
    const gate = /^ {4}if: \$\{\{ (.*) \}\}$/m.exec(fallback)[1];
    for (const result of ['success', 'failure', 'cancelled', 'skipped']) {
      for (const cancelled of [false, true]) {
        for (const apply of ['', 'enabled', 'disabled']) {
          const got = require('node:vm').runInNewContext(gate, {
            cancelled: () => cancelled, needs: { next: { result } }, vars: { PASS_APPLY: apply },
          });
          assert.equal(got, result === 'failure' && !cancelled && apply === 'enabled');
        }
      }
    }
    assert.match(fallback, /^ {4}timeout-minutes: 12$/m);
    assert.match(fallback, /^ {4}permissions:\n {6}actions: write\n {4}steps:/m);
    assert.doesNotMatch(fallback, /uses:|continue-on-error:|^ {2}\S/m);
    assert.equal((fallback.match(/^ {6}- /gm) ?? []).length, 1, 'one step without setup');
    assert.match(fallback, /^ {10}GH_TOKEN: \$\{\{ github.token \}\}$/m);
    assert.match(fallback, /^ {10}DEFAULT_BRANCH: \$\{\{ github.event.repository.default_branch \}\}$/m);
    const recovery = /^ {8}run: \|\n((?: {10}.*\n)+)/m.exec(fallback)[1].replace(/^ {10}/gm, '');
    const sandbox = fs.mkdtempSync(path.join(require('node:os').tmpdir(), 'poll-fallback-'));
    try {
      fs.writeFileSync(path.join(sandbox, 'gh'), '#!/bin/bash\nif [[ $1 == api ]]; then printf "%s\\n" "$*" >&2; printf "2026-11-02T17:51:00Z\\n"; exit "${API_EXIT:-0}"; fi\nprintf "%s\\n" "$*"\nexit "${DISPATCH_EXIT:-0}"\n', { mode: 0o755 });
      fs.writeFileSync(path.join(sandbox, 'date'), '#!/bin/bash\nif [[ $1 == -d ]]; then printf "1000\\n"; else printf "%s\\n" "$NOW"; fi\n', { mode: 0o755 });
      fs.writeFileSync(path.join(sandbox, 'sleep'), '#!/bin/bash\nprintf "sleep %s\\n" "$*"\n', { mode: 0o755 });
      const api = 'api repos/owner/repo/actions/runs/42 --jq .run_started_at';
      const dispatch = 'workflow run poll.yml --repo owner/repo --ref main -f apply=true';
      const recover = (env) => require('node:child_process').spawnSync('bash', ['--noprofile', '--norc', '-eo', 'pipefail', '-c', recovery], {
        env: { PATH: `${sandbox}:${process.env.PATH}`, GITHUB_REPOSITORY: 'owner/repo', GITHUB_RUN_ID: '42', DEFAULT_BRANCH: 'main', ...env }, encoding: 'utf8',
      });
      for (const [now, delay] of [['1120', '480'], ['1600', null], ['1900', null], ['900', '600']]) {
        const got = recover({ NOW: now });
        assert.equal(got.status, 0, got.stderr);
        assert.equal(got.stderr.trimEnd(), api);
        assert.deepEqual(got.stdout.trimEnd().split('\n'), [...(delay ? [`sleep ${delay}`] : []), dispatch]);
      }
      const failed = recover({ NOW: '1900', DISPATCH_EXIT: '1' });
      assert.equal(failed.status, 1, 'dispatch failure stays visible');
      assert.equal(failed.stderr.trimEnd(), api);
      assert.deepEqual(failed.stdout.trimEnd().split('\n'), [dispatch], 'no retry on failure');
      const unreadable = recover({ NOW: '1900', API_EXIT: '1' });
      assert.equal(unreadable.status, 1);
      assert.equal(unreadable.stderr.trimEnd(), api);
      assert.equal(unreadable.stdout, '', 'API failure stops recovery');
    } finally {
      fs.rmSync(sandbox, { recursive: true, force: true });
    }
    console.log('ok poll fallback is failure-only, waits at most ten minutes and dispatches once');

# The one agent-board commit every workflow pins as `  AGENT_BOARD_REV:`,
# printed; fails when the workflows pin different revisions, or none, so a
# move by hand cannot miss a workflow.
agent-board-pin:
    #!/usr/bin/env bash
    set -euo pipefail
    pins=$(sed -n 's/^  AGENT_BOARD_REV: //p' .github/workflows/*.yml | sort -u)
    if ! [[ $pins =~ ^[0-9a-f]{40}$ ]]; then
      echo "::error::.github/workflows pin more than one agent-board revision, or none:" >&2
      grep -H '^  AGENT_BOARD_REV:' .github/workflows/*.yml >&2 || true
      exit 1
    fi
    echo "$pins"

# The runner configuration's checks; those that run `agentic-job` skip where
# it is not installed. The build goes outside the source tree.
test-config:
    cargo test --locked --manifest-path .github/agentic-job/config-test/Cargo.toml --target-dir "{{ env('CARGO_TARGET_DIR', cache_directory() / 'tracker-config-test') }}"

# No moving refs or source fallback: substituted assets must not run with the
# bot's write token. The attested manifest binds both digests to reviewed CI.
build-agent-board rev=env("AGENT_BOARD_REV", ""):
    #!/usr/bin/env bash
    set -euo pipefail
    rev=$1
    [[ $rev =~ ^[0-9a-f]{40}$ ]] || { echo 'expected a pinned 40-character AGENT_BOARD_REV' >&2; exit 1; }
    [[ $(uname -s)-$(uname -m) == Linux-x86_64 ]] || { echo 'agent-board binaries support only Linux x86_64' >&2; exit 1; }
    repo=cgwalters-forge/agent-board target=x86_64-unknown-linux-musl
    tag=build-$rev
    dest=$RUNNER_TEMP/agent-board/bin
    mkdir -p "$dest"
    rm -f "$dest/agent-board"
    stage=$(mktemp -d "$RUNNER_TEMP/agent-board-download.XXXXXX")
    trap 'rm -rf "$stage"' EXIT
    timeout 180 gh release download "$tag" --repo "$repo" --dir "$stage" \
      --pattern "*-$target" --pattern SHA256SUMS --pattern release.json --pattern provenance.jsonl
    GH_TOKEN='' GITHUB_TOKEN='' timeout 180 gh attestation verify "$stage/release.json" \
      --bundle "$stage/provenance.jsonl" --repo "$repo" \
      --cert-identity "https://github.com/$repo/.github/workflows/ci.yml@refs/heads/main" \
      --source-ref refs/heads/main --source-digest "$rev" --deny-self-hosted-runners
    jq -e --arg repo "$repo" --arg tag "$tag" --arg commit "$rev" --arg target "$target" \
      '.schema == "agent-board.release.v1" and .repository == $repo and .tag == $tag and .commit == $commit and .target == $target' "$stage/release.json" > /dev/null
    # Accept only the two fixed filenames, never paths supplied by a manifest.
    node -e 'const fs = require("node:fs"); const d = process.argv[1]; const s = JSON.parse(fs.readFileSync(d + "/release.json")).sha256sums; if (typeof s !== "string" || !/^[0-9a-f]{64}  agent-board-x86_64-unknown-linux-musl\n[0-9a-f]{64}  gh-agent-board-x86_64-unknown-linux-musl\n$/.test(s)) throw Error("invalid release checksums"); fs.writeFileSync(d + "/attested-SHA256SUMS", s);' "$stage"
    cmp "$stage/SHA256SUMS" "$stage/attested-SHA256SUMS"
    (cd "$stage" && sha256sum --check attested-SHA256SUMS)
    install -m 755 "$stage/agent-board-$target" "$dest/agent-board"
    echo "rev=$rev" >> "${GITHUB_OUTPUT:-/dev/null}"
    echo "Installed agent-board $rev ($target)"

# Offline transport fixtures exercise the real installer; no network or token.
test-agent-board-install:
    #!/usr/bin/env node
    const assert = require('node:assert/strict');
    const fs = require('node:fs');
    const os = require('node:os');
    const path = require('node:path');
    const { spawnSync } = require('node:child_process');
    const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'agent-board-install-'));
    const rev = 'a'.repeat(40);
    const target = 'x86_64-unknown-linux-musl';
    const stub = `#!/usr/bin/env node
    const fs = require('node:fs'), path = require('node:path'), crypto = require('node:crypto');
    const args = process.argv.slice(2), mode = process.env.CASE;
    if (args[0] === 'attestation') {
      if (process.env.GH_TOKEN || process.env.GITHUB_TOKEN) process.exit(9);
      for (const s of ['--source-digest', '${rev}', '--deny-self-hosted-runners', 'https://github.com/cgwalters-forge/agent-board/.github/workflows/ci.yml@refs/heads/main']) if (!args.includes(s)) process.exit(8);
      process.exit(mode === 'attestation' ? 1 : 0);
    }
    if (['missing-release', 'download'].includes(mode)) process.exit(1);
    const d = args[args.indexOf('--dir') + 1];
    let sums = '';
    for (const n of ['agent-board', 'gh-agent-board']) {
      const name = n + '-${target}', data = '#!/bin/sh\\nexit 0\\n';
      fs.writeFileSync(path.join(d, name), data);
      sums += crypto.createHash('sha256').update(data).digest('hex') + '  ' + name + '\\n';
    }
    fs.writeFileSync(path.join(d, 'SHA256SUMS'), mode === 'sums' ? 'bad' : sums);
    fs.writeFileSync(path.join(d, 'release.json'), JSON.stringify({schema: 'agent-board.release.v1', repository: 'cgwalters-forge/agent-board', tag: 'build-${rev}', commit: mode === 'commit' ? 'b'.repeat(40) : '${rev}', target: '${target}', sha256sums: sums}));
    fs.writeFileSync(path.join(d, 'provenance.jsonl'), 'fixture');
    if (mode === 'integrity') fs.appendFileSync(path.join(d, 'agent-board-${target}'), 'tampered');
    if (mode === 'missing-asset') fs.unlinkSync(path.join(d, 'agent-board-${target}'));
    `;
    try {
      fs.writeFileSync(path.join(dir, 'gh'), stub, {mode: 0o755});
      fs.writeFileSync(path.join(dir, 'uname'), '#!/bin/sh\nif [ "$CASE" = platform ]; then printf Darwin; else /usr/bin/uname "$@"; fi\n', {mode: 0o755});
      for (const mode of ['ok', 'missing-release', 'missing-asset', 'platform', 'download', 'attestation', 'commit', 'sums', 'integrity', 'revision']) {
        const temp = fs.mkdtempSync(path.join(dir, 'run-'));
        const output = path.join(temp, 'output');
        const result = spawnSync('{{ just_executable() }}', ['build-agent-board', mode === 'revision' ? '' : rev], {encoding: 'utf8', env: {...process.env, PATH: `${dir}:${process.env.PATH}`, RUNNER_TEMP: temp, GITHUB_OUTPUT: output, GH_TOKEN: '', GITHUB_TOKEN: '', CASE: mode}});
        assert.equal(result.status === 0, mode === 'ok', `${mode}: ${result.stdout}\n${result.stderr}`);
        assert.equal(fs.existsSync(path.join(temp, 'agent-board/bin/agent-board')), mode === 'ok', mode);
        if (mode === 'ok') assert.equal(fs.readFileSync(output, 'utf8'), `rev=${rev}\n`);
        else assert.equal(fs.existsSync(output), false, mode);
        console.log(`ok agent-board installer: ${mode}`);
      }
      const pins = fs.mkdtempSync(path.join(dir, 'pins-'));
      fs.mkdirSync(path.join(pins, '.github/workflows'), {recursive: true});
      fs.copyFileSync('Justfile', path.join(pins, 'Justfile'));
      const checkPin = () => spawnSync('{{ just_executable() }}', ['agent-board-pin'], {cwd: pins, encoding: 'utf8'});
      fs.writeFileSync(path.join(pins, '.github/workflows/a.yml'), `env:\n  AGENT_BOARD_REV: ${rev}\n`);
      assert.equal(checkPin().stdout.trim(), rev);
      fs.writeFileSync(path.join(pins, '.github/workflows/b.yml'), `env:\n  AGENT_BOARD_REV: ${'b'.repeat(40)}\n`);
      assert.notEqual(checkPin().status, 0);
      console.log('ok agent-board pin agreement and mismatch');
    } finally { fs.rmSync(dir, {recursive: true, force: true}); }

# The shared workflow check that ci.yml's lint job calls, run locally from
# a checkout of the forge's actions repository (its lint/README.md), the
# path relative to this repository's root; CONTAINER=podman without docker:
#   just lint ../actions
lint actions:
    {{ just_executable() }} --justfile "{{ actions }}/lint/Justfile" --working-directory . check
