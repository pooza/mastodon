module Paperclip
  class JpegProcessor < Paperclip::Thumbnail
    def initialize(file, options = {}, attachment = nil)
      super
      @source_file_options = "-define jpeg:size=#{@target_geometry.width.to_i}x#{@target_geometry.height.to_i}" if @current_geometry.width.to_i > @target_geometry.width.to_i && @current_geometry.height.to_i > @target_geometry.height.to_i
    end
  end
end
