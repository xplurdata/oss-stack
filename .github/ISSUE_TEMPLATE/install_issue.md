---
name: Installation Issue
about: Problem during installation
title: '[INSTALL] '
labels: installation
assignees: ''
---

## Installation Step That Failed
Which step failed? (e.g. Pulling images / Starting containers / Waiting for services)

## Error Message
```
# Paste the exact error here
```

## Install Command Used
```bash
bash -c "$(curl -fsSL https://raw.githubusercontent.com/xplurdata/oss-stack/main/install.sh)"
```

## Environment
- OS: [e.g. Ubuntu 22.04 / macOS 13]
- Architecture: [e.g. amd64 / arm64 (Apple Silicon)]
- Docker version: [e.g. 24.0.5]
- RAM: [e.g. 8 GB]
- Free disk: [e.g. 50 GB]

## Container Logs
```
# docker logs otel-doris-fe
# docker logs otel-doris-be
# docker logs otel-app
```

## Did you try cleanup and retry?
- [ ] Yes — `docker compose -f ~/xd-oss-stack/docker-compose.yml down -v && sudo rm -rf /var/lib/xd-oss-stack && docker network prune -f`

---
💬 Need faster help? Join our [Slack](https://xplurdata.slack.com/join/shared_invite/zt-3ztbx9k5e-ZAqInDjoyoICfB2ohq9NsQ#/shared-invite/email)
