require 'discordrb'
require 'yaml'

yaml = YAML.load_file('secret.yml')
token = yaml['token']
client_id = yaml['client_id']

bot = Discordrb::Commands::CommandBot.new token: token, client_id: client_id, prefix: '/'

# hello
bot.command :hello do |event|
  event.send_message("こんにちは！#{event.user.name}さん！")
end

# dice
bot.command :dice do |event|
  rand(1..6)
end

# eval
bot.command(:e, help_available: false) do |event, *code|
  eval code.join(' ') rescue 'それはできないよ！'
end

# set game status
bot.command :setgame do |event, game_name|
  bot.game = game_name.to_s
  event.send_message("#{game_name}をやるよ！")
end

# release game status
bot.command :releasegame do |event|
  bot.game = nil
end

# notice join voice channel
bot.voice_state_update do |event|
  next if event.user.bot_account
  # get default text channel
  begin
    default_text_channel = nil
    event.server.channels.each do |channel|
      if channel.type == 0
        default_text_channel ||= channel.id
        default_text_channel = channel.id if channel.name == 'general'
      end
    end
    exit unless default_text_channel
  rescue SystemExit => err
    puts "[WARN] There is no text channel."
  end

  # notify only when joining any channel
  if event.old_channel.nil?
    text = "#{event.user.name}さんが#{event.channel.name}に入ったよ！"
  # elsif event.channel.nil?
  #   text = "#{event.user.name}さんが#{event.old_channel.name}から抜けたよ！"
  end
  event.bot.send_message(default_text_channel, text)
end

# join voice channel 
bot.command(:connect) do |event|
  channel = event.user.voice_channel
  next 'ボイスチャンネルにいないじゃん！' unless channel

  # The `voice_connect` method does everything necessary for the bot to connect to a voice channel. Afterwards the bot
  # will be connected and ready to play stuff back.
  bot.voice_connect(channel)
  "このチャンネルに入ったよ！: #{channel.name}"
end

bot.run
