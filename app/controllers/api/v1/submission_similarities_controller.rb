# frozen_string_literal: true

require 'api_keys_handler'
require 'pdfkit'

module Api
  module V1
    # The `SubmissionSimilaritiesController` is responsible for handling API requests related to
    # fetching submission similarities for assignments. It provides an endpoint for clients to
    # retrieve submission similarities associated with a given assignment. The API key must be
    # provided and validated for access, and the user associated with the API key must have
    # authorization for the specified course.
    class SubmissionSimilaritiesController < ApplicationController
      skip_before_action :authenticate_user!

      before_action do |_controller|
        set_api_key_and_assignment
      end

      def index
        APIKeysHandler.authenticate_api_key
        render_submission_similarities
      rescue APIKeysHandler::APIKeyError => e
        render json: { error: e.message }, status: e.status
      end

      def show
        APIKeysHandler.authenticate_api_key
        render_pair_of_flagged_submissions
      rescue APIKeysHandler::APIKeyError => e
        render json: { error: e.message }, status: e.status
      end

      def view_pdf
        APIKeysHandler.authenticate_api_key
        generate_pdf
      rescue APIKeysHandler::APIKeyError => e
        render json: { error: e.message }, status: e.status
      end

      private

      def set_api_key_and_assignment
        set_api_key
        set_course_and_assignment
      end

      def set_api_key
        api_key_value = request.headers['X-API-KEY']
        APIKeysHandler.api_key = ApiKey.find_by(value: api_key_value)
      end

      def set_course_and_assignment(assignment_id = params[:assignment_id])
        assignment = Assignment.find_by(id: assignment_id)
        return nil if assignment.nil?

        APIKeysHandler.course = assignment.course
        assignment
      end

      def render_submission_similarities
        assignment = set_course_and_assignment(params[:assignment_id])

        if assignment.nil?
          render json: { error: 'Assignment does not exist' }, status: :bad_request
          return
        end

        submission_similarities = assignment.submission_similarities

        if assignment.submissions.empty?
          render json: { status: 'empty' }, status: :ok
          return
        end

        submission_similarity_process = assignment.submission_similarity_process

        case submission_similarity_process.status
        when SubmissionSimilarityProcess::STATUS_RUNNING, SubmissionSimilarityProcess::STATUS_WAITING
          render_processing_status
        when SubmissionSimilarityProcess::STATUS_ERRONEOUS
          render_error_status
        else
          submission_similarities = apply_filters(submission_similarities)
          render_paginated_or_limited_submission_similarities(submission_similarities)
        end
      end

      def render_filtered_submission_similarities(submission_similarities)
        submission_similarities = apply_filters(submission_similarities)

        render_paginated_submission_similarities(submission_similarities)
      end

      def apply_filters(submission_similarities)
        # Apply the threshold filter
        if params[:threshold].present?
          threshold_value = params[:threshold].to_f
          submission_similarities = submission_similarities.where('similarity >= ?', threshold_value)
        end

        # Apply the limit filter
        if params[:limit].present?
          limit_value = params[:limit].to_i
          submission_similarities = submission_similarities.limit(limit_value)
        end

        submission_similarities
      end

      def render_paginated_or_limited_submission_similarities(submission_similarities)
        if params[:limit].present?
          render_json_response(submission_similarities)
        else
          # Set the default per page value to 20 for pagination
          per_page = 20

          # Sort the submission_similarities by similarity in descending order by default
          submission_similarities = submission_similarities.order(similarity: :desc)

          submission_similarities = submission_similarities.paginate(page: params[:page], per_page: per_page)

          render_json_response(submission_similarities)
        end
      end

      def render_json_response(submission_similarities)
        render json: { status: 'processed', submissionSimilarities: submission_similarities }, status: :ok
      end

      def render_processing_status
        render json: { status: 'processing' }, status: :ok
      end

      def render_error_status
        render json: { status: 'error', message: 'SSID is busy or under maintenance. Please try again later.' },
               status: :service_unavailable
      end

      def render_pair_of_flagged_submissions
        submission_similarity = SubmissionSimilarity.find_by(
          assignment_id: params[:assignment_id],
          id: params[:id]
        )

        if submission_similarity.nil?
          render json: { error: 'Submission similarities requested do not exist.' }, status: :bad_request
          return
        end

        max_similarity_percentage = submission_similarity.similarity
        matches = []

        submission_similarity.similarity_mappings.each do |similarity|
          matches.append(
            {
              student1: similarity.line_range1_string,
              student2: similarity.line_range2_string,
              statementCount: similarity.statement_count
            }
          )
        end

        pdf_file_path = "api/v1/assignments/#{submission_similarity.assignment_id}/" \
                        "submission_similarities/#{submission_similarity.id}/view_pdf"

        render json: {
          similarity: submission_similarity.similarity,
          matches: matches,
          pdf_link: pdf_file_path
        }, status: :ok
      end

      def generate_pdf
        submission_similarity = SubmissionSimilarity.find_by(
          assignment_id: params[:assignment_id],
          id: params[:id]
        )

        if submission_similarity.nil?
          render json: { error: 'Submission similarities requested do not exist.' }, status: :bad_request
          return
        end

        pdf_content = generate_pdf_content(submission_similarity)
        send_data pdf_content, type: 'application/pdf', 
                              disposition: 'attachment', filename: "#{submission_similarity.id}.pdf"
      end

      def generate_pdf_content(submission_similarity)
        @submission_similarity = submission_similarity
        html_content = render_to_string(template: 'api/v1/submission_similarities/report_template', layout: false)
        pdf_report = PDFKit.new(html_content)
        pdf_report.to_pdf
      end
    end
  end
end
