# frozen_string_literal: true

# プリセットサーバーのデフォルトハッシュタグ（ENV['DEFAULT_TAG']）を「この投稿は
# ローカル扱い」の判定根拠として使うための共通の口（#908）。
#
# デフォルトタグの本質的な意味はローカル準拠（curesta=precure_fun / delmulin=delmulin）
# なので、リモート投稿でもデフォルトタグが付いていれば地元の投稿として扱いたい。その
# 適用範囲を段階的に広げていくため、判定はここへ集約し、**各フォークは ENV の値だけを
# 変える**（bshockdon は空値＝無効）。フォークごとに同じ判定を書き写さない。
#
# ⚠ 撤去した旧実装（#835）は `tootctl media remove` の中でタグ名をハードコードし、
# `media_attachment.status` を1件ずつ辿っていた。孤児メディア（status_id が nil）で
# NoMethodError になる不動コードだったので、ここでは **SQL 側で判定する**。
class DefaultTag
  class << self
    # ⚠ '#' 付きで設定されても Tag 側の正規化（HashtagNormalizer）が落とすので、
    # ここでは素の文字列を返すだけにする。
    def tag_name
      ENV.fetch('DEFAULT_TAG', nil).presence
    end

    def configured?
      tag_name.present?
    end

    def tag
      name = tag_name
      return nil if name.nil?

      Tag.find_normalized(name)
    end

    # ⚠ 記憶しない。デフォルトタグの Tag 行は「まだ誰も使っていない」段階では存在せず、
    # 後から作られる。長命なプロセスで nil を握り続けると永久に無効化されてしまう。
    def tag_id
      tag&.id
    end

    # 指定したタグ名に DEFAULT_TAG を足し、実在する Tag の id に解決する（#977）。
    # `tootctl statuses remove --keep-tags` で、削除対象から外すタグを決めるのに使う。
    # 名前は Tag の正規化（'#' 落とし・大文字小文字・全角半角）を通して照合し、
    # まだ Tag 行が無い名前は結果に出てこない（＝無視する）。
    def protected_tag_ids(names = [])
      names = (Array(names) + [tag_name]).compact_blank.uniq
      return [] if names.empty?

      Tag.matching_name(names).pluck(:id)
    end

    # 与えられた relation から、デフォルトタグ付き投稿に紐づく行を除く。
    # `status_id` を持つテーブル（media_attachments など）で使える。
    # デフォルトタグが未設定、または Tag 行がまだ無ければ relation をそのまま返す。
    def exclude_tagged(scope)
      id = tag_id
      return scope if id.nil?

      table = scope.klass.arel_table
      statuses_tags = Arel::Table.new(:statuses_tags)

      scope.where.not(
        statuses_tags
          .project(1)
          .where(statuses_tags[:status_id].eq(table[:status_id]).and(statuses_tags[:tag_id].eq(id)))
          .exists
      )
    end
  end
end
