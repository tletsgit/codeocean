# frozen_string_literal: true

module ProformaService
  class ConvertTaskToExercise < ServiceBase
    def initialize(task:, user:, exercise: nil)
      @task = task
      @user = user
      @exercise = exercise || Exercise.new(unpublished: true)
    end

    def execute
      import_exercise
      @exercise
    end

    private

    def import_exercise
      @exercise.assign_attributes(
        user: @user,
        title: @task.title,
        description: @task.description,
        instructions: @task.internal_description,
        files: files
      )
    end

    def files
      test_files + task_files.values
    end

    def test_files
      @task.tests.map do |test_object|
        task_files.delete(test_object.files.first.id).tap do |file|
          file.weight = 1.0
          file.feedback_message = test_object.meta_data['feedback-message']
        end
      end
    end

    def task_files
      @task_files ||= Hash[
        @task.all_files.reject { |file| file.id == 'ms-placeholder-file' }.map do |task_file|
          [task_file.id, codeocean_file_from_task_file(task_file)]
        end
      ]
    end

    def codeocean_file_from_task_file(file)
      codeocean_file = CodeOcean::File.new(
        context: @exercise,
        file_type: FileType.find_by(file_extension: File.extname(file.filename)),
        hidden: file.visible == 'no',
        name: File.basename(file.filename, '.*'),
        read_only: file.usage_by_lms != 'edit',
        role: file.internal_description,
        path: File.dirname(file.filename).in?(['.', '']) ? nil : File.dirname(file.filename)
      )
      if file.binary
        codeocean_file.native_file = FileIO.new(file.content.dup.force_encoding('UTF-8'), File.basename(file.filename))
      else
        codeocean_file.content = file.content
      end
      codeocean_file
    end
  end
end
