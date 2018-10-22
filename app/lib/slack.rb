require 'httparty'
require 'addressable/uri'
require 'json'

class Slack
  def initialize
    @url = Addressable::URI.parse('https://discordapp.com/api/webhooks/414236087540514826/azbPQmk_3Xj5FnhIADXxW-tZLgRs1sCek7_1tQIoGW2PAK9E7anIY-KjjheiD1C_-RNM/slack')
  end

  def say(message)
    response = HTTParty.post(@url, {
      body: {text: JSON.pretty_generate(message)}.to_json,
    })
  end
end

