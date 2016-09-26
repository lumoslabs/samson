class AddBranchToJobs < ActiveRecord::Migration[5.0]
  def change
    change_table :jobs do |t|
      t.string :branch
    end

    change_table :deploys do |t|
      t.string :branch
    end
  end
end
