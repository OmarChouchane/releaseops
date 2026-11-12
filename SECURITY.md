# Security policy

## Reporting a vulnerability

Please report vulnerabilities privately through GitHub:
**Security > Report a vulnerability** (`/security/advisories/new` on this repository).
Do not open a public issue for a security problem.

Include what you found, how to reproduce it, and the affected version or commit. You will get an
acknowledgement, and a fix or mitigation plan, as soon as the maintainer can review it.

## Supported versions

Only the latest commit on `main` is supported.

## How this repository handles security

- No credentials or state files are committed. Local passwords are generated per cluster.
- Images are pinned by digest, scanned with Trivy (fixable HIGH/CRITICAL findings fail the build) and
  come with an SBOM and a provenance attestation.
- GitHub Actions are pinned by commit SHA and run with minimal `permissions`.
- Accepted vulnerabilities live in [`.trivyignore.yaml`](.trivyignore.yaml), each with a reason and an
  expiry date.

See [docs/architecture.md](docs/architecture.md) for the full security summary.
