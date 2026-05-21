# frozen_string_literal: true

require_relative "lib/active_record/trino/version"

Gem::Specification.new do |spec|
  spec.name = "activerecord-trino-adapter"
  spec.version = ActiveRecord::Trino::VERSION
  spec.authors = ["Garett Arrowood"]
  spec.email = ["garettarrowood@gmail.com"]

  spec.summary = "Read-only ActiveRecord adapter for Trino"
  spec.description = "A read-only ActiveRecord SQL adapter for Trino, built on top of the " \
                     "trino-client gem. Lets Rails applications query a Trino data warehouse " \
                     "using familiar ActiveRecord scopes, where clauses, and joins, while " \
                     "preventing accidental writes."
  spec.homepage = "https://github.com/powerhome/activerecord-trino-adapter"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.2"

  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = spec.homepage
  spec.metadata["changelog_uri"] = "#{spec.homepage}/blob/main/CHANGELOG.md"
  spec.metadata["rubygems_mfa_required"] = "true"

  spec.files = Dir["{lib}/**/*", "README.md", "LICENSE.txt"]
  spec.require_paths = ["lib"]

  spec.add_dependency "activerecord", ">= 7.1", "< 8.1"
  spec.add_dependency "activesupport", ">= 7.1", "< 8.1"
  spec.add_dependency "trino-client", "2.2.4"

  spec.add_development_dependency "appraisal", "2.5.0"
  spec.add_development_dependency "license_finder", "7.2.1"
  spec.add_development_dependency "pry-byebug", "3.10.1"
  spec.add_development_dependency "rspec", "3.13.2"
  spec.add_development_dependency "rubocop", "1.82.1"
  spec.add_development_dependency "rubocop-powerhome"
  spec.add_development_dependency "webmock", "3.26.2"
end
