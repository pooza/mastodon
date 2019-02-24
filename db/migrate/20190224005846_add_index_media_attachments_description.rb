class AddIndexMediaAttachmentsDescription < ActiveRecord::Migration[5.2]
  disable_ddl_transaction!

  def change
    add_index :media_attachments, :description, algorithm: :concurrently
  end
end
