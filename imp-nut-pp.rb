#!/usr/bin/env ruby

# =============================================================================
# Electric Imp code preprocessor
# -----------------------------------------------------------------------------
# This utility allows you to preprocess your *.nut files roughly the way
# C preprocessor works.
#
# Currently implemented: include, define, undef, ifdef, ifndef, else, endif
#
# Author: Michal "Wejn" Jirku (box at wejn dot org)
# License: CC BY 3.0
# Version: 0.1
# Created: around 2014-07-13
#
# Please read the (brief) documentation before attempting to use this.
# =============================================================================

fail 'need Ruby 2.0+' if RUBY_VERSION < '2.0.0'

require 'tempfile'

module ElectricImp
	VERSION = '0.1'

	# This class safely (atomically) writes new version of a file.
	#
	# It writes into tempfile first and then renames it to proper name.
	class SafeWriter
		def initialize(file)
			@file = file
		end

		def self.open(file, &b)
			new(file).open(&b)
		end

		def open
			tf = Tempfile.new(File.basename(@file), File.dirname(@file))
			begin
				yield tf
				File.rename(tf, @file)
				tf = nil
				self
			rescue Object
				tf.close rescue nil
				tf.unlink rescue nil
				raise
			end
		end
	end

	class Preprocessor
		def initialize(src = '/dev/stdin', dst = nil)
			@src, @dst = src, dst
		end

		def run(vars = ENV)
			if @dst.nil?
				process(STDOUT, @src, vars)
			else
				SafeWriter.open(@dst) do |out|
					process(out, @src, vars)
				end
			end
		end

		PROLOGUE = "^\\s*#\\s*"
		VARIABLE = "[a-zA-Z0-9_]+"
		def process(dst, src, vars)
			context = [src, nil]
			logic = DefLogic.new(vars)
			File.open(src).each_with_index do |inp, l|
				context = [src, l+1]
				case inp
				when /#{PROLOGUE}include\s+(['"])(.*)(\1)$/
					next unless logic.outputting?
					dst.puts "// " + "=" * 75
					dst.puts "// start of: #$2"
					dst.puts "// " + "-" * 75
					abs_path = File.expand_path($2, File.dirname(src))
					process(dst, abs_path, vars)
					dst.puts "// " + "-" * 75
					dst.puts "// end of: #$2, #{src} continues with line #{l+2}"
					dst.puts "// " + "=" * 75
				when /#{PROLOGUE}undef\s+(#{VARIABLE})$/
					logic.unset($1)
				when /#{PROLOGUE}define\s+(#{VARIABLE})(\s+(.*))?$/
					logic.set($1, $3)
				when /#{PROLOGUE}ifdef(ined)?\s+(#{VARIABLE})$/
					logic.ifdef($2)
				when /#{PROLOGUE}ifndef(ined)?\s+(#{VARIABLE})$/
					logic.ifndef($2)
				when /#{PROLOGUE}else$/
					logic.else
				when /#{PROLOGUE}endif$/
					logic.endif
				when /#{PROLOGUE}/
					fail "Unknown PP instruction: #{inp.inspect}"
				else
					dst.write inp if logic.outputting?
				end
			end
		rescue Object
			raise "Got exception when processing #{context}: #$!"
		end

		private

		# define/undef/ifdef/ifndef/endif logic implementation
		class DefLogic
			Level = Struct.new(:firstbranch_res, :had_else)
			def initialize(variables)
				@levels = []
				@variables = variables
			end

			def outputting?
				@levels.reduce(true) do |m, x|
					m && (x.had_else ? !x.firstbranch_res : x.firstbranch_res)
				end
			end

			def set(var, value)
				@variables[var] = value
				self
			end

			def unset(var)
				@variables.delete(var)
				self
			end

			def ifdef(var)
				@levels << Level.new(@variables.has_key?(var), false)
				self
			end

			def ifndef(var)
				@levels << Level.new(!@variables.has_key?(var), false)
				self
			end

			def else
				l = @levels.last
				if l.had_else
					fail "duplicate else"
				else
					l.had_else = true
				end
				self
			end

			def endif
				if @levels.empty?
					fail "no if block open"
				else
					@levels.pop
				end
				self
			end
		end
	end
end

if __FILE__ == $0
	ElectricImp::Preprocessor.new(*ARGV).run
end
