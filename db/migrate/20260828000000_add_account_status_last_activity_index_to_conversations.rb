class AddAccountStatusLastActivityIndexToConversations < ActiveRecord::Migration[7.1]
  disable_ddl_transaction!

  def change
    add_index :conversations, [:account_id, :status, :last_activity_at],
              order: { last_activity_at: :desc },
              name: 'index_conversations_on_account_status_last_activity',
              algorithm: :concurrently,
              if_not_exists: true
  end
end
