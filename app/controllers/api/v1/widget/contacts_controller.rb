class Api::V1::Widget::ContactsController < Api::V1::Widget::BaseController
  include WidgetHelper

  prepend_before_action :log_set_user_request, only: [:set_user]
  before_action :validate_hmac, only: [:set_user]
  after_action :log_set_user, only: [:set_user]

  def show; end

  def update
    identify_contact(@contact)
  end

  def set_user
    contact = nil

    if a_different_contact?
      @contact_inbox, @widget_auth_token = build_contact_inbox_with_token(@web_widget)
      contact = @contact_inbox.contact
    else
      contact = @contact
    end

    @contact_inbox.update(hmac_verified: true) if should_verify_hmac?

    identify_contact(contact)
  end

  # TODO : clean up this with proper routes delete contacts/custom_attributes
  def destroy_custom_attributes
    @contact.custom_attributes = @contact.custom_attributes.excluding(params[:custom_attributes])
    @contact.save!
    render json: @contact
  end

  private

  # Runs before any auth/lookup so we always capture the incoming request,
  # even when set_web_widget/set_contact later halt the chain (404) and no response log is produced.
  def log_set_user_request
    Rails.logger.info("[Widget#set_user] received request=#{request.raw_post}")
  end

  def log_set_user
    id = begin
      JSON.parse(response.body)['id']
    rescue StandardError
      nil
    end
    Rails.logger.info("[Widget#set_user] id=#{id} request=#{request.raw_post} response=#{response.body}")
  end

  def identify_contact(contact)
    contact_identify_action = ContactIdentifyAction.new(
      contact: contact,
      params: permitted_params.to_h.deep_symbolize_keys,
      discard_invalid_attrs: true
    )
    @contact = contact_identify_action.perform
  end

  def a_different_contact?
    @contact.identifier.present? && @contact.identifier != permitted_params[:identifier]
  end

  def validate_hmac
    return unless should_verify_hmac?
    return if valid_hmac?

    Rails.logger.info(
      "[Widget#set_user] HMAC failed identifier=#{params[:identifier]} " \
      "received_hash=#{params[:identifier_hash]} hmac_mandatory=#{@web_widget&.hmac_mandatory}"
    )
    render json: { error: 'HMAC failed: Invalid Identifier Hash Provided' }, status: :unauthorized
  end

  def should_verify_hmac?
    return false if params[:identifier_hash].blank? && !@web_widget.hmac_mandatory

    # Taking an extra caution that the hmac is triggered whenever identifier is present
    return false if params[:custom_attributes].present? && params[:identifier].blank?

    true
  end

  def valid_hmac?
    params[:identifier_hash] == OpenSSL::HMAC.hexdigest(
      'sha256',
      @web_widget.hmac_token,
      params[:identifier].to_s
    )
  end

  def permitted_params
    params.permit(:website_token, :identifier, :identifier_hash, :email, :name, :avatar_url, :phone_number, custom_attributes: {},
                                                                                                            additional_attributes: {})
  end
end
