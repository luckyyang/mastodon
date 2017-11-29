class RemovePinnedStatus < ActiveRecord::Migration[5.1]
  def up
    # rename and migrate
    drop_table :status_pins
    rename_table :pinned_statuses, :status_pins

    change_table :status_pins do |t|
      t.change :id, :bigint
      t.change :account_id, :bigint
      t.change_default :created_at, -> { 'CURRENT_TIMESTAMP' }
      t.change_default :updated_at, -> { 'CURRENT_TIMESTAMP' }
      t.remove_index :status_id
    end

    remove_foreign_key :status_pins, column: :account_id
    remove_foreign_key :status_pins, column: :status_id

    add_foreign_key :status_pins, :accounts, column: :account_id, on_delete: :cascade
    add_foreign_key :status_pins, :statuses, column: :status_id, on_delete: :cascade
  end

  def down
    create_table :pinned_statuses, id: :serial, force: :cascade do |t|
      t.integer :account_id, null: false
      t.bigint :status_id, null: false
      t.timestamps null: false

      t.index [:account_id, :status_id], name: 'index_pinned_statuses_on_account_id_and_status_id', unique: true
      t.index :status_id, name: 'index_pinned_statuses_on_status_id'
      t.foreign_key :accounts
      t.foreign_key :statuses
    end
  end
end
