Gem::Specification.new do |spec|
  spec.name          = "rails_profiler"
  spec.version       = "1.0.0"
  spec.authors       = ["Your Name"]
  spec.email         = ["your.email@example.com"]
  spec.summary       = "Production Rails profiler with query tracking and dashboard"
  spec.description   = "A comprehensive profiler for Rails applications that tracks queries, code performance, and provides a web dashboard."
  spec.homepage      = "https://github.com/yourusername/rails_profiler"
  spec.license       = "MIT"

  spec.files         = Dir["{app,config,db,lib}/**/*", "MIT-LICENSE", "Rakefile", "README.md"]
  spec.require_paths = ["lib"]

  spec.add_dependency "rails", ">= 5.0"
  spec.add_dependency "redis", ">= 4.0"
  spec.add_dependency "chartkick", ">= 3.0"
  spec.add_dependency "groupdate", ">= 5.0"

  spec.add_development_dependency "rspec-rails"
  spec.add_development_dependency "factory_bot_rails"
  spec.add_development_dependency "sqlite3"
end