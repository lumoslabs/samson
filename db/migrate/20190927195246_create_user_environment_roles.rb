class CreateUserEnvironmentRoles < ActiveRecord::Migration[5.2]
  def change
    create_table :user_environment_roles do |t|
      t.belongs_to :environment, null: false, index: true
      t.belongs_to :user,        null: false, index: true
      t.integer :role_id,        null: false
      t.timestamps               null: false
    end
  end
end
