# The checks and jobs of this repository's automation. Workflows call these
# recipes rather than inline scripts, so a check runs the same here and in CI.

# Recipes see their arguments as $1, $2, ...
set positional-arguments

# Repository and workflow checks run by CI.
test: test-runner-profiles test-agent-board-install test-config test-pass-config test-poll-bounds test-poll-next test-pass-state agent-board-pin test-agent-board-bump

# Execute the workflow's actual resolver, without credentials or forge traffic.
test-runner-profiles:
    #!/usr/bin/env node
    const assert = require('node:assert/strict');
    const fs = require('node:fs');
    const { spawnSync } = require('node:child_process');
    const workflow = fs.readFileSync('.github/workflows/dispatch.yml', 'utf8');
    const gate = workflow.split('\n  runner-gate:\n')[1].split('\n  # Threat:')[0];
    const script = /          python3 - <<'PY'\n([^]*?)          PY/.exec(gate)[1].replace(/^          /gm, '');
    const mapPath = '.github/agentic-job/runner-profiles.json';
    const example = JSON.parse(fs.readFileSync(mapPath));
    assert.ok(Object.values(example).every(p => p.enabled === false));
    const name = Object.keys(example)[0], target = change => JSON.stringify({ full_name: 'jmarrero-forge/bootc', owner: { login: 'jmarrero-forge' }, fork: true, topics: ['ci', 'bot-midstream'], ...change });
    const temp = fs.mkdtempSync(require('node:path').join(require('node:os').tmpdir(), 'runner-profile-'));
    const env = { RUNNER_PROFILE: name, KIND: 'implement', REPO: 'jmarrero-forge/bootc',
      POOL: '', EFFORT: '', CONFIG: 'hosted', DETECT_MODEL: 'deployment-model',
      CALLER_REF: 'refs/heads/main', DEFAULT_BRANCH: 'main', TARGET: target({}) };
    const run = (map, extra = {}) => {
      if (map === undefined) fs.rmSync(`${temp}/${mapPath}`, { force: true });
      else fs.writeFileSync(`${temp}/${mapPath}`, typeof map === 'string' ? map : JSON.stringify(map));
      return spawnSync('python3', ['-c', script], { cwd: temp, encoding: 'utf8', env: { ...process.env, ...env, ...extra } });
    };
    const refuse = (map, extra, reason) => {
      const result = run(map, extra);
      assert.notEqual(result.status, 0, reason);
      assert.ok(result.stderr.includes(reason), result.stderr);
      assert.equal(result.stdout, '', 'resolver releases no execution selectors');
    };
    const enabled = structuredClone(example);
    enabled[name].enabled = true;
    try {
      fs.mkdirSync(`${temp}/.github/agentic-job`, { recursive: true });
      fs.copyFileSync('.github/agentic-job/midstream.toml', `${temp}/.github/agentic-job/midstream.toml`);
      for (const map of [undefined, '{', { hosted: {} }]) assert.equal(run(map, { RUNNER_PROFILE: 'hosted' }).status, 0);
      refuse('{', {}, 'JSONDecodeError');
      refuse(undefined, {}, 'FileNotFoundError');
      refuse(example, { RUNNER_PROFILE: 'unknown' }, 'unknown runner');
      refuse(example, {}, 'disabled');
      refuse(enabled, {}, 'unimplemented');
      for (const kind of ['fix', 'review', 'research', 'triage']) refuse(enabled, { KIND: kind }, 'requires implement');
      for (const [repo, change] of [['jmarrero-forge/tracker', { full_name: 'jmarrero-forge/tracker', fork: false }], ['jmarrero-forge/bootc', { topics: ['bot-fork'] }], ['bootc-dev/bootc', { full_name: 'bootc-dev/bootc', owner: { login: 'bootc-dev' } }], ['jmarrero-forge/bootc', { full_name: 'jmarrero-forge/ostree-x' }]]) refuse(enabled, { REPO: repo, TARGET: target(change) }, 'outside midstream');
      for (const [key, value, reason] of [['POOL', 'claude', 'pool/effort'], ['EFFORT', 'heavy', 'pool/effort'],
        ['CONFIG', 'acp-experiment', 'hosted config'], ['DETECT_MODEL', '', 'detection configuration'],
        ['DETECT_MODEL', '  ', 'detection configuration'], ['CALLER_REF', 'refs/heads/other', 'default branch']]) refuse(enabled, { [key]: value }, reason);
      for (const change of [p => { delete p.commit; }, p => { p.extra = true; }, p => { p.enabled = 'false'; },
        p => { p.kvm = 1; }, p => { p.libvirt = 'system'; }, p => { p.libvirt = null; },
        p => { p.repository = 'https://example/repo'; }, p => { p.workflow = '../agent.yml'; },
        p => { p.ref = 'main..other'; }, p => { p.inputs.cores = 64; }, p => { p.inputs.task = 'override'; },
        p => { p.inputs = []; }, p => { p.limits.extra = 1; }, p => { delete p.limits.vcpus; },
        p => { p.limits['lifetime-minutes'] = 331; }, p => { p.limits['lifetime-minutes'] = 240; }]) {
        const map = structuredClone(enabled); change(map[name]);
        refuse(map, { RUNNER_PROFILE: 'unknown' }, 'runner'); // Whole map is validated, not just selected entry.
        assert.ok(!run(map).stderr.includes('unimplemented'));
      }
      for (const pin of ['commit', 'agentic-job', 'actions']) for (const value of ['main', 'a'.repeat(39), 'A'.repeat(40)]) {
        const map = structuredClone(enabled); map[name][pin] = value; refuse(map, {}, 'immutable');
      }
      for (const key of Object.keys(enabled[name].limits)) for (const value of [0, -1, 1.5, true, '1', null]) {
        const map = structuredClone(enabled); map[name].limits[key] = value; refuse(map, {}, 'positive integers');
      }
      for (const badName of ['hosted', 'Bad', '../runner', 'x'.repeat(33)]) refuse({ [badName]: enabled[name] }, {}, 'profile name');
      for (const map of ['[]', 'null', '{"x":{},"x":{}}']) refuse(map, {}, map.includes('"x"') ? 'duplicate' : 'object');
      const ceiling = structuredClone(enabled); ceiling[name].limits['lifetime-minutes'] = 330;
      delete ceiling[name].libvirt;
      refuse(ceiling, { REPO: 'JMARRERO-FORGE/BOOTC' }, 'unimplemented');
      assert.match(gate, /if: inputs.runner != 'hosted'/);
      assert.match(gate, /repository: \$\{\{ github.repository \}\}/);
      assert.match(gate, /ref: \$\{\{ github.sha \}\}/);
      assert.doesNotMatch(gate, /inputs.task|secrets\.|actions: write|workflow_dispatch|GITHUB_OUTPUT/);
      for (const job of ['profile', 'review-gate']) assert.match(workflow, new RegExp(`  ${job}:\\n    needs: runner-gate`));
      assert.match(workflow, /  run:\n    needs: profile/);
      assert.match(workflow, /  review:\n    needs: review-gate/);
      assert.match(workflow, /      runner:\n[^]*?default: hosted/);
      assert.doesNotMatch(workflow, /runner: \$\{\{ inputs.runner/);
      console.log('ok runner map validation, hosted bypass and workflow boundary (external execution remains unimplemented)');
    } finally { fs.rmSync(temp, { recursive: true, force: true }); }

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
# pinned CLI's help (AGENT_BOARD), which reads no token. Best-effort recovery
# uses runner tools and makes just one dispatch attempt. Fixtures are not
# live proof of GitHub's missing-job behavior or schedule delivery.
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
      env: { PATH: process.env.PATH, RUNNER_TEMP: temp, DEFAULT_BRANCH: 'main', GITHUB_RUN_ID: '42', SUPERVISOR: '', RELEASE_TRAIN: '', ...env },
    }).toString().trimEnd().split('\n');
    const base = ['pass', 'next', '--workflow', 'poll.yml', '--branch', 'main', '--input', 'apply=true',
      '--input', 'previous_run_id=42', '--apply-title', 'pass (apply)', '--wait-minutes', '10'];
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
    assert.match(fallback, /^ {4}needs: \[pass, next\]$/m);
    const gate = /^ {4}if: >-\n((?: {6}.*\n)+)/m.exec(fallback)[1].trim().replace(/^\$\{\{ | \}\}$/g, '');
    for (const result of ['success', 'failure', 'cancelled', 'skipped', '']) {
      for (const pass of ['success', 'failure', 'cancelled', 'skipped', '']) {
      for (const cancelled of [false, true]) {
        for (const apply of ['', 'enabled', 'disabled']) {
          for (const event of ['schedule', 'workflow_dispatch', 'push']) {
          for (const applying of [false, true]) {
          for (const ref of ['refs/heads/main', 'refs/heads/other', 'refs/tags/main']) {
          const got = require('node:vm').runInNewContext(gate, {
            cancelled: () => cancelled, needs: { pass: { result: pass }, next: { result } }, vars: { PASS_APPLY: apply },
            github: { ref, event_name: event, event: { repository: { default_branch: 'main' } } },
            inputs: { apply: applying }, format: (template, branch) => template.replace('{0}', branch),
          });
          assert.equal(got, ['failure', 'skipped', ''].includes(result) && pass !== 'cancelled' && !cancelled &&
            apply === 'enabled' && ref === 'refs/heads/main' && (event === 'schedule' || (event === 'workflow_dispatch' && applying)));
          }
          }
          }
        }
      }
      }
    }
    assert.match(fallback, /^ {4}timeout-minutes: 12$/m);
    assert.match(fallback, /^ {4}permissions:\n {6}actions: write\n {4}steps:/m);
    assert.doesNotMatch(fallback, /uses:|continue-on-error:|^ {2}\S/m);
    assert.equal((fallback.match(/^ {6}- /gm) ?? []).length, 1, 'one step without setup');
    assert.match(fallback, /^ {10}GH_TOKEN: \$\{\{ github.token \}\}$/m);
    assert.match(fallback, /^ {10}DEFAULT_BRANCH: \$\{\{ github.event.repository.default_branch \}\}$/m);
    for (const job of ['PASS', 'NEXT']) assert.ok(fallback.includes(`${job}_RESULT: \u0024{` + `{ needs.${job.toLowerCase()}.result }}`));
    const recovery = /^ {8}run: \|\n((?: {10}.*\n)+)/m.exec(fallback)[1].replace(/^ {10}/gm, '');
    const sandbox = fs.mkdtempSync(path.join(require('node:os').tmpdir(), 'poll-fallback-'));
    try {
      fs.writeFileSync(path.join(sandbox, 'gh'), `#!${process.execPath}
    const args = process.argv.slice(2);
    require('node:fs').appendFileSync(process.env.CALLS, JSON.stringify(args) + '\\n');
    if (args[0] === 'api') {
      const listing = args.includes('--method');
      if (process.env.API_FAIL === (listing ? 'list' : 'start')) { console.error('fixture API failure'); process.exit(1); }
      process.stdout.write(listing ? (process.env[args.includes('page=2') ? 'PAGE2' : 'RUNS']) : (process.env.START || '2026-11-02T17:51:00Z'));
    } else { console.log(args.join(' ')); process.exit(Number(process.env.DISPATCH_EXIT || 0)); }
    `, { mode: 0o755 });
      fs.writeFileSync(path.join(sandbox, 'date'), '#!/bin/bash\nif [[ $1 == -d ]]; then printf "1000\\n"; else printf "%s\\n" "$NOW"; fi\n', { mode: 0o755 });
      fs.writeFileSync(path.join(sandbox, 'sleep'), '#!/bin/bash\nprintf "sleep %s\\n" "$*"\n', { mode: 0o755 });
      const dispatch = 'workflow run poll.yml --repo owner/repo --ref main -f apply=true -f previous_run_id=42';
      const me = { id: 42, created_at: '2026-11-02T17:51:00Z', head_branch: 'main', event: 'workflow_dispatch', display_title: 'pass (apply)', status: 'in_progress' };
      const rows = runs => JSON.stringify({ workflow_runs: runs });
      const log = 'Recovery dependencies: pass=<> next=<skipped>';
      const callsPath = path.join(sandbox, 'calls');
      const recover = (env = {}) => {
        fs.writeFileSync(callsPath, '');
        return require('node:child_process').spawnSync('bash', ['--noprofile', '--norc', '-eo', 'pipefail', '-c', recovery], {
          env: { PATH: `${sandbox}:${process.env.PATH}`, GITHUB_REPOSITORY: 'owner/repo', GITHUB_RUN_ID: '42', DEFAULT_BRANCH: 'main',
            PASS_RESULT: '', NEXT_RESULT: 'skipped', CALLS: callsPath, NOW: '1900', RUNS: rows([me]), ...env }, encoding: 'utf8',
        });
      };
      const calls = () => fs.readFileSync(callsPath, 'utf8').trim().split('\n').map(JSON.parse);
      for (const [now, delay] of [['1120', '480'], ['1600', null], ['1900', null], ['900', '600']]) {
        const got = recover({ NOW: now });
        assert.equal(got.status, 0, got.stderr);
        assert.deepEqual(got.stdout.trimEnd().split('\n'), [log, ...(delay ? [`sleep ${delay}`] : []), dispatch]);
        assert.deepEqual(calls().at(-1), dispatch.split(' '));
        assert.equal(calls().length, 3);
      }
      const failed = recover({ NOW: '1900', DISPATCH_EXIT: '1' });
      assert.equal(failed.status, 1, 'dispatch failure stays visible');
      assert.deepEqual(failed.stdout.trimEnd().split('\n'), [log, dispatch], 'no retry on failure');
      assert.equal(calls().filter(args => args[0] === 'workflow').length, 1);
      for (const env of [{ API_FAIL: 'start' }, { API_FAIL: 'list' }, { START: 'null' }, { RUNS: '{}' }, { RUNS: '{' },
        { RUNS: rows([]) }, { RUNS: rows([{ ...me, status: null }]) }, { RUNS: rows([{ ...me, created_at: 'invalid' }]) }]) {
        const unreadable = recover(env);
        assert.notEqual(unreadable.status, 0, JSON.stringify(env));
        assert.ok(unreadable.stderr, 'failure stays visible');
        assert.equal(unreadable.stdout.trimEnd(), log, 'API failure stops recovery');
        assert.ok(calls().every(args => args[0] === 'api'));
      }
      const newer = { ...me, id: 43 };
      for (const status of ['queued', 'waiting', 'pending', 'requested', 'in_progress']) {
        for (const event of ['schedule', 'workflow_dispatch']) {
          const got = recover({ RUNS: rows([{ ...newer, status, event }, me]) });
          assert.equal(got.status, 0, got.stderr);
          assert.match(got.stdout, /run 43 continues the chain/);
          assert.equal(calls().length, 2, 'no dispatch for newer active applying run');
        }
      }
      for (const other of [{ ...newer, status: 'completed' }, { ...newer, head_branch: 'other' },
        { ...newer, display_title: 'pass' }, { ...newer, event: 'push' }, { ...me, id: 41 },
        { ...newer, created_at: '2026-11-02T17:50:59Z' }]) {
        const got = recover({ RUNS: rows([other, me]) });
        assert.equal(got.status, 0, got.stderr);
        assert.match(got.stdout, /workflow run poll.yml/);
      }
      const full = Array.from({ length: 100 }, (_, i) => ({ ...newer, id: 100 + i, status: 'completed' }));
      assert.equal(recover({ RUNS: rows(full), PAGE2: rows([me]) }).status, 0);
      assert.equal(calls().length, 4, 'second page reaches current run before dispatch');
      assert.notEqual(recover({ RUNS: rows(full), PAGE2: rows(full) }).status, 0);
      assert.equal(calls().length, 3, 'bounded at two pages; no blind dispatch');
    } finally {
      fs.rmSync(sandbox, { recursive: true, force: true });
    }
    console.log('ok offline fallback guards, dependency fixtures, bounded wait/listing, newer-run ownership and visible API failures; not live GitHub proof');

# Offline state provenance, public-only export and workflow plumbing.
test-pass-state:
    #!/usr/bin/env node
    const assert = require('node:assert/strict');
    const fs = require('node:fs');
    const source = /^pass-state mode:\n((?:    .*\n|\n)+)/m.exec(fs.readFileSync('Justfile', 'utf8'))[1].replace(/^    /gm, '');
    const functions = {};
    new Function('require', 'process', 'exports', source.replace(/^#!.*\n/, ''))(require, { argv: ['node', 'recipe', 'test'] }, functions);
    const { validate, publicStates } = functions;
    const env = { PREVIOUS_RUN_ID: '41', GITHUB_RUN_ID: '42', GITHUB_REPOSITORY: 'owner/tracker', DEFAULT_BRANCH: 'main' };
    const run = { id: 41, workflow_id: 123, path: '.github/workflows/poll.yml',
      repository: { full_name: env.GITHUB_REPOSITORY }, head_repository: { full_name: env.GITHUB_REPOSITORY },
      head_branch: 'main', event: 'workflow_dispatch', display_title: 'pass (apply)' };
    const jobs = { total_count: 2, jobs: [{ name: 'pass', status: 'completed', conclusion: 'success' },
      { name: 'next', status: 'in_progress' }] };
    function predecessor(change = {}, jobChange = {}, extra = {}) {
      const calls = [];
      const id = validate({ ...env, ...extra }, endpoint => {
        calls.push(endpoint);
        assert.ok(calls.length <= 3);
        if (endpoint.endsWith('/workflows/poll.yml')) return { id: 123 };
        if (endpoint.endsWith('/jobs?filter=latest&per_page=100')) return { ...jobs, ...jobChange };
        assert.equal(endpoint, 'repos/owner/tracker/actions/runs/41');
        return { ...run, ...change };
      });
      return { id, calls };
    }
    assert.equal(predecessor().id, '41');
    assert.equal(predecessor({ event: 'schedule', display_title: 'pass' }).id, '41');
    assert.equal(predecessor({}, { jobs: [{ ...jobs.jobs[0], conclusion: 'failure' }], total_count: 1 }).id, '41');
    for (const change of [{ workflow_id: 124 }, { id: 40 }, { path: '.github/workflows/other.yml' },
      { repository: { full_name: 'other/tracker' } }, { head_repository: { full_name: 'fork/tracker' } },
      { head_branch: 'feature' }, { event: 'pull_request' }, { event: 'push' }, { display_title: 'pass' }]) {
      assert.equal(predecessor(change).id, '', JSON.stringify(change));
    }
    for (const change of [{ total_count: 101 }, { jobs: [] }, { jobs: null },
      { jobs: [jobs.jobs[0], jobs.jobs[0]] },
      ...['in_progress', 'queued'].map(status => ({ total_count: 1, jobs: [{ ...jobs.jobs[0], status }] })),
      ...['cancelled', 'skipped', null].map(conclusion => ({ total_count: 1, jobs: [{ ...jobs.jobs[0], conclusion }] }))]) {
      assert.equal(predecessor({}, change).id, '', JSON.stringify(change));
    }
    for (const id of ['42', '0', '-1', '../41', '41;exit', '1'.repeat(21)]) {
      assert.deepEqual(predecessor({}, {}, { PREVIOUS_RUN_ID: id }), { id: '', calls: [] });
    }
    // Cursors survive the handoff only for a verified public repository.
    const visibility = endpoint => {
      const repo = endpoint.slice('repos/'.length);
      if (repo === 'owner/down') throw new Error('API outage');
      if (repo === 'owner/vague') return { full_name: repo };
      return repo === 'owner/private' ? { full_name: repo, private: true, visibility: 'private' } :
        { full_name: repo === 'owner/renamed' ? 'other/name' : repo, private: false, visibility: 'public' };
    };
    // Shapes the pinned pass loads: a repository, a thread (scan), or either (share).
    const repoKeys = ['follow_cursor', 'action_first_cursor', 'authored_cursor'];
    const keepers = { 'Owner/Public': [...repoKeys, 'share_cursor'], 'owner/public#12': ['share_cursor', 'scan_cursor'] };
    for (const cursor of ['Owner/Public', 'owner/public#12', 'owner/private#12', 'owner/private', 'owner/vague#1',
      'owner/renamed', 'owner/down#3', 'owner/public#0', 'owner/public#', 'owner/public/x', 'owner/public\n',
      'my_org/public', 'owner', ' owner/public', 42, null, { repo: 'owner/public' }]) {
      for (const key of [...repoKeys, 'share_cursor', 'scan_cursor']) {
        const { state } = publicStates({ [key]: cursor, holds: { [cursor]: 'private hold' }, intake_waiting: {},
          maintain: {}, action_first_positions: { [cursor]: 1 } }, null, visibility);
        assert.deepEqual(state, { schema: 'agent-board/poll-state/v1', interval_seconds: 300, responses: {}, pass_responses: {},
          ...(keepers[cursor]?.includes(key) && { [key]: cursor }) }, `${key} ${JSON.stringify(cursor)}`);
      }
    }
    const mixed = publicStates({ share_cursor: 'owner/public#1', scan_cursor: 'owner/down#2', authored_cursor: 'owner/private' },
      null, visibility).state;
    assert.equal(mixed.share_cursor, 'owner/public#1', 'one failed lookup keeps other public cursors');
    assert.ok(!('scan_cursor' in mixed) && !('authored_cursor' in mixed));
    // Cursors only use repository slots the caches leave; at the cap they are dropped, not fatal.
    const full = Object.fromEntries(Array.from({ length: 100 }, (_, i) => [`https://api.github.com/repos/owner/r${i}/issues`, {}]));
    const capped = publicStates({ responses: full, follow_cursor: 'owner/public' }, null, visibility).state;
    assert.equal(Object.keys(capped.responses).length, 100);
    assert.ok(!('follow_cursor' in capped));
    const tests = fs.readFileSync('.github/workflows/ci.yml', 'utf8').split('      - name: Test pass state export\n')[1];
    new Function('require', tests.split('        run: |\n')[1].split('      - run: just test\n')[0].replace(/^          /gm, ''))(require);

# Public cache and durable status handoff. Never print bodies or API diagnostics.
pass-state mode:
    #!/usr/bin/env node
    const fs = require('node:fs');
    const { execFileSync } = require('node:child_process');
    const STATE = '.state/pass.json';
    const LIVING = '.state/living-status.json';
    const MAX_BYTES = 32 * 1024 * 1024; // The pinned pass's state-file limit.
    const MAX_REPOSITORIES = 100;
    function api(endpoint, timeout = 20000) {
      return JSON.parse(execFileSync('gh', ['api', endpoint], {
        timeout, maxBuffer: MAX_BYTES, stdio: ['ignore', 'pipe', 'pipe'],
      }));
    }
    function validate(env = process.env, get = api) {
      let id = env.PREVIOUS_RUN_ID;
      const root = `repos/${env.GITHUB_REPOSITORY}/actions`;
      if (!id) {
        // Bootstrap/schedule use the same provenance gate as explicit dispatches.
        // Bound discovery; never accept an artifact merely because its name fits.
        const listed = get(`${root}/workflows/poll.yml/runs?branch=${encodeURIComponent(env.DEFAULT_BRANCH)}&per_page=100`).workflow_runs;
        if (!Array.isArray(listed) || listed.length > 100) throw new Error('invalid run listing');
        const previous = listed.filter(run => /^[1-9][0-9]{0,19}$/.test(String(run.id)) &&
          BigInt(run.id) < BigInt(env.GITHUB_RUN_ID) && run.head_branch === env.DEFAULT_BRANCH &&
          (run.event === 'schedule' || (run.event === 'workflow_dispatch' && run.display_title === 'pass (apply)')) &&
          run.conclusion !== 'cancelled').sort((a, b) => BigInt(a.id) > BigInt(b.id) ? -1 : 1)[0];
        if (!previous) return '';
        id = String(previous.id);
      }
      // Input is data, never a URL/path or shell fragment.
      if (!/^[1-9][0-9]{0,19}$/.test(id) || id === env.GITHUB_RUN_ID) return '';
      const run = get(`${root}/runs/${id}`);
      const workflow = get(`${root}/workflows/poll.yml`);
      if (String(run.id) !== id || run.workflow_id !== workflow.id ||
          run.path !== '.github/workflows/poll.yml' ||
          run.repository?.full_name !== env.GITHUB_REPOSITORY ||
          run.head_repository?.full_name !== env.GITHUB_REPOSITORY ||
          run.head_branch !== env.DEFAULT_BRANCH ||
          !(run.event === 'schedule' ||
            (run.event === 'workflow_dispatch' && run.display_title === 'pass (apply)'))) return '';
      // The next job may still be running. Require the state-writing job, not
      // the whole workflow, to have finished. Refuse truncated job listings.
      const jobs = get(`${root}/runs/${id}/jobs?filter=latest&per_page=100`);
      if (!Array.isArray(jobs.jobs) || jobs.total_count !== jobs.jobs.length ||
          jobs.jobs.length > 100) return '';
      const passes = jobs.jobs.filter(job => job.name === 'pass');
      return passes.length === 1 && passes[0].status === 'completed' &&
        ['success', 'failure'].includes(passes[0].conclusion) ? id : '';
    }
    function publicStates(state, living, get = api) {
      const issueRepository = key => /^([A-Za-z0-9_.-]+\/[A-Za-z0-9_.-]+)#[1-9][0-9]*$(?![\s\S])/.exec(key)?.[1].toLowerCase();
      if (living !== null) {
        if (living?.schema !== 'agent-board/status/v1' || typeof living.bot !== 'string' ||
            !living.entries || typeof living.entries !== 'object' || Array.isArray(living.entries) ||
            Object.keys(living).some(key => !['schema', 'bot', 'entries'].includes(key)) ||
            Object.keys(living.entries).some(key => !issueRepository(key))) throw new Error('invalid status ledger');
      }
      // Both caches contain PAT-authenticated bodies. A public repository alone
      // is not enough: reviews can include the viewer's unpublished PENDING body.
      // Allow only public issue/PR lists/details, issue comments and label lists.
      // Timelines can embed private cross-references. Every other endpoint stays
      // cold. Match the entire raw
      // path, without URL normalization accepting extra/dot/encoded segments.
      const repository = url => /^https:\/\/api\.github\.com\/repos\/([A-Za-z0-9_.-]+\/[A-Za-z0-9_.-]+)\/(?:issues(?:\/[1-9][0-9]*(?:\/(?:comments|labels))?|\/comments\/[1-9][0-9]*)?|pulls(?:\/[1-9][0-9]*)?|labels)(?:\?[^#\s]*)?$(?![\s\S])/
        .exec(url)?.[1].toLowerCase();
      const caches = ['responses', 'pass_responses'];
      // Without its read cursors the next pass restarts every walk at the first
      // repository. A cursor can name a private repository or thread, so export
      // it unchanged only when its repository is verified public. Each key keeps
      // the one shape the pinned pass loads; it refuses the whole state otherwise.
      const cursors = { follow_cursor: '', action_first_cursor: '', authored_cursor: '',
        share_cursor: '(?:#[1-9][0-9]*)?', scan_cursor: '#[1-9][0-9]*' };
      const cursorRepository = key => typeof state[key] === 'string' &&
        new RegExp(`^([A-Za-z0-9-]+/[A-Za-z0-9_.-]+)${cursors[key]}$(?![\\s\\S])`).exec(state[key])?.[1].toLowerCase();
      const repositories = new Set([...caches.flatMap(key => Object.keys(state[key] || {}).map(repository).filter(Boolean)),
        ...Object.keys(living?.entries || {}).map(issueRepository)]);
      if (repositories.size > MAX_REPOSITORIES) throw new Error('too many repositories');
      // Cursors are checked last, within the remaining cap and deadline, so they never fail the export.
      const required = repositories.size;
      for (const key of Object.keys(cursors)) {
        const repo = cursorRepository(key);
        if (repo && repositories.size < MAX_REPOSITORIES) repositories.add(repo);
      }
      const publicRepos = new Set();
      const ledgerRepos = new Set(Object.keys(living?.entries || {}).map(issueRepository));
      const deadline = Date.now() + 90000;
      let checked = 0;
      for (const repo of repositories) {
        if (Date.now() >= deadline) {
          if (checked < required) throw new Error('metadata deadline');
          break;
        }
        checked++;
        try {
          const metadata = get(`repos/${repo}`, Math.min(10000, deadline - Date.now()));
          if (metadata.full_name?.toLowerCase() === repo && metadata.private === false && metadata.visibility === 'public') {
            publicRepos.add(repo);
          } else if (ledgerRepos.has(repo) && !(metadata.full_name?.toLowerCase() === repo &&
              metadata.private === true && ['private', 'internal'].includes(metadata.visibility))) throw new Error('unverified ledger repository');
        } catch { if (ledgerRepos.has(repo)) throw new Error('cannot verify ledger visibility'); }
      }
      // Holds, intake and maintenance metadata can also name private repositories.
      // Publish only the response-cache envelope and public cursors, not arbitrary state fields.
      const exported = { schema: 'agent-board/poll-state/v1',
        interval_seconds: Number.isSafeInteger(state.interval_seconds) ? state.interval_seconds : 300 };
      for (const key of Object.keys(cursors)) if (publicRepos.has(cursorRepository(key))) exported[key] = state[key];
      for (const key of caches) {
        // Drop entries whole: changing a body would invalidate its cached ETag.
        exported[key] = Object.fromEntries(Object.entries(state[key] || {}).filter(([url]) => publicRepos.has(repository(url))));
      }
      // Keep public entries whole: redacting records breaks their replay hashes.
      // The original ledger stays intact; only the public copy drops private entries.
      const ledger = living === null ? null : { schema: living.schema, bot: living.bot,
        entries: Object.fromEntries(Object.entries(living.entries).filter(([key]) => publicRepos.has(issueRepository(key)))) };
      return { state: exported, living: ledger };
    }
    if (process.argv[2] === 'validate') {
      let id = '';
      try { id = validate(); } catch { /* Missing provenance starts cold. */ }
      fs.appendFileSync(process.env.GITHUB_OUTPUT, `run-id=${id}\n`);
      console.log(id ? `Validated predecessor ${id}` : 'No trusted predecessor; starting cold');
    } else if (process.argv[2] === 'export') {
      fs.rmSync('.state/public', { recursive: true, force: true });
      const paths = [STATE, LIVING];
      if (paths.some(path => fs.existsSync(path))) {
        try {
          const read = (path, limit) => {
            if (!fs.existsSync(path)) return null;
            try {
              if (fs.statSync(path).size > limit) throw new Error('oversized state');
              const value = JSON.parse(fs.readFileSync(path, 'utf8'));
              if (!value || typeof value !== 'object' || Array.isArray(value)) throw new Error('invalid state');
              return value;
            } catch {
              // A corrupt disposable cache must not discard valid replay guards.
              if (path === LIVING) throw new Error('unreadable ledger');
              fs.rmSync(path, { force: true });
              console.log('Discarded an unreadable state file');
              return null;
            }
          };
          const state = read(STATE, MAX_BYTES);
          const living = read(LIVING, 4 * 1024 * 1024);
          const exported = publicStates(state || {}, living);
          fs.mkdirSync('.state/public', { recursive: true });
          if (state !== null) fs.writeFileSync('.state/public/pass.json', JSON.stringify(exported.state) + '\n');
          if (living !== null) fs.writeFileSync('.state/public/living-status.json', JSON.stringify(exported.living) + '\n');
          console.log('Prepared public response cache for the next pass');
        } catch {
          fs.rmSync('.state/public', { recursive: true, force: true });
          console.error('Could not prepare public state; original ledger retained; refusing export');
          process.exitCode = 1;
        }
      }
    } else if (process.argv[2] === 'test') {
      Object.assign(exports, { validate, publicStates });
    } else {
      throw new Error('expected validate or export');
    }

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

# Opens or updates the one pull request, from the bot's fork, that moves
# every AGENT_BOARD_REV to the newest installable main CI commit in a bounded
# scan, once it is ahead of the pin (agent-board-pin.yml). It commits in this
# checkout, and needs GITHUB_REPOSITORY and GH_TOKEN to push and open the PR.
# Ours: with no newer commit to move to, it fails once the pin's artifact
# nears expiry, since installs have no release to fall back on. Otherwise
# the open bump pull request is the signal.
bump-agent-board:
    #!/usr/bin/env bash
    set -euo pipefail
    pin=$({{ just_executable() }} agent-board-pin)
    upstream={{ agent_board_repo }} branch={{ agent_board_branch }} bot={{ agent_board_bot }}
    source=https://github.com/$upstream
    selected=$({{ just_executable() }} select-agent-board latest "$branch")
    head=$(jq -r '.sha // empty' <<< "$selected")
    if [[ -z $head || $head == "$pin" ]]; then
      run=$({{ just_executable() }} select-agent-board "$pin" "$branch" | jq -r '.run // empty')
      expires=$(if [[ -n $run ]]; then timeout 20 gh api "repos/$upstream/actions/runs/$run/artifacts?per_page=100" |
        jq -r '[.artifacts[] | select(.name == "agent-board-main" and .expired == false)][0].expires_at // empty'; fi)
      if [[ -z $expires ]]; then
        echo "::error::the pin $pin has no unexpired agent-board-main artifact and $upstream $branch no newer one: installs fail"; exit 1
      fi
      if (( $(date -ud "$expires" +%s) - $(date -u +%s) < {{ agent_board_expiry_days }} * 86400 )); then
        echo "::error::the pin $pin's agent-board-main artifact expires $expires and $upstream $branch has no newer installable commit; installs fail after then"; exit 1
      fi
      echo "no newer installable $branch commit; the pin's artifact expires $expires"; exit 0
    fi
    [[ $head =~ ^[0-9a-f]{40}$ ]]
    (export RUNNER_TEMP=$(mktemp -d); trap 'rm -rf "$RUNNER_TEMP"' EXIT
      GITHUB_OUTPUT=/dev/null {{ just_executable() }} build-agent-board "$head")
    # Never backwards or onto rewritten history; compare lists at most 250 commits.
    compare=$(gh api "repos/$upstream/compare/$pin...$head")
    status=$(jq -r .status <<< "$compare")
    [[ $status == ahead ]] || { echo "::error::$head is $status of the pin $pin, not ahead"; exit 1; }
    title="workflows: Move agent-board to ${head:0:7}"
    pr_branch=agent-board-pin
    open=$(gh pr list --repo "$GITHUB_REPOSITORY" --author "$bot" --head "$pr_branch" --state open --json number,title --jq '.[0] // empty')
    if [[ $(jq -r '.title // ""' <<< "$open") == "$title" ]]; then echo "already proposed: $title"; exit 0; fi
    fork=$(gh api --paginate "repos/$GITHUB_REPOSITORY/forks" --jq ".[] | select(.owner.login == \"$bot\") | .full_name" | head -n1)
    [[ -n $fork ]] || { echo "::error::$bot has no fork of $GITHUB_REPOSITORY"; exit 1; }
    body=$(
      echo "Every \`AGENT_BOARD_REV\` in \`.github/workflows/\` moves from $pin to $head, the newest $branch commit with a successful CI artifact in the discovery window. Its attestation and checksums verified before this proposal. Review [what changes]($source/compare/$pin...$head) in the program given the bot's token. The agent-board commits in between:"
      echo
      # Subjects in code spans, so their #N and @login do not reference here.
      jq -r --arg s "$source" '.commits[] | "- [\(.sha[0:7])](\($s)/commit/\(.sha)) `\(.commit.message | split("\n")[0] | gsub("`"; "'\''"))`"' <<< "$compare"
      jq -r 'if .total_commits > (.commits | length) then "\n\(.total_commits - (.commits | length)) more commits are not listed." else empty end' <<< "$compare"
    )
    sed -i "s/^  AGENT_BOARD_REV: $pin\$/  AGENT_BOARD_REV: $head/" .github/workflows/*.yml
    [[ $({{ just_executable() }} agent-board-pin) == "$head" ]]
    email=$(gh api "users/$bot" --jq '"\(.id)+\(.login)@users.noreply.github.com"')
    git -c user.name="$bot" -c user.email="$email" commit -q -a -m "$title" -m "$body"
    gh auth setup-git
    git push -q --force "https://github.com/$fork" "HEAD:refs/heads/$pr_branch"
    if [[ -n $open ]]; then
      gh pr edit "$(jq -r .number <<< "$open")" --repo "$GITHUB_REPOSITORY" --title "$title" --body "$body"
    else
      gh pr create --repo "$GITHUB_REPOSITORY" --head "${fork%%/*}:$pr_branch" --base "$(gh repo view "$GITHUB_REPOSITORY" --json defaultBranchRef --jq .defaultBranchRef.name)" --title "$title" --body "$body"
    fi

# bump-agent-board with nothing newer than the pin, against a stub gh that
# answers only the selector's and the expiry check's reads: the pin's
# artifact expiry decides, and no other call (build, push, PR) is made.
test-agent-board-bump:
    #!/usr/bin/env node
    const assert = require('node:assert/strict');
    const fs = require('node:fs');
    const path = require('node:path');
    const { execFileSync, spawnSync } = require('node:child_process');
    const just = '{{ just_executable() }}';
    const pin = execFileSync(just, ['agent-board-pin'], { encoding: 'utf8' }).trim();
    const temp = fs.mkdtempSync(path.join(require('node:os').tmpdir(), 'agent-board-bump-'));
    fs.writeFileSync(path.join(temp, 'gh'), `#!${process.execPath}
    const args = process.argv.slice(2), e = process.env, out = v => console.log(JSON.stringify(v));
    require('node:fs').appendFileSync(e.CALLS, JSON.stringify(args) + '\\n');
    if (args[0] !== 'api' || args.length !== 2) process.exit(3);
    if (args[1].includes('/actions/workflows/ci.yml/runs?')) out({ workflow_runs: e.RUNS ? [{ id: 42, head_sha: e.PIN, head_branch: '{{ agent_board_branch }}', event: 'push', status: 'completed', conclusion: 'success', path: '.github/workflows/ci.yml' }] : [] });
    else if (args[1].includes('/commits?')) out([{ sha: e.PIN }]);
    else if (args[1].endsWith('/runs/42/artifacts?per_page=100')) out({ artifacts: e.EXPIRES ? [{ name: 'agent-board-main', expired: false, expires_at: e.EXPIRES }] : [] });
    else process.exit(3);
    `, { mode: 0o755 });
    const days = n => new Date(Date.now() + n * 86400000).toISOString().replace(/\.\d{3}Z$/, 'Z');
    const calls = path.join(temp, 'calls');
    const [later, sooner] = [days(22), days(20)];
    try {
      for (const [runs, expires, success, message] of [['1', later, true, `the pin's artifact expires ${later}`],
        ['1', sooner, false, `::error::the pin ${pin}'s agent-board-main artifact expires ${sooner}`],
        ['1', '', false, `::error::the pin ${pin} has no unexpired`], ['', '', false, `::error::the pin ${pin} has no unexpired`]]) {
        fs.writeFileSync(calls, '');
        const got = spawnSync(just, ['bump-agent-board'], { encoding: 'utf8', env: { PATH: `${temp}:${process.env.PATH}`,
          CALLS: calls, PIN: pin, RUNS: runs, EXPIRES: expires, GITHUB_REPOSITORY: 'owner/tracker' } });
        const log = `${runs ? 'run' : 'no run'} ${expires || 'no artifact'}: ${got.stdout}${got.stderr}`;
        assert.equal(got.status === 0, success, log);
        assert.ok(got.stdout.includes(message), log);
        const seen = fs.readFileSync(calls, 'utf8').trim().split('\n').map(JSON.parse);
        assert.ok(seen.every(args => args[0] === 'api' && args.length === 2), log);
        assert.equal(seen.some(args => args[1].endsWith('/runs/42/artifacts?per_page=100')), runs !== '', log);
      }
    } finally { fs.rmSync(temp, { recursive: true, force: true }); }
    console.log('ok bump-agent-board fails, naming the date, within 21 days of the pin artifact expiring with nothing newer');

# The runner configuration's checks; those that run `agentic-job` skip where
# it is not installed. The build goes outside the source tree.
test-config:
    cargo test --locked --manifest-path .github/agentic-job/config-test/Cargo.toml --target-dir "{{ env('CARGO_TARGET_DIR', cache_directory() / 'tracker-config-test') }}"

# pass.json and the fix bounds poll.yml passes, through the pinned binary's
# `pass --check-config` (agent-board#756), which reads only the org listing: a
# setting the pass refuses would otherwise fail every pass after the merge
# (#1403). It runs on every pull request, so a pin move that tightens the
# checks is caught too. The pin is the poll's: agent-board-pin keeps one.
test-pass-config:
    #!/usr/bin/env bash
    set -euo pipefail
    if [[ -z ${AGENT_BOARD:-} ]]; then echo 'skipped: set AGENT_BOARD to the built binary'; exit 0; fi
    "$AGENT_BOARD" pass --check-config --config .github/pass.json \
      --fix-bounds .github/agentic-job/fix.toml --fix-bounds .github/agentic-job/midstream-fix.toml

# Ours: the agent-board source the installer verifies and the pin bump
# follows, and the bot whose fork proposes the bump. A resync keeps these.
# The source is our fork, so its fixes reach the pass (tracker#108); the
# attestation then pins the fork's CI.
agent_board_repo := 'jmarrero-forge/agent-board'
agent_board_branch := 'main'
agent_board_bot := 'jmarrero-bot'

# The pin's artifact retention, in days, under which bump-agent-board fails
# when there is nothing newer to move to (90 when CI uploads it).
agent_board_expiry_days := '21'

# No moving refs or source fallback: substituted assets must not run with the
# bot's write token. The attested manifest binds both digests to reviewed CI.
select-agent-board rev branch=agent_board_branch:
    #!/usr/bin/env bash
    set -euo pipefail
    rev=$1 branch=$2 repo={{ agent_board_repo }}
    [[ $rev == latest || $rev =~ ^[0-9a-f]{40}$ ]] || { echo 'expected pinned revision' >&2; exit 1; }
    branch=$(jq -rn --arg b "$branch" '$b | @uri')
    runs=$(timeout 20 gh api "repos/$repo/actions/workflows/ci.yml/runs?branch=$branch&event=push&status=success&per_page=100&head_sha=${rev/latest/}")
    commits=$(if [[ $rev == latest ]]; then timeout 20 gh api "repos/$repo/commits?sha=$branch&per_page=100" | jq -c '[.[].sha]'; else jq -nc --arg sha "$rev" '[$sha]'; fi)
    candidates=$(jq -c --arg branch "$2" --argjson commits "$commits" '[ $commits[] as $sha | .workflow_runs[] | select(.head_sha == $sha and .head_branch == $branch and .event == "push" and .status == "completed" and .conclusion == "success" and .path == ".github/workflows/ci.yml") | {sha:$sha, run:.id} ]' <<< "$runs")
    listings=0
    while read -r candidate; do
      (( listings += 1 )); [[ $listings -le 30 ]] || { echo 'agent-board artifact discovery exceeded 30 runs' >&2; exit 1; }
      run=$(jq -er '.run | select(type == "number" and . > 0 and . <= 9007199254740991 and floor == .)' <<< "$candidate")
      count=$(timeout 20 gh api "repos/$repo/actions/runs/$run/artifacts?per_page=100" | jq -er '[.artifacts[] | select(.name == "agent-board-main" and .expired == false)] | length')
      [[ $count -le 1 ]] || { echo 'ambiguous agent-board-main artifact' >&2; exit 1; }
      if [[ $count == 1 ]]; then echo "$candidate"; exit 0; fi
    done < <(jq -c '.[]' <<< "$candidates")
    echo null

build-agent-board rev=env("AGENT_BOARD_REV", ""):
    #!/usr/bin/env bash
    set -euo pipefail
    rev=$1
    [[ $rev =~ ^[0-9a-f]{40}$ ]] || { echo 'expected a pinned 40-character AGENT_BOARD_REV' >&2; exit 1; }
    [[ $(uname -s)-$(uname -m) == Linux-x86_64 ]] || { echo 'agent-board binaries support only Linux x86_64' >&2; exit 1; }
    repo={{ agent_board_repo }} target=x86_64-unknown-linux-musl
    tag=build-$rev
    dest=$RUNNER_TEMP/agent-board/bin
    mkdir -p "$dest"
    rm -f "$dest/agent-board"
    stage=$(mktemp -d "$RUNNER_TEMP/agent-board-download.XXXXXX")
    trap 'rm -rf "$stage"' EXIT
    selected=$({{ just_executable() }} select-agent-board "$rev")
    if [[ $selected != null ]]; then
      run=$(jq -er .run <<< "$selected")
      timeout 180 gh run download "$run" --repo "$repo" --name agent-board-main --dir "$stage"
      tag=''
    else
      timeout 180 gh release download "$tag" --repo "$repo" --dir "$stage" \
        --pattern "*-$target" --pattern SHA256SUMS --pattern release.json --pattern provenance.jsonl
    fi
    GH_TOKEN='' GITHUB_TOKEN='' timeout 180 gh attestation verify "$stage/release.json" \
      --bundle "$stage/provenance.jsonl" --repo "$repo" \
      --cert-identity "https://github.com/$repo/.github/workflows/ci.yml@refs/heads/{{ agent_board_branch }}" \
      --source-ref refs/heads/{{ agent_board_branch }} --source-digest "$rev" --deny-self-hosted-runners
    jq -e --arg repo "$repo" --arg tag "$tag" --arg commit "$rev" --arg target "$target" \
      '.schema == "agent-board.release.v1" and .repository == $repo and .tag == $tag and .commit == $commit and .target == $target' "$stage/release.json" > /dev/null
    # Accept only the two fixed filenames, never paths supplied by a manifest.
    node -e 'const fs = require("node:fs"); const d = process.argv[1]; const s = JSON.parse(fs.readFileSync(d + "/release.json")).sha256sums; if (typeof s !== "string" || !/^[0-9a-f]{64}  agent-board-x86_64-unknown-linux-musl\n[0-9a-f]{64}  gh-agent-board-x86_64-unknown-linux-musl\n$/.test(s)) throw Error("invalid release checksums"); fs.writeFileSync(d + "/attested-SHA256SUMS", s);' "$stage"
    cmp "$stage/SHA256SUMS" "$stage/attested-SHA256SUMS"
    (cd "$stage" && sha256sum --check attested-SHA256SUMS)
    install -m 755 "$stage/agent-board-$target" "$dest/agent-board"
    echo "rev=$rev" >> "${GITHUB_OUTPUT:-/dev/null}"
    echo "Installed agent-board $rev ($target)"

# Offline installer probes live with the other config-test transport fixtures.
test-agent-board-install:
    JUST_BIN="{{ just_executable() }}" cargo test --locked --manifest-path .github/agentic-job/config-test/Cargo.toml --target-dir "{{ env('CARGO_TARGET_DIR', cache_directory() / 'tracker-config-test') }}" agent_board_

# The shared workflow check that ci.yml's lint job calls, run locally from
# a checkout of the forge's actions repository (its lint/README.md), the
# path relative to this repository's root; CONTAINER=podman without docker:
#   just lint ../actions
lint actions:
    {{ just_executable() }} --justfile "{{ actions }}/lint/Justfile" --working-directory . check
