namespace :dev_func do
  desc "Rebuild tables"
  task rebuild: :environment do
    system("bundle exec rake tmp:clear log:clear")
    system("bundle exec rake db:drop db:create")
    system("bundle exec rake db:migrate db:seed")
  end

  desc "test app"
  task test_app: :environment do
    system("rspec spec")
  end

  desc "check style"
  task check_style: :environment do
    system("rubocop .")
  end

  desc "Run code quality tools"
  task code_analysis: :environment do
    system "bundle exec brakeman . -z -q"
    system "bundle exec rubocop . -a"
    system "bundle exec reek app lib spec"
    system "bundle exec rails_best_practices ."
  end
end
