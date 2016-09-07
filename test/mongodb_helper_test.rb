require_relative '../libraries/mongodb_helper'
require 'minitest/autorun'
include MongoDB::Helper

class TestMongoDBHelper < Minitest::Test
  require 'aws-sdk'
  def test_make_tag_collection
    assert_equal([], make_tag_collection(0))
    assert_equal(['000'], make_tag_collection(1))
    assert_equal(['000','001', '002','003','004'], make_tag_collection(5))
  end

  def test_pick_one_available_tag
    assert(['002', '003'].include?(pick_one_available_tag(['001', '002', '003'], ['001'])))
    assert(['001', '002', '003'].include?(pick_one_available_tag(['001', '002', '003'], [])))
  end
end