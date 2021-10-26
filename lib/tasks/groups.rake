namespace :db do

  desc 'Create groups for assignments'
  task :groups => :environment do
    puts 'Assign Groups/Students for Assignments'
    Faker::Config.random = Random.new(42) # seeds the random number generator so Faker output is deterministic
    students = Student.all
    Assignment.all.each do |assignment|
      num_groups = (assignment.short_identifier == 'A1' || assignment.short_identifier == 'A3') ? students.length : 15
      num_groups.times do |time|
        student = students[time]
        # if this is an individual assignment
        if assignment.group_min == 1 && assignment.group_max == 1
          student.create_group_for_working_alone_student(assignment.id)
          grouping = student.accepted_grouping_for(assignment.id)
          group = grouping.group
        # if this is a group assignment
        else
          grouping = student.create_autogenerated_name_group(assignment)
          grouping.invite(
            [students[time + num_groups].human.user_name],
            StudentMembership::STATUSES[:accepted],
            invoked_by_admin: true)
        end
        if !assignment.is_timed && assignment.section_due_dates_type && grouping.id % 5 == 0
            note = Faker::Movies::PrincessBride.quote
            Extension.create(grouping: grouping, time_delta: 1.week, note: note)
        end
      end
    end

    Grouping.find_each do |grouping|
      grouping.access_repo do |repo|
        # add files to the root folder of the repo (e.g. "A1")
        # recursively copying contents(files & directories) inside the file_dir
        txn = repo.get_transaction(grouping.inviter.user_name)
        file_dir = File.join(File.dirname(__FILE__), '/../../db/data/submission_files')
        copy_dir(file_dir, txn, grouping.assignment.repository_folder)
        repo.commit(txn)
      end
    end

    Repository.get_class.update_permissions
  end

  def copy_dir(seed_dir, txn, repo_dir)
    Dir.foreach(seed_dir) do |filename|
      if filename[0] == '.' # skip dir and files starting with .
        next
      end
      seed_path = File.join(seed_dir, filename)
      repo_path = File.join(repo_dir, filename)
      if File.directory?(seed_path)
        txn.add_path(repo_path)
        copy_dir(seed_path, txn, repo_path)
      else
        File.open(seed_path, 'r') do |file|
          txn.add(repo_path, file.read, '')
        end
      end
    end
  end
end
