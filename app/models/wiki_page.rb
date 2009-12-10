class WikiPage < ActiveRecord::Base
  include ActionController::UrlWriter
  include WikiEngine::Model
  belongs_to :project
  # self.friendly_id_options[:scope] = :project
  self.friendly_id_options[:scope] = :scope_value
  self.non_versioned_columns << :project_id
  named_scope :main, lambda{ |project| {:conditions => {:main => true, :project_id => project.id}} }

  after_create  :process_create
  before_update :process_update_params
  before_destroy :process_destroy

  def scope_value
	self.project.id.to_s
  end

  def process_create
    ApplicationLog.new_log(self, self.created_by, :add)
  end

  def process_update_params
    ApplicationLog.new_log(self, self.created_by, :edit)
  end

  def process_destroy
    ApplicationLog.new_log(self, self.created_by, :delete)
  end

  def object_name
    self.title
  end

  def object_url(host = nil)
    url_for :only_path => host.nil?, :host => host, :controller => 'wiki_pages', :action => 'show', :id => self, :active_project => self.project_id
  end

  # Core permissions

  def self.can_be_created_by(user, project)
    project.is_active? and user.member_of(project) and user.has_permission(project, :can_manage_wiki_pages)
  end

  def can_be_edited_by(user)
    project.is_active? and user.member_of(project) and user.has_permission(project, :can_manage_wiki_pages)
  end

  def can_be_deleted_by(user)
    user.is_admin and project.is_active? and user.member_of(project)
  end

  protected
  def main_page
    @main_page ||= self.class.main(project).first
  end
end
