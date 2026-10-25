class AddMetricsToResponses < ActiveRecord::Migration[8.1]
  def change
    # Token counts and timings reported by Ollama. Durations are in nanoseconds.
    change_table :responses, bulk: true do |t|
      t.integer :prompt_eval_count
      t.integer :eval_count
      t.bigint :load_duration
      t.bigint :prompt_eval_duration
      t.bigint :eval_duration
      t.bigint :total_duration
    end
  end
end
