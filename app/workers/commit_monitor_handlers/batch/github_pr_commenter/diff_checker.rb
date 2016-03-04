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
      diff = branch.git_diff
      # diff = Branch.first.git_diff
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
      check_line(content, location)
    end

    def add_offense(severity, offender, location)
      @offenses << "#{severity} **\"#{offender}\"** Detected at #{location}"
    end

    def settings
      @settings ||= Settings.diff_checker
    end

    def check_line(content, location)
      settings.each do |offender, options|
        next if options.except.try(:any?) { |except| location.start_with?(except) }
        string = offender.to_s
        add_offense(options.severity, string, location) if content.include?(string)
      end
    end
  end
end
