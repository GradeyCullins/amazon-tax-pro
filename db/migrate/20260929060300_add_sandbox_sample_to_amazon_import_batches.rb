class AddSandboxSampleToAmazonImportBatches < ActiveRecord::Migration[8.1]
  def change
    add_column :amazon_import_batches, :sandbox_sample, :boolean, default: false, null: false
  end
end
