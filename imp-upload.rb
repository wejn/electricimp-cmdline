#!/usr/bin/env ruby

# =============================================================================
# Electric Imp code upload utility
# -----------------------------------------------------------------------------
# This utility allows you to upload code for your ElectricImp from commandline.
#
# Be warned that it uses **UNOFFICIAL** API and might break at any point.
#
# It is based on the following tool from mikob:
# http://forums.electricimp.com/discussion/2533/alternative-for-those-who-don039t-like-the-web-ide
#
# Author: Michal "Wejn" Jirku (box at wejn dot org)
# License: CC BY 3.0
# Version: 0.1
# Created: around 2014-07-01
#
# Please read the (brief) documentation before attempting to use this.
# =============================================================================

fail "need Ruby 2.0+" if RUBY_VERSION < "2.0.0"

require 'pp'
require 'json'
require 'uri'
require 'net/https'

module ElectricImp
	VERSION = '0.1'

	USER_AGENT = 'Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/34.0.1847.132 Safari/537.36'
	#USER_AGENT = 'imp-upload.rb/' + VERSION + '; (+https://github.com/wejn/electricimp-cmdline)'

	module AccountAPI
		LOGIN_URL = 'https://ide.electricimp.com/account/login'
		REFERER_URL = 'https://ide.electricimp.com/login'
		TOKEN_CACHE = File.join(ENV['HOME'], ".electricimp-token")

		def self.fetch_token(config)
			t = load_from_cache(config)
			t ||= perform_login(config)
			save_to_cache(config, t)
			t
		rescue Object
			nil
		end

		def self.load_from_cache(config)
			return nil if config['no_token_caching']
			File.open(TOKEN_CACHE, 'r').read.strip
		rescue Object
			nil
		end

		def self.save_to_cache(config, token)
			return false if token.nil? || config['no_token_caching']
			File.open(TOKEN_CACHE, 'w') { |f| f.write(token) }
			true
		rescue Object
			false
		end

		def self.perform_login(config)
			return nil unless config['email'] && config['password']
			uri = URI.parse(LOGIN_URL)

			https = Net::HTTP.new(uri.host, uri.port)
			https.use_ssl = true

			headers = {
				'Origin' => 'https://ide.electricimp.com',
				'Accept-Language' => 'en-US,en;q=0.8',
				'User-Agent' => USER_AGENT,
				'Content-Type' => 'application/json',
				'Accept' => 'application/json, text/javascript, */*; q=0.01',
				'Referer' => REFERER_URL,
				'X-Requested-With' => 'XMLHttpRequest',
			}
			body = {
				'email' => config['email'],
				'password' => config['password'],
			}
			req = Net::HTTP::Post.new(uri.path, headers)
			req.body = body.to_json
			res = https.request(req)
			if res.code.to_i == 200
				res.get_fields('set-cookie').each do |c|
					if /imp\.token=(.*)/ =~ c.split(/;/)[0]
						return $1.strip
					end
				end
			end
			nil
		rescue Object
			nil
		end
	end

	class CodeUploader
		SYNTAX_URL = "https://ide.electricimp.com/ide/v3/syntax"
		CODE_URL = "https://ide.electricimp.com/ide/v3/models/$model/code"
		DEVICE_URL = 'https://ide.electricimp.com/ide/models/$model/devices/$device'

		def initialize(config)
			@model = config.fetch('model').to_s
			@device = config.fetch('device').to_s
			@token = config.fetch('token').to_s

			@code_url = CODE_URL.dup
			@code_url['$model'] = @model
		end

		def post_code(device_code, agent_code)
			uri = URI.parse(@code_url)
			https = Net::HTTP.new(uri.host, uri.port)
			https.use_ssl = true

			referer = DEVICE_URL.dup
			referer['$model'] = @model
			referer['$device'] = @device

			headers = {
				'Cookie' => 'imp.token=' + @token,
				'Origin' => 'https://ide.electricimp.com',
				#'Accept-Encoding' => 'gzip,deflate,sdch',
				'Accept-Language' => 'en-US,en;q=0.8',
				'User-Agent' => USER_AGENT,
				'Content-Type' => 'application/json',
				'Accept' => 'application/json, text/javascript, */*; q=0.01',
				'Referer' => referer,
				'X-Requested-With' => 'XMLHttpRequest',
			}
			body = {
				'device_id' => @device,
				'imp_code' => device_code,
				'agent_code' => agent_code,
			}
			req = Net::HTTP::Post.new(uri.path, headers)
			req.body = body.to_json
			res = https.request(req)
			body = res.body
			JSON.parse(body) rescue body
		end

		def verify_syntax(device_code, agent_code)
			uri = URI.parse(SYNTAX_URL)
			https = Net::HTTP.new(uri.host, uri.port)
			https.use_ssl = true

			referer = DEVICE_URL.dup
			referer['$model'] = @model
			referer['$device'] = @device

			headers = {
				'Cookie' => 'imp.token=' + @token,
				'Origin' => 'https://ide.electricimp.com',
				#'Accept-Encoding' => 'gzip,deflate,sdch',
				'Accept-Language' => 'en-US,en;q=0.8',
				'User-Agent' => USER_AGENT,
				'Content-Type' => 'application/json',
				'Accept' => 'application/json, text/javascript, */*; q=0.01',
				'Referer' => referer,
				'X-Requested-With' => 'XMLHttpRequest',
			}
			body = {
				'imp_code' => device_code,
				'agent_code' => agent_code,
			}
			req = Net::HTTP::Post.new(uri.path, headers)
			req.body = body.to_json
			res = https.request(req)
			body = res.body
			JSON.parse(body) rescue body
		end
	end

	module TokenExtraction
		def self.extract_token(config)
			token = nil
			token ||= extract_token_via_users_command(config)
			token ||= extract_firefox_token_via_sqlite3_gem(config)
			token ||= extract_firefox_token_via_sqlite3_command(config)
			token
		end

		FF_COOKIE_QUERY = 'SELECT value FROM moz_cookies WHERE baseDomain="electricimp.com" and name="imp.token"'

		def self.extract_token_via_users_command(config)
			STDERR.puts "Trying user command ..." if $DEBUG
			cmd = config.fetch('token_command')
			IO.popen(cmd, 'r') do |f|
				out = f.read.strip
				unless out.empty?
					return out
				end
			end
			nil
		rescue Object
			nil
		end

		def self.extract_firefox_token_via_sqlite3_gem(config)
			STDERR.puts "Trying gem ..." if $DEBUG
			require 'sqlite3'
			cookie_stores(config).each do |cs|
				fst = SQLite3::Database.open(cs).query(FF_COOKIE_QUERY).first
				unless fst.first.empty?
					return fst.first
				end
			end
			nil
		rescue Object
			nil
		end

		def self.extract_firefox_token_via_sqlite3_command(config)
			STDERR.puts "Trying sqlite3 command ..." if $DEBUG
			cookie_stores(config).each do |cs|
				suppress_stdin_stderr do
					IO.popen(['sqlite3', cs, FF_COOKIE_QUERY]) do |f|
						out = f.read.strip
						unless out.empty?
							return out
						end
					end
				end
			end
			nil
		rescue Object
			nil
		end

		def self.suppress_stdin_stderr
			i = $stdin.dup
			e = $stderr.dup
			begin
				$stdin.reopen('/dev/null', 'r')
				$stderr.reopen('/dev/null', 'w')
				yield
			ensure
				$stdin.reopen(i) if i
				$stderr.reopen(e) if e
			end
		end

		def self.cookie_stores(config)
			Array(config.fetch('ff_cookie_store') {
				Dir[File.join(ENV['HOME'], '.mozilla', '**', 'cookies.sqlite')]
			})
		end
	end
end

if __FILE__ == $0
	AGENT_FILE = 'agent.nut'
	DEVICE_FILE = 'device.nut'
	CONFIG_FILE = 'config.json'

	config = nil
	begin
		config = JSON.parse(File.open(CONFIG_FILE).read)
	rescue Object
		STDERR.puts "Error loading config: #$!"
		STDERR.puts "Put '#{CONFIG_FILE}' with 'device', 'model' keys to CWD."
		exit 1
	end

	unless config['model'] && config['device']
		STDERR.puts "invalid config: model, device keys must be present"
		exit 1
	end

	if config['token'].nil? && !config['no_token_autoextract']
		t = ElectricImp::TokenExtraction.extract_token(config)
		if t
			config['token'] = t
		else
			STDERR.puts "Warning: Token autoextract failed. :-("
		end
	end

	if config['token'].nil?
		t = ElectricImp::AccountAPI.fetch_token(config)
		if t
			config['token'] = t
		else
			STDERR.puts "Warning: Login failed. :-("
		end
	end

	unless config['token']
		STDERR.puts "Error: can't continue without token."
		exit 1
	end

	dc = File.open(DEVICE_FILE).read rescue nil
	ac = File.open(AGENT_FILE).read rescue nil

	if dc.nil? && ac.nil?
		STDERR.puts "No device code and no agent code, abort."
		STDERR.puts "Put '#{DEVICE_FILE}' and '#{AGENT_FILE}' to CWD."
		exit 2
	end

	STDERR.puts "Warn: No '#{AGENT_FILE}', replacing with empty." if ac.nil?
	STDERR.puts "Warn: No '#{DEVICE_FILE}', replacing with empty." if dc.nil?

	ei = ElectricImp::CodeUploader.new(config)

	unless config['no_verify']
		res = ei.verify_syntax(dc, ac)
		ok = res['imp_code']['status'] == 'ok' rescue false
		ok &&= res['agent_code']['status'] == 'ok' rescue false
		unless ok
			STDERR.puts "Error: verification failed:"
			PP.pp(res, STDERR)
			exit 3
		end
	end

	res = ei.post_code(dc, ac)
	pp res
end
