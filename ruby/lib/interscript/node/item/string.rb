class Interscript::Node::Item::String  < Interscript::Node::Item
  attr_accessor :data
  def initialize data
    self.data = data
  end

  def to_hash
    { :class => self.class.to_s,
      :data => self.data }
  end

  def + other
    if Interscript::Node::Item::String === self &&
      (Interscript::Node::Item::String === other || ::String === other)

      other = Interscript::Node::Item.try_convert(other)

      Interscript::Node::Item::String.new(self.data + other.data)
    else
      super
    end
  end
end

# stdext
class String
  alias plus_before_interscript +
  def + other
    if Interscript::Node === other
      Interscript::Node::Item.try_convert(self) + other
    else
      self.plus_before_interscript(other)
    end
  end
end