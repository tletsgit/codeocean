class FlowrController < ApplicationController

  def insights
    require_user!
    # get the latest submission for this user that also has a test run (i.e. structured_errors if applicable)
    submission = Submission.joins(:testruns)
                     .where(submissions: {user_id: current_user.id, user_type: current_user.class.name})
                     .order('testruns.created_at DESC').first

    # Return if no submission was found
    if submission.blank? || @embed_options[:disable_hints] || @embed_options[:hide_test_results]
      skip_authorization
      render json: [], status: :ok
      return
    end

    # verify authorization for the submission, as all queried errors are generated by this submission anyway
    # and structured_errors don't have a policy yet
    authorize(submission)
    errors = StructuredError.where(submission_id: submission.id)

    # for each error get all attributes, filter out uninteresting ones, and build a query
    insights = errors.map do |error|
      attributes = error.structured_error_attributes.select do |attribute|
        is_interesting(attribute) and attribute.match
      end
      # once the programming language model becomes available, the language name can be added to the query to
      # produce more relevant results
      query = attributes.map{|att| att.value}.join(' ')
      { submission: submission, error: error, attributes: attributes, query: query }
    end

    # Always return JSON
    render json: insights, status: :ok
  end

  def is_interesting(attribute)
    attribute.error_template_attribute.key.index(/error message|error type/i) != nil
  end
  private :is_interesting
end
