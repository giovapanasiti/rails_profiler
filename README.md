# Rails Profiler

A comprehensive profiler for Rails applications that tracks database queries, code performance, and provides a web dashboard for production environments.

## Features

- **Query Tracking**: Automatically tracks all SQL queries with execution time and backtrace
- **Code Profiling**: Profile specific code blocks with the `RailsProfiler.profile` method
- **Production Ready**: Configurable sampling rate to minimize overhead
- **Web Dashboard**: Built-in Rails engine with authentication for viewing profiles
- **Multiple Storage Backends**: Redis (default) and database storage options
- **Configurable Retention**: Automatic cleanup of old profile data

## Installation

Add this gem to your Rails application's Gemfile:

```ruby
gem 'rails_profiler'
```

Then execute:
```bash
bundle install
```

## Configuration

Create an initializer `config/initializers/rails_profiler.rb`:

```ruby
RailsProfiler.configure do |config|
  config.enabled = Rails.env.production? || Rails.env.staging?
  config.storage_backend = :redis
  config.redis_url = ENV.fetch('REDIS_URL', 'redis://localhost:6379/0')
  config.sample_rate = 0.1 # Profile 10% of requests
  config.track_queries = true
  config.track_code = true
  config.retention_days = 7
  config.dashboard_username = ENV.fetch('PROFILER_USERNAME', 'admin')
  config.dashboard_password = ENV.fetch('PROFILER_PASSWORD', 'password')
end
```

## Usage

### Manual Code Profiling

```ruby
# Profile a specific block of code
RailsProfiler.profile("expensive_operation") do
  # Your code here
  User.expensive_calculation
end

# Profile with automatic naming based on location
RailsProfiler.profile do
  # This will be named based on the file and line
  perform_complex_task
end
```

### Dashboard Access

Mount the dashboard in your routes (`config/routes.rb`):

```ruby
mount RailsProfiler::Engine => '/profiler'
```

Visit `/profiler` in your application and log in with your configured credentials.

## Dashboard Features

- **Overview Statistics**: Average response times, query counts, and performance metrics
- **Profile List**: Browse all captured profiles with filtering options
- **Detailed Views**: Drill down into individual requests to see:
  - All executed SQL queries with execution times
  - Code profile blocks with durations
  - Full backtraces for debugging

## Storage Options

### Redis (Default)
Stores profiles in Redis with automatic expiration based on retention settings.

### Database
Alternative storage using ActiveRecord (implementation extends the base gem).

## Security

The dashboard is protected with HTTP Basic Authentication. Make sure to:
1. Use strong credentials in production
2. Consider additional security measures (IP restrictions, VPN access, etc.)
3. Monitor access logs

## Performance Impact

The profiler is designed for production use:
- Configurable sampling rate (default: 10% of requests)
- Minimal overhead when disabled
- Efficient storage with automatic cleanup
- Non-blocking query tracking

## License

MIT License - see LICENSE file for details.