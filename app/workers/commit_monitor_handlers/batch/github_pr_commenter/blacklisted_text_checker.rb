module CommitMonitorHandlers::Batch
  class GithubPrCommenter::BlacklistedTextChecker
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
      offenses.collect do |file_path, line_errors_hash|
        line_errors_hash.collect do |line_number, texts|
          texts.collect { |text| ":black_circle: Blacklisted Text \"#{text}\" found in #{file_path}:#{line_number}" }
        end
      end.flatten.join("\n")
    end

    def offenses
      @offenses ||= begin
        # diff = branch.git_diff
        diff = Branch.first.git_diff
        diff.patches.each_with_object({}) do |patch, hash|
          patch.hunks.each do |hunk|
            errors = check_hunk(hunk)
            next unless errors
            (hash[patch.delta.new_file[:path]] ||= {}).merge!(errors)
          end
        end
      end
    end

    def check_hunk(hunk)
      hunk.lines.select(&:addition?).each_with_object({}) do |line, hash|
        errors = check_line(line.content)
        hash[line.new_lineno] = errors if errors
      end.presence
    end

    def check_line(line)
      line = line.downcase
      Settings.blacklisted_text_checker.strings.select { |text| line.include?(text) }.presence
    end
  end
end
