INVALID_FIELDS = [nil, [], {}, ''].freeze
class Hash
  def snap
    delete_if { |_k, v| INVALID_FIELDS.include?(v) }
  end

  def strip
    collect { |k, v| { k => v.blank? ? nil : (v.strip rescue v) } }.inject(&:update)
  end
end

class Array
  def strip
    collect { |str| str.nil? ? nil : (str.strip rescue str) }
  end

  def snap
    delete_if { |item| INVALID_FIELDS.include?(item) }
  end
end
