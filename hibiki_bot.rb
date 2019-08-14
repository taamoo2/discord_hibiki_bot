require "discordrb"
require "yaml"
require "net/http"
require "uri"
require "json"

class HibikiBot
  attr_accessor :bot

  yaml = YAML.load_file("secret.yml")
  TOKEN = yaml["token"].freeze
  CLIENT_ID = yaml["client_id"].freeze

  HOT_PEPPER_API_HOST = "http://webservice.recruit.co.jp/hotpepper/gourmet/v1".freeze
  RECRUIT_API_KEY = yaml["recruit_api_key"].freeze

  RANK_TOTAL_COUNT = 200 # 発言数集計のために取得する件数

  def initialize
    @bot = Discordrb::Commands::CommandBot.new(token: TOKEN, client_id: CLIENT_ID, prefix: "/")
    @notice_voice_state = false
  end

  def start
    puts "This bot's invite URL is #{@bot.invite_url}"
    puts "Click on it to invite it to your server."

    settings

    @bot.run
  end

  def settings
    # Ping
    @bot.command :ping do |event|
      message = event.respond("Pong！")
      message.edit "Pong！ 応答までに #{(Time.now - event.timestamp).floor(2)} 秒かかりました"
    end

    # dice
    @bot.command :dice do |event, max|
      event.respond(dice_message(max: max))
    end

    # rank
    @bot.command [:rank] do |event|
      channel = event.channel # Discordrb::Channel
      event.respond(user_rank_message(channel: channel))
    end
    
    # eval
    @bot.command(:eval, help_available: false) do |event, *code|
      event.respond(eval_message(code))
    end
    
    # set game status
    @bot.command :setgame do |event, game_name|
      @bot.game = game_name.to_s
      event.respond("#{game_name}をやるよ！")
    end
    
    # release game status
    @bot.command :releasegame do |event|
      @bot.game = nil
      event.respond("今のゲームをやめるよ！")
    end
    
    #toggle notice voice state
    @bot.command :setnotice do |event, toggle|
      if toggle == 'off'
        @notice_voice_state = false
        event.respond("チャンネル参加通知をOFFにするね")
      elsif toggle == 'on'
        @notice_voice_state = true
        event.respond("チャンネル参加通知をONにするね")
      end
    end

    # 料理屋さん検索
    @bot.command [:gourmet, :gurume, :grm] do |event, address, keyword|
      event.respond(gourmet_message(address: address, keyword: keyword))
    end

    @bot.message(contains: /^(おなかすいた|おなすき)/) do |event|
      if match_data = event.content.match(/^([^、,]+)、([^、,]+)、?(.+)?$/)
        address = match_data[2]
        keyword = match_data[3]
        event.respond(gourmet_message(address: address, keyword: keyword))
      else
        event.respond(gourmet_message)
      end
    end

    # response menthion
    @bot.mention do |event|
      mention_users = event.message.mentions
      message = event.content

      # 不要な文字列を除去
      message.delete!("\s")
      mention_users.each do |user|
        message.slice!("<@#{user.id}>")
      end

      reply = mention_message(message: message, event: event)
      event.respond(reply) unless reply.nil?
    end
    
    # notice join voice channel
    @bot.voice_state_update do |event|
      return unless @notice_voice_state
      return if event.user.bot_account
      # get default text channel
      begin
        default_text_channel = nil
        event.server.channels.each do |channel|
          if channel.type == 0
            default_text_channel ||= channel.id
            default_text_channel = channel.id if channel.name == "general"
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
    # bot.command(:connect) do |event|
    #   channel = event.user.voice_channel
    #   return "ボイスチャンネルにいないじゃん！" unless channel
    
    #   # The `voice_connect` method does everything necessary for the bot to connect to a voice channel. Afterwards the bot
    #   # will be connected and ready to play stuff back.
    #   bot.voice_connect(channel)
    #   "このチャンネルに入ったよ！: #{channel.name}"
    # end

    # help
    @bot.command :help do |event|
      event.respond(help_message)
    end
  end

  def dice_message(max: nil)
    max ||= 6 # 指定がなければ6面ダイス
    max = max.to_i.abs
    "#{max}面サイコロを回したら、「#{rand(1..max)}」が出たよ！"
  end

  def user_rank_message(channel: nil)
    return nil if channel.nil?

    max_count = RANK_TOTAL_COUNT
    max_per_page = 100 # APIの仕様上ページあたりは100件まで
    remain = max_count

    messages = []

    oldest_message_id = nil
    while remain > 0 do
      response = Discordrb::API::Channel.messages(TOKEN, channel.id, (remain < max_per_page) ? remain : max_per_page, oldest_message_id)

      res_json = JSON.parse(response)
      break if res_json.empty?

      oldest_message_id = res_json.last["id"]
      messages += res_json
      remain -= max_per_page
    end

    user_and_post_count = Hash.new

    messages.each{ |message|
      post_user = message["author"]["username"]

      if user_and_post_count[post_user].nil?
        user_and_post_count[post_user] = 1
      else
        user_and_post_count[post_user] += 1
      end
    }

    user_and_post_count = user_and_post_count.sort_by{|key, val| -val}.to_h
    amount = user_and_post_count.values.sum
    top_five = user_and_post_count.first(5)

    message = "ヒマな人ランキング in <##{channel.id}> だよ！ "
    message += %W(人生は有意義にね！ 楽しそうだね！ 目指すならトップだよね！ ねえねえ、仕事は？ 最新#{amount}件の結果だよ！ この人たちに話しかけよう！ 他にやることないんだね〜 かわいいね！ これが最強戦士……！).sample
    message += "\n"

    top_five.each_with_index{ |item, idx|
      message +=
        case idx
        when 0
          ":first_place: "
        when 1
          ":second_place: "
        when 2
          ":third_place: "
        else
          ""
        end
      username = item[0]
      post_count = item[1]
      message += "#{idx + 1}. #{username} (#{post_count}: #{(post_count.to_f / amount * 100).round(2)}%)\n"
    }

    message
  end

  def eval_message(code)
    eval code.join(" ") rescue "そがんこつわからん！"
  end

  def gourmet_message(address: nil, keyword: nil)
    address ||= "東京駅"
    keyword.gsub!(/(,|、)/, " ") unless keyword.nil?
    max_count = 100

    query_str  = "key=#{RECRUIT_API_KEY}"
    query_str += "&address=#{address}"
    query_str += "&keyword=#{keyword}" unless keyword.nil?
    query_str += "&count=#{max_count}"
    query_str += "&format=json"

    encoded_query = URI.encode(query_str)

    uri = URI.parse("#{HOT_PEPPER_API_HOST}?#{encoded_query}")
    response = Net::HTTP.get_response(uri)
    res_json = JSON.parse(response.body)

    shop_list = res_json.dig("results", "shop")
    return "ごめんね、お店見つけられなかったよ" if shop_list.empty?

    shop_info = shop_list.sample

    message = "#{address}で"
    message += "#{keyword}を" if keyword
    message += "探してみたよ！ こことかどう？\n"
    message += "#{shop_info["mobile_access"]} 『#{shop_info["name"]}』\n"
    message += shop_info.dig("urls", "pc")
  end

  def help_message
    message = "`/dice` : サイコロを回すよ。引数があると、それを最大値とするサイコロを回すよ :game_die:\n"
    message += "`/eval` : 「るびぃ」っていうのを動かせるんだって！1+1とか入れてみてね！\n"
    message += "`/setgame` : 私がやってるゲームを設定できますよ\n"
    message += "`/releasegame` : ゲームの設定を外せますよ:\n"
    message += "`/ping` : 「そつうかくにん」？らしいよ\n"
    message += "`/rank` : 最近ヒマそうにしてる人を教えてあげるね :kiss_ww:\n"
    message += "`/help` : これのことです\n"
    message += "\n"
    message += "アットマークでメンションをくれたら何か反応するかも・・？\n"
    message += "あとあと、誰かがボイスチャンネルに入ったらお知らせしますよ！"
  end

  def mention_message(message: nil, event: nil)
    case message
    when /(さいころ|サイコロ)/
      dice_message
    when /ランキング/
      user_rank_message(channel: event.channel)
    when /(おなかすいた|おなすき)/
      [
        "栄養あるものをしっかり食べようね！",
        "ぐぐぅぅー",
        "実は /gurume コマンドは /gourmet や /grm と打っても使えるよ！",
      ].sample
    when /あり/
      [
        "どういたしまして！",
        "よかばい！",
        "今後ともごひいきにー！",
      ].sample
    when /にゃ(ん|ー)/
      [
        "(」・ω・)」うー！(/・ω・)/にゃー！",
      ].sample
    when /(ひま|ヒマ|暇)/
      news_message
    when /！！$/
      [
        "そうだね！！！",
        "元気いっぱいだねー！！",
      ].sample
    when /(おは)/
      [
        "おはようございます！今日も頑張りましょう！",
        "おはよう！にぃに！"
      ].sample
    when /help/
      help_message
    else
      [
        "ん～？ごめんね、わかんなかったです・・"
      ].sample
    end
  end
end

hibiki_bot = HibikiBot.new
hibiki_bot.start
