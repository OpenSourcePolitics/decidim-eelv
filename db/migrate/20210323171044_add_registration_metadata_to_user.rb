class AddRegistrationMetadataToUser < ActiveRecord::Migration[5.2]
  def change
    add_column :decidim_users, :registration_metadata, :jsonb, null: true, default: {}
  end
end
