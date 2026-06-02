export const meta = {
  name: 'vet-artifacts-phaseA',
  description: 'Bounded upstream-verification of the 7 dotfile artifacts (one agent per artifact, hard agent cap, no per-claim fan-out), then adversarially refute only the findings',
  phases: [
    { title: 'Verify', detail: 'one agent per artifact, checks its drift-prone claims vs upstream' },
    { title: 'Refute', detail: 'independent refutation of each non-confirmed finding' },
  ],
}

// HARD BOUND: one verify agent per artifact. 7 artifacts -> max 7 verify agents.
// Refute fans out ONLY over actual findings (typically a handful), never over all claims.
// This cannot approach the 1000 cap — the whole point after the prior blowup.

const SOURCES = `
Authoritative sources (check the tool's own docs / man page / release notes; today is June 2026):
- git config: https://git-scm.com/docs/git-config  (verify version-gating: zdiff3 needs git 2.35+, rebase.updateRefs 2.38+, push.autoSetupRemote 2.37+, etc.)
- delta (pager): https://dandavison.github.io/delta/  (config keys: navigate, line-numbers, features, syntax-theme)
- OpenSSH ssh_config: https://man.openbsd.org/ssh_config  (AddKeysToAgent, IdentitiesOnly, ControlMaster/Path/Persist, ProxyJump, UseKeychain, IdentityAgent, StrictHostKeyChecking accept-new, UpdateHostKeys, HashKnownHosts)
- mise: https://mise.jdx.dev  (config.toml [tools]/[settings] keys: idiomatic_version_file_enable_tools, python.uv_venv_auto, github_attestations, status.* — confirm these settings exist and are spelled right)
- direnv stdlib: https://direnv.net/man/direnv-stdlib.1.html  (but the helper FUNCTIONS here are custom — verify the WRAPPED tool syntax instead)
- 1Password CLI: https://developer.1password.com/docs/cli/reference  (op read, op inject -i, op account list)
- HashiCorp Vault: https://developer.hashicorp.com/vault/docs/commands/kv/get  (vault kv get -field=)
- sops: https://github.com/getsops/sops  (sops -d)
- libsecret secret-tool: https://man.archlinux.org/man/secret-tool.1  (lookup attribute/value pairs)
- tmux: https://man.openbsd.org/tmux.1  (set-clipboard, terminal-overrides RGB/Ms, tmux-256color, key-table, bind -T root, escape-time, focus-events)
`

const ARTIFACTS = [
  { key: 'git-config', file: 'git/config', focus: 'Version-gated config keys especially: merge.conflictStyle=zdiff3 (git 2.35+), rebase.updateRefs (2.38+), push.autoSetupRemote (2.37+), fetch.pruneTags, branch.sort=-committerdate, the [delta] pager keys, includeIf gitdir behavior, gpg.format=ssh + allowedSignersFile. Flag any key that does not exist or is misspelled or whose behavior is misstated.' },
  { key: 'ssh-config', file: 'ssh/config.example', focus: 'OpenSSH directives: IdentitiesOnly, AddKeysToAgent, UseKeychain (macOS-only, ignored on Linux), ControlMaster/ControlPath/ControlPersist, ProxyJump, StrictHostKeyChecking accept-new, UpdateHostKeys yes, HashKnownHosts, IdentityAgent for 1Password. Confirm each directive name and stated behavior against current ssh_config(5).' },
  { key: 'direnvrc', file: 'direnv/direnvrc', focus: 'The helper functions are custom — do NOT flag them. Verify the WRAPPED external CLI syntax: op read, op inject -i, op account list (1Password); vault kv get -field= (Vault); sops -d (sops); secret-tool lookup service X account Y (libsecret) — is the attribute pairing correct?; security find-generic-password -a -s -w (macOS). Flag any wrapped-tool invocation whose flags/syntax are wrong on current versions.' },
  { key: 'tmux', file: 'tmux/tmux.conf', focus: 'tmux directives and version-gating: default-terminal tmux-256color, terminal-overrides RGB capability + the Ms OSC52 override, set-clipboard on, focus-events, escape-time, base-index/pane-base-index, mode-keys/status-keys emacs, the F12 nested-escape using set key-table / bind -T root / bind -T off / refresh-client -S. Confirm syntax is valid on current tmux (3.x+).' },
  { key: 'mise', file: 'mise/config.toml', focus: 'mise config schema: [tools] entries, [settings] keys (auto_install, python.compile, python.uv_venv_auto="create|source", idiomatic_version_file_enable_tools, github_attestations, status.show_tools/show_env), [env]. Confirm each setting KEY actually exists in current mise and is spelled correctly — mise renames settings occasionally. min_version format.' },
  { key: 'profile', file: 'profile', focus: 'Already edited this session (gcr socket fallback added). Re-confirm: POSIX-only constructs, XDG defaults, the SSH_AUTH_SOCK detection loop (gcr/ssh then ssh-agent.socket), PATH dedup via case. Flag any bashism or incorrect POSIX assumption.' },
  { key: 'bootstrap', file: 'bootstrap.sh', focus: 'Already edited this session (~/opensource added). Re-confirm: POSIX sh correctness, the symlink/backup logic, the rogue-injection audit grep patterns (NVM_DIR, VOLTA_HOME, pyenv init, asdf.sh, etc.), and that the printed "next steps" install commands (curl https://mise.run | sh, the rv installer URL) are current.' },
]

const FINDING_SCHEMA = {
  type: 'object',
  required: ['artifact', 'findings'],
  properties: {
    artifact: { type: 'string' },
    findings: {
      type: 'array',
      description: 'ONLY problems — claims/syntax that are wrong, outdated, or misstated. Empty array if the artifact is fully correct.',
      items: {
        type: 'object',
        required: ['locator', 'problem', 'verdict', 'confidence', 'correction', 'sourceUrl'],
        properties: {
          locator: { type: 'string', description: 'the exact line/directive/key in the file' },
          problem: { type: 'string', description: 'what is wrong' },
          verdict: { type: 'string', enum: ['wrong', 'outdated', 'misstated', 'uncertain'] },
          confidence: { type: 'string', enum: ['high', 'medium', 'low'] },
          correction: { type: 'string', description: 'the fix' },
          sourceUrl: { type: 'string', description: 'authoritative source actually checked' },
        },
      },
    },
  },
}

const REFUTE_SCHEMA = {
  type: 'object',
  required: ['survives', 'reasoning'],
  properties: {
    survives: { type: 'boolean' },
    reasoning: { type: 'string' },
    sourceUrl: { type: 'string' },
  },
}

phase('Verify')
log(`Phase A: verifying ${ARTIFACTS.length} dotfile artifacts (one agent each, hard cap ${ARTIFACTS.length})`)

// pipeline: each artifact verified, then its findings (if any) refuted — no barrier,
// no per-claim fan-out. Refute fans out over findings only (bounded, usually 0-3 per artifact).
const results = await pipeline(
  ARTIFACTS,
  (a) => agent(
    `Read the dotfile artifact \`${a.file}\` and verify its technical claims against CURRENT authoritative upstream sources (today is June 2026). Use the Read tool, then WebFetch/WebSearch.

FOCUS: ${a.focus}

${SOURCES}

Report ONLY problems (wrong/outdated/misstated/uncertain). Be conservative: if a directive or key is correct and current, do not report it. Empty findings array = the artifact checks out. For each problem give the exact locator, the correction, and the source URL you actually checked.`,
    { label: `verify:${a.key}`, phase: 'Verify', schema: FINDING_SCHEMA }
  ).then(r => ({ artifact: a.file, key: a.key, findings: (r && r.findings) || [] })),
  (verified) => {
    if (!verified.findings.length) return verified
    return parallel(verified.findings.map(f => () =>
      agent(
        `An auditor flagged a problem in the dotfile \`${verified.artifact}\`. Independently try to REFUTE it using authoritative upstream docs (today is June 2026). Default survives=false if you cannot independently confirm the auditor is right.

DIRECTIVE/LOCATOR: ${f.locator}
AUDITOR SAYS: ${f.problem}
VERDICT: ${f.verdict} (${f.confidence})
PROPOSED FIX: ${f.correction}
AUDITOR SOURCE: ${f.sourceUrl}

${SOURCES}

Consult a different authoritative source if you can. Does the problem hold up? survives=true only if you independently confirm it.`,
        { label: `refute:${verified.key}`, phase: 'Refute', schema: REFUTE_SCHEMA }
      ).then(ref => ({ ...f, refutation: ref })).catch(() => ({ ...f, refutation: { survives: false, reasoning: 'refute agent errored' } }))
    )).then(refuted => ({ ...verified, findings: refuted }))
  }
)

const all = results.filter(Boolean)
const confirmedFindings = all.flatMap(r => (r.findings || []).filter(f => !f.refutation || f.refutation.survives))
const dismissed = all.flatMap(r => (r.findings || []).filter(f => f.refutation && !f.refutation.survives))
const cleanArtifacts = all.filter(r => !(r.findings || []).some(f => !f.refutation || f.refutation.survives)).map(r => r.artifact)

phase('Refute')
log(`Phase A done: ${confirmedFindings.length} confirmed findings, ${dismissed.length} dismissed by refutation, ${cleanArtifacts.length}/${ARTIFACTS.length} artifacts clean`)

return {
  confirmedFindings,
  dismissed,
  cleanArtifacts,
  perArtifact: all.map(r => ({ artifact: r.artifact, problemCount: (r.findings || []).filter(f => !f.refutation || f.refutation.survives).length })),
}
