# frozen_string_literal: true

require 'rails_helper'
require 'mastodon/cli/emoji'

# 姉妹 Misskey サーバー（ダイスキー）からカスタム絵文字とカテゴリを引き取る同期（#945）。
#
# 「向こうが正・こちらは完全上書き・削除はしない」という運用上の約束をここで固定する。
# とくに「向こうで削除された絵文字を蘇らせない」「向こうに無いローカル絵文字を消さない」は、
# 壊れると利用者の目に見える形で事故になるので、正のテストとして持っておく。
RSpec.describe MisskeyEmojiSync do
  subject(:syncer) { described_class.new('https://misskey.example') }

  let(:origin_emojis) { [{ name: 'kept', category: 'Greetings' }] }

  before do
    stub_request(:get, 'https://misskey.example/api/emojis')
      .to_return(status: 200, body: { emojis: origin_emojis }.to_json, headers: { 'Content-Type' => 'application/json' })
  end

  describe '#domain' do
    it 'accepts an origin with or without a scheme and trailing slash' do
      expect([described_class.new('https://misskey.example/').domain, described_class.new('misskey.example').domain])
        .to all(eq('misskey.example'))
    end

    it 'rejects an origin that is not a bare host' do
      expect { described_class.new('https://misskey.example/api') }.to raise_error(described_class::Error)
    end
  end

  describe '#plan' do
    context 'with a local emoji categorized differently than on the origin' do
      before { Fabricate(:custom_emoji, shortcode: 'kept', category: Fabricate(:custom_emoji_category, name: 'Stale')) }

      it 'plans to overwrite the category and drop the category left empty' do
        expect(syncer.plan.recategorize).to eq [{ shortcode: 'kept', from: 'Stale', to: 'Greetings' }]
        expect(syncer.plan.obsolete_categories).to eq ['Stale']
      end
    end

    context 'with a local emoji already categorized as on the origin' do
      before { Fabricate(:custom_emoji, shortcode: 'kept', category: Fabricate(:custom_emoji_category, name: 'Greetings')) }

      it 'plans nothing' do
        expect(syncer.plan.recategorize).to be_empty
        expect(syncer.plan.obsolete_categories).to be_empty
      end
    end

    context 'with a federated emoji that has no local counterpart' do
      before { Fabricate(:custom_emoji, shortcode: 'kept', domain: 'misskey.example') }

      it 'plans to copy it' do
        expect(syncer.plan.copy.map(&:shortcode)).to eq ['kept']
        expect(syncer.plan.awaiting_federation).to be_empty
      end
    end

    context 'with a federated emoji the origin no longer lists' do
      before { Fabricate(:custom_emoji, shortcode: 'withdrawn', domain: 'misskey.example') }

      it 'does not plan to copy it' do
        expect(syncer.plan.copy).to be_empty
      end
    end

    context 'with a local emoji unknown to the origin' do
      before { Fabricate(:custom_emoji, shortcode: 'ours_only', category: Fabricate(:custom_emoji_category, name: 'Ours')) }

      it 'reports it as an orphan and keeps its category alive' do
        expect(syncer.plan.orphans).to eq ['ours_only']
        expect(syncer.plan.recategorize).to be_empty
        expect(syncer.plan.obsolete_categories).to be_empty
      end
    end

    context 'with an emoji on the origin that has not federated here yet' do
      it 'reports it as awaiting federation' do
        expect(syncer.plan.awaiting_federation).to eq ['kept']
      end
    end

    context 'with an emoji on the origin whose name is not a valid shortcode here' do
      let(:origin_emojis) { [{ name: 'wa-i', category: 'Deprecated' }, { name: 'a', category: 'Feelings' }] }

      it 'reports it as unsyncable rather than awaiting federation' do
        expect(syncer.plan.unsyncable).to eq %w(a wa-i)
        expect(syncer.plan.awaiting_federation).to be_empty
      end
    end

    # ローカル絵文字は 128 文字まで、リモート絵文字は 2048 文字まで。長すぎる名前を
    # syncable と誤判定すると copy! が検証で落ちる（#946 の Codex 指摘）
    context 'with an emoji on the origin whose name is too long for a local shortcode' do
      let(:long_name) { 'x' * (CustomEmoji::MAX_SHORTCODE_SIZE + 1) }
      let(:origin_emojis) { [{ name: long_name, category: 'Greetings' }] }

      before { Fabricate(:custom_emoji, shortcode: long_name, domain: 'misskey.example') }

      it 'reports it as unsyncable instead of planning to copy it' do
        expect(syncer.plan.unsyncable).to eq [long_name]
        expect(syncer.plan.copy).to be_empty
      end
    end

    context 'when the origin cannot be reached' do
      before { stub_request(:get, 'https://misskey.example/api/emojis').to_return(status: 500) }

      it 'raises' do
        expect { syncer.plan }.to raise_error(described_class::Error, /HTTP 500/)
      end
    end

    context 'when the origin returns no emoji' do
      let(:origin_emojis) { [] }

      it 'raises rather than treating every category as empty' do
        expect { syncer.plan }.to raise_error(described_class::Error, /No custom emoji/)
      end
    end
  end

  describe '#apply!' do
    context 'with a local emoji categorized differently than on the origin' do
      let!(:emoji) { Fabricate(:custom_emoji, shortcode: 'kept', category: Fabricate(:custom_emoji_category, name: 'Stale')) }

      it 'overwrites the category and removes the one left empty' do
        expect { syncer.apply! }
          .to change { emoji.reload.category.name }.from('Stale').to('Greetings')
          .and change { CustomEmojiCategory.exists?(name: 'Stale') }.from(true).to(false)
      end

      it 'converges, so a second run has nothing left to do' do
        syncer.apply!

        expect(described_class.new('https://misskey.example').plan.recategorize).to be_empty
      end
    end

    context 'with a federated emoji that has no local counterpart' do
      before { Fabricate(:custom_emoji, shortcode: 'kept', domain: 'misskey.example') }

      it 'copies it locally with the category from the origin' do
        expect { syncer.apply! }
          .to change { CustomEmoji.local.exists?(shortcode: 'kept') }.from(false).to(true)

        expect(CustomEmoji.local.find_by(shortcode: 'kept').category.name).to eq 'Greetings'
      end
    end

    context 'with a local emoji unknown to the origin' do
      let!(:emoji) { Fabricate(:custom_emoji, shortcode: 'ours_only', category: Fabricate(:custom_emoji_category, name: 'Ours')) }

      it 'never deletes it' do
        expect { syncer.apply! }
          .to not_change { emoji.reload.category.name }
          .and(not_change { CustomEmoji.local.count })
      end
    end

    # コピー 1 件の失敗で本命のカテゴリ同期まで落とさないこと
    context 'when copying one emoji fails' do
      let(:origin_emojis) { [{ name: 'kept', category: 'Greetings' }, { name: 'broken', category: 'Greetings' }] }
      let!(:emoji) { Fabricate(:custom_emoji, shortcode: 'kept', category: Fabricate(:custom_emoji_category, name: 'Stale')) }

      before do
        Fabricate(:custom_emoji, shortcode: 'broken', domain: 'misskey.example')
        broken = syncer.plan.copy.find { |candidate| candidate.shortcode == 'broken' }
        allow(broken).to receive(:copy!).and_raise(ActiveRecord::RecordInvalid.new(CustomEmoji.new.tap(&:validate)))
      end

      it 'records the failure and still syncs categories' do
        expect { syncer.apply! }.to change { emoji.reload.category.name }.from('Stale').to('Greetings')
        expect(syncer.copy_failures.pluck(:shortcode)).to eq ['broken']
      end

      # 計画は 2 件の張り替えを含むが、コピーに失敗した側は実施されない
      it 'counts only what it actually wrote' do
        syncer.apply!

        expect(syncer.plan.recategorize.size).to eq 2
        expect(syncer.applied).to eq({ copied: 0, recategorized: 1, removed_categories: 1 })
      end
    end

    context 'with a category whose featured emoji moved away' do
      let!(:category) { Fabricate(:custom_emoji_category, name: 'Greetings') }
      let!(:emoji) { Fabricate(:custom_emoji, shortcode: 'ours_only', category: category) }

      before do
        Fabricate(:custom_emoji, shortcode: 'kept', category: category)
        category.update!(featured_emoji: emoji)
        emoji.update!(category: Fabricate(:custom_emoji_category, name: 'Ours'))
      end

      it 'clears the dangling reference' do
        expect { syncer.apply! }.to change { category.reload.featured_emoji_id }.from(emoji.id).to(nil)
      end
    end
  end

  describe Mastodon::CLI::Emoji, type: :cli do
    subject { cli.invoke(:sync, ['https://misskey.example'], options) }

    let(:cli) { described_class.new }
    let(:options) { { dry_run: true } }

    let!(:emoji) { Fabricate(:custom_emoji, shortcode: 'kept', category: Fabricate(:custom_emoji_category, name: 'Stale')) }

    it 'reports what it would do without writing anything' do
      expect { subject }
        .to output_results('kept: Stale -> Greetings', '(DRY RUN)')
        .and(not_change { emoji.reload.category.name })
    end

    context 'with --no-dry-run' do
      let(:options) { { dry_run: false } }

      it 'writes and reports counts' do
        expect { subject }
          .to output_results('Copied 0, recategorized 1, removed 1 empty categories')
          .and change { emoji.reload.category.name }.from('Stale').to('Greetings')
      end
    end

    # 128 文字超の名前は正規表現のほうは満たすので、字面だけでは弾かれた理由が分からない
    context 'with an unsyncable name on the origin' do
      let(:origin_emojis) { [{ name: 'kept', category: 'Greetings' }, { name: 'x' * (CustomEmoji::MAX_SHORTCODE_SIZE + 1), category: 'Greetings' }] }

      it 'states the length limit alongside the pattern' do
        expect { subject }
          .to output_results("must match #{CustomEmoji::SHORTCODE_RE_FRAGMENT} and be at most #{CustomEmoji::MAX_SHORTCODE_SIZE} characters")
      end
    end

    # 新設サーバーや初回は未連合が数百件になる。通知へ流せる長さに畳まれること
    context 'with more emoji awaiting federation than the report lists' do
      let(:origin_emojis) { (1..15).map { |i| { name: format('pending_%02d', i), category: 'Greetings' } } + [{ name: 'kept', category: 'Greetings' }] }

      it 'truncates the list' do
        expect { subject }
          .to output_results('15 emoji on misskey.example have not federated here yet', 'pending_10 and 5 more')
      end
    end
  end
end
