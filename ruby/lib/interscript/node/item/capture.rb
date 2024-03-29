# (...)
class Interscript::Node::Item::CaptureGroup < Interscript::Node::Item
  attr_accessor :data

  def initialize(data)
    data = Interscript::Node::Item.try_convert(data)
    @data = data
  end

  def first_string
    data.first_string
  end

  def to_hash
    { :class => self.class.to_s,
      :data => self.data.to_hash }
  end

  def inspect
    "capture(#{@data.inspect})"
  end
end

# \1
class Interscript::Node::Item::CaptureRef < Interscript::Node::Item
  attr_accessor :id

  def initialize(id)
    @id = id
  end

  def first_string
    self
  end

  def to_hash
    { :class => self.class.to_s,
      :id => self.id }
  end

  def inspect
    "ref(#{@id.inspect})"
  end
end
