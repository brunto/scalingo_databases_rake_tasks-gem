namespace :scalingo do
  namespace :mongodb do
    desc "Backup local MongoDB database"
    task :backup_local => :environment do
      database, user, password, host = ScalingoMongoDB.local_credentials ENV['FILE']
      ScalingoMongoDB.backup(database, user, password, host)
    end

    desc "Backup remote Scalingo MongoDB database"
    task :backup_remote => :environment do
      open_tunnel("SCALINGO_MONGO_URL") do |database, user, password|
        ScalingoMongoDB.backup(database, user, password, "127.0.0.1:27717")
      end
    end

    desc "Restore local MongoDB database using a Scalingo backup"
    task :restore_local => :environment do
      database, user, password, host = ScalingoMongoDB.local_credentials ENV['FILE']
      ScalingoMongoDB.restore(database, user, password, host)
    end

    desc "Restore remote Scalingo MongoDB database using local backup"
    task :restore_remote => :environment do
      open_tunnel("SCALINGO_MONGO_URL") do |database, user, password|
        confirm_remote(database)
        ScalingoMongoDB.restore(database, user, password, "127.0.0.1:27717")
      end
    end

    private

    module ScalingoMongoDB
      DUMP_NAME = "scalingo_mongodb_dump"
      DUMP_PATH = Dir.tmpdir() + "/#{DUMP_NAME}"

      def self.local_credentials(filename)
        filename ||= "mongoid"
        result = File.read "#{Rails.root}/config/#{filename}.yml"
        config_file = YAML::load(ERB.new(result).result)

        if config_file[Rails.env]['sessions']['default']['uri']
          require 'uri'
          uri = URI.parse config_file[Rails.env]['sessions']['default']['uri']

          return [
            uri.path[1..-1],
            uri.user,
            uri.password,
            (uri.host || "127.0.0.1")
          ]
        else
          return [
            config_file[Rails.env]['sessions']['default']['database'],
            config_file[Rails.env]['sessions']['default']['username'],
            config_file[Rails.env]['sessions']['default']['password'],
            config_file[Rails.env]['sessions']['default']['hosts'].first || "127.0.0.1"
          ]
        end
      end

      def self.backup database, user, password, host
        cmd = "rm -rf #{DUMP_PATH} 2>/dev/null && /usr/bin/env mongodump -h #{host} -d #{database} -o #{DUMP_PATH}"
        if user.blank?
          output = cmd
        else
          cmd << " -u #{user}"
          if password.blank?
            output = cmd
          else
            cmd << " --password"
            output = "#{cmd} ... [password filtered]"
            cmd << " #{password}"
          end
        end

        [cmd, output].each do |command|
          command << " && tar czfh #{archive_name DUMP_NAME} -C #{Dir.tmpdir()} #{DUMP_NAME}"
        end

        puts "*** Executing #{output}"
        make_tmp_dir
        system(cmd)
      end

      def self.restore database, user, password, host
        cmd = "rm -rf #{DUMP_PATH}/ 2>/dev/null && tar xvzf #{archive_name DUMP_NAME} -C #{Dir.tmpdir()}"
        cmd << " && /usr/bin/env mongorestore --drop -h #{host} -d #{database} --dir #{DUMP_PATH}/*"
        if user.blank?
          output = cmd
        else
          cmd << " -u #{user}"
          if password.blank?
            output = cmd
          else
            cmd << " --password"
            output = "#{cmd} ... [password filtered]"
            cmd << " #{password}"
          end
        end

        puts "*** Executing #{output}"
        system(cmd)
      end
    end
  end
end
