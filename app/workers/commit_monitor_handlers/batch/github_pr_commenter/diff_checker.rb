module CommitMonitorHandlers::Batch
  class GithubPrCommenter::DiffChecker
    include Sidekiq::Worker
    sidekiq_options :queue => :miq_bot_glacial

    include BatchEntryWorkerMixin
    include BranchWorkerMixin

    def perform(batch_entry_id, branch_id, _new_commits)
      return unless find_batch_entry(batch_entry_id)
      return unless find_branch(branch_id, :pr)

      complete_batch_entry(bad_text_and_files.any? ? {:result => new_comment} : {})
    end

    private

    def new_comment
      @offenses ||= []
      process_diff
      @offenses.join("\n")
    end

    def process_diff
      # diff = branch.git_diff
      diff = Branch.first.git_diff
      diff.patches.each { |patch| process_patch(patch) }
    end

    def process_patch(patch)
      patch.hunks.each { |hunk| process_hunk(hunk, patch) }
    end

    def process_hunk(hunk, parent_patch)
      hunk.lines.each { |line| process_line(line, hunk, parent_patch) }
    end

    def process_line(line, parent_hunk, parent_patch)
      return unless line.addition?
      location = "#{parent_patch.delta.new_file[:path]}:#{line.new_lineno}"
      content  = line.content.downcase
      check_line_blacklisted(content, location)
      check_line_puts(content, location)
    end

    def add_offense(severity, offense, location)
      @offenses << "#{severity} Detected *\"#{offense}\"* at #{location}"
    end

    def check_line_blacklisted(content, location)
      return if Settings.diff_checker.blacklisted_strings.except.try(:any?) { |except| location.start_with?(except) }
      Settings.diff_checker.blacklisted_strings.matchers.each do |matcher|
        add_offense(":black_circle:", matcher, location) if content.include?(matcher)
      end
    end

    def check_line_puts(content, location)
      return if Settings.diff_checker.puts.except.any? { |except| location.start_with?(except) }
      add_offense(":red_circle:", "puts", location) if content.include?("puts")
    end
  end
end
