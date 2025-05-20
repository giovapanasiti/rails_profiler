# Rails Profiler ✨

<!--[![Gem Version](https://badge.fury.io/rb/rails_profiler.svg)](https://badge.fury.io/rb/rails_profiler) <!-- Replace with your actual gem name if different -->

**Rails Profiler** is your ultimate co-pilot for understanding and supercharging your Ruby on Rails application's performance. Dive deep into request lifecycles, pinpoint slow database queries, identify code bottlenecks, and visualize complex interactions – all through a beautiful and insightful web dashboard. Designed with production in mind, it's lightweight, configurable, and ready to help you make your app fly! 🚀

![Rails Profiler Dashboard Screenshot](https://via.placeholder.com/800x400.png?text=Rails+Profiler+Dashboard+Overview)
*(Imagine a stunning screenshot of your dashboard's overview page here!)*

## 🌟 Key Features

*   📊 **Comprehensive Dashboard:** Get a bird's-eye view of your app's health with stats, charts for request volume, response times, performance breakdown, and query distribution.
*   🔍 **Detailed Request Tracing:** Drill down into individual requests to see timelines, parameters, status codes, and a full breakdown of where time is spent.
*   🐢 **Slow Query Detection:** Automatically identify and list the slowest SQL queries across your application, complete with full SQL and context.
*   🔥 **Code Hotspot Analysis:** Pinpoint slow controllers, models, and view templates that are consuming the most time.
*   🌲 **Flame Graphs:** Visualize method execution stacks to quickly identify performance bottlenecks within your code for specific requests.
*   🔗 **Call Graphs:** Understand the relationships and call sequences between methods in a profiled request.
*   📈 **Performance Trends:** Track request volume and response times over hours, days, or weeks to spot regressions or improvements.
*   ⚙️ **Automatic & Manual Profiling:**
    *   **Automatic:** Controller actions, ActiveRecord model methods (common ones), and view rendering are profiled out-of-the-box.
    *   **Manual:** Use `RailsProfiler.profile("my_block") { ... }` for fine-grained profiling of specific code sections.
*   💾 **Flexible Storage:**
    *   **Redis (Default):** Fast, efficient, with automatic data expiration. Includes a compatibility patch for resilience against common Redis client version issues.
    *   **Database:** Persistent storage using ActiveRecord, with a Rake task for cleanup.
*   🚀 **Production Ready:**
    *   **Request Sampling:** Configurable to minimize overhead in production.
    *   **Secure Dashboard:** HTTP Basic Authentication protects your valuable performance data.
    *   **Lightweight Design:** Minimal impact when disabled or with low sampling rates.
*   🎨 **Customizable UI:** Includes a theme toggle (light/dark mode) for the dashboard.
*   🔧 **Configurable:** Tailor most aspects of the profiler to your needs.

## 🛠️ Installation

1.  Add `rails_profiler` to your application's Gemfile:

    ```ruby
    gem 'rails_profiler'
    ```

2.  Install the gem:

    ```bash
    bundle install
    ```

3.  **Database Storage (Optional):** If you plan to use the `:database` storage backend, you need to run the migration:

    ```bash
    # The gem should provide a task for this, or you can copy the migration manually
    # rails generate rails_profiler:install (if available)
    rails db:migrate
    ```
    This creates the `rails_profiler_profiles` table.

4.  Mount the Rails Profiler engine in your `config/routes.rb`:

    ```ruby
    mount RailsProfiler::Engine => '/profiler' # Or any path you prefer
    ```

## ⚙️ Configuration

Create an initializer file (e.g., `config/initializers/rails_profiler.rb`) to configure the profiler:

```ruby
RailsProfiler.configure do |config|
  # General
  config.enabled = !Rails.env.test?  # Enable profiling (default: true, good to disable for tests)
  config.sample_rate = 0.1           # Profile 10% of requests (default: 0.1)

  # Storage
  config.storage_backend = :redis     # :redis (default) or :database
  config.redis_url = ENV.fetch('REDIS_PROFILER_URL', 'redis://localhost:6379/12') # Default Redis URL
  config.retention_days = 7           # Data retention period (default: 7 days)

  # Dashboard Authentication
  config.dashboard_username = ENV.fetch('PROFILER_USERNAME', 'admin')
  config.dashboard_password = ENV.fetch('PROFILER_PASSWORD', 'password')

  # Feature Toggles
  config.track_queries = true         # Track SQL queries (default: true)
  config.track_code = true            # Enable code profiling features (default: true)

  # Automatic Profiling (when track_code is true)
  config.profile_controllers = true   # Auto-profile controller actions (default: true)
  config.profile_models = false # DEPRECATED / NO LONGER AVAILABLE Auto-profile common ActiveRecord methods (default: true).
                                    # Query tracking is handled by `track_queries`.
                                    # Model-specific code can be profiled via `auto_profile_methods`.

  # Define specific methods/classes for automatic profiling (powerful!)
  # Examples:
  #   'User#process_payment'
  #   'ReportService.*' (all class methods)
  #   'Invoice#*' (all instance methods)
  config.auto_profile_methods = [
    # 'MyCriticalService#perform_heavy_lifting',
  ]

  # UI Customization (see lib/rails_profiler/configuration.rb for all options)
  # config.color_scheme[:primary] = "#your_brand_color"
end
```

✨ **Note on Redis Compatibility:** `RailsProfiler` includes a patch to enhance compatibility with various `redis-rb` and `redis-client` gem versions. If an incompatible Redis setup is detected, it will attempt to gracefully log the issue and may fall back to `:database` storage if available, prioritizing application stability.

## 🚀 Usage

### Accessing the Dashboard

Navigate to the path you mounted the engine at (e.g., `http://localhost:3000/profiler`). You'll be prompted for the username and password you configured.

### Manual Code Profiling

For granular insights into specific code paths, use the `profile` block:

```ruby
# Profile a specific block with a custom name
RailsProfiler.profile("MyService#complex_algorithm") do
  # ... your computationally intensive code ...
end

# Profile with an automatically generated name (based on file and line number)
RailsProfiler.profile do
  # ... some other code ...
end
```
Manual profiling is active if `config.enabled`, `config.track_code` are true, and the current request is sampled.

## 📊 Dashboard Deep Dive

The Rails Profiler dashboard is packed with information to help you optimize:

*   **Overview:**
    *   At-a-glance statistics: Total Requests, Average Response Time, Average Queries, etc.
    *   Interactive charts for Request Volume, Response Time trends, Performance Breakdown (DB, View, Ruby), and Query Type Distribution.
    *   Quick links to Top Endpoints and Recent Slow Queries.

*   **Requests:**
    *   Paginated list of all captured request profiles.
    *   Details: Path, method, status, duration, query counts, and timestamps.
    *   Click "View" for an in-depth analysis of any request.

*   **Request Detail View:**
    *   Comprehensive timeline visualizing time spent in Database, View, Controller, and Ruby code.
    *   Detailed breakdown cards for each segment.
    *   Full list of SQL queries executed, with individual timings and full SQL statements.
    *   Code Hotspots specific to that request (if `track_code` is enabled).
    *   Request parameters (viewable in a modal).

*   **Endpoints:**
    *   Aggregated performance data for each `Controller#action`.
    *   Metrics: Request count, average duration, and breakdown of time spent (DB, View, Ruby).
    *   Click an endpoint to see individual traces for it.

*   **Slowest Queries:**
    *   A dedicated page listing the most time-consuming SQL queries across your application.
    *   Shows rank, duration, SQL (view full in modal), path, and links to the originating request profile.

*   **Trends:**
    *   Line charts illustrating request volume and average response time over 24 hours, 7 days, or 30 days.

*   **Code Hotspots:**
    *   Identifies overall performance hotspots across multiple requests:
        *   **Controller Hotspots:** Which controllers (and their top actions) are taking the most time.
        *   **Model Hotspots:** Models associated with significant database time/query counts.
        *   **View Hotspots:** View templates and partials (full path shown) with the longest rendering times.
        *(Note: General method hotspots are best visualized via Flame Graphs)*

*   **Flame Graph:**
    *   For a selected profiled request, this powerful visualization shows the execution stack and the relative time spent in different methods.
    *   Excellent for visually identifying deep bottlenecks in your Ruby code.
    *   Includes a table of method execution times for the selected profile.

*   **Call Graph:**
    *   Provides a force-directed graph illustrating how methods call each other within a selected profiled request.
    *   Helps understand the flow of execution and dependencies between methods.

## 💾 Storage Options

Rails Profiler offers two storage backends:

### 1. Redis (Default)
*   **Pros:** Fast, efficient, great for high-traffic environments. Uses Redis `SETEX` for automatic data expiration based on `config.retention_days`.
*   **Configuration:** Set `config.storage_backend = :redis` and configure `config.redis_url`.

### 2. Database
*   **Pros:** Persistent storage within your application's primary database. Good if you don't have a separate Redis instance or prefer SQL-based storage.
*   **Configuration:** Set `config.storage_backend = :database`.
*   **Cleanup:** Requires running the migration to create the `rails_profiler_profiles` table. A Rake task is provided for cleaning up old data:
    ```bash
    rails rails_profiler:cleanup
    ```
    It's recommended to run this periodically (e.g., via a cron job).

## ⚡ Performance Considerations

*   **Sampling is Key:** For production, use `config.sample_rate` (e.g., `0.01` for 1%, `0.1` for 10%) to minimize overhead. Profiling every request can be resource-intensive.
*   **Minimal Impact:** When disabled or for unsampled requests, the profiler adds negligible overhead.
*   **Efficient Query Tracking:** Uses `ActiveSupport::Notifications` for low-impact SQL monitoring.
*   **Redis vs. Database:** Redis is generally lower overhead for write-heavy profiling data.

## 🔒 Security

*   **Dashboard Authentication:** The dashboard is protected by HTTP Basic Authentication. Use strong, unique credentials for `config.dashboard_username` and `config.dashboard_password`, especially in production.
*   **Network Access:** Consider restricting access to the profiler's mount path (e.g., via IP allowlists, VPN) in production environments.
*   **Sensitive Data:** The profiler may display request parameters and SQL query details. Ensure your application's `Rails.application.config.filter_parameters` is configured to redact sensitive information if it might be captured.

## 🤝 Contributing

Contributions are welcome! If you'd like to help improve Rails Profiler:

1.  Fork the repository.
2.  Create your feature branch (`git checkout -b my-new-feature`).
3.  Commit your changes (`git commit -am 'Add some feature'`).
4.  Push to the branch (`git push origin my-new-feature`).
5.  Create a new Pull Request.

Please write tests for your changes and ensure the existing test suite passes.

## 📜 License

This gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).

---

**To make this README even "nicer":**

*   **Add actual screenshots** of the dashboard, flame graph, and call graph. Visuals are incredibly powerful.
*   **Consider a short GIF** demonstrating the dashboard's interactivity or the process of drilling down into a request.
*   **Add badges** for build status, code coverage, etc., once you have CI/CD set up.
*   **Refine the "Model Hotspots" description** based on exactly how it's implemented (is it purely based on `SELECT ... Load` query names, or does it involve `profile_models` config too?). The current code seems to rely on query names and `profile_models` was removed from `CodeProfiler`.
*   If the `rails_profiler:install:migrations` Rake task doesn't exist, clarify that the migration needs to be copied or provide a generator for it.

This version should be a great starting point!