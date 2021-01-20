class Interscript::Stdlib
  ALIASES = {
    none: "",
    space: " ",
    whitespace: "[\\b \\t\\0\\r\\n]",
    boundary: "\\b",
    word: "\\w",
    not_word: "\\W",
    alpha: "[a-zA-Z]",
    not_alpha: "[^a-zA-Z]",
    digit: "\\d",
    not_digit: "\\D",
    line_start: "^",
    line_end: "$",
    string_start: "\\A",
    string_end: "\\z"
  }

  def self.re_only_alias?(a)
    ! %i[none space].include?(a)
  end

  @recache = {}

  def self.parallel_replace(str, hash)
    if @recache[hash.hash]
      re, newhash = @recache[hash.hash]
    else
      newhash = {}
      hash.map do |k,v|
        if String === k
          newhash[k] = v
        elsif Array === k
          k.each { |kk| newhash[kk] = v }
        end
      end
      re = Regexp.union(newhash.keys.sort_by(&:length).reverse)
      @recache[hash.hash] = [re, newhash]
    end
    str.gsub(re) do |i|
      newhash[i]
    end
  end

  def self.available_functions
    %i[title_case]
  end

  module Functions
    def self.title_case(output, character_separator: "", word_separator: " ")
      re = /^(.)/
      output = output.gsub(re, &:upcase) #if title_case
      if word_separator != ''
        re = /#{word_separator}#{character_separator}/
        output = output.gsub(re, word_separator)

        #if title_case
          re = /#{word_separator}(.)/
          output = output.gsub(re, &:upcase)
        #end
      end
      output
    end
  end
end
