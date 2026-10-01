class ApplicationController < ActionController::Base
  include SiteGate
  include Authentication
  include TaxYearContext
end
