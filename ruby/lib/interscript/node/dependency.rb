class Interscript::Node::Dependency < Interscript::Node
  attr_accessor :name, :full_name, :import, :document

  def initialize
  end

  def to_hash
    { :class => self.class.to_s,
      :name => @name,
      :full_name => @full_name,
      :import => @import }
  end
end
