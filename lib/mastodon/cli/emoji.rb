# frozen_string_literal: true

require 'rubygems/package'
require_relative 'base'

module Mastodon::CLI
  class Emoji < Base
    option :prefix
    option :suffix
    option :overwrite, type: :boolean
    option :unlisted, type: :boolean
    option :category
    desc 'import PATH', 'Import emoji from a TAR GZIP archive at PATH'
    long_desc <<-LONG_DESC
      Imports custom emoji from a TAR GZIP archive specified by PATH.

      Existing emoji will be skipped unless the --overwrite option
      is provided, in which case they will be overwritten.

      You can specify a --category under which the emojis will be
      grouped together.

      With the --prefix option, a prefix can be added to all
      generated shortcodes. Likewise, the --suffix option controls
      the suffix of all shortcodes.

      With the --unlisted option, the processed emoji will not be
      visible in the emoji picker (but still usable via other means)
    LONG_DESC
    def import(path)
      imported = 0
      skipped  = 0
      failed   = 0
      category = options[:category] ? CustomEmojiCategory.find_or_create_by(name: options[:category]) : nil

      Gem::Package::TarReader.new(Zlib::GzipReader.open(path)) do |tar|
        tar.each do |entry|
          next unless entry.file? && entry.full_name.end_with?('.png', '.gif')

          filename = File.basename(entry.full_name, '.*')

          # Skip macOS shadow files
          next if filename.start_with?('._')

          shortcode    = [options[:prefix], filename, options[:suffix]].compact.join
          custom_emoji = CustomEmoji.local.find_by('LOWER(shortcode) = ?', shortcode.downcase)

          if custom_emoji && !options[:overwrite]
            skipped += 1
            next
          end

          custom_emoji ||= CustomEmoji.new(shortcode: shortcode, domain: nil)
          custom_emoji.image = StringIO.new(entry.read)
          custom_emoji.image_file_name = File.basename(entry.full_name)
          custom_emoji.visible_in_picker = !options[:unlisted]
          custom_emoji.category = category

          if custom_emoji.save
            imported += 1
          else
            failed += 1
            say('Failure/Error: ', :red)
            say(entry.full_name)
            shell.indent(2) do
              say(custom_emoji.errors[:image].join(', '), :red)
            end
          end
        end
      end

      say("Imported #{imported}, skipped #{skipped}, failed to import #{failed}", color(imported, skipped, failed))
    end

    option :category
    option :overwrite, type: :boolean
    desc 'export PATH', 'Export emoji to a TAR GZIP archive at PATH'
    long_desc <<-LONG_DESC
      Exports custom emoji to 'export.tar.gz' at PATH.

      The --category option dumps only the specified category.
      If this option is not specified, all emoji will be exported.

      The --overwrite option will overwrite an existing archive.
    LONG_DESC
    def export(path)
      exported         = 0
      category         = CustomEmojiCategory.find_by(name: options[:category])
      export_file_name = File.join(path, 'export.tar.gz')

      fail_with_message "Archive already exists! Use '--overwrite' to overwrite it!" if File.file?(export_file_name) && !options[:overwrite]
      fail_with_message "Unable to find category '#{options[:category]}'!" if category.nil? && options[:category]

      File.open(export_file_name, 'wb') do |file|
        Zlib::GzipWriter.wrap(file) do |gzip|
          Gem::Package::TarWriter.new(gzip) do |tar|
            scope = !options[:category] || category.nil? ? CustomEmoji.local : category.emojis
            scope.find_each do |emoji|
              say("Adding '#{emoji.shortcode}'...")
              tar.add_file_simple(emoji.shortcode + File.extname(emoji.image_file_name), 0o644, emoji.image_file_size) do |io|
                io.write Paperclip.io_adapters.for(emoji.image).read
                exported += 1
              end
            end
          end
        end
      end
      say("Exported #{exported}")
    end

    option :remote_only, type: :boolean
    option :suspended_only, type: :boolean
    desc 'purge', 'Remove all custom emoji'
    long_desc <<-LONG_DESC
      Removes all custom emoji.

      With the --remote-only option, only remote emoji will be deleted.

      With the --suspended-only option, only emoji from suspended servers will be deleted.
    LONG_DESC
    def purge
      if options[:suspended_only]
        DomainBlock.where(severity: :suspend).find_each do |domain_block|
          CustomEmoji.by_domain_and_subdomains(domain_block.domain).find_in_batches do |custom_emojis|
            AttachmentBatch.new(CustomEmoji, custom_emojis).delete
          end
        end
      else
        scope = options[:remote_only] ? CustomEmoji.remote : CustomEmoji
        scope.in_batches.destroy_all
      end

      say('OK', :green)
    end

    # 未連合の絵文字は初回や新設サーバーで数百件になりうるので、通知に流せる長さに畳む
    REPORTED_SHORTCODES = 10

    option :dry_run, type: :boolean, default: true
    desc 'sync ORIGIN', 'Sync custom emoji and their categories from a sister Misskey server at ORIGIN'
    long_desc <<-LONG_DESC
      Aligns local custom emoji with the sister Misskey server at ORIGIN,
      which is treated as the single source of truth.

      Emoji that already federated from ORIGIN but have no local counterpart
      are copied locally, every local emoji known to ORIGIN has its category
      overwritten with the one used there, and categories left without any
      emoji are removed.

      Nothing is ever deleted, and local emoji unknown to ORIGIN are left
      untouched and reported instead. Running this repeatedly is safe, since
      it always writes only what differs.

      Nothing is written unless --no-dry-run is given.
    LONG_DESC
    def sync(origin)
      syncer = MisskeyEmojiSync.new(origin)
      plan   = syncer.plan

      say("Syncing custom emoji from #{syncer.domain}#{dry_run_mode_suffix}")

      if dry_run?
        plan.copy.each { |emoji| say("  copy #{emoji.shortcode}") }
        plan.recategorize.each { |change| say("  #{change[:shortcode]}: #{change[:from] || '(none)'} -> #{change[:to] || '(none)'}") }
        plan.obsolete_categories.each { |name| say("  remove empty category #{name}") }
        counts = { copied: plan.copy.size, recategorized: plan.recategorize.size, removed_categories: plan.obsolete_categories.size }
      else
        syncer.apply!
        counts = syncer.applied
      end

      say("Copied #{counts[:copied]}, recategorized #{counts[:recategorized]}, removed #{counts[:removed_categories]} empty categories#{dry_run_mode_suffix}", :green)

      syncer.copy_failures.each { |failure| say("Failed to copy #{failure[:shortcode]}: #{failure[:message]}", :red) }

      say("#{plan.awaiting_federation.size} emoji on #{syncer.domain} have not federated here yet, post them there to bring them over: #{summarize_shortcodes(plan.awaiting_federation)}", :yellow) if plan.awaiting_federation.any?
      say("#{plan.orphans.size} local emoji are unknown to #{syncer.domain} and were left untouched: #{summarize_shortcodes(plan.orphans)}", :yellow) if plan.orphans.any?
      say("#{plan.unsyncable.size} emoji on #{syncer.domain} cannot be represented here, names must match #{CustomEmoji::SHORTCODE_RE_FRAGMENT} and be at most #{CustomEmoji::MAX_SHORTCODE_SIZE} characters: #{summarize_shortcodes(plan.unsyncable)}", :yellow) if plan.unsyncable.any?
    rescue MisskeyEmojiSync::Error => e
      fail_with_message e.message
    end

    private

    def summarize_shortcodes(shortcodes)
      return shortcodes.join(', ') if shortcodes.size <= REPORTED_SHORTCODES

      "#{shortcodes.first(REPORTED_SHORTCODES).join(', ')} and #{shortcodes.size - REPORTED_SHORTCODES} more"
    end

    def color(green, _yellow, red)
      if !green.zero? && red.zero?
        :green
      elsif red.zero?
        :yellow
      else
        :red
      end
    end
  end
end
