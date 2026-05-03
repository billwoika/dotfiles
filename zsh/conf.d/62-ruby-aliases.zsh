# $ZDOTDIR/conf.d/62-ruby-aliases.zsh
# ─────────────────────────────────────────────────────────────────────
# Ruby / Rails / Bundler domain aliases.
# Core `be`, `bi`, `rvr`, `rvi` are in 60-aliases.zsh.
# ─────────────────────────────────────────────────────────────────────

# Rails server / console
alias rs='rails server'
alias rc='DISABLE_PRY_RAILS=1 rails console'

# Always use bundled rake, not the system one
alias rake='bundle exec rake'
alias sidekiq='bundle exec sidekiq'

# Yarn — kept as a transitional alias for teams migrating to bun.
# Drop once the team is fully on bun (Section 8.3).
alias yi='yarn install'
alias yd='yarn deps'

# DB migrations — adjust schema names to match your app.
migrate-rails-db() {
  rails db:migrate:primary && rails db:migrate:data_warehouse
}
alias rdbm='RAILS_ENV=development migrate-rails-db'
alias rdbmt='RAILS_ENV=test migrate-rails-db'

# Asset precompile (one-off for production-like builds)
alias compile-rails-assets='rails assets:precompile'

# Bring up project-local supporting services (postgres, redis, etc.).
# Adjust the --project-directory path to your docker-compose setup.
alias rdeps='docker compose --project-directory $HOME/vscode up -d'

# Clean test output runner
alias t-rspec='bundle exec rspec --format progress --color'
