# frozen_string_literal: true

class Users::PasswordsController < Devise::PasswordsController
  # ゲスト向けの reject_guest はここには置かない。Devise の require_no_authentication が
  # prepend_before_action で先に走り、ログイン中のユーザーを追い返すため、常にログイン
  # 状態であるゲストはこのコントローラに到達しない。置いても死んだコードになる。
  # （ゲストのメールは guest_xxxx@example.com という架空アドレスで届かないため、
  # 到達させないこと自体は必要。検証は spec/requests/guest_restrictions_spec.rb にある）

  # GET /resource/password/new
  # def new
  #   super
  # end

  # POST /resource/password
  # def create
  #   super
  # end

  # GET /resource/password/edit?reset_password_token=abcdef
  # def edit
  #   super
  # end

  # PUT /resource/password
  # def update
  #   super
  # end

  # protected

  # def after_resetting_password_path_for(resource)
  #   super(resource)
  # end

  # The path used after sending reset password instructions
  # def after_sending_reset_password_instructions_path_for(resource_name)
  #   super(resource_name)
  # end
end
