require 'sidekiq-scheduler'

require_relative 'job_presenter'

module SidekiqScheduler
  # Hook into *Sidekiq::Web* app which adds a new '/recurring-jobs' page

  module Web
    VIEW_PATH = File.expand_path('../../../web/views', __FILE__)

    def self.registered(app)
      app.get '/recurring-jobs' do
        @presented_jobs = JobPresenter.build_collection(Sidekiq.schedule!)

        erb File.read(File.join(VIEW_PATH, 'recurring_jobs.erb'))
      end

      app.post '/recurring-jobs/:name/enqueue' do
        schedule = Sidekiq.get_schedule(params[:name])
        SidekiqScheduler::Scheduler.instance.enqueue_job(schedule)
        redirect "#{root_path}recurring-jobs"
      end

      app.post '/recurring-jobs/:name/toggle' do
        Sidekiq.reload_schedule!

        SidekiqScheduler::Scheduler.instance.toggle_job_enabled(params[:name])
        redirect "#{root_path}recurring-jobs"
      end

      app.post '/recurring-jobs/:name/remove' do
        Sidekiq.reload_schedule!

        Sidekiq.remove_schedule(params[:name])
        redirect "#{root_path}recurring-jobs"
      end

      app.post '/recurring-jobs/toggle-all' do
        SidekiqScheduler::Scheduler.instance.toggle_all_jobs(params[:action] == 'enable')
        redirect "#{root_path}recurring-jobs"
      end

      # New actions
      app.post '/recurring-jobs/:name/destroy' do
        Sidekiq.reload_schedule!

        dynamo_clas_name = ENV.fetch('SIDEKIQ_SCHEDUER_DYNAMOID_CLASS', 'ScheduleRule')
        klass = dynamo_clas_name.constantize
        sr = klass.where(job_name: params[:name]).first
        if sr.present?
          sr.destroy
        else
          Sidekiq.remove_schedule(params[:name])
        end

        redirect "#{root_path}recurring-jobs"
      end

      app.post '/recurring-jobs/:name/edit' do
        @title = 'Recurring Job Update'
        @form_action = "#{root_path}recurring-jobs/#{ERB::Util.url_encode(params[:name])}/update"
        @existing_rule = true
        @presented_job = JobPresenter.new(params[:name], Sidekiq.get_schedule(params[:name]))
        erb File.read(File.join(VIEW_PATH, 'recurring_job.erb'))
      end

      app.post '/recurring-jobs/new' do
        @title = 'New Recurring Job'
        @presented_job = JobPresenter.new('', {})
        @existing_rule = false
        @form_action = "#{root_path}recurring-jobs/create"
        erb File.read(File.join(VIEW_PATH, 'recurring_job.erb'))
      end

      app.post '/recurring-jobs/:name/update' do
        dynamo_clas_name = ENV.fetch('SIDEKIQ_SCHEDUER_DYNAMOID_CLASS', 'ScheduleRule')
        klass = dynamo_clas_name.constantize
        config = params.slice(*%w[worker_class description cron queue args]).transform_values(&:presence)
        sr = klass.where(job_name: params[:name]).first
        if sr.present?
          config.each { |k, v| sr.send "#{k}=", v}
          sr.save!
        else
          klass.create config.merge(job_name: params[:name])
        end

        Sidekiq.reload_schedule!
        redirect "#{root_path}recurring-jobs"
      end

      app.post '/recurring-jobs/create' do
        dynamo_clas_name = ENV.fetch('SIDEKIQ_SCHEDUER_DYNAMOID_CLASS', 'ScheduleRule')
        klass = dynamo_clas_name.constantize
        config = params.slice(*%w[job_name worker_class description cron queue args])
                       .transform_values(&:presence)
        klass.create config

        Sidekiq.reload_schedule!
        redirect "#{root_path}recurring-jobs"
      end
    end
  end
end

require_relative 'extensions/web'
