class User < ApplicationRecord
  has_secure_password
  has_many :sessions, dependent: :destroy

  belongs_to :company

  normalizes :email_address, with: ->(e) { e.strip.downcase }

  def name
    email_address.split("@").first.capitalize
  end
end
