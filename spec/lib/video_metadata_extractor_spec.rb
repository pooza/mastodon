# frozen_string_literal: true

require 'rails_helper'

RSpec.describe VideoMetadataExtractor do
  describe '#width / #height' do
    context 'with an anamorphic video (SAR != 1:1)' do
      subject(:extractor) { described_class.new(Rails.root.join('spec', 'fixtures', 'files', 'anamorphic.mp4').to_s) }

      it 'is valid' do
        expect(extractor.valid?).to be true
      end

      it 'keeps the coded dimensions for validation/transcoding' do
        # Coded raster stays 1440x1080 so upload-limit checks see the real frame
        expect(extractor.width).to eq(1440)
        expect(extractor.height).to eq(1080)
      end

      it 'exposes square-pixel display dimensions derived from the sample aspect ratio' do
        # SAR 4:3 -> DAR 16:9 -> display 1920x1080 (used for layout metadata)
        expect(extractor.display_width).to eq(1920)
        expect(extractor.display_height).to eq(1080)
      end
    end
  end
end
