export const meta = {
  name: 'vet-docs-phaseB',
  description: 'Bounded upstream-verification of operations/, reference/ (incl. firmware), shell-environment/ docs — one agent per page, adversarial refute on findings only',
  phases: [
    { title: 'Verify', detail: 'one agent per doc page, checks its claims vs upstream' },
    { title: 'Refute', detail: 'independent refutation of each non-confirmed finding' },
  ],
}

// BOUND: one verify agent per page. ~37 pages -> ~37 verify agents.
// Refute fans out over findings only. Cannot approach the 1000 cap.

const SOURCES = `
Check the tool's/standard's OWN docs, man pages, RFCs, or release notes (today is June 2026). Examples:
- shell/POSIX: POSIX spec, dash/bash man pages, zsh docs (zshexpn, zshoptions), XDG Base Directory spec
- git/ssh/tmux/direnv/mise/delta: their official docs + man pages (as in Phase A)
- networking/DNS/VPN: relevant RFCs, ip(8)/ss(8)/resolvectl(1)/dig(1) man pages, WireGuard docs, systemd-resolved docs
- containers/podman networking: docs.podman.io, netavark/aardvark-dns docs
- firmware/UEFI: UEFI spec concepts, kernel.org admin-guide, fwupd/LVFS docs, efibootmgr(8), TPM2 (tpm2-tools), Secure Boot (sbctl/mokutil), GRUB manual, PCIe/ASPM + ACPI kernel docs, nvme-cli, smartctl
- Fedora/Debian platform: distro docs (these pages may overlap already-verified material — only flag NEW errors)
Be conservative: only flag claims that are wrong, outdated, or misstated on CURRENT versions. Stable, long-correct commands are not findings.
`

// Page list. reference/ EXCLUDES the 4 already-vetted (fedora, debian-ubuntu, macos, onboarding)
// but INCLUDES the full firmware/ subtree per user's choice.
const PAGES = [
  // operations/ (7)
  'docs/operations/dns.md',
  'docs/operations/ssh.md',
  'docs/operations/vpn.md',
  'docs/operations/proxy-and-capture.md',
  'docs/operations/container-networking.md',
  'docs/operations/secrets.md',
  'docs/operations/networking.md',
  // reference/ non-firmware, not-already-vetted (6)
  'docs/reference/disk-strategy.md',
  'docs/reference/troubleshooting.md',
  'docs/reference/repository.md',
  'docs/reference/customization.md',
  'docs/reference/test-suite.md',
  'docs/reference/platform-setup/index.md',
  'docs/reference/platform-setup/disk-strategy.md',
  'docs/reference/platform-setup/firmware-checklist.md',
  // reference/firmware/ full subtree (13)
  'docs/reference/firmware/index.md',
  'docs/reference/firmware/secure-boot.md',
  'docs/reference/firmware/tpm.md',
  'docs/reference/firmware/boot-management.md',
  'docs/reference/firmware/grub.md',
  'docs/reference/firmware/firmware-updates.md',
  'docs/reference/firmware/acpi.md',
  'docs/reference/firmware/pcie.md',
  'docs/reference/firmware/usb.md',
  'docs/reference/firmware/storage.md',
  'docs/reference/firmware/power-thermal.md',
  'docs/reference/firmware/virtualization.md',
  'docs/reference/firmware/hardware-topology.md',
  // shell-environment/ (12)
  'docs/shell-environment/architecture.md',
  'docs/shell-environment/posix-profile.md',
  'docs/shell-environment/xdg-and-posix.md',
  'docs/shell-environment/environment.md',
  'docs/shell-environment/installer-behavior.md',
  'docs/shell-environment/aliases.md',
  'docs/shell-environment/command-line-techniques.md',
  'docs/shell-environment/integration-strategy.md',
  'docs/shell-environment/performance.md',
  'docs/shell-environment/terminal.md',
  'docs/shell-environment/philosophy.md',
  'docs/shell-environment/index.md',
]

const FINDING_SCHEMA = {
  type: 'object',
  required: ['page', 'findings'],
  properties: {
    page: { type: 'string' },
    findings: {
      type: 'array',
      description: 'ONLY problems — wrong/outdated/misstated claims. Empty if the page is correct.',
      items: {
        type: 'object',
        required: ['locator', 'problem', 'verdict', 'confidence', 'correction', 'sourceUrl'],
        properties: {
          locator: { type: 'string', description: 'heading or quoted snippet locating the claim' },
          problem: { type: 'string' },
          verdict: { type: 'string', enum: ['wrong', 'outdated', 'misstated', 'uncertain'] },
          confidence: { type: 'string', enum: ['high', 'medium', 'low'] },
          correction: { type: 'string' },
          sourceUrl: { type: 'string' },
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
log(`Phase B: verifying ${PAGES.length} doc pages (one agent each), refute on findings only`)

const results = await pipeline(
  PAGES,
  (page) => agent(
    `Read the documentation page \`${page}\` and verify its technical claims against CURRENT authoritative upstream sources (today is June 2026). Use the Read tool, then WebFetch/WebSearch.

${SOURCES}

Report ONLY problems (wrong/outdated/misstated/uncertain). For each: the locator (heading or quoted text), the problem, the correction, and the source URL you actually checked. Empty findings array = the page checks out. Skip pure opinion/philosophy — only checkable facts.`,
    { label: `verify:${page.split('/').slice(-1)[0]}`, phase: 'Verify', schema: FINDING_SCHEMA }
  ).then(r => ({ page, findings: (r && r.findings) || [] })),
  (verified) => {
    if (!verified.findings.length) return verified
    return parallel(verified.findings.map(f => () =>
      agent(
        `An auditor flagged a problem in doc page \`${verified.page}\`. Independently try to REFUTE it via authoritative upstream docs (today is June 2026). Default survives=false unless you independently confirm the auditor is right.

LOCATOR: ${f.locator}
AUDITOR SAYS: ${f.problem}
VERDICT: ${f.verdict} (${f.confidence})
PROPOSED FIX: ${f.correction}
AUDITOR SOURCE: ${f.sourceUrl}

${SOURCES}

Consult a different authoritative source if possible. survives=true only if independently confirmed.`,
        { label: `refute:${verified.page.split('/').slice(-1)[0]}`, phase: 'Refute', schema: REFUTE_SCHEMA }
      ).then(ref => ({ ...f, page: verified.page, refutation: ref })).catch(() => ({ ...f, page: verified.page, refutation: { survives: false, reasoning: 'refute agent errored' } }))
    )).then(refuted => ({ ...verified, findings: refuted }))
  }
)

const all = results.filter(Boolean)
const confirmed = all.flatMap(r => (r.findings || []).filter(f => !f.refutation || f.refutation.survives))
const dismissed = all.flatMap(r => (r.findings || []).filter(f => f.refutation && !f.refutation.survives))
const cleanPages = all.filter(r => !(r.findings || []).some(f => !f.refutation || f.refutation.survives)).map(r => r.page)

phase('Refute')
log(`Phase B done: ${confirmed.length} confirmed, ${dismissed.length} dismissed, ${cleanPages.length}/${PAGES.length} pages clean`)

// Group confirmed findings by page for easy application
const byPage = {}
for (const f of confirmed) { (byPage[f.page] ||= []).push(f) }

return {
  summary: { pages: PAGES.length, confirmed: confirmed.length, dismissed: dismissed.length, cleanPages: cleanPages.length },
  confirmedByPage: byPage,
  confirmed,
  dismissed,
  cleanPages,
}
