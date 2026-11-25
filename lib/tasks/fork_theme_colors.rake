# frozen_string_literal: true

# #1005 — 4.7 までの独自テーマの選択を、5.0 のテーマカラーへ移す。
#
# 4.7 の独自テーマ（bshock / cure-* / dai ほか）は、5.0 では同じ名前のテーマカラーとして作り直している。
# テーマとして選ばれたままだと上流が default へフォールバックするだけで色は付かないので、
# 5.0 へ上げた日に 1 回流して、テーマの選択をテーマカラーへ付け替える。何度流しても結果は同じ。
#
#   bin/rails fork:theme_colors:migrate              # 確認だけ（件数と内訳を出す）
#   EXECUTE=1 bin/rails fork:theme_colors:migrate    # 書き込む
#
# 移す対象は、選んでいたテーマの名前がこのブランチの config/themes.yml の colors にあるものだけ。
# 色を選んでいない人は、サーバー既定（Setting.theme_color）に従う（user_settings.rb のフォーク改変）。
namespace :fork do
  namespace :theme_colors do
    desc 'Move legacy custom theme selections to 5.0 theme colors (#1005). Set EXECUTE=1 to write.'
    task migrate: :environment do
      execute = ENV['EXECUTE'] == '1'
      colors = Themes.instance.available_theme_colors('default')
      puts "選べる色: #{colors.join(', ')}"
      puts execute ? '書き込みます。' : '確認だけです（書き込むには EXECUTE=1）。'

      site_theme = Setting.theme
      if colors.include?(site_theme)
        puts "サイト既定: theme=#{site_theme} → theme=default, theme_color=#{site_theme}"
        if execute
          Setting.theme_color = site_theme
          Setting.theme = 'default'
        end
      else
        puts "サイト既定: theme=#{site_theme}（移す対象ではない）, theme_color=#{Setting.theme_color}"
      end

      counts = Hash.new(0)
      User.find_each do |user|
        # 既定値（サーバー既定）に化ける前の、本人が保存した値だけを見る
        theme = user.settings.as_json[:theme]
        next unless colors.include?(theme)

        counts[theme] += 1
        next unless execute

        user.settings['web.theme_color'] = theme
        user.settings['theme'] = nil
        user.save!(validate: false)
      end

      if counts.empty?
        puts '利用者: 移す対象なし'
      else
        counts.sort.each { |theme, count| puts "利用者: theme=#{theme} → theme_color=#{theme}: #{count} 人" }
      end
    end
  end
end
