require 'test_helper'

class RakeTest < SecondBase::TestCase

  def test_db_create
    refute_dummy_databases
    run_db :create
    assert_dummy_databases
  end

  def test_db_create_all
    refute_dummy_databases
    run_db 'create:all'
    assert_dummy_databases
  end

  def test_db_setup
    run_db :create
    run_db :migrate
    assert_dummy_databases
    run_db :drop
    refute_dummy_databases
    run_db :setup
    assert_dummy_databases
  end

  def test_db_drop
    run_db :create
    run_db :drop
    refute_dummy_databases
  end

  def test_db_drop_all
    run_db :create
    run_db 'drop:all'
    refute_dummy_databases
  end

  def test_db_purge_all
    skip 'Rails 4.2 & Up' unless rails_42_up?
    run_db :create
    run_db :migrate
    assert_dummy_databases
    run_db 'purge:all'
    establish_connection
    assert_equal [], ActiveRecord::Base.connection.tables
    assert_equal [], SecondBase::Base.connection.tables
  end

  def test_db_purge
    skip 'Rails 4.2 & Up' unless rails_42_up?
    run_db :create
    run_db :migrate
    assert_dummy_databases
    run_db :purge
    establish_connection
    assert_equal [], ActiveRecord::Base.connection.tables
    assert_equal [], SecondBase::Base.connection.tables
  end

  def test_db_migrate
    run_db :create
    run_db :migrate
    # First database and schema.
    schema = File.read(dummy_schema)
    assert_match %r{version: 20141214142700}, schema
    assert_match %r{create_table "users"}, schema
    assert_match %r{create_table "posts"}, schema
    refute_match %r{create_table "comments"}, schema
    assert_connection_tables ActiveRecord::Base, ['users', 'posts']
    # Second database and schema.
    secondbase_schema = File.read(dummy_secondbase_schema)
    assert_match %r{version: 20151202075826}, secondbase_schema
    refute_match %r{create_table "users"}, secondbase_schema
    refute_match %r{create_table "posts"}, secondbase_schema
    assert_match %r{create_table "comments"}, secondbase_schema
    assert_connection_tables SecondBase::Base, ['comments']
  end

  def test_secondbase_migrate_updown
    run_db :create
    run_db :migrate
    assert_match /no migration.*20151202075826/i, run_db('migrate:down VERSION=20151202075826', :stderr)
    run_secondbase 'migrate:down VERSION=20151202075826'
    secondbase_schema = File.read(dummy_secondbase_schema)
    refute_match %r{version: 20151202075826}, secondbase_schema
    refute_match %r{create_table "comments"}, secondbase_schema
    assert_match /no migration.*20151202075826/i, run_db('migrate:up VERSION=20151202075826', :stderr)
    run_secondbase 'migrate:up VERSION=20151202075826'
    secondbase_schema = File.read(dummy_secondbase_schema)
    assert_match %r{version: 20151202075826}, secondbase_schema
    assert_match %r{create_table "comments"}, secondbase_schema
  end

  def test_secondbase_migrate_reset
    run_db :create
    run_db :migrate
    secondbase_schema = File.read(dummy_secondbase_schema)
    assert_match %r{version: 20151202075826}, secondbase_schema
    assert_match %r{create_table "comments"}, secondbase_schema
    FileUtils.rm_rf dummy_secondbase_schema
    run_secondbase 'migrate:reset'
    secondbase_schema = File.read(dummy_secondbase_schema)
    assert_match %r{version: 20151202075826}, secondbase_schema
    assert_match %r{create_table "comments"}, secondbase_schema
  end

  def test_secondbase_migrate_redo
    run_db :create
    run_db :migrate
    secondbase_schema = File.read(dummy_secondbase_schema)
    assert_match %r{version: 20151202075826}, secondbase_schema
    assert_match %r{create_table "comments"}, secondbase_schema
    FileUtils.rm_rf dummy_secondbase_schema
    run_secondbase 'migrate:redo'
    secondbase_schema = File.read(dummy_secondbase_schema)
    assert_match %r{version: 20151202075826}, secondbase_schema
    assert_match %r{create_table "comments"}, secondbase_schema
    # Can redo latest SecondBase migration using previous VERSION env.
    version = dummy_migration[:version]
    run_db :migrate
    assert_match %r{version: #{version}}, File.read(dummy_secondbase_schema)
    establish_connection
    Comment.create! body: 'test', user_id: 420
    run_secondbase 'migrate:redo VERSION=20151202075826'
    secondbase_schema = File.read(dummy_secondbase_schema)
    assert_match %r{version: #{version}}, secondbase_schema
    assert_match %r{create_table "comments"}, secondbase_schema
    establish_connection
    assert_nil Comment.first
  end

  def test_secondbase_migrate_status
    run_db :create
    stream = rails_42_up? ? :stderr : :stdout
    assert_match %r{migrations table does not exist}, run_secondbase('migrate:status', stream)
    run_db :migrate
    assert_match %r{up.*20151202075826}, run_secondbase('migrate:status')
    version = dummy_migration[:version]
    status = run_secondbase('migrate:status')
    assert_match %r{up.*20151202075826}, status
    assert_match %r{down.*#{version}}, status
  end

  def test_secondbase_forward_and_rollback
    run_db :create
    run_db :migrate
    secondbase_schema = File.read(dummy_secondbase_schema)
    assert_match %r{version: 20151202075826}, secondbase_schema
    refute_match %r{create_table "foos"}, secondbase_schema
    version = dummy_migration[:version] # ActiveRecord does not support start index 0.
    run_secondbase :forward
    secondbase_schema = File.read(dummy_secondbase_schema)
    assert_match %r{version: #{version}}, secondbase_schema
    assert_match %r{create_table "foos"}, secondbase_schema
    run_secondbase :rollback
    secondbase_schema = File.read(dummy_secondbase_schema)
    assert_match %r{version: 20151202075826}, secondbase_schema
    refute_match %r{create_table "foos"}, secondbase_schema
  end

  def test_db_test_purge
    run_db :create
    assert_dummy_databases
    run_db 'test:purge'
    establish_connection
    assert_equal [], ActiveRecord::Base.connection.tables
    assert_equal [], SecondBase::Base.connection.tables
  end

  def test_db_test_load_schema
    run_db :create
    assert_dummy_databases
    run_db 'test:purge'
    run_db :migrate
    Dir.chdir(dummy_root) { `rake db:test:load_schema` }
    establish_connection
    assert_connection_tables ActiveRecord::Base, ['users', 'posts']
    assert_connection_tables SecondBase::Base, ['comments']
  end

  def test_abort_if_pending
    run_db :create
    run_db :migrate
    assert_equal "", run_db(:abort_if_pending_migrations, :stderr)
    version = dummy_migration[:version]
    capture(:stderr) do
      stdout = run_db :abort_if_pending_migrations
      assert_match /1 pending migration/, stdout
      assert_match /#{version}/, stdout
    end
  end

  def test_db_test_load_structure
    run_db :create
    assert_dummy_databases
    run_db 'test:purge'
    Dir.chdir(dummy_root) { `env SCHEMA_FORMAT=sql rake db:migrate` }
    Dir.chdir(dummy_root) { `rake db:test:load_structure` }
    establish_connection
    assert_connection_tables ActiveRecord::Base, ['users', 'posts']
    assert_connection_tables SecondBase::Base, ['comments']
  end

  def test_secondbase_version
    run_db :create
    assert_match /version: 0/, run_secondbase(:version)
    run_db :migrate
    assert_match /version: 20141214142700/, run_db(:version)
    assert_match /version: 20151202075826/, run_secondbase(:version)
  end


  private

  def assert_connection_tables(model, expected_tables)
    establish_connection
    tables = model.connection.tables
    expected_tables.each do |table|
      message = "Expected #{model.name} tables #{tables.inspect} to include #{table.inspect}"
      assert tables.include?(table), message
    end
  end

end
