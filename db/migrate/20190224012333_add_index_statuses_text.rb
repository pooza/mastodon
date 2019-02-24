class AddIndexStatusesText < ActiveRecord::Migration[5.2]
  disable_ddl_transaction!

  def change
    add_index :statuses, :text, :length => 8192, algorithm: :concurrently
  end
end

