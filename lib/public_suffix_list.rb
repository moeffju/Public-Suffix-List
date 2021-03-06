$:.unshift(File.dirname(__FILE__)) unless $:.include?(File.dirname(__FILE__))

require 'open-uri'
require "public_suffix_list/cache_file.rb"
require "public_suffix_list/parser.rb"

class PublicSuffixList

  VERSION = "0.1.1"

  def self.config
    @@config ||= Config.new
  end

  def self.configure(&block)
    yield config
  end
  
  class Config

    attr_accessor :cache_dir
    attr_accessor :cache_expiry_period
    attr_accessor :url

    # effective_tld_names_url is deprecated
    alias_method :effective_tld_names_url, :url
    alias_method :effective_tld_names_url=, :url=

    def initialize
      @cache_dir = nil
      @cache_expiry_period = 30 * 24 * 60 * 60
      @url = "http://mxr.mozilla.org/mozilla-central/source/netwerk/dns/effective_tld_names.dat?raw=1"
    end

  end

  attr_reader :config, :cache_file

  def initialize(options = {})
    @config = self.class.config.dup
    options.each { |k, v| @config.send("#{k}=", v) }
    if @config.cache_dir
      @cache_file = CacheFile.new(@config)
    end
    if @cache_file and @cache_file.exist?
      uncache or (fetch and cache)
    elsif @cache_file
      fetch and cache
    else
      fetch
    end
  end

  def rules
    @rules
  end

  def split(domain)
    domain = domain.split(".")
    result = best(match(domain, rules))
    [gimme!(domain, result.size), gimme!(domain), domain].reverse.map { |d| d ? d.join(".") : "" }
  end

  def tld(domain)
    domain = domain.split(".")
    result = best(match(domain, rules))
    gimme!(domain, result.size).join(".")
  end

  def cdn(domain)
    domain = domain.split(".")
    result = best(match(domain, rules))
    gimme!(domain, result.size + 1).join(".")
  end

  private

  def fetch
    @rules = Parser.parse(open(@config.url))
  end

  def cache
    @cache_file[:rules] = @rules
  end

  def uncache
    @rules = @cache_file[:rules] unless @cache_file.expired?
  end

  def match(domain, rules)
    return [] if domain.empty? or rules.empty?
    domain = domain.dup
    first = domain.pop
    set = []
    [[first.downcase, first], ["!#{first.downcase}", "!#{first}"], ["*", first]].each do |pattern, name|
      if rules[pattern]
        set << [name] if rules[pattern][:term]
        match(domain, rules[pattern]).each { |result| set << [first] + result }
      end
    end
    set
  end

  def best(results)
    return [] if results.empty?
    result = results.find { |r| r.last[0] == ?! } || results.sort { |a, b| a.size <=> b.size }.last
    result = result[0..result.size - 2] if result.last[0] == ?!
    result
  end

  def gimme!(domain, n = 1)
    domain.slice!(-n, n) || []
  end

end
