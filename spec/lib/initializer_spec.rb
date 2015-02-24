require 'fileutils'
require_relative '../../lib/straight-server'

RSpec.describe StraightServer::Initializer do

  class StraightServer::TestInitializerClass
    include StraightServer::Initializer
    include StraightServer::Initializer::ConfigDir
  end

  before(:each) do
    # redefining Kernel #puts and #print, to get rid of outputs/noise while running specs
    module Kernel 
      alias :original_puts :puts
      alias :original_print :print
      def puts(s); end
      def print(s); end
    end
    remove_tmp_dir
    @templates_dir = File.expand_path('../../templates', File.dirname(__FILE__))
    ENV['HOME']   = File.expand_path('../tmp', File.dirname(__FILE__))
    @initializer = StraightServer::TestInitializerClass.new
    StraightServer::Initializer::ConfigDir.set!
  end

  after(:each) do
    # reverting redefinition of Kernel #puts and #print made in before block
    module Kernel 
      alias :puts :original_puts
      alias :print :original_print
    end
    remove_tmp_dir
  end

  # as #create_config_files method contains #exit method we need to rescue SystemExix: exit() error
  # and at the same time its good to assert that method execution went well, which we do in rescue
  let(:create_config_files) do
    begin
      @initializer.create_config_files
    rescue Exception => e
      expect(e.status).to eq 0 
    end
  end

  it "creates config files" do
    create_config_files
    expect(File.exist?(StraightServer::Initializer::ConfigDir.path)).to eq true
    created_config_files = Dir.glob(File.join(File.expand_path('../tmp', File.dirname(__FILE__)), '**', '*'), File::FNM_DOTMATCH).select { |f| File.file? f }
    expect(created_config_files.size).to eq 3
    created_config_files.each do |file|
      expect(File.read(file)).to eq File.read(@templates_dir + '/addons.yml') if file.match(/.*\.straight\/addons.yml\Z/)
      expect(File.read(file)).to eq File.read(@templates_dir + '/config.yml') if file.match(/.*\.straight\/config.yml\Z/)
      expect(File.read(file).scan(/\w+/).join.size).to eq 16                  if file.match(/.*\.straight\/server_secret\Z/)
    end
  end

  it "connects to the database" do
    StraightServer::Config.db = { 
      adapter: 'sqlite',
      name: 'straight.db', 
    }
    create_config_files
    @initializer.connect_to_db
    expect(StraightServer.db_connection.test_connection).to be true
  end

  it "creates logger" do
    StraightServer::Config.logmaster = { 'log_level' => 'WARN', 'file' => 'straight.log' }
    create_config_files
    expect(@initializer.create_logger).to be_kind_of(StraightServer::Logger)
  end

  it "runs migrations" do
    StraightServer::Config.db = { 
      adapter: 'sqlite',
      name: 'straight.db', 
    }
    create_config_files
    @initializer.connect_to_db
    expect(Sequel::Migrator).to receive(:run).with(any_args)
    expect( -> { @initializer.run_migrations }).not_to raise_error
  end

  it "loads addons" do
    configuration = { 
      'test_addon' => {
        'path'   => 'addons/test_addon',
        'module' => 'TestAddon'  
      }
    }
    module_definition = <<-EOD
      module StraightServer
        module Addon
          module TestAddon
            def test_addon_method
            end
          end
        end
      end
    EOD
    create_config_files
    FileUtils.mkdir_p(ENV['HOME'] + '/.straight/addons')
    FileUtils.touch(ENV['HOME'] + '/.straight/addons/test_addon.rb')
    open(ENV['HOME'] + '/.straight/addons/test_addon.rb', 'w') { |f| f << module_definition }
    open(ENV['HOME'] + '/.straight/addons.yml', 'a') { |f| YAML.dump(configuration, f) }
    StraightServer::Config.logmaster = { 'log_level' => 'INFO', 'file' => 'straight.log' }
    @initializer.create_logger
    expect(StraightServer.logger).to receive(:info).and_return ''
    @initializer.load_addons
    expect(@initializer).to respond_to(:test_addon_method)
  end

  def remove_tmp_dir
    if Dir.exist?(File.expand_path('../tmp/', File.dirname(__FILE__)))
      FileUtils.rm_r(File.expand_path('../tmp/', File.dirname(__FILE__)))
    end      
  end

end