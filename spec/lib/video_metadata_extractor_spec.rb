# frozen_string_literal: true

require 'rails_helper'

RSpec.describe VideoMetadataExtractor do
  describe '#width / #height' do
    context 'with an anamorphic video (SAR != 1:1)' do
      subject(:extractor) { described_class.new(Rails.root.join('spec', 'fixtures', 'files', 'anamorphic.mp4').to_s) }

      it 'is valid' do
        expect(extractor.valid?).to be true
      end

      it 'reports square-pixel display width derived from the sample aspect ratio' do
        # Stored as 1440x1080 with SAR 4:3, i.e. DAR 16:9 -> display width 1920
        expect(extractor.width).to eq(1920)
        expect(extractor.height).to eq(1080)
      end
    end
  end
end
