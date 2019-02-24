class AddIndexStatusesText < ActiveRecord::Migration[5.2]
  disable_ddl_transaction!

  def change
    add_index :statuses, :text, algorithm: :concurrently
  end
end
