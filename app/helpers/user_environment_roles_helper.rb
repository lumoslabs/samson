# frozen_string_literal: true
module UserEnvironmentRolesHelper
  # multiple are checked, but browser only shows last
  def user_environment_role_radio(user, role_name, role_id, user_environment_role_id)
    super_admin = (user.role_id == Role::SUPER_ADMIN.id)
    user_role_is_inferior = user.role_id < role_id.to_i
    # Environment roles are meant only to limit, so the user
    # can't be set to a level above their current level.
    disabled = super_admin || user_role_is_inferior

    global_access = (user.role_id >= role_id.to_i)
    environment_access = (user_environment_role_id && user_environment_role_id.to_i >= role_id.to_i)
    checked = environment_access || !role_id
    title = "User is a global #{user.role.name.capitalize}" if global_access

    label_tag nil, class: ('disabled' if disabled), title: title do
      radio_button_tag(:role_id, role_id.to_s, checked, disabled: disabled) <<
        " " <<
        role_name.titlecase
    end
  end
end
