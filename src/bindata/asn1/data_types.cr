class ASN1::BER < BinData
  class InvalidTag < Exception; end
  class InvalidObjectId < Exception; end

  enum UniversalTags
    EndOfContent
    Boolean
    Integer
    BitString # Binary data
    OctetString # Hex values of the payload. Bytes[0x01, 0x02] == "0102"
    Null
    ObjectIdentifier # The tree like structure for objects 1.234.2.45.23 etc
    ObjectDescriptor
    External
    Float
    Enumerated
    EmbeddedPDV
    UTF8String
    RelativeOID
    Reserved1
    Reserved2
    Sequence # like a c-struct ordered list of objects
    Set      # set of objects no ordering
    NumericString
    PrintableString
    T61String
    VideotexString
    IA5String
    UTCTime
    GeneralizedTime
    GraphicString
    VisibleString
    GeneralString
    UniversalString
    CharacterString # Probably ASCII or UTF8
    BMPString
  end

  private def ensure_universal(check_tag)
    raise InvalidTag.new("not a universal tag: #{tag_class}") unless tag_class == TagClass::Universal
    raise InvalidTag.new("object is a #{tag}, expecting #{check_tag}") unless tag == check_tag
  end

  def get_object_id
    ensure_universal(UniversalTags::ObjectIdentifier)
    return "" if @payload.size == 0

    value0 = @payload[0].to_i32
    second = value0 % 40
    first = (value0 - second) / 40
    raise InvalidObjectId.new(@payload.inspect) if first > 2
    object_id = [first, second]

    # Some crazy shit going on here: https://docs.microsoft.com/en-us/windows/desktop/seccertenroll/about-object-identifier
    n = 0
    (1...@payload.size).each do |i|
      if @payload[i] > 0x80 && n == 0
        n = (@payload[i].to_i32 & 0x7f) << 8
      elsif n > 0
        # We need to ignore the high bit of the 2nd byte
        n = n + (@payload[i] << 1)
        object_id << (n >> 1)
        n = 0
      else
        object_id << @payload[i].to_i32
      end
    end

    object_id.join(".")
  end

  def set_object_id(oid)
    value = oid.split(".").map &.to_i

    raise InvalidObjectId.new(value.inspect) if value.size < 1
    raise InvalidObjectId.new(value.inspect) if value[0] > 2

    # Set the appropriate tags
    self.tag_class = TagClass::Universal
    self.tag_number = UniversalTags::ObjectIdentifier
    data = IO::Memory.new

    # Convert the string to bytes
    if value.size > 1
      raise InvalidObjectId.new(value.inspect) if value[0] < 2 && value[1] > 40
      # First two parts are combined
      data.write_byte (40 * value[0] + value[1]).to_u8
      (2...value.size).each do |i|
        if value[i] < 0x80
          data.write_byte(value[i].to_u8)
        else
          # Parts bigger than 128 are represented by 2 bytes (14 usable bits)
          bytes = value[i] << 1
          data.write_byte (((bytes & 0xFF00) >> 8) | 0x80).to_u8
          data.write_byte ((bytes & 0xFF) >> 1).to_u8
        end
      end
    else
      data.write_byte((40 * value[0]).to_u8)
    end

    @payload = data.to_slice

    self
  end

  def get_octet_string
    ensure_universal(UniversalTags::OctetString)
    @payload.hexstring
  end

  def set_octet_string(string)
    self.tag_class = TagClass::Universal
    self.tag_number = UniversalTags::OctetString

    string = string.gsub(/(0x|[^0-9A-Fa-f])*/, "")
    string = "0#{string}" if string.size % 2 > 0
    @payload = string.hexbytes
    self
  end

  def get_string
    check_tags = {UniversalTags::UTF8String, UniversalTags::CharacterString, UniversalTags::PrintableString, UniversalTags::IA5String}
    raise InvalidTag.new("not a universal tag: #{tag_class}") unless tag_class == TagClass::Universal
    raise InvalidTag.new("object is a #{tag}, expecting one of #{check_tags}") unless check_tags.includes?(tag)

    String.new(@payload)
  end

  def set_string(string, tag = UniversalTags::UTF8String)
    self.tag_class = TagClass::Universal
    self.tag_number = tag

    @payload = string.to_slice
    self
  end

  def get_boolean
    ensure_universal(UniversalTags::Boolean)
    @payload[0] != 0_u8
  end

  def set_boolean(value)
    self.tag_class = TagClass::Universal
    self.tag_number = UniversalTags::Boolean

    @payload = value ? Bytes[0xFF] : Bytes[0x0]
    self
  end

  def get_integer : Int64
    ensure_universal(UniversalTags::Integer)
    return 0_i64 if @payload.size == 0

    negative = false
    start = 0_i64
    len = @payload.size - 1

    if (@payload[0] & 0x80) > 0
      negative = true
      start = (~@payload[0]).to_i64 << (8 * len)
    else
      start = @payload[0].to_i64 << (8 * len)
    end

    index = len
    @payload.each do |byte|
      if index == len
        index -= 1
        next
      end

      byte = ~byte if negative
      start += (byte.to_i64 << (index * 8))
      index -= 1
    end

    return -(start + 1) if negative
    start
  end

  def set_integer(value)
    self.tag_class = TagClass::Universal
    self.tag_number = UniversalTags::Integer

    io = IO::Memory.new
    io.write_bytes value, IO::ByteFormat::BigEndian

    ignore = true
    data = io.to_slice
    bytes = IO::Memory.new

    if value < 0
      data.each do |byte|
        next if ignore && byte == 0xFF
        ignore = false
        bytes.write_byte byte
      end
    else
      data.each do |byte|
        next if ignore && byte == 0x00
        ignore = false
        bytes.write_byte byte
      end
    end

    bytes.write_byte(value < 0 ? 0xFF_u8 : 0x00_u8) if bytes.size == 0

    @payload = bytes.to_slice
    self
  end

  def get_bitstring
    ensure_universal(UniversalTags::BitString)
    if @payload[0] == 0
      @payload[1, @payload.size - 1]
    else
      # skip = @payload[0]
      raise "skip not implemented"
    end
  end
end