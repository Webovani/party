class SessionsController < ApplicationController
  def create
    nick = params[:nick].to_s.strip
    if nick.match?(User::NICK_FORMAT)
      cookies.signed.permanent[:nick] = { value: nick, httponly: true }
      User.touch_nick(nick)
      redirect_to root_path
    else
      redirect_to root_path, alert: "Nickname must be 1–32 letters, numbers, spaces, . or -."
    end
  end

  def destroy
    cookies.delete(:nick)
    redirect_to root_path
  end
end
