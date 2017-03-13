# frozen_string_literal: true
threads 8, 16
preload_app!

bind 'tcp://0.0.0.0:9080'
