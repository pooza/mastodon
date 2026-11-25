# frozen_string_literal: true

require 'rails_helper'
require 'rake'

# #1005 — 4.7 の独自テーマの選択を 5.0 のテーマカラーへ移すタスク（lib/tasks/fork_theme_colors.rake）。
RSpec.describe Rake::Task do
  subject(:task) { described_class['fork:theme_colors:migrate'] }

  before do
    Rails.application.load_tasks unless described_class.task_defined?('fork:theme_colors:migrate')
    task.reenable
    allow(Themes.instance).to receive(:available_theme_colors).with('default').and_return(%w(bshock indigo lime))
    Setting.theme = 'bshock'
    Setting.theme_color = 'indigo'
  end

  let!(:legacy_user) { user_with_theme('bshock') }
  let!(:untouched_user) { Fabricate(:user) }
  let!(:other_theme_user) { user_with_theme('contrast') }

  def user_with_theme(theme)
    Fabricate(:user).tap do |user|
      user.settings['theme'] = theme
      user.save!
    end
  end

  def run_task(execute:)
    ClimateControl.modify(EXECUTE: execute ? '1' : nil) do
      expect { task.invoke }.to output(/選べる色/).to_stdout
    end
  end

  it '既定（確認だけ）では何も書き換えない' do
    run_task(execute: false)

    expect(Setting.theme).to eq 'bshock'
    expect(Setting.theme_color).to eq 'indigo'
    expect(legacy_user.reload.settings.as_json[:theme]).to eq 'bshock'
  end

  it 'EXECUTE=1 で、独自テーマの選択をテーマカラーへ付け替える' do
    run_task(execute: true)

    expect(Setting.theme).to eq 'default'
    expect(Setting.theme_color).to eq 'bshock'

    legacy = legacy_user.reload.settings.as_json
    expect(legacy[:theme]).to be_nil
    expect(legacy[:'web.theme_color']).to eq 'bshock'

    expect(untouched_user.reload.settings.as_json).to_not have_key(:'web.theme_color')
    expect(other_theme_user.reload.settings.as_json[:theme]).to eq 'contrast'
  end

  it '2 回流しても結果は同じ' do
    run_task(execute: true)
    task.reenable
    run_task(execute: true)

    expect(Setting.theme_color).to eq 'bshock'
    expect(legacy_user.reload.settings.as_json[:'web.theme_color']).to eq 'bshock'
  end
end
