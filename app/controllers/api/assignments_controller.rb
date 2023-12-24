module Api
  # Allows for adding, modifying and showing Markus assignments.
  # Uses Rails' RESTful routes (check 'rake routes' for the configured routes)
  class AssignmentsController < MainApiController
    include AutomatedTestsHelper
    include SubmissionsHelper

    # Define default fields to display for index and show methods
    DEFAULT_FIELDS = [:id, :description, :short_identifier, :message, :due_date,
                      :group_min, :group_max, :tokens_per_period, :allow_web_submits,
                      :student_form_groups, :remark_due_date, :remark_message,
                      :assign_graders_to_criteria, :enable_test, :enable_student_tests, :allow_remarks,
                      :display_grader_names_to_students, :group_name_autogenerated,
                      :repository_folder, :is_hidden, :vcs_submit, :token_period,
                      :non_regenerating_tokens, :unlimited_tokens, :token_start_date, :has_peer_review,
                      :starter_file_type, :default_starter_file_group_id].freeze

    # Returns a list of assignments and their attributes
    # Optional: filter, fields
    def index
      assignments = get_collection(current_role.visible_assessments) || return

      respond_to do |format|
        json_response = "[#{assignments.map { |assignment| assignment.to_json(only: DEFAULT_FIELDS) }.join(',')}]"

        format.xml { render xml: assignments.to_xml(only: DEFAULT_FIELDS, root: 'assignments', skip_types: 'true') }
        format.json { render json: json_response }
      end
    end

    # Returns an assignment and its attributes
    # Requires: id
    # Optional: filter, fields
    def show
      assignment = record
      if assignment.nil?
        # No assignment with that id
        render 'shared/http_status', locals: { code: '404', message:
          'No assignment exists with that id' }, status: :not_found
      else
        respond_to do |format|
          format.xml { render xml: assignment.to_xml(only: DEFAULT_FIELDS, root: 'assignment', skip_types: 'true') }
          format.json { render json: assignment.to_json(only: DEFAULT_FIELDS) }
        end
      end
    end

    # Creates a new assignment
    # Requires: short_identifier, due_date, description
    # Optional: repository_folder, group_min, group_max, tokens_per_period,
    # submission_rule_type, allow_web_submits,
    # display_grader_names_to_students, enable_test, assign_graders_to_criteria,
    # message, allow_remarks, remark_due_date, remark_message, student_form_groups,
    # group_name_autogenerated, submission_rule_deduction, submission_rule_hours,
    # submission_rule_interval
    def create
      if has_missing_params?([:short_identifier, :due_date, :description])
        # incomplete/invalid HTTP params
        render 'shared/http_status', locals: { code: '422', message:
          HttpStatusHelper::ERROR_CODE['message']['422'] }, status: :unprocessable_entity
        return
      end

      # check if there is an existing assignment
      assignment = Assignment.find_by(short_identifier: params[:short_identifier])
      unless assignment.nil?
        render 'shared/http_status', locals: { code: '409', message:
          'Assignment already exists' }, status: :conflict
        return
      end

      # No assignment found so create new one
      attributes = { short_identifier: params[:short_identifier], course_id: params[:course_id] }
      attributes = process_attributes(params, attributes)

      new_assignment = Assignment.new(attributes)

      # Get and assign the submission_rule
      submission_rule = get_submission_rule(params)

      if submission_rule.nil?
        render 'shared/http_status', locals: { code: '500', message:
          HttpStatusHelper::ERROR_CODE['message']['500'] }, status: :internal_server_error
        return
      end

      new_assignment.submission_rule = submission_rule

      unless new_assignment.save
        # Some error occurred
        render 'shared/http_status', locals: { code: '500', message:
          HttpStatusHelper::ERROR_CODE['message']['500'] }, status: :internal_server_error
        return
      end

      # Otherwise everything went alright.
      render 'shared/http_status', locals: { code: '201', message:
        HttpStatusHelper::ERROR_CODE['message']['201'] }, status: :created
    end

    # Updates an existing assignment
    # Requires: id
    # Optional: short_identifier, due_date,repository_folder, group_min, group_max,
    # tokens_per_period, submission_rule_type, allow_web_submits,
    # display_grader_names_to_students, enable_test, assign_graders_to_criteria,
    # description, message, allow_remarks, remark_due_date, remark_message,
    # student_form_groups, group_name_autogenerated, submission_rule_deduction,
    # submission_rule_hours, submission_rule_interval, starter_file_type,
    # default_starter_file_group_id
    def update
      # If no assignment is found, render an error.
      assignment = record
      if assignment.nil?
        render 'shared/http_status', locals: { code: '404', message:
          'Assignment was not found' }, status: :not_found
        return
      end

      # Create a hash to hold fields/values to be updated for the assignment
      attributes = {}

      if params[:short_identifier].present?
        # Make sure another assignment isn't using the new short_identifier
        other_assignment = Assignment.find_by(
          short_identifier: params[:short_identifier]
        )
        if !other_assignment.nil? && other_assignment != assignment
          render 'shared/http_status', locals: { code: '409', message:
            'short_identifier already in use' }, status: :conflict
          return
        end
        attributes[:short_identifier] = params[:short_identifier]
      end

      attributes = process_attributes(params, attributes)
      assignment.attributes = attributes

      # Update the submission rule if provided
      unless params[:submission_rule_type].nil?
        submission_rule = get_submission_rule(params)
        if submission_rule.nil?
          render 'shared/http_status', locals: { code: '500', message:
            HttpStatusHelper::ERROR_CODE['message']['500'] }, status: :internal_server_error
          return
        elsif submission_rule.valid?
          # If it's a valid submission rule, replace the existing one
          assignment.submission_rule.destroy
          assignment.submission_rule = submission_rule
        end
      end

      unless assignment.save
        # Some error occurred
        render 'shared/http_status', locals: { code: '500', message:
          HttpStatusHelper::ERROR_CODE['message']['500'] }, status: :internal_server_error
        return
      end

      # Made it this far, render success
      render 'shared/http_status', locals: { code: '200', message:
        HttpStatusHelper::ERROR_CODE['message']['200'] }, status: :ok
    end

    # Process the parameters passed for assignment creation and update
    def process_attributes(params, attributes)
      # Loop through default fields other than id
      fields = Array.new(DEFAULT_FIELDS)
      fields.delete(:id)
      fields.each do |field|
        attributes[field] = params[field] unless params[field].nil?
      end

      # Some attributes have to be set with default values when creating a new
      # assignment. They're based on the view's defaults.
      if request.post?
        attributes[:assignment_properties_attributes] = {}
        params[:assignment_properties_attributes] = {} if params[:assignment_properties_attributes].nil?
        if params[:assignment_properties_attributes][:repository_folder].nil?
          attributes[:assignment_properties_attributes][:repository_folder] = attributes[:short_identifier]
        end
        attributes[:is_hidden] = 0 if params[:is_hidden].nil?
      end

      attributes
    end

    # Get test specs file content
    def test_specs
      assignment = record
      content = autotest_settings_for(assignment)
      respond_to do |format|
        format.any { render json: content }
      end
    rescue ActiveRecord::RecordNotFound => e
      render 'shared/http_status', locals: { code: '404', message: e }, status: :not_found
    end

    # Upload test specs file content in a json format
    def update_test_specs
      assignment = record
      content = nil
      if params[:specs].is_a? ActionController::Parameters
        content = params[:specs].permit!.to_h
      elsif params[:specs].is_a? String
        begin
          content = JSON.parse params[:specs]
        rescue JSON::ParserError => e
          render 'shared/http_status', locals: { code: '422', message: e.message }, status: :unprocessable_entity
          return
        end
      end
      if content.nil?
        render 'shared/http_status',
               locals: { code: '422',
                         message: HttpStatusHelper::ERROR_CODE['message']['422'] },
               status: :unprocessable_entity
      else
        AutotestSpecsJob.perform_now(request.protocol + request.host_with_port, assignment, content)
      end
    rescue ActiveRecord::RecordNotFound => e
      render 'shared/http_status', locals: { code: '404', message: e }, status: :not_found
    rescue StandardError => e
      render 'shared/http_status', locals: { code: '500', message: e }, status: :internal_server_error
    end

    # Gets the submission rule for POST/PUT requests based on the supplied params
    # Defaults to NoLateSubmissionRule
    def get_submission_rule(params)
      if params[:submission_rule_type] == 'GracePeriod'
        submission_rule = GracePeriodSubmissionRule.new
        period = Period.new(hours: params[:submission_rule_hours])
        submission_rule.periods << period

      elsif params[:submission_rule_type] == 'PenaltyDecayPeriod'
        submission_rule = PenaltyDecayPeriodSubmissionRule.new
        period = Period.new(hours: params[:submission_rule_hours],
                            deduction: params[:submission_rule_deduction],
                            interval: params[:submission_rule_interval])
        submission_rule.periods << period

      elsif params[:submission_rule_type] == 'PenaltyPeriod'
        submission_rule = PenaltyPeriodSubmissionRule.new
        period = Period.new(hours: params[:submission_rule_hours],
                            deduction: params[:submission_rule_deduction])
        submission_rule.periods << period

      else
        submission_rule = NoLateSubmissionRule.new
      end

      submission_rule
    end

    def grades_summary
      assignment = record
      send_data assignment.summary_csv(current_role),
                type: 'text/csv',
                filename: "#{assignment.short_identifier}_grades_summary.csv",
                disposition: 'inline'
    rescue ActiveRecord::RecordNotFound => e
      render 'shared/http_status', locals: { code: '404', message: e }, status: :not_found
    end

    def test_files
      assignment = record
      zip_path = assignment.zip_automated_test_files(current_user)
      send_file zip_path, filename: File.basename(zip_path)
    rescue ActiveRecord::RecordNotFound => e
      render 'shared/http_status', locals: { code: '404', message: e }, status: :not_found
    end

    def submit_file
      student = current_role
      assignment = record

      # Do not submit a file if assignment is hidden
      unless allowed_to?(:see_hidden?, assignment)
        render 'shared/http_status', locals: { code: '403', message:
          HttpStatusHelper::ERROR_CODE['message']['403'] }, status: :forbidden
        return
      end

      # Disable submission via API if the instructor desires to
      unless assignment.api_submit
        render 'shared/http_status', locals: { code: '403', message:
          t('submissions.api_submission_disabled') }, status: :forbidden
        return
      end

      grouping = if student.has_accepted_grouping_for?(assignment.id)
                   student.accepted_grouping_for(assignment.id)
                 elsif assignment.group_max == 1
                   student.create_group_for_working_alone_student(assignment.id)
                   student.accepted_grouping_for(assignment.id)
                 else
                   student.create_autogenerated_name_group(assignment)
                 end

      upload_file(grouping, only_required_files: assignment.only_required_files)
    end

    def destroy
      assignment = Assignment.find_by(id: params[:id])
      if assignment.nil?
        render 'shared/http_status', locals: { code: '404', message: 'assignment not found' }, status: :not_found
        # render 'shared/http_status', locals: { code: '404', message: I18n.t('tags.not_found') }, status: :not_found
      elsif assignment.groups.length != 0
        render 'shared/http_status',
               locals: { code: :conflict, message: 'Assignment still has groupings!' }, status: :conflict
      else
        assignment.destroy
        render 'shared/http_status',
               locals: { code: '200', message: HttpStatusHelper::ERROR_CODE['message']['200'] }, status: :ok
      end
    end

    protected

    def implicit_authorization_target
      Assignment
    end
  end
end
