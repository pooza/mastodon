# frozen_string_literal: true

require 'rails_helper'

# フォーク独自に upstream から拡張している上限値の「巻き戻り検知」ガード（#909）。
#
# upstream とのマージ衝突解決でこれらが既定値へ静かに戻ると、ユーザー影響のある
# リグレッションになる。実例: 4.6.0 移行で Account::DEFAULT_FIELDS_SIZE が 10→4 に
# 巻き戻り、補足情報を変更した投稿が検証で弾かれた。
#
# 運用: upstream マージ後に `bundle exec rspec spec/fork` を回して検知する。
# 値を意図的に変える場合は、ここの期待値も更新すること。
RSpec.describe 'Fork customization guard (#909)' do
  # [定数値, フォーク期待値, upstream 既定値(参考), ラベル]
  [
    [Account::DEFAULT_FIELDS_SIZE,       10,   4,   'Account::DEFAULT_FIELDS_SIZE（プロフィール補足情報の数）'],
    [Account::DISPLAY_NAME_LENGTH_LIMIT, 60,   30,  'Account::DISPLAY_NAME_LENGTH_LIMIT（表示名の長さ）'],
    [Account::NOTE_LENGTH_LIMIT,         3000, 500, 'Account::NOTE_LENGTH_LIMIT（bio の長さ）'],
    [TagFeed::LIMIT_PER_MODE,            100,  4,   'TagFeed::LIMIT_PER_MODE'],
    [PollOptionsValidator::MAX_OPTIONS,  10,   4,   'PollOptionsValidator::MAX_OPTIONS（投票の選択肢数）'],
  ].each do |actual, expected, upstream, label|
    it "#{label} がフォーク値 #{expected} に保たれている（upstream 既定 #{upstream} へ巻き戻っていない）" do
      expect(actual).to eq(expected)
    end
  end

  # MAX_CHARS は ENV 駆動（ENV.fetch('MAX_CHARS', 3000)）。コードが upstream の 500 へ
  # 巻き戻る（ハードコード化される）ことを検知する。ENV による上書きは許容するため、
  # 「upstream 既定 500 ではない」ことだけを確認する。
  it 'StatusLengthValidator::MAX_CHARS が upstream 既定 500 へ巻き戻っていない（ENV 既定 3000）' do
    expect(StatusLengthValidator::MAX_CHARS).to be > 500
  end
end

# アナモルフィック動画（SAR != 1:1）のサムネ/プレーヤー枠が縦に伸びる不具合の
# フォーク修正（#923）の「巻き戻り検知」ガード。upstream は SAR を扱わないため、
# マージ衝突解決でこれらの改変が静かに消えると症状が再発する。
# ffmpeg 非依存にするため、ここでは実挙動ではなくコード上の改変有無のみを静的に検知する
# （実挙動の回帰は ffmpeg のある通常 CI 上の spec/lib/video_metadata_extractor_spec.rb が担保）。
RSpec.describe 'Fork customization guard: anamorphic video SAR (#923)' do
  it 'VideoMetadataExtractor が SAR 解釈メソッド parse_sar を保持している' do
    expect(VideoMetadataExtractor.private_instance_methods).to include(:parse_sar)
  end

  it 'VideoMetadataExtractor が width に SAR を反映している（iw を表示寸法へ補正）' do
    source = VideoMetadataExtractor.instance_method(:parse_metadata).source_location.first
    expect(File.read(source)).to match(/@width\s*=\s*\(@width \* sar\)\.round/)
  end

  it 'サムネ生成フィルタが SAR 正規化（setsar）を含んでいる（縦伸び対策）' do
    vf = MediaAttachment::VIDEO_STYLES.dig(:small, :convert_options, :output, :vf)
    expect(vf).to include('iw*sar')
    expect(vf).to include('setsar=1')
  end
end
