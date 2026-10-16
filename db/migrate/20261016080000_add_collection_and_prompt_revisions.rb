require "digest"

class AddCollectionAndPromptRevisions < ActiveRecord::Migration[8.1]
  class MigrationRecord < ActiveRecord::Base
    self.abstract_class = true
  end

  class MigrationCollection < MigrationRecord
    self.table_name = "collections"
  end

  class MigrationPrompt < MigrationRecord
    self.table_name = "prompts"
  end

  class MigrationTrial < MigrationRecord
    self.table_name = "trials"
  end

  class MigrationResponse < MigrationRecord
    self.table_name = "responses"
  end

  class MigrationCollectionRevision < MigrationRecord
    self.table_name = "collection_revisions"
  end

  class MigrationPromptRevision < MigrationRecord
    self.table_name = "prompt_revisions"
  end

  class MigrationMember < MigrationRecord
    self.table_name = "collection_revision_prompts"
  end

  def change
    create_table :collection_revisions do |table|
      table.references :collection, null: false, foreign_key: true
      table.integer :version, null: false
      table.string :name, null: false
      table.string :content_digest, null: false

      table.timestamps
    end
    add_index :collection_revisions, [ :collection_id, :version ], unique: true
    add_index :collection_revisions, [ :collection_id, :content_digest ], unique: true

    create_table :prompt_revisions do |table|
      table.references :prompt, null: false, foreign_key: true
      table.integer :version, null: false
      table.string :name, null: false
      table.text :template, null: false
      table.string :content_digest, null: false

      table.timestamps
    end
    add_index :prompt_revisions, [ :prompt_id, :version ], unique: true
    add_index :prompt_revisions, [ :prompt_id, :content_digest ], unique: true

    create_table :collection_revision_prompts do |table|
      table.references :collection_revision, null: false, foreign_key: true
      table.references :prompt_revision, null: false, foreign_key: true
      table.integer :position, null: false

      table.timestamps
    end
    add_index :collection_revision_prompts,
      [ :collection_revision_id, :prompt_revision_id ],
      unique: true,
      name: "index_revision_prompts_on_revision_and_prompt"
    add_index :collection_revision_prompts,
      [ :collection_revision_id, :position ],
      unique: true,
      name: "index_revision_prompts_on_revision_and_position"

    add_reference :trials, :collection_revision, foreign_key: true
    add_reference :responses, :collection_revision_prompt, foreign_key: true
    add_column :responses, :rendered_prompt, :text
    add_index :responses,
      [ :trial_id, :collection_revision_prompt_id ],
      unique: true,
      name: "index_responses_on_trial_and_revision_prompt"

    reversible do |direction|
      direction.up { backfill_revisions }
    end

    change_column_null :trials, :collection_revision_id, false
    change_column_null :responses, :collection_revision_prompt_id, false
    change_column_null :responses, :rendered_prompt, false
  end

  private

  def backfill_revisions
    [ MigrationCollectionRevision, MigrationPromptRevision, MigrationMember, MigrationTrial, MigrationResponse ].each(&:reset_column_information)

    MigrationCollection.find_each do |collection|
      prompts = MigrationPrompt.where(collection_id: collection.id).order(:position, :id)
      collection_revision = MigrationCollectionRevision.create!(
        collection_id: collection.id,
        version: 1,
        name: collection.name,
        content_digest: digest(collection.name, prompts.map { |prompt| [ prompt.id, prompt.name, prompt.template, prompt.position ] })
      )

      prompts.each_with_index do |prompt, position|
        prompt_revision = MigrationPromptRevision.create!(
          prompt_id: prompt.id,
          version: 1,
          name: prompt.name,
          template: prompt.template,
          content_digest: digest(prompt.name, prompt.template)
        )
        MigrationMember.create!(
          collection_revision_id: collection_revision.id,
          prompt_revision_id: prompt_revision.id,
          position: position
        )
      end

      MigrationTrial.where(collection_id: collection.id).update_all(collection_revision_id: collection_revision.id)
    end

    MigrationResponse.find_each do |response|
      trial = MigrationTrial.find(response.trial_id)
      prompt_revision = MigrationPromptRevision.find_by!(prompt_id: response.prompt_id)
      member = MigrationMember.find_by!(
        collection_revision_id: trial.collection_revision_id,
        prompt_revision_id: prompt_revision.id
      )
      response.update_columns(
        collection_revision_prompt_id: member.id,
        rendered_prompt: prompt_revision.template
      )
    end
  end

  def digest(*values)
    Digest::SHA256.hexdigest(values.to_json)
  end
end
