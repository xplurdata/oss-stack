# Security Policy

## Supported Versions

| Version | Supported |
|---------|-----------|
| 1.0.x   | ✅ Yes    |

## Reporting a Vulnerability

**Please do not report security vulnerabilities through public GitHub issues.**

If you discover a security vulnerability in XD-oss-stack, please report it responsibly:

**Email:** bridge@xplurdata.com

Include the following in your report:
- Description of the vulnerability
- Steps to reproduce
- Potential impact
- Suggested fix (if any)

We will acknowledge receipt within **48 hours** and aim to release a fix within **14 days** for critical issues.

## Security Considerations

### Default Credentials
XD-oss-stack ships with default credentials (`admin` / `admin`) for the web UI and internal Doris database users. **Change these immediately after installation** in a production environment.

### Network Exposure
By default the stack binds to `0.0.0.0`. In production:
- Place a reverse proxy (nginx, Caddy) with TLS in front of port 80
- Restrict port 4318 (OTLP) to trusted networks only
- Do not expose Doris ports (8030, 9030, 8040) to the public internet

### Image Security
All container images are scanned on every push using Trivy. Scan results are available in the [Security tab](https://github.com/xplurdata/oss-stack/security/code-scanning).

## Scope

| In Scope | Out of Scope |
|----------|-------------|
| XD-oss-stack installer (`install.sh`) | Third-party dependencies (Apache Doris, OTel Collector) |
| XD-APP and XD-API | Infrastructure of the reporter |
| Docker Compose configuration | Social engineering |
