# Agents

Use Docker Compose for Ruby, Rails, Bundler, and test commands; the host Ruby environment is not part of this project.

- Start or refresh the app: `scripts/compose.sh`
- Run tests: `docker compose run --rm app bin/rails test`
- Run Rails commands: `docker compose run --rm app bin/rails <command>`
- Use `docker compose exec app ...` instead when the app container is already running.
