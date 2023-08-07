require 'test_helper'

class SessionsControllerTest < ActionController::TestCase
  test 'should get new session when requested' do
    get :new
    assert_response :success
  end

  test 'should direct to sessions page for ' do
    get :create
    assert_redirected_to controller: 'sessions', action: 'login'
  end

  test 'should auto redirect to index page for unauthorised destroy action' do
    get :destroy
    assert_redirected_to controller: 'sessions', action: 'index'
  end
end
