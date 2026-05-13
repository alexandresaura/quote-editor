require "test_helper"

class ApplicationSystemTestCase < ActionDispatch::SystemTestCase
  driven_by :selenium, using: :headless_chrome, screen_size: [ 1400, 1400 ]

  def sign_in_as(user)
    session = user.sessions.create!

    cookie_jar = ActionDispatch::TestRequest.create.cookie_jar
    cookie_jar.signed[:session_id] = session.id

    visit new_session_path
    page.driver.browser.manage.add_cookie(name: "session_id", value: cookie_jar["session_id"])
  end
end
