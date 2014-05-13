gh_issues_exporter
==================

Exports GitHub issues to CSV

Running
=======

1. Register [a github application](https://github.com/settings/applications/new)
2. `cp config.sample.yml config.yml`
3. Provide GitHub app credentials in `config.yml`
4. `bundle exec thin start`
