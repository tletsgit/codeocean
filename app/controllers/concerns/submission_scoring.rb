require 'concurrent/future'

module SubmissionScoring
  def collect_test_results(submission)
    # Mnemosyne.trace 'custom.codeocean.collect_test_results', meta: { submission: submission.id } do
    submission.collect_files.select(&:teacher_defined_test?).map do |file|
      future = Concurrent::Future.execute do
        # Mnemosyne.trace 'custom.codeocean.collect_test_results_block', meta: { file: file.id, submission: submission.id } do
        assessor = Assessor.new(execution_environment: submission.execution_environment)
        output = execute_test_file(file, submission)
        assessment = assessor.assess(output)
        passed = ((assessment[:passed] == assessment[:count]) and (assessment[:score] > 0))
        testrun_output = passed ? nil : 'message: ' + output[:message].to_s + "\n stdout: " + output[:stdout].to_s + "\n stderr: " + output[:stderr].to_s
        unless testrun_output.blank?
          submission.exercise.execution_environment.error_templates.each do |template|
            pattern = Regexp.new(template.signature).freeze
            if pattern.match(testrun_output)
              StructuredError.create_from_template(template, testrun_output, submission)
            end
          end
        end
        Testrun.new(
            submission: submission,
            cause: 'assess',
            file: file,
            passed: passed,
            output: testrun_output,
            container_execution_time: output[:container_execution_time],
            waiting_for_container_time: output[:waiting_for_container_time]
        ).save
        output.merge!(assessment)
        output.merge!(filename: file.name_with_extension, message: feedback_message(file, output[:score]), weight: file.weight)
        # end
      end
      future.value
    end
    # end
  end

  private :collect_test_results

  def execute_test_file(file, submission)
    DockerClient.new(execution_environment: file.context.execution_environment).execute_test_command(submission, file.name_with_extension)
  end

  private :execute_test_file

  def feedback_message(file, score)
    set_locale
    score == Assessor::MAXIMUM_SCORE ? I18n.t('exercises.implement.default_feedback') : render_markdown(file.feedback_message)
  end

  def score_submission(submission)
    outputs = collect_test_results(submission)
    score = 0.0
    unless outputs.nil? || outputs.empty?
      outputs.each do |output|
        unless output.nil?
          score += output[:score] * output[:weight]
        end

        if output.present? && output[:status] == :timeout
          output[:stderr] += "\n\n#{t('exercises.editor.timeout', permitted_execution_time: submission.exercise.execution_environment.permitted_execution_time.to_s)}"
        end
      end
    end
    submission.update(score: score)
    if submission.normalized_score == 1.0
      Thread.new do
        RequestForComment.where(exercise_id: submission.exercise_id, user_id: submission.user_id, user_type: submission.user_type).each { |rfc|
          rfc.full_score_reached = true
          rfc.save
        }
      ensure
        ActiveRecord::Base.connection_pool.release_connection
      end
    end
    if @embed_options.present? && @embed_options[:hide_test_results] && outputs.present?
      outputs.each do |output|
        output.except!(:error_messages, :count, :failed, :filename, :message, :passed, :stderr, :stdout)
      end
    end
    outputs
  end
end
