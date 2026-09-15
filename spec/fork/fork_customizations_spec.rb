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
  let(:source) { Rails.root.join('streaming', 'index.js').read }

  it 'channelNameToIds が DEFAULT_TAG を参照している' do
    expect(source).to include('process.env.DEFAULT_TAG')
  end

  it 'public:local を hashtag+tag=DEFAULT_TAG に読み替えている（federated hashtag / :local ではない）' do
    remap = source[/if \(name === 'public:local' && \w+\) \{.*?\n\s*\}/m]
    expect(remap).to be_present
    expect(remap).to include("name = 'hashtag'")
    expect(remap).to match(/tag: \w+/)
    expect(remap).to_not include('hashtag:local')
  end

  # remap 後、ローカル列(public:local)とハッシュタグ列(#DEFAULT_TAG)は同じ channelIds
  # (timeline:hashtag:<tag>) に解決される。共有WSの購読を channelIds だけでキーにすると
  # 後から購読した列が握り潰され、そのラベルが配信されず片方が更新されなくなる。購読キーに
  # クライアント向け channelName を含めることで両立させている。これが消えると衝突が再発する。
  it 'WS 購読キーに channelName を含め、ローカル列とハッシュタグ列を共存させている' do
    expect(source).to include('subscriptionKeyForChannel')
    expect(source).to include('subscriptions[subscriptionKey]')
  end
end

# 「荒らし共栄圏」を名乗る集団のスパム大量送信に対抗して導入した受信フィルタの
# 「巻き戻り検知」ガード。実効のあった防御を、騒動の再燃に備えて休眠状態で残している。
#
# ⚠ 休眠防御は「消えても平常時は誰も困らない」ため、マージ衝突解決で静かに落ちても
# 気づけない。次の波が来たときに初めて「効いていない」ことが分かる＝最悪のタイミングに
# なる。だからコードの存在自体をここで固定する。
RSpec.describe 'Fork customization guard: 受信スパムフィルタ (荒らし共栄圏対策)' do
  let(:source) { File.read(ActivityPub::Activity::Create.instance_method(:perform).source_location.first) }

  it 'ActivityPub::Activity::Create が判定メソッド like_a_spam? を保持している' do
    expect(ActivityPub::Activity::Create.private_instance_methods).to include(:like_a_spam?)
  end

  it '判定条件が「リモート かつ フォロワー0 かつ メンション4件以上」のまま' do
    predicate = source[/def like_a_spam\?.*?\n  end/m]
    expect(predicate).to be_present
    expect(predicate).to include('!@status.account.local?')
    expect(predicate).to include('@status.account.followers_count.zero?')
    expect(predicate).to include('@mentions.count >= 4')
  end

  it '該当時はトランザクションを巻き戻して投稿を保存しない' do
    branch = source[/if like_a_spam\?.*?\n      end/m]
    expect(branch).to be_present
    expect(branch).to include('@status = nil')
    expect(branch).to include('raise ActiveRecord::Rollback')
    # rollback 後の後続処理（resolve_thread 等）を nil の @status で走らせないためのガード
    expect(source).to include('return if @status.nil?')
  end

  # 無言の破棄だと誤爆にも発動にも気づけないため、発動を必ずログに残す。
  it '破棄時に Rails.logger へ発動を記録する' do
    branch = source[/if like_a_spam\?.*?\n      end/m]
    expect(branch).to include('Rails.logger')
  end
end

# ハッシュタグ列に指定できるタグ数の上限（upstream 4 → フォーク 100）は、
# サーバー側 TagFeed::LIMIT_PER_MODE と WebUI 側の入力制限が対になっている。
# 片方だけ巻き戻ると「UI では追加できるが API が弾く」「UI が先に止める」の
# どちらかの齟齬になり、上の定数ガードだけでは検知できない。
RSpec.describe 'Fork customization guard: ハッシュタグ列のタグ数上限（WebUI 側）' do
  let(:path) { Rails.root.join('app', 'javascript', 'mastodon', 'features', 'hashtag_timeline', 'components', 'column_settings.jsx') }
  let(:limit) { path.read[/value\.length > (\d+)/, 1]&.to_i }

  it 'WebUI 側の入力制限が upstream 既定 4 へ巻き戻っていない' do
    expect(limit).to be_present
    expect(limit).to be > 4
  end

  it 'WebUI 側の上限がサーバー側 TagFeed::LIMIT_PER_MODE と一致している' do
    expect(limit).to eq(TagFeed::LIMIT_PER_MODE)
  end
end

# スタートメニューのアイコンは Google Fonts の Material Symbols を**リガチャ**で描いている（#895）。
# スタイルシートかフォントが読めないと、アイコンの代わりに `home` などの文字列がそのまま出る。
#
# ⚠ これは WebUI でしか症状が出ない。API クライアント経由の利用者にも、クライアントを使う
# 管理者にも見えないため、落ちたことに誰も気づけない（#954）。
#
# CSP のホスト指定は upstream の initializer に相乗りしているので、版上げの衝突解決で静かに
# 落ちうる。4.7 では `if Rails.env.development? / else` から
# `next unless Rails.env.development?` 形式へ組み替わっており、構造が変わるマージほど危ない。
# そのため initializer のソース文字列ではなく、**開発以外の環境で組み上がった実効ポリシー**を
# 直接見る（development ブロックにだけ残った場合を素通りさせないため）。
RSpec.describe 'Fork customization guard: Material Symbols (Google Fonts) の参照 (#954)' do
  let(:directives) { Rails.application.config.content_security_policy.directives }

  it 'style-src にスタイルシートの取得元 https://fonts.googleapis.com が含まれている' do
    expect(directives['style-src']).to include('https://fonts.googleapis.com')
  end

  it 'font-src にフォント本体の取得元 https://fonts.gstatic.com が含まれている' do
    expect(directives['font-src']).to include('https://fonts.gstatic.com')
  end

  it 'レイアウトが Material Symbols のスタイルシートを読み込んでいる' do
    layout = Rails.root.join('app', 'views', 'layouts', 'application.html.haml').read
    expect(layout).to match(%r{rel: 'stylesheet'.*fonts\.googleapis\.com/css2\?family=Material\+Symbols})
  end
end

# デフォルトハッシュタグ付き投稿を「ローカル扱い」する範囲の第一歩（#908）。
# `tootctl media remove` がデフォルトタグ付き投稿のキャッシュメディアを消さないことを守る。
#
# ⚠ 判定はロジックをフォーク基点（DefaultTag）へ置き ENV['DEFAULT_TAG'] を参照する形で、
# curesta / delmulin は値だけが違う。ここでは値に依存しないよう ENV を差し替えて検証する。
# ⚠⚠ 撤去した旧実装（#835）は `media_attachment.status` を1件ずつ辿り、孤児メディア
# （status_id が nil）で落ちた。孤児が対象に残ることも合わせて守る。
RSpec.describe 'Fork customization guard: DEFAULT_TAG media retention (#908)' do
  subject { MediaAttachment.without_default_tag }

  let(:tagged_status) { Fabricate(:status) }
  let(:plain_status) { Fabricate(:status) }
  let!(:tagged_media) { Fabricate(:media_attachment, status: tagged_status) }
  let!(:plain_media) { Fabricate(:media_attachment, status: plain_status) }
  let!(:orphan_media) { Fabricate(:media_attachment, status: nil) }

  before { tagged_status.tags << Fabricate(:tag, name: 'delmulin') }

  context 'when DEFAULT_TAG が設定されている（curesta / delmulin）' do
    around do |example|
      ClimateControl.modify(DEFAULT_TAG: 'delmulin') { example.run }
    end

    it 'デフォルトタグ付き投稿のメディアを削除対象から外す' do
      expect(subject).to_not include(tagged_media)
    end

    it 'タグの無い投稿のメディアと孤児メディアは削除対象に残す' do
      expect(subject).to include(plain_media, orphan_media)
    end
  end

  context 'when DEFAULT_TAG が空（bshockdon）' do
    around do |example|
      ClimateControl.modify(DEFAULT_TAG: nil) { example.run }
    end

    it '何も除外せず upstream と同じ対象になる' do
      expect(subject).to include(tagged_media, plain_media, orphan_media)
    end
  end

  it 'tootctl media remove が without_default_tag を通している' do
    source = Rails.root.join('lib', 'mastodon', 'cli', 'media.rb').read
    expect(source).to include('without_default_tag')
  end
end
# rubocop:enable RSpec/DescribeClass, RSpec/MultipleDescribes
