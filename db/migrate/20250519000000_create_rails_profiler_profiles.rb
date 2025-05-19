class CreateRailsProfilerProfiles < ActiveRecord::Migration[6.0]
  def change
    create_table :rails_profiler_profiles do |t|
      t.string :request_id, null: false, index: { unique: true }
      t.string :url
      t.string :method
      t.string :path
      t.string :format
      t.integer :status
      t.float :duration
      t.integer :query_count
      t.float :total_query_time
      t.datetime :started_at
      t.text :queries
      t.text :additional_data

      t.timestamps
    end

    add_index :rails_profiler_profiles, :started_at
  end
end