require 'simplecov'
SimpleCov.start

require 'hostapd'
require 'pry'
require 'minitest/autorun'
require "minitest/reporters"

ENV['SLEEP_TIME'] = 0

Minitest::Reporters.use!
