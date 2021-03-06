require 'mini_racer'

class Interscript::Compiler::Javascript < Interscript::Compiler
  def compile(map)
    @map = map
    @parallel_trees = {}
    @parallel_regexps = {}
    c = "Interscript.define_map(#{map.name.inspect}, function(Interscript, map) {\n";
    c

    map.aliases.each do |name, value|
      val = compile_item(value.data, map, :str)
      c << "map.aliases[#{name.to_json}] = #{val};\n"
      val = '"'+compile_item(value.data, map, :re)+'"'
      c << "map.aliases_re[#{name.to_json}] = #{val};\n"
    end

    map.stages.each do |_, stage|
      c << compile_rule(stage, @map, true)
    end
    @parallel_trees.each do |k,v|
      c << "map.cache.PTREE_#{k} = #{v.to_json}\n"
    end
    @parallel_regexps.each do |k,v|
      v = "[\"#{v[0]}\", #{v[1].to_json}]"
      c << "map.cache.PRE_#{k} = #{v}\n"
    end

    c << "});"
    @code = c
  end

  def parallel_regexp_compile(subs_hash)
    # puts subs_hash.inspect
    regexp = subs_hash.each_with_index.map do |p,i|
      "(?<_%d>%s)" % [i,p[0]]
    end.join("|")
    subs_regexp = regexp
    # puts subs_regexp.inspect
  end

  def compile_rule(r, map = @map, wrapper = false)
    c = ""
    case r
    when Interscript::Node::Stage
      c += "map.stages[#{r.name.to_json}] = function(s) {\n"
      r.children.each do |t|
        c += compile_rule(t, map)
      end
      c += "return s;\n"
      c += "};\n"
    when Interscript::Node::Group::Parallel
      begin
        # Try to build a tree
        a = []
        r.children.each do |i|
          raise ArgumentError, "Can't parallelize #{i.class}" unless Interscript::Node::Rule::Sub === i
          raise ArgumentError, "Can't parallelize rules with :before" if i.before
          raise ArgumentError, "Can't parallelize rules with :after" if i.after
          raise ArgumentError, "Can't parallelize rules with :not_before" if i.not_before
          raise ArgumentError, "Can't parallelize rules with :not_after" if i.not_after

          a << [compile_item(i.from, map, :par), compile_item(i.to, map, :parstr)]
        end
        ah = a.hash.abs
        unless @parallel_trees.include? ah
          tree = Interscript::Stdlib.parallel_replace_compile_tree(a)
          @parallel_trees[ah] = tree
        end
        c += "s = Interscript.parallel_replace_tree(s, map.cache.PTREE_#{ah});\n"
      rescue
        # Otherwise let's build a megaregexp
        a = []
        r.children.sort_by{ |rule| -rule.max_length }.each do |i|
          raise ArgumentError, "Can't parallelize #{i.class}" unless Interscript::Node::Rule::Sub === i

          a << [build_regexp(i, map), compile_item(i.to, map, :parstr)]
        end
        ah = a.hash.abs
        unless @parallel_regexps.include? ah
          re = parallel_regexp_compile(a)
          @parallel_regexps[ah] = [re, a.map(&:last)]
        end
        c += "s = Interscript.parallel_regexp_gsub(s, map.cache.PRE_#{ah});\n"
      end
    when Interscript::Node::Rule::Sub
      from = %{"#{build_regexp(r, map).gsub("/", "\\\\/")}"}
      if r.to == :upcase
        to = 'function(a){return a.toUpperCase();}'
      else
        to = compile_item(r.to, map, :str)
      end
      c += "s = Interscript.gsub(s, #{from}, #{to});\n"
    when Interscript::Node::Rule::Funcall
      c += "s = Interscript.functions.#{r.name}(s, #{r.kwargs.to_json});\n"
    when Interscript::Node::Rule::Run
      if r.stage.map
        doc = map.dep_aliases[r.stage.map].document
        stage = doc.imported_stages[r.stage.name]
      else
        stage = map.imported_stages[r.stage.name]
      end
      c += "s = Interscript.transcribe(#{stage.doc_name.to_json}, s, #{stage.name.to_json});\n"
    else
      raise ArgumentError, "Can't compile unhandled #{r.class}"
    end
    c
  end

  def build_boundary(reverse=false)
    @boundary ||= {}
    return @boundary[reverse] if @boundary[reverse]
    iter = 0
    z = ""
    (0..65535).select do |i|
      ("" << i) =~ (reverse ? /\B/ : /\b/) rescue false
    end.each do |i|
      if iter == 0
        z << "\\u%04x"%i
      elsif iter+1 != i
        z << "-\\u%04x\\u%04x" % [iter,i]
      end
      iter = i
    end
    z << "\\u%04x" % iter
    @boundary[reverse] = z.gsub(/\\u(....)-\1/, "\\\\u\\1")
  end

  def build_regexp(r, map=@map)
    from = compile_item(r.from, map, :re)
    before = compile_item(r.before, map, :re) if r.before
    after = compile_item(r.after, map, :re) if r.after
    not_before = compile_item(r.not_before, map, :re) if r.not_before
    not_after = compile_item(r.not_after, map, :re) if r.not_after

    w_boundary = "\"+Interscript.aliases[\"boundary\"]+\""
    n_boundary = "\"+Interscript.aliases[\"non_word_boundary\"]+\""

    [[w_boundary, false], [n_boundary, true]].each do |boundary, f|
      if from == boundary
        from = "(?<![#{build_boundary(f)}])(?![#{build_boundary(f)}])"
      end

      if from.start_with? boundary
        from = "(?<![#{build_boundary(f)}])"+from[boundary.length..-1]
      end

      if from.end_with? boundary
        from = from[0..-1-boundary.length]+"(?![#{build_boundary(f)}])"
      end

      if before && before.start_with?(boundary)
        before = "(?:[#{build_boundary(!f)}]|^)" + before[boundary.length..-1]
      end

      if after && after.end_with?(boundary)
        after = after[0..-1-boundary.length] + "(?:[#{build_boundary(!f)}]|$)"
      end

      #if not_before && not_before.start_with?(boundary)
      #  not_before = "[#{build_boundary(f)}]" + not_before[boundary.length..-1]
      #end

      #if not_after && not_after.end_with?(boundary)
      #  not_after = not_after[0..-1-boundary.length] + "[#{build_boundary(f)}]"
      #end
    end

    re = ""
    re += "(?<=#{before})" if before
    re += "(?<!#{not_before})" if not_before
    re += from
    re += "(?!#{not_after})" if not_after
    re += "(?=#{after})" if after
    re
  end

  def compile_item i, doc=@map, target=nil
    i = i.first_string if %i[str parstr].include? target
    i = Interscript::Node::Item.try_convert(i)
    if target == :parstr
      parstr = true
      target = :par
    end

    out = case i
    when Interscript::Node::Item::Alias
      astr = if i.map
        d = doc.dep_aliases[i.map].document
        a = d.imported_aliases[i.name]
        raise ArgumentError, "Alias #{i.name} of #{i.stage.map} not found" unless a
        "Interscript.get_alias_ALIASTYPE(#{a.doc_name.to_json}, #{a.name.to_json})"
      elsif Interscript::Stdlib::ALIASES.include?(i.name)
        if target != :re && Interscript::Stdlib.re_only_alias?(i.name)
          raise ArgumentError, "Can't use #{i.name} in a #{target} context"
        end
        stdlib_alias = true
        "Interscript.aliases[#{i.name.to_json}]"
      else
        a = doc.imported_aliases[i.name]
        raise ArgumentError, "Alias #{i.name} not found" unless a

        "Interscript.get_alias_ALIASTYPE(#{a.doc_name.to_json}, #{a.name.to_json})"
      end

      if target == :str
        astr = astr.sub("_ALIASTYPE(", "(")
      elsif target == :re
        astr = %{"+#{astr.sub("_ALIASTYPE(", "_re(")}+"}
      elsif parstr && stdlib_alias
        astr = Interscript::Stdlib::ALIASES[i.name]
      elsif target == :par
        # raise NotImplementedError, "Can't use aliases in parallel mode yet"
        astr = Interscript::Stdlib::ALIASES[i.name]
      end
    when Interscript::Node::Item::String
      if target == :str
        # Replace $1 with \$1, this is weird, but it works!
        i.data.gsub("$", "\\\\$").to_json
      elsif target == :par
        i.data
      elsif target == :re
        Regexp.escape(i.data)
      end
    when Interscript::Node::Item::Group
      if target == :par
        i.children.map do |j|
          compile_item(j, doc, target)
        end.reduce([""]) do |j,k|
          Array(j).product(Array(k)).map(&:join)
        end
      elsif target == :str
        i.children.map { |j| compile_item(j, doc, target) }.join("+")
      elsif target == :re
        i.children.map { |j| compile_item(j, doc, target) }.join
      end
    when Interscript::Node::Item::CaptureGroup
      if target != :re
        raise ArgumentError, "Can't use a CaptureGroup in a #{target} context"
      end
      "(" + compile_item(i.data, doc, target) + ")"
    when Interscript::Node::Item::MaybeSome
      if target == :par
        raise ArgumentError, "Can't use a MaybeSome in a #{target} context"
      end
      if Interscript::Node::Item::String === i.data
        "(?:" + compile_item(i.data, doc, target) + ")*"
      else
        compile_item(i.data, doc, target) + "*"
      end
    when Interscript::Node::Item::Some
      if target == :par
        raise ArgumentError, "Can't use a Some in a #{target} context"
      end
      if Interscript::Node::Item::String === i.data
        "(?:" + compile_item(i.data, doc, target) + ")+"
      else
        compile_item(i.data, doc, target) + "+"
      end
    when Interscript::Node::Item::Maybe
      if target == :par
        raise ArgumentError, "Can't use a Maybe in a #{target} context"
      end
      if Interscript::Node::Item::String === i.data
        "(?:" + compile_item(i.data, doc, target) + ")?"
      else
        compile_item(i.data, doc, target) + "?"
      end
    when Interscript::Node::Item::CaptureRef
      if target == :par
        raise ArgumentError, "Can't use CaptureRef in parallel mode"
      elsif target == :re
        "\\\\#{i.id}"
      elsif target == :str
        "\"$#{i.id}\""
      end
    when Interscript::Node::Item::Any
      if target == :str
        raise ArgumentError, "Can't use Any in a string context" # A linter could find this!
      elsif target == :par
        i.data.map(&:data)
      elsif target == :re
        case i.value
        when Array
          data = i.data.map { |j| compile_item(j, doc, target) }
          "(?:"+data.join("|")+")"
        when String
          "[#{Regexp.escape(i.value)}]"
        when Range
          "[#{Regexp.escape(i.value.first)}-#{Regexp.escape(i.value.last)}]"
        end
      end
    end
  end

  @maps_loaded = {}
  @ctx = nil
  class << self
    attr_accessor :maps_loaded
    attr_accessor :ctx
  end

  def load
    if !self.class.maps_loaded[@map.name]
      @map.dependencies.each do |dep|
        dep = dep.full_name
        if !self.class.maps_loaded[dep]
          Interscript.load(dep, compiler: self.class).load
        end
      end

      ctx = self.class.ctx
      unless ctx
        ctx = MiniRacer::Context.new
        ctx.eval File.read(__dir__+"/../../../../js/xregexp.js")
        # Compatibility with Safari: will come later
        #ctx.eval File.read(__dir__+"/../../../js/xregexp-oniguruma.js")
        ctx.eval File.read(__dir__+"/../../../../js/stdlib.js")
        self.class.ctx = ctx
      end
      #puts @code
      ctx.eval @code
      self.class.maps_loaded[@map.name] = true
    end
  end

  def call(str, stage=:main)
    load
    self.class.ctx.eval "Interscript.transcribe(#{@map.name.to_json}, #{str.to_json}, #{stage.to_json})"
  end
end
