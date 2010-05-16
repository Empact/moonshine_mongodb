require 'pathname'

module Mongodb
  def self.included(manifest)
    manifest.class_eval do
      extend ClassMethods
    end
  end

  module ClassMethods
    def mongo_yml
      @mongo_yml ||= Pathname.new(configuration[:deploy_to]) + 'shared/config/mongo.yml'
    end

    def mongo_rb
      @mongo_rb ||= Pathname.new(configuration[:deploy_to]) + 'current/config/initializers/mongo.rb'
    end

    def mongo_configuration
      configuration[:mongo][rails_env.to_sym]
    end

    def mongo_template_dir
      @mongo_template_dir ||= Pathname.new(__FILE__).dirname.dirname.join('templates')
    end
  end

  # Define options for this plugin via the <tt>configure</tt> method
  # in your application manifest:
  #
  #   configure(:mongodb => {:foo => true})
  #
  # Then include the plugin and call the recipe(s) you need:
  #
  #  plugin :mongodb
  #  recipe :mongodb
  def mongodb(hash = {})
    configure :mongo => YAML::load(template(mongo_template_dir + 'mongo.yml', binding))

    options = {
      :version => '1.4.0',
      :master => false,
      :auth => false,
      :slave_enabled => false,
      :slave => {
        :auto_resync => false,
        :source_master => '',
        :source_port => 27017
      }
    }.merge(hash)

    # ensure the mongo.yml template file is there
    file mongo_yml.to_s,
      :content => template(mongo_template_dir.join('mongo.yml')),
      :ensure => :file,
      :owner => configuration[:user],
      :group => configuration[:group] || configuration[:user],
      :mode => '664'

    # ensure the mongo.rb template file is there
    file mongo_rb.to_s,
      :content => template(mongo_template_dir.join('mongo.rb')),
      :ensure => :file,
      :owner => configuration[:user],
      :group => configuration[:group] || configuration[:user],
      :mode => '664'

    # ensure config/mongo.yml
    file rails_root + 'config/mongo.yml',
      :ensure => mongo_yml.to_s,
      :require => file(mongo_yml.to_s)

    file rails_root + 'config/initializers/mongo.rb',
      :ensure => mongo_rb.to_s,
      :require => file(mongo_rb.to_s)

    # dependencies for install
    package 'wget',              :ensure => :installed
    # default dirs for mongo storage
    file '/data',                :ensure => :directory
    file '/data/db',             :ensure => :directory
    # install location
    file '/opt/local',           :ensure => :directory
    # logs
    file '/var/log/mongodb',     :ensure => :directory


    arch = Facter.architecture
    arch = 'i686' if arch == 'i386'

    exec 'install_mongodb',
      :command => [
        "wget http://downloads.mongodb.org/linux/mongodb-linux-#{arch}-#{options[:version]}.tgz",
        "tar xzf mongodb-linux-#{arch}-#{options[:version]}.tgz",
        "mv mongodb-linux-#{arch}-#{options[:version]} /opt/local/mongo-#{options[:version]}"
      ].join(' && '),
      :cwd => '/tmp',
      :creates => "/opt/local/mongo-#{options[:version]}/bin/mongod",
      :require => [
        file('/opt/local'),
        package('wget')
      ]

    file '/etc/init.d/mongodb',
        :mode => '744',
        :content => template(File.join(File.dirname(__FILE__), '..', 'templates', 'mongo.init.erb'), binding),
        :before => service('mongodb')

    service "mongodb",
      :ensure => :running,
      :enable => true,
      :require => [
        file('/data/db'),
        file('/var/log/mongodb'),
        exec('install_mongodb')
      ]
  end

end
