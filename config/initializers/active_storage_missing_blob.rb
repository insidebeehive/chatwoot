# ActiveStorage's SetBlob concern resolves signed IDs with find_signed!, which raises
# RecordNotFound once the blob row is gone. Every controller including it inherits from
# ActiveStorage::BaseController, which has no handler for it, so a request carrying a
# stale attachment URL surfaces as a 500 rather than a 404. Chatwoot's own controllers
# already map RecordNotFound to 404 via RequestExceptionHandler; this brings the
# ActiveStorage controllers in line.
Rails.application.config.to_prepare do
  ActiveStorage::BaseController.rescue_from(ActiveRecord::RecordNotFound) { head :not_found }
end
