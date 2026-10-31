# Rails code quality checks

This project already incorporates a range of quality checks. This includes RuboCop, Brakeman, gem vulnerability scanning, importmap auditing, and Rails tests. These are based on [Rails’ recommended CI setup](https://github.com/rails/rails/blob/main/guides/source/getting_started.md).

This note covers some other recommended improvements.

## Recommended improvements

### 1. Browser system tests

Add a small suite covering critical user flows. Controller tests do not catch broken Stimulus interactions or browser rendering. System tests are currently commented out in `config/ci.rb`.

### 2. Test coverage with SimpleCov

Measure line and branch coverage to find untested behavior. Establish a baseline and prevent regressions rather than immediately demanding 100% coverage.

### 3. ERB linting

Implemented with `erb_lint` in local and hosted CI. Run `docker compose exec app bin/erb_lint --lint-all` (or `docker compose run --rm app bin/erb_lint --lint-all` when the app is stopped). The configuration covers all ERB views, including Turbo Stream templates, with parser, comment syntax, and interpolation safety checks. Style rules remain opt-in for later adoption.

### 4. N+1 query detection

Use Bullet during development and selected tests to catch query counts that grow with the number of records. This is particularly useful on association-heavy listing pages.

### 5. JavaScript linting

Add ESLint for Stimulus controllers to catch undefined variables, unused code, and common mistakes. Keep the configuration small.

Tool references:

- [SimpleCov](https://github.com/simplecov-ruby/simplecov)
- [erb_lint](https://github.com/Shopify/erb_lint)
- [Bullet](https://github.com/flyerhzm/bullet)

## Additional inexpensive checks

- **Autoloading:** run `docker compose run --rm app bin/rails zeitwerk:check` to catch constant naming and file placement problems.
- **Deployment smoke checks:** verify production asset precompilation and database preparation against a fresh disposable database.
- **Local and hosted CI consistency:** `config/ci.rb` checks seed loading, but the GitHub workflow currently does not. Align the checks so both environments enforce the same expectations.

Use Docker Compose for Ruby, Rails, Bundler, and test commands. When the app container is already running, use `docker compose exec app ...` instead.

## Suggested rollout

Start with pull request enforcement, SimpleCov, ERB linting, and a few critical browser tests. Add query detection next.

Defer strict complexity limits and additional code-smell tools until there are concrete maintenance problems they would help address.

The observations above describe the repository when this note was written; they are recommendations, not a record of completed changes.
