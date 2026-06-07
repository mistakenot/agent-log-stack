# Contributing

Thanks for your interest in contributing to agent-log-stack! This project is designed to give AI coding agents local observability over the apps and runtimes they drive.

## Getting Started

1. Fork and clone the repo.
2. Make sure you have Docker and Docker Compose installed.
3. Run `./start.sh` to bring up the stack.
4. Run `./scripts/e2e.sh` to verify everything works.

## Development Workflow

- Create a feature branch from `main`.
- Make your changes.
- Run `./scripts/e2e.sh` to confirm nothing is broken.
- Open a pull request against `main`.

## What to Contribute

- Bug fixes and reliability improvements.
- New integration helpers (loggers, plugins, framework adapters).
- Improvements to query scripts and CLI ergonomics.
- Documentation fixes and new examples.
- E2E test coverage for new features.

## Guidelines

- Keep scripts deterministic and non-interactive.
- Bind published ports to `127.0.0.1` by default.
- Never commit secrets, tokens, or API keys.
- Prefer flat `snake_case` fields in log schemas.
- Add E2E coverage for new ingest paths or query features.
- Keep the stack lightweight enough to run on a developer laptop.

## Reporting Issues

Open an issue on GitHub. Include:

- What you expected to happen.
- What actually happened.
- Output of `docker compose ps` and relevant container logs.
- Your OS and Docker/Compose versions.

## License

By contributing, you agree that your contributions will be licensed under the MIT License.
