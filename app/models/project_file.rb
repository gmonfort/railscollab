=begin
RailsCollab
-----------

Copyright (C) 2007 James S Urquhart (jamesu at gmail.com)

This program is free software; you can redistribute it and/or
modify it under the terms of the GNU General Public License
as published by the Free Software Foundation; either version 2
of the License, or (at your option) any later version.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with this program; if not, write to the Free Software
Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301, USA.
=end

class ProjectFile < ActiveRecord::Base
	include ActionController::UrlWriter
	
	belongs_to :project
	belongs_to :project_folder, :foreign_key => 'folder_id'
	
	has_many :project_file_revisions, :foreign_key => 'file_id', :order => 'revision_number DESC', :dependent => :destroy
	has_many :comments, :as => 'rel_object', :dependent => :destroy
	has_many :tags, :as => 'rel_object', :dependent => :destroy
	
	before_create :process_params
	before_update :process_update_params
	before_destroy :process_destroy
	
	def process_params
	  write_attribute("created_on", Time.now.utc)
	end
	
	def process_update_params
      write_attribute("updated_on", Time.now.utc)
	end
	
	def process_destroy
		AttachedFile.clear_files(self.id)
	end
	
	def tags
	 return Tag.list_by_object(self).join(',')
	end
	
	def tags=(val)
	 Tag.clear_by_object(self)
	 real_owner = project_file_revisions.empty? ? nil : self.project_file_revisions[0].created_by
	 Tag.set_to_object(self, val.split(','), real_owner) unless val.nil?
	end
	
	def created_by
		return project_file_revisions[0].created_by
	end
	
	def updated_by
		return project_file_revisions[0].updated_by
	end

	def object_name
	  return self.filename
	end
	
	def object_url
		url_for :only_path => true, :controller => 'files', :action => 'file_details', :id => self.id, :active_project => self.project_id
	end
	
	def download_url
		url_for :only_path => true, :controller => 'files', :action => 'download_file', :id => self.id, :active_project => self.project_id
	end
	
	def filetype_icon_url
		return project_file_revisions.empty? ? "/images/filetypes/unknown.png" : project_file_revisions[0].filetype_icon_url
	end
	
	def file_size
		return project_file_revisions.empty? ? 0 : project_file_revisions[0].filesize
	end
	
	def last_revision
		return self.project_file_revisions[0]
	end
	
	def add_revision(file, new_revision, user, comment)
		file_revision = ProjectFileRevision.new(:revision_number => new_revision)
		file_revision.project_file = self
		file_revision.upload_file = file
		
		file_revision.created_by = user
		file_revision.comment = comment
		
		file_revision.update_thumb
		
		file_revision.save!
	end
	
	def update_revision(file, old_revision, user, comment)
		old_revision.upload_file = file
		
		old_revision.updated_by = user
		old_revision.comment = comment
		
		old_revision.update_thumb
		
		old_revision.save!
	end
	
	def self.handle_files(files, to_object, user, is_private)
		if !files.nil?
			files.each do |file|
				return if file.class != StringIO
				
				filename = (file.original_filename).sanitize_filename
				
				ProjectFile.transaction do
					attached_file = ProjectFile.new()
					attached_file.filename = filename
					attached_file.is_private = is_private
					attached_file.is_visible = true
					attached_file.expiration_time = Time.now.utc
					attached_file.project = to_object.project
					
					attached_file.save!
					
					# Upload revision
					attached_file.add_revision(file, 1, user, "")
					to_object.project_file << attached_file
					
					
					ApplicationLog::new_log(attached_file, user, :add)
				end
			end
		end
	end
	
	def self.find_grouped(group_field, params)
		grouped_fields = {}
		found_files = ProjectFile.find(:all, params)
		
		group_type = DateTime if ['created_on', 'updated_on'].include?(group_field)
		group_type ||= String
		
		today = Date.today
		
		found_files.each do |file|
			dest_str = nil
			
			if group_type == DateTime
				file_time = file[group_field]
				if file_time.year == today.year
					dest_str = file_time.strftime("%A, %d %B")
				else
					dest_str = file_time.strftime("%A, %d %B %Y")
				end
			else
				dest_str = file[group_field].to_s[0..0]
			end
			
			grouped_fields[dest_str] ||= []
			grouped_fields[dest_str] << file
		end
		
		return found_files, grouped_fields
	end
	
	def self.select_list(project)
	   [['--None--', 0]] + ProjectFile.find(:all, :conditions => "project_id = #{project.id}", :select => 'id, filename').collect do |file|
	      [file.filename, file.id]
	   end
	end

    # Core permissions
    
	def self.can_be_created_by(user, project)
	  user.has_permission(project, :can_upload_files)
	end
	
	def can_be_edited_by(user)
	 if (!self.project.has_member(user))
	   return false
	 end
	 
	 if user.has_permission(project, :can_manage_files)
	   return true
	 end
	 
	 if self.created_by == user
	   return true
	 end
    end

	def can_be_deleted_by(user)
	 if !self.project.has_member(user)
	   return false
	 end
	 
	 if user.has_permission(project, :can_manage_files)
	   return true
	 end
	 
	 return false
    end
    
	def can_be_seen_by(user)
	 if !self.project.has_member(user)
	   return false
	 end
	 
	 if user.has_permission(project, :can_manage_files)
	   return true
	 end
	 
	 if self.is_private and !user.member_of_owner?
	   return false
	 end
	 
	 return true
    end
	
	# Specific Permissions

    def can_be_managed_by(user)
      return user.has_permission(project, :can_manage_files)
    end
    
    def can_be_downloaded_by(user)
      self.can_be_seen_by(user)
    end
    
    def options_can_be_changed_by(user)
      return (user.member_of_owner? and self.can_be_edited_by(user))
    end
    
    def comment_can_be_added_by(user)
      return (user.member_of(self.project) and self.comments_enabled)
    end
    
	# Accesibility
	
	attr_accessible :folder_id, :description
	
	# Validation
	
	validates_presence_of :filename
end
