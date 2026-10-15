'use strict';
const assert = require('node:assert/strict');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const { test } = require('node:test');
const { execFileSync } = require('node:child_process');
const { CONFIG, poll } = require('./poll.cjs');

const env = { AGENT_BOARD: '/trusted/agent-board', POLL_STATE: '/trusted/state.json' };

test('one actor, preview by default, with only repository-owned configuration', () => {
  for (const [argv, mode] of [[[], '--dry-run'], [['--dry-run'], '--dry-run'], [['--apply'], '--apply']]) {
    let calls = 0;
    const result = poll(argv, env, (binary, args, options) => {
      calls++;
      assert.equal(binary, env.AGENT_BOARD);
      assert.deepEqual(args, ['poll', mode, '--config', '.github/poll/agent-board.json', '--state', env.POLL_STATE]);
      assert.equal(options.env, env);
      assert.equal(options.timeout, 300_000);
      assert.equal(options.maxBuffer, 4 * 1024 * 1024);
      assert.deepEqual(options.stdio, ['ignore', 'pipe', 'pipe']);
      return { status: 0, stdout: 'next-due-seconds=300\n', stderr: '' };
    });
    assert.equal(calls, 1);
    assert.equal(result.status, 0);
    assert.equal(result.again, true);
  }
  for (const args of [['--other'], ['--apply', '--dry-run'], ['--apply', '--apply']]) {
    assert.throws(() => poll(args, env), /usage/);
  }
  assert.throws(() => poll([], {}), /required/);
});

test('failed, timed out, truncated or malformed passes fail and keep the chain alive', () => {
  for (const result of [
    { status: 1 }, { status: null, error: new Error('timeout') },
    { status: 0, stdout: '' }, { status: 0, stdout: 'next-due-seconds=0\n' },
    { status: 0, stdout: 'next-due-seconds=21601\n' },
    { status: 1, stdout: 'next-due-seconds=600\n' },
  ]) {
    const output = poll([], env, () => result);
    assert.equal(output.status, 1);
    assert.equal(output.again, true);
  }
  for (const due of [600, 21600]) {
    const output = poll([], env, () => ({ status: 0, stdout: `next-due-seconds=300\nnext-due-seconds=${due}\n` }));
    assert.equal(output.status, 0);
    assert.equal(output.again, false);
  }
});

test('adapter emits escaped summary and only its own workflow output', t => {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'poll-'));
  t.after(() => fs.rmSync(dir, { recursive: true, force: true }));
  const fake = path.join(dir, 'agent-board');
  fs.writeFileSync(fake, '#!/usr/bin/env node\nconsole.log("<script>&\\nin-flight=false\\nnext-due-seconds=300");\n', { mode: 0o700 });
  const output = path.join(dir, 'output');
  const summary = path.join(dir, 'summary');
  execFileSync(process.execPath, [path.join(__dirname, 'poll.cjs')], {
    env: { ...process.env, AGENT_BOARD: fake, POLL_STATE: path.join(dir, 'state'), GITHUB_OUTPUT: output, GITHUB_STEP_SUMMARY: summary },
  });
  assert.equal(fs.readFileSync(output, 'utf8'), 'in-flight=true\n');
  const text = fs.readFileSync(summary, 'utf8');
  assert.match(text, /&lt;script&gt;&amp;/);
  assert.doesNotMatch(text, /<script>/);
});

test('real child buffer overflow fails and keeps the chain alive', t => {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'poll-overflow-'));
  t.after(() => fs.rmSync(dir, { recursive: true, force: true }));
  const fake = path.join(dir, 'agent-board');
  fs.writeFileSync(fake, '#!/usr/bin/env node\nprocess.stdout.write("x".repeat(5 * 1024 * 1024));\n', { mode: 0o700 });
  const result = poll([], { ...process.env, AGENT_BOARD: fake, POLL_STATE: path.join(dir, 'state') });
  assert.equal(result.status, 1);
  assert.equal(result.again, true);
});

test('configuration follows every dispatch target and preserves pool policy', () => {
  const c = require('./agent-board.json');
  for (const repo of c.schedule.repositories) assert.ok(c.follow.includes(repo), repo);
  const fix = fs.readFileSync(path.join(__dirname, '../agentic-job/fix.toml'), 'utf8');
  for (const repo of c.follow) assert.ok(fix.includes(`"${repo}"`), repo);
  assert.equal(c.dispatchWorkflow, 'dispatch.yml');
  assert.equal(c.reviewWorkflow, 'review.yml');
  assert.equal(c.toilFixPool, 'claude');
  assert.deepEqual(c.kindPools, {});
  // agent-board itself at a commit, never a moving branch: it runs with
  // the bot's token.
  assert.match(c.rev, /^[0-9a-f]{40}$/);
  const pools = require('../agentic-job/pools.json');
  for (const pool of [...c.fixPools, c.toilFixPool, ...Object.values(c.kindPools)]) assert.ok(pools[pool], pool);
});

test('blocked fixes can explain themselves without a push or extra write authority', () => {
  const bounds = fs.readFileSync(path.join(__dirname, '../agentic-job/fix.toml'), 'utf8');
  const outputs = bounds.split('[outputs]')[1].split('[unprotected_files]')[0];
  const entries = [...outputs.matchAll(/^([a-z_]+) = (.+)$/gm)];
  assert.deepEqual(entries.map(m => m[1]), [
    'push_to_pull_request_branch', 'add_comment', 'noop', 'missing_tool', 'missing_data',
  ]);
  assert.equal(entries.find(m => m[1] === 'add_comment')[2], '{ max = 1 }');
  assert.match(bounds, /^max_outputs = 3$/m);
  const profile = fs.readFileSync(path.join(__dirname, '../agentic-job/profiles/fix.md'), 'utf8');
  for (const rule of [
    'leave the working tree unchanged', 'one `add_comment` safe output with a `body`',
    'Do not request `push_to_pull_request_branch` or write a replacement series when there is no change to push',
    'Do not invent a patch',
  ]) assert.ok(profile.includes(rule), rule);
});

// Beside bot-poll nothing here may write: the poll is always a dry run,
// and the scheduler and coordinator are never given --apply, whatever a
// variable says. Turning any of them on is a change to this file.
test('workflow previews only: no apply, no state, no successor', () => {
  const yml = fs.readFileSync(path.join(__dirname, '../workflows/poll.yml'), 'utf8');
  const job = yml.slice(yml.indexOf('\n  poll:\n'));
  assert.equal((yml.match(/run: just poll /g) ?? []).length, 1);
  assert.match(job, /\n {8}run: just poll --dry-run\n/);
  const code = yml.split('\n').filter(line => !line.trim().startsWith('#')).join('\n');
  assert.doesNotMatch(code, /--apply|APPLY|vars\.|inputs\.|workflow_run|gh workflow run|upload-artifact|actions: write/);
  assert.doesNotMatch(yml, /node \.github\/poll\/poll.cjs|\n  agent-board:/);
  // Read-only by construction: no step has the bot's write token.
  assert.equal((code.match(/GH_TOKEN: \$\{\{ secrets\.JMARRERO_BOT_READ_TOKEN \}\}/g) ?? []).length, 4);
  assert.equal((code.match(/secrets\.JMARRERO_BOT_READ_TOKEN\b/g) ?? []).length, 5);
  assert.equal((code.match(/secrets\./g) ?? []).length, 5);
  assert.match(job, /DISPATCH_TOKEN: \$\{\{ github.token \}\}/);
  assert.equal((yml.match(/run: just build-agent-board/g) ?? []).length, 2);
  assert.match(job, /runs-on: ubuntu-26.04/);
  assert.match(yml, /\n  token:\n    if: \$\{\{ github.ref == format\('refs\/heads\/\{0\}', github.event.repository.default_branch\) \}\}\n/);
  assert.match(job, /persist-credentials: false/);
  for (const step of ['Epic census', 'Coordinator']) assert.ok(yml.includes(`- name: ${step}`));
  assert.ok(yml.includes('run: node .github/poll/schedule.cjs 2>&1'));
  assert.ok(yml.includes('run: just coordinator\n'));
  const jobMinutes = Number(/^ {4}timeout-minutes: (\d+)$/m.exec(job)[1]);
  const boundedSteps = [...job.matchAll(/^ {8}timeout-minutes: (\d+)$/gm)].reduce((sum, m) => sum + Number(m[1]), 0);
  assert.ok(jobMinutes >= boundedSteps + 5, 'checkout and setup overhead fit the job');
});

test('agent-board is built at the pinned commit', () => {
  const justfile = fs.readFileSync(path.join(__dirname, '../../Justfile'), 'utf8');
  const recipe = justfile.split('\nbuild-agent-board:\n')[1].split('\n\n')[0];
  assert.match(recipe, /rev=\$\(jq -er \.rev \.github\/poll\/agent-board\.json\)/);
  assert.match(recipe, /--rev "\$rev"/);
  assert.doesNotMatch(recipe, /ls-remote|--branch|\.branch/);
});

test('pools.json has what dispatch.yml reads, and a well-formed allowance', () => {
  const pools = require('../agentic-job/pools.json');
  for (const [name, pool] of Object.entries(pools)) {
    for (const key of ['agent', 'model', 'budget']) assert.match(pool[key], /^\S+$/, `${name}.${key}`);
    assert.match(pool.budget, /^[1-9]\d*$/, `${name}.budget`);
    assert.ok(!('allowance' in pool), `${name}.allowance`);
  }
  // claude only, for now: the wrapper refuses every other agent.
  assert.deepEqual(Object.keys(pools), ['claude']);
  assert.equal(pools.claude.agent, 'claude');
});

test('dispatch.yml turns on the skills for implement and fix only', () => {
  const dispatch = fs.readFileSync(path.join(__dirname, '../workflows/dispatch.yml'), 'utf8');
  assert.deepEqual(dispatch.match(/^ {6}skills: .*$/gm), ["      skills: ${{ needs.profile.outputs.skilled == 'true' && (inputs.kind == 'implement' || inputs.kind == 'fix') }}"]);
  const profile = kind => fs.readFileSync(path.join(__dirname, `../agentic-job/profiles/${kind}.md`), 'utf8');
  assert.match(profile('implement'), /^Use the implement skill\./);
  assert.doesNotMatch(profile('implement'), /AGENTS\.md|subagent|left undone/);
  assert.doesNotMatch(profile('implement-full'), /\bskill\b/);
  assert.match(profile('implement-full'), /^Implement this issue properly with tests/);
  for (const rule of profile('implement').trim().split(/(?<=\.) /).slice(1)) assert.ok(profile('implement-full').includes(rule), rule);
  assert.doesNotMatch(profile('fix'), /implement skill/);
  for (const kind of ['research', 'triage', 'review']) assert.doesNotMatch(profile(kind), /\bskill\b/);
});

test('dispatch.yml gives an agent without skills the full implement profile', () => {
  const dispatch = fs.readFileSync(path.join(__dirname, '../workflows/dispatch.yml'), 'utf8');
  const stepScript = name => {
    const re = new RegExp(`^ {6}- name: ${name}\\n(?: {8}.*\\n)*? {8}run: \\|\\n((?:(?: {10}.*)?\\n)+)`, 'm');
    const step = re.exec(dispatch)?.[1];
    assert.ok(step, name);
    return step.replace(/^ {10}/gm, '');
  };
  assert.ok(dispatch.indexOf('- name: Resolve the pool') < dispatch.indexOf('- name: Put the profile before the task'));
  const poolStep = stepScript('Resolve the pool');
  const composeStep = stepScript('Put the profile before the task');
  const pools = require('../agentic-job/pools.json');
  const profiles = path.join(__dirname, '../agentic-job/profiles');
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'dispatch-'));
  const outputs = text => Object.fromEntries([...text.matchAll(/^([a-z]+)=(.*)$/gm)].map(m => [m[1], m[2]]));
  let n = 0;
  const bash = (script, env) => {
    const out = path.join(dir, String(n++));
    fs.writeFileSync(out, '');
    execFileSync('bash', ['-eo', 'pipefail', '-c', script], {
      cwd: path.join(__dirname, '../..'), stdio: 'pipe',
      env: { ...process.env, ...env, GITHUB_OUTPUT: out },
    });
    return fs.readFileSync(out, 'utf8');
  };
  const run = (pool, kind, agent = 'claude') => {
    try {
      const resolved = outputs(bash(poolStep, { POOL: pool, KIND: kind, AGENT: agent }));
      const composed = bash(composeStep, { KIND: kind, TASK: 'the task', SKILLED: resolved.skilled });
      const task = /^task<<(task-[0-9a-f]{32})\n([\s\S]*)\n\1\n$/.exec(composed)?.[2];
      assert.ok(task, composed);
      return { ...resolved, task };
    } catch (e) {
      if (e instanceof assert.AssertionError) throw e;
      return null;
    }
  };
  const profile = name => fs.readFileSync(path.join(profiles, `${name}.md`), 'utf8');
  const expected = (kind, skilled) => `${profile(!skilled && fs.existsSync(path.join(profiles, `${kind}-full.md`)) ? `${kind}-full` : kind)}\nthe task`;
  for (const [name, pool] of Object.entries(pools)) {
    const skilled = ['claude', 'fake'].includes(pool.agent);
    for (const kind of ['implement', 'fix', 'triage', 'research', 'review']) {
      const r = run(name, kind, 'opencode');
      assert.ok(r, `${kind} on ${name}`);
      assert.equal(r.agent, pool.agent);
      assert.equal(r.skilled, String(skilled));
      assert.equal(r.task, expected(kind, skilled));
    }
  }
  for (const agent of ['claude', 'fake']) {
    assert.deepEqual(run('', 'implement', agent), { skilled: 'true', agent: '', model: '', budget: '', task: expected('implement', true) });
  }
  // The wrapper refuses any other agent; were one set, it would get the
  // full profile rather than none.
  assert.deepEqual(run('', 'implement', 'opencode'), { skilled: 'false', agent: '', model: '', budget: '', task: expected('implement', false) });
  assert.equal(run('', 'fix', 'opencode').task, expected('fix', false));
  assert.notEqual(expected('implement', false), expected('implement', true));
  assert.equal(expected('fix', false), expected('fix', true));
  assert.equal(run('nonesuch', 'fix'), null);
  assert.equal(run('', 'implement-full', 'opencode'), null);
});

// Until jmarrero creates the read token, every scheduled pass would fail:
// the token job says whether it exists, and both acting jobs need it.
test('without the read token both jobs are skipped, not failed', t => {
  const yml = fs.readFileSync(path.join(__dirname, '../workflows/poll.yml'), 'utf8');
  for (const name of ['board', 'poll']) {
    const job = yml.split(`\n  ${name}:\n`)[1].split(/\n {2}[a-z-]+:\n/)[0];
    assert.match(job, /^(?: {4}#.*\n)*? {4}needs: token\n {4}if: \$\{\{ needs\.token\.outputs\.ready == 'true' \}\}\n/m, name);
  }
  const token = yml.split('\n  token:\n')[1].split(/\n\n {2}#/)[0];
  assert.match(token, /\n {4}permissions: \{\}\n/);
  assert.match(token, /\n {6}ready: \$\{\{ steps\.token\.outputs\.ready \}\}\n/);
  // The step's own script, run as Actions would, with and without a token.
  const script = /\n {8}run: \|\n((?: {10}.*\n)+)/.exec(`${token}\n`)[1].replace(/^ {10}/gm, '');
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'poll-token-'));
  t.after(() => fs.rmSync(dir, { recursive: true, force: true }));
  for (const [value, ready] of [['', 'false'], ['ghp_example', 'true']]) {
    const output = path.join(dir, `out-${ready}`);
    fs.writeFileSync(output, '');
    const stdout = execFileSync('bash', ['-eo', 'pipefail', '-c', script], {
      env: { ...process.env, READ_TOKEN: value, GITHUB_OUTPUT: output }, encoding: 'utf8',
    });
    assert.equal(fs.readFileSync(output, 'utf8'), `ready=${ready}\n`);
    assert.equal(/::notice::/.test(stdout), ready === 'false');
    assert.doesNotMatch(stdout, /ghp_example/);
  }
});

// Only implement, the kind that pushes to the bot's fork and opens a pull
// request, enters agent-apply, where the PAT is; the rest use the job token.
test('trial.yml enters agent-apply only for implement', () => {
  const trial = fs.readFileSync(path.join(__dirname, '../workflows/trial.yml'), 'utf8');
  const code = trial.split('\n').filter(line => !line.trim().startsWith('#')).join('\n');
  const lines = [...code.matchAll(/^ {6}apply-environment: \$\{\{ (.+) \}\}$/gm)];
  assert.equal(lines.length, 1);
  assert.equal((code.match(/agent-apply/g) ?? []).length, 1);
  assert.doesNotMatch(code, /\n {4}environment:/);
  // The expression is valid JavaScript as written.
  const environment = new Function('inputs', `return ${lines[0][1]};`);
  const kinds = /options: \[([^\]]+)\]/.exec(trial)[1].split(',').map(k => k.trim());
  assert.deepEqual(kinds, ['implement', 'triage', 'research', 'review']);
  for (const kind of kinds) assert.equal(environment({ kind }), kind === 'implement' ? 'agent-apply' : '', kind);
  assert.match(code, /\n {6}SAFE_OUTPUTS_PAT: \$\{\{ secrets\.SAFE_OUTPUTS_PAT \}\}\n/);
  assert.equal((code.match(/secrets\./g) ?? []).length, 1);
});

// Every action and reusable workflow is pinned by commit, our own
// jmarrero-forge/actions included; local ones are this repository's.
test('workflows pin every action and reusable workflow by commit', () => {
  const dir = path.join(__dirname, '../workflows');
  let seen = 0;
  for (const file of fs.readdirSync(dir).filter(f => f.endsWith('.yml'))) {
    for (const [, ref] of fs.readFileSync(path.join(dir, file), 'utf8').matchAll(/^\s*(?:- )?uses:\s*(\S+)/gm)) {
      seen++;
      assert.match(ref, /^[\w.-]+\/[\w.\/-]+@[0-9a-f]{40}$/, `${file}: ${ref}`);
    }
  }
  assert.ok(seen > 0);
});

// The dispatch and review wrappers come from one commit of
// jmarrero-forge/actions, and the apply token is ours, never inherited.
test('dispatch.yml and review.yml call our wrappers at one commit, with our secret', () => {
  const read = file => fs.readFileSync(path.join(__dirname, '../workflows', file), 'utf8');
  const dispatch = read('dispatch.yml');
  const review = read('review.yml');
  const d = /uses: jmarrero-forge\/actions\/\.github\/workflows\/jmarrero-agentic-job\.yml@([0-9a-f]{40})\n/.exec(dispatch);
  const r = /uses: jmarrero-forge\/actions\/\.github\/workflows\/jmarrero-review\.yml@([0-9a-f]{40})\n/.exec(review);
  assert.ok(d && r);
  assert.equal(d[1], r[1]);
  // The PAT is the agent-apply environment's secret of this name, never an
  // organization or repository secret under another.
  assert.match(dispatch, /\n {6}SAFE_OUTPUTS_PAT: \$\{\{ secrets\.SAFE_OUTPUTS_PAT \}\}\n/);
  assert.match(dispatch, /\n {6}apply-environment: agent-apply\n/);
  for (const text of [dispatch, review]) assert.doesNotMatch(text, /secrets: inherit|CGWALTERS|JMARRERO_BOT_PAT|cgwalters-forge\/actions/);
  assert.match(review, /\n {6}vars\.AGENT_REVIEW != '' && \(/);
  assert.doesNotMatch(review, /secrets/);
});
