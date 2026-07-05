# frozen_string_literal: true

require 'rails_helper'

# ここのガード群は単一クラスではなく横断的なフォーク改変（上限値・挙動）を検証するため、
# 文字列 describe を意図的に使い、issue 単位で兄弟の top-level group として並べる。
# rubocop:disable RSpec/DescribeClass, RSpec/MultipleDescribes

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

  it 'VideoMetadataExtractor が表示寸法 display_width/display_height を公開している' do
    expect(VideoMetadataExtractor.instance_methods).to include(:display_width, :display_height)
  end

  it 'display_width が SAR 反映の表示幅を算出し、coded @width は上書きしない' do
    source = File.read(VideoMetadataExtractor.instance_method(:parse_metadata).source_location.first)
    expect(source).to match(/@display_width\s*=.*\(@width \* sar\)\.round/)
    # coded @width を表示幅で上書きすると上限検証(MAX_VIDEO_MATRIX_LIMIT)が騙される（#924 review P2）
    expect(source).to_not match(/^\s*@width\s*=\s*\(@width \* sar\)/)
  end

  it 'video_metadata（layout meta）が coded ではなく display 寸法を使う' do
    source = File.read(MediaAttachment.instance_method(:video_metadata).source_location.first)
    expect(source).to match(/width:\s*movie\.display_width/)
    expect(source).to match(/height:\s*movie\.display_height/)
  end

  it 'サムネ生成フィルタが SAR 正規化（setsar）を含んでいる（縦伸び対策）' do
    vf = MediaAttachment::VIDEO_STYLES.dig(:small, :convert_options, :output, :vf)
    expect(vf).to include('iw*sar')
    expect(vf).to include('setsar=1')
  end
end

# streaming の local public TL を DEFAULT_TAG の（federated）hashtag ストリームへ
# 読み替えるフォーク改変（#925）の「巻き戻り検知」ガード。REST は nginx 302 で
# /timelines/tag/<tag> に飛ぶが streaming には読み替えが無く、実況ローカルTLの
# ライブ更新が遠隔デフォルトタグ投稿を取りこぼしていた。upstream マージ衝突で
# この remap が静かに消えると症状が再発する。streaming(JS) は Ruby から実行できない
# ため、ここではコード上の改変有無のみを静的に検知する。
RSpec.describe 'Fork customization guard: streaming public:local -> DEFAULT_TAG remap (#925)' do
  let(:source) { File.read(Rails.root.join('streaming', 'index.js')) }

  it 'channelNameToIds が DEFAULT_TAG を参照している' do
    expect(source).to match(/process\.env\.DEFAULT_TAG/)
  end

  it 'public:local を hashtag+tag=DEFAULT_TAG に読み替えている（federated hashtag / :local ではない）' do
    remap = source[/if \(name === 'public:local' && \w+\) \{.*?\n\s*\}/m]
    expect(remap).to be_present
    expect(remap).to match(/name = 'hashtag'/)
    expect(remap).to match(/tag: \w+/)
    expect(remap).to_not match(/hashtag:local/)
  end
end
# rubocop:enable RSpec/DescribeClass, RSpec/MultipleDescribes
