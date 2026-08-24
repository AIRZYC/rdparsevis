#!/usr/bin/env ruby

# This file is called rdparse.rb because it implements a Recursive
# Descent Parser. Read more about the theory on e.g.
# http://en.wikipedia.org/wiki/Recursive_descent_parser

# 2010-02-11 New version of this file for the 2010 instance of TDP007
#   which handles false return values during parsing, and has an easy way
#   of turning on and off debug messages.
# 2014-02-16 New version that handles { false } blocks and :empty tokens.
#
# 2025-01-30 Improved logging for better debugging

require 'logger'
require 'json'

# Responsible for creating, setting up and providing a logger
# Can be extended and changed as needed
# Larger projects might want to move this to a separate file
class LoggerFactory

  # Toggle print of parse trace summary at end of parse
  @@show_parse_trace = true
  @@logger_instance = nil

  def LoggerFactory.show_parse_trace?
    return @@show_parse_trace
  end

  # Get a logger instance
  def LoggerFactory.get()

    # This method uses the singleton pattern ensuring only one instance is created

    # Return logger instance if exists, otherwise create it
    if @@logger_instance.nil? then
      @@logger_instance = create_logger()
    end

    return @@logger_instance
  end

  private

  # Create logger instance and do initial setup
  # This can be changed as needed or could be moved to a config file
  def self.create_logger()

    # Clear old log file
    if File.exist?("main.log") then
      File.delete("main.log")
    end

    logger = Logger.new("main.log") # Set up logger to print to file
    #logger = Logger.new(STDOUT) # Alternative version to get console output

    # Make output more readable by modifying the default formatter
    logger.formatter = proc do |severity, datetime, progname, msg|
      "[#{datetime.strftime("%H:%M:%S")}] #{severity}: #{msg}\n"
    end
    
    logger.level = Logger::DEBUG # Change level as needed, INFO for normal running and DEBUG for detailed tracing / figuring out bugs

    logger.info("Logger initialized - Time = #{Time.now}")

    return logger
  end

end

class ParseTrace
  @@parse_trace = []
  @@timeline = [] # New timeline array
  @@parse_result = []


  def ParseTrace.add_trace(rule_name, result, rule_stack)
    @@parse_trace << { 
      rule: rule_name, 
      result: result, 
      depth: rule_stack.length }
  end

  
  def ParseTrace.log_enter(rule_name, pos, depth)
    @@timeline << { 
      action: "enter", 
      rule: rule_name, 
      pos: pos, 
      depth: depth, 
      message: "Entering rule '#{rule_name}' at pos #{pos}" }
  end

  
  def ParseTrace.log_result(rule_name, pos, depth, result)
    status = result.nil? ? "fail" : "success"
    safe_result = result.nil? ? "nil" : result.inspect 
    @@timeline << { 
      action: status, 
      rule: rule_name, 
      pos: pos, 
      depth: depth, 
      result: safe_result, 
      message: "Rule '#{rule_name}' #{status} at pos #{pos}" }
  end

  
  def ParseTrace.export_timeline(filename = "timeline.json", available_rules = [], tokens = [])
    output_data = {
      rules: available_rules,
      tokens: tokens.map(&:inspect),
      timeline: @@timeline
    }
    File.write(filename, JSON.pretty_generate(output_data))
    LoggerFactory.get().info("Timeline exported to #{filename}")
    @@timeline = [] # clear it for the next run
  end

  def ParseTrace.get_and_clear_trace()
    trace = @@parse_trace.clone
    @@parse_trace = []
    trace.reverse!
    return trace
  end
end


class Rule

  # A rule is created through the rule method of the Parser class, like this:
  #   rule :term do
  #     match(:term, '*', :dice) {|a, _, b| a * b }
  #     match(:term, '/', :dice) {|a, _, b| a / b }
  #     match(:dice)
  #   end
  
  Match = Struct.new :pattern, :block
  
  def initialize(name, parser)
    @logger = parser.logger
    # The name of the expressions this rule matches
    @name = name
    # We need the parser to recursively parse sub-expressions occurring 
    # within the pattern of the match objects associated with this rule
    @parser = parser
    @matches = []
    # Left-recursive matches
    @lrmatches = []
  end

  def definition
    patterns = []
    @lrmatches.each do |match|
      patterns << ([@name] + match.pattern).map(&:to_s).join(' ')
    end
    @matches.each do |match|
      patterns << (match.pattern.empty? ? "empty" : match.pattern.map(&:to_s).join(' '))
    end
    return "#{@name} -> #{patterns.join(' | ')}"
  end

  def raw_matches
    code_lines = []
    @lrmatches.each do |match|
      full_pattern = [@name] + match.pattern
      code_lines << "match(#{full_pattern.map(&:inspect).join(', ')})"
    end
    @matches.each do |match|
      code_lines << "match(#{match.pattern.map(&:inspect).join(', ')})"
    end
    return code_lines
  end
  
  # Add a matching expression to this rule, as in this example:
  #   match(:term, '*', :dice) {|a, _, b| a * b }
  # The arguments to 'match' describe the constituents of this expression.
  def match(*pattern, &block)
    match = Match.new(pattern, block)
    # If the pattern is left-recursive, then add it to the left-recursive set
    if pattern[0] == @name
      pattern.shift
      @lrmatches << match
    else
      @matches << match
    end
  end
  
  def parse
    @logger.debug("Parsing rule '#{@name}' at pos #{@parser.pos}")

    @parser.rule_stack.push(@name)
    current_depth = @parser.rule_stack.length # Grab depth for the timeline
    
    ParseTrace.log_enter(@name, @parser.pos, current_depth)

    @logger.debug("Entering parse for rule '#{@name}' at pos #{@parser.pos}")
    @logger.debug("Current rule stack: #{@parser.rule_stack.inspect}")

    # Try non-left-recursive matches first
    match_result = try_matches(@matches)
    
    if match_result.nil?
      ParseTrace.log_result(@name, @parser.pos, current_depth, nil)
      
      @parser.rule_stack.pop 
      @logger.warn("No matches found for rule '#{@name}' at pos #{@parser.pos}")
      return nil 
    end

    loop do
      # Attempt to find further left-recursive matches
      result = try_matches(@lrmatches, match_result)
      
      # If no left recursive match was found, return the last successful result
      if result.nil?
        @logger.debug("Exiting parse for rule '#{@name}' at pos #{@parser.pos} with result: #{match_result.inspect}")
        @logger.info("Rule '#{@name}' final result #{match_result.inspect}. Pos: #{@parser.pos}. Match stack: #{@parser.rule_stack.inspect}")

        ParseTrace.log_result(@name, @parser.pos, current_depth, match_result)
        ParseTrace.add_trace(@name, match_result, @parser.rule_stack.clone)

        @parser.rule_stack.pop 
        return match_result
      end

      @logger.debug("Left-recursive match found for rule '#{@name}' at pos #{@parser.pos}, new result: #{result.inspect} overwriting previous result: #{match_result.inspect}")
      match_result = result
    end
  end

  private
  
  # Try out all matching patterns of this rule
  def try_matches(matches, pre_result = nil)
    match_result = nil
    start = @parser.pos
    current_depth = @parser.rule_stack.length + 1 

    matches.each do |match|
      @logger.debug("Trying pattern #{match.pattern.inspect} for rule '#{@name}' at pos #{start}")
      

      pattern_label = match.pattern.empty? ? "empty" : match.pattern.join(' ')
      ParseTrace.log_enter("Try: [#{pattern_label}]", start, current_depth)

      # pre_result is a previously available result from evaluating expressions
      result = pre_result.nil? ? [] : [pre_result]

      # We iterate through the parts of the pattern
      match.pattern.each_with_index do |token,index|
        
        if @parser.rules[token]
          # Recursively call other rules
          result << @parser.rules[token].parse
          if result.last.nil?
            result = nil
            break
          end
          @logger.debug("Matched '#{@name} = #{match.pattern[index..-1].inspect}'")
        else
          # Match actual tokens
          nt = @parser.expect(token)
          if nt
            result << nt
            if @lrmatches.include?(match.pattern) then
              pattern = [@name]+match.pattern
            else
              pattern = match.pattern
            end
            @logger.debug("Matched token '#{nt}' as part of rule '#{@name} <= #{pattern.inspect}'")
          else
            result = nil
            @logger.debug("Pattern #{match.pattern.inspect} failed at pos #{@parser.pos}")
            @logger.debug("Expected token #{token.inspect} but did not find it")
            break
          end
        end # pattern.each
      end # matches.each

      if result
        if match.block
          match_result = match.block.call(*result)
        else
          match_result = result[0]
        end
        @logger.debug("'#{@parser.string[start..@parser.pos-1]}' matched '#{@name}' and generated '#{match_result.inspect}'") unless match_result.nil?
        
        ParseTrace.log_result("Try: [#{pattern_label}]", @parser.pos, current_depth, match_result)
        
        break # We found a match, stop trying siblings
      else
        @parser.pos = start
        ParseTrace.log_result("Try: [#{pattern_label}]", @parser.pos, current_depth, nil)
        
        # If this rule did not match the current token list, move
        # back to the scan position of the last match
      end
    end
    
    return match_result
  end
end

class Parser

  attr_accessor :pos, :rule_stack
  attr_reader :rules, :string, :logger, :tokens

  class ParseError < RuntimeError
  end

  def initialize(language_name, &block)
    @logger = LoggerFactory.get()
    @lex_tokens = []
    @rules = {}
    @start = nil
    @language_name = language_name

    @rule_stack = [] # Used for keeping track of current stack of rules being parsed - used for logging and debugging

    instance_eval(&block)
  end
  
  # Tokenize the string into small pieces
  def tokenize(string)
    @tokens = []
    @string = string.clone
    until string.empty? # while there is still string left to tokenize
      @logger.debug("Tokenizing remainder: #{string.inspect}")
      
      # Try all token patterns to see which one matches the start of 'string'
      # Return true if any matched
      matched = @lex_tokens.any? do |tok|
        match = tok.pattern.match(string)
        # The regular expression of a token has matched the beginning of 'string'
        if match
          @logger.debug("String #{match[0].inspect} consumed")
          # Also, evaluate this expression by using the block
          # associated with the token
          if tok.block
            result = tok.block.call(match.to_s)
            @logger.debug("Token produced: #{result.inspect} of type #{result.class}")
            @tokens << result # Add last in token list
          else
            @logger.debug("No token block for #{match[0].inspect}, skipping")
          end
          # consume the match and proceed with the rest of the string
          string = match.post_match
          true
        else
          # this token pattern did not match, try the next
          false
        end
      end

      unless matched
        @logger.error("Unable to lex '#{string}'")
        raise ParseError, "unable to lex '#{string}'"
      end
    end
  end
  
 def parse(string)
    @logger.info("Starting parse of string: #{string.inspect}")

    # Tokenize the string
    tokenize(string)
    @logger.info("Tokens after tokenize: #{@tokens.inspect}")

    @pos = 0
    @max_pos = 0
    @expected = []
    
    begin
      # Parse (and evaluate) the tokens received
      result = @start.parse

      # If there are unparsed extra tokens, signal error
      if @pos != @tokens.size
        @logger.error("Parse error at pos #{@pos}, max_pos #{@max_pos}: expected '#{@expected.join(', ')}', found '#{@tokens[@max_pos].inspect}' #{@tokens[@max_pos].class}")
        raise ParseError, "Parse error. expected: '#{@expected.join(', ')}', found '#{@tokens[@max_pos]}' #{@tokens[@max_pos].class}"
      end

      # Print parse tree summary
      if LoggerFactory.show_parse_trace?
        trace = ParseTrace.get_and_clear_trace()
        unless trace.empty?
          @logger.info("PARSE TREE: All successfully matched rules in order")
          @logger.info("-" * 50)
          trace.each do |entry|
            indent = "\t" * (entry[:depth] - 1)
            @logger.info("#{indent}#{entry[:rule].inspect} => #{entry[:result].inspect}")
          end
          @logger.info("-" * 50)
        end
      end

      @logger.info("################################################################")
      @logger.info("Parse successful, result: #{result.inspect}")
      @logger.info("################################################################")

      return result

    rescue => e
      # This catches any errors that happen during parsing
      @logger.error("Parse failed at pos #{@pos}, max_pos #{@max_pos}: #{e.class}: #{e.message}")
      @logger.debug("Expected tokens around failure: #{@expected.inspect}")
      raise # Re-raise the error so the terminal still shows it
      
    ensure
      rule_definitions = @rules.map do |name, rule|
        { 
          name: name.to_s, 
          text: rule.definition, 
          raw_matches: rule.raw_matches
        }
      end
      # Export 
      ParseTrace.export_timeline("timeline.json", rule_definitions, @tokens)
      @logger.info("Timeline export triggered by ensure block.")
    end
  end
  
  def next_token
    @pos += 1
    return @tokens[@pos - 1]
  end

  # Return the next token in the queue
  def expect(tok)
    return tok if tok == :empty
    t = next_token
    if @pos - 1 > @max_pos
      @logger.debug("Updating max_pos to #{@pos - 1}, clearing expected tokens")
      @max_pos = @pos - 1
      @expected = []
    end
    @logger.debug("Expecting #{tok.inspect}, got #{t.inspect} at pos #{@pos - 1}")
    return t if tok === t
    @logger.debug("Token mismatch: expected #{tok.inspect} but found #{t.inspect}")
    @expected << tok if @max_pos == @pos - 1 && !@expected.include?(tok)
    return nil
  end
  
  def to_s
    "Parser for #{@language_name}"
  end

  private
  
  LexToken = Struct.new(:pattern, :block)
  
  def token(pattern, &block)
    @lex_tokens << LexToken.new(Regexp.new('\\A' + pattern.source), block)
  end
  
  def start(name, &block)
    rule(name, &block)
    @start = @rules[name]
  end
  
  def rule(name,&block)
    @current_rule = Rule.new(name, self)
    @rules[name] = @current_rule
    instance_eval &block # In practise, calls match 1..N times
    @current_rule = nil
  end
  
  def match(*pattern, &block)
    # Basically calls memberfunction "match(*pattern, &block)
    @current_rule.send(:match, *pattern, &block)
  end

end

##############################################################################
#
# This part defines the dice language
#
##############################################################################

class DiceRoller
        
  def DiceRoller.roll(times, sides)
    # Throw "sides" sided dice "times" times and return the total
    result = (1..times).inject(0) {|sum, _| sum + rand(sides) + 1 }

    # Need to get a new instance since this is a class method
    LoggerFactory.get().info("Rolled #{times}d#{sides} getting #{result}")

    return result
  end
  
  def initialize

    @logger = LoggerFactory.get()

    @diceParser = Parser.new("dice roller") do
      token(/\s+/) # Ignore whitespace
      token(/\d+/) {|m| m.to_i } # Any string of digits is converted to an Integer
      token(/./) {|m| m }
      
      start :expr do 
        match(:expr, '+', :term) {|a, _, b| a + b }
        match(:expr, '-', :term) {|a, _, b| a - b }
        match(:term)
      end
      
      rule :term do 
        match(:term, '*', :dice) {|a, _, b| a * b }
        match(:term, '/', :dice) {|a, _, b| a / b }
        match(:dice)
      end

      rule :dice do
        match(:atom, 'd', :sides) {|a, _, b| DiceRoller.roll(a, b) }
        match(:atom)
      end
      
      rule :sides do
        match('%') { 100 }
        match(:atom)
      end
      
      rule :atom do
        # Match the result of evaluating an integer expression, which
        # should be an Integer
        match(Integer)
        match('(', :expr, ')') {|_, a, _| a }
      end
    end
  end
  
  def done(str)
    ["quit","exit","bye","done",""].include?(str.chomp)
  end
  
  def roll
    print "[diceroller] "
    str = gets
    if done(str) then
      puts "Bye."
    else
      puts "=> #{@diceParser.parse str}"
      roll
    end
  end

end

# Examples of use

# irb(main):1696:0> DiceRoller.new.roll
# [diceroller] 1+3
# => 4
# [diceroller] 1+1d4
# => 2
# [diceroller] 1+1d4
# => 3
# [diceroller] (2+8*1d20)*3d6
# => 306

DiceRoller.new.roll

