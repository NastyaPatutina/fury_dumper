require 'rails'
require './spec/test_models/test_schema'

RSpec::Matchers.define :eq_model do |name, keys, values|
  match do |actual|
    return actual.source_model == name &&
        actual.relation_items.eql?(actual.relation_items)
  end
end

RSpec.describe FuryDumper::Dumper do
  before do
    allow_any_instance_of(FuryDumper::Dumper).to receive(:dump_model).with(any_args).and_return(true)
  end

  def dump_models
    request_relation_items = FuryDumper::Dumper::RelationItems.new_with_key_value(item_key: 'id',
                                                                                  item_values: User.all.ids)
    sync = FuryDumper::Dumper.new \
        password:   nil,
        host:       nil,
        port:       nil,
        user:       nil,
        database:   nil,
        debug_mode: :full,
        model:      FuryDumper::Dumper::Model.new(source_model: 'User',
                                                  relation_items: request_relation_items)


    sync.sync_models
  end

  it "two_way_relation" do
    require './spec/test_models/two_way_relation'

    # Expected
    expect_any_instance_of(FuryDumper::Dumper).to receive(:dump_model).
        with(eq_model('User', ['id'], [User.all.ids])).
        and_return(true)

    expect_any_instance_of(FuryDumper::Dumper).to receive(:dump_model).
        with(eq_model('Document', ['user_id'], [User.all.ids])).
        and_return(true)

    dump_models
  end

  it "scoped_relation" do
    require './spec/test_models/scoped_relation'

    # Expected
    expect_any_instance_of(FuryDumper::Dumper).to receive(:dump_model).
        with(eq_model('User', ['id'], [User.all.ids])).
        and_return(true)

    expect_any_instance_of(FuryDumper::Dumper).to receive(:dump_model).
        with(eq_model('Document', ["\"documents\".\"status\" = 'actual'", 'user_id'], [nil, User.all.ids])).
        and_return(true)

    expect_any_instance_of(FuryDumper::Dumper).to receive(:dump_model).
        with(eq_model('Document', ["\"documents\".\"status\" != 'actual'", 'user_id'], [nil, User.all.ids])).
        and_return(true)

    dump_models
  end

  it "narrowing_relation" do
    require './spec/test_models/narrowing_relation'

    # Expected
    expect_any_instance_of(FuryDumper::Dumper).to receive(:dump_model).
        with(eq_model('User', ['id'], [User.all.ids])).
        and_return(true)

    expect_any_instance_of(FuryDumper::Dumper).to receive(:dump_model).
        with(eq_model('Document', ['user_id'], [User.all.ids])).
        and_return(true)

    # Not expected
    expect_any_instance_of(FuryDumper::Dumper).not_to receive(:dump_model).
        with(eq_model('Document', ["\"documents\".\"status\" = 'actual'", 'user_id'], [nil, User.all.ids]))

    dump_models
  end

  it "as_relation" do
    require './spec/test_models/as_relation'

    # Expected
    expect_any_instance_of(FuryDumper::Dumper).to receive(:dump_model).
        with(eq_model('User', ['id'], [User.all.ids])).
        and_return(true)

    expect_any_instance_of(FuryDumper::Dumper).to receive(:dump_model).
        with(eq_model('Document', ['owner_id', 'owner_type'], [User.all.ids, ['User']])).
        and_return(true)

    expect_any_instance_of(FuryDumper::Dumper).to receive(:dump_model).
        with(eq_model('Device', ['owner_id', 'owner_type'], [User.all.ids, ['User']])).
        and_return(true)

    expect_any_instance_of(FuryDumper::Dumper).to receive(:dump_model).
        with(eq_model('Comment', ['resource_id', 'resource_type'], [Device.all.ids, ['Device']])).
        and_return(true)

    expect_any_instance_of(FuryDumper::Dumper).to receive(:dump_model).
        with(eq_model('Comment', ['resource_id', 'resource_type'], [Document.all.ids, ['Document']])).
        and_return(true)

    dump_models
  end

  it "hardcore_as_relation" do
    require './spec/test_models/hardcore_as_relation'

    # Expected
    expect_any_instance_of(FuryDumper::Dumper).to receive(:dump_model).
        with(eq_model('User', ['id'], [User.all.ids])).
        and_return(true)

    expect_any_instance_of(FuryDumper::Dumper).to receive(:dump_model).
        with(eq_model('Document', ['owner_id', 'owner_type'], [User.all.ids, ['User']])).
        and_return(true)

    expect_any_instance_of(FuryDumper::Dumper).to receive(:dump_model).
        with(eq_model('Device', ['owner_id', 'owner_type'], [User.all.ids, ['User']])).
        and_return(true)

    expect_any_instance_of(FuryDumper::Dumper).to receive(:dump_model).
        with(eq_model('Comment', ['resource_id', 'resource_type'], [User.all.ids, ['User']])).
        and_return(true)

    # Not expected
    expect_any_instance_of(FuryDumper::Dumper).not_to receive(:dump_model).
        with(eq_model('Comment', ['resource_id', 'resource_type'], [Device.all.ids, ['Device']]))

    expect_any_instance_of(FuryDumper::Dumper).not_to receive(:dump_model).
        with(eq_model('Comment', ['resource_id', 'resource_type'], [Document.all.ids, ['Document']]))

    dump_models
  end
end
