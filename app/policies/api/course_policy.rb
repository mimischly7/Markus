module Api
  # Policies for Api::CoursesController
  class CoursePolicy < MainApiPolicy
    skip_pre_check :role_exists?

    def index?
      # has at least one instructor role
      real_user.is_a?(EndUser) && real_user.roles.pluck(:type).include?('Instructor')
    end
  end
end
