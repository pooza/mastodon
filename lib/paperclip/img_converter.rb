module Paperclip
  class ImgConverter < Processor
    def make
      opaque = identify('-format "%[opaque]" :src', src: File.expand_path(file.path)).strip.downcase

      if opaque == 'true'
        basename = File.basename(file.path, File.extname(file.path))
        dst_name = basename << ".jpeg"

        dst = Paperclip::TempfileFactory.new.generate(dst_name)

        convert(':src :dst',
                src: File.expand_path(file.path),
                dst: File.expand_path(dst.path))

        if @file.size > dst.size
          attachment.instance.file_content_type = 'image/jpeg'
          return dst
        end
      end
      @file
    end
  end
end
