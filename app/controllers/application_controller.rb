class ApplicationController < ActionController::Base
  include Authentication
  # Only allow modern browsers supporting webp images, web push, badges, import maps, CSS nesting, and CSS :has.
  allow_browser versions: :modern

  # Changes to the importmap will invalidate the etag for HTML responses
  stale_when_importmap_changes

  private
    def paginate(scope)
      @per_page = 25
      @total_count = scope.count(:all)
      @total_pages = [ (@total_count + @per_page - 1) / @per_page, 1 ].max
      @page = (Integer(params[:page].to_s, 10, exception: false) || 1).clamp(1, @total_pages)
      @offset = (@page - 1) * @per_page

      scope.limit(@per_page).offset(@offset)
    end
end
