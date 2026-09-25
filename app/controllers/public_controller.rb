class PublicController < ActionController::Base
  include RequestExceptionHandler
  skip_before_action :verify_authenticity_token
end
