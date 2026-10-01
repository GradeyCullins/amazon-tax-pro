ENV["BUNDLE_GEMFILE"] ||= File.expand_path("../Gemfile", __dir__)

require "bundler/setup"
if Gem.win_platform?
  require "active_model"
  validations_dir = File.join(Gem::Specification.find_by_name("activemodel").full_gem_path, "lib/active_model/validations")
  Dir.chdir(validations_dir) { Dir["*.rb"].each { |name| require File.join(validations_dir, name) } }
  require "active_model/validations"
end
